#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# aw_extract.py -- unpack every Another World (MS-DOS) resource from MEMLIST.BIN + BANKxx.
#
# MEMLIST.BIN is a list of 20-byte big-endian entries, ended by an entry whose state byte is 0xFF:
#   +0 state  +1 type  +2 u16 buf_ptr  +4 u16 (unused)  +6 rank  +7 bank  +8 u32 bank offset
#   +12 u32 packed size  +16 u32 unpacked size
# A resource whose packed size differs from its size is ByteKiller-packed; this is the same
# unpacker as the reference VM's (rustyworld src/resources.rs) and Gregory Montoir's rawgl.
#
#   python3 -I tools/aw_extract.py <dir with MEMLIST.BIN + BANK01..0D> <out dir> [--list] [--inc F]
# writes <out>/resource-0xNN.bin for every entry (0x00..0x91) and <out>/memlist.tsv
# (id, type, bank, offset, packed, size, crc32 of the unpacked bytes). --inc F (F = <out>/awres.inc)
# also lays the resources out for the KN7000 module (see layout) and writes the pack files the SD
# card carries (<out>/AWPxx.bin), the module's tables (awres.inc + awres_tab.s) and the card's
# file list for sd_addfile.py (<out>/card.args). --parts F LAYOUT FONTS (F = <out>/awpart.inc) writes
# the KN7APP.BIN build's per-part loading tables and the game files it reads from the SD card
# (write_parts: <out>/sdfiles/, listed in <out>/sdfiles.lst), with the memory layout read from LAYOUT
# (src/platformcnv.inc) and the font/string tables from FONTS.
import os, struct, sys, zlib

TYPES = {0: "sound", 1: "music", 2: "bitmap", 3: "palette", 4: "bytecode", 5: "video1", 6: "video2"}


def memlist(path):
    data = open(path, "rb").read()
    out = []
    for i in range(0, len(data) - 19, 20):
        state, rtype, buf_ptr, _, rank, bank, off, packed, size = struct.unpack(">BBHHBBIII", data[i:i + 20])
        if state == 0xFF:
            break
        out.append(dict(id=len(out), type=rtype, rank=rank, bank=bank, offset=off, packed=packed, size=size))
    return out


class Bits:
    """ByteKiller bit reader: 32-bit big-endian words consumed from the END of the stream."""

    def __init__(self, data, end, crc):
        self.data, self.pos = data, end - 4          # pos = offset of the word to read next
        self.bits = self.word()                      # the first word seeds the bit buffer
        self.crc = crc ^ self.bits

    def word(self):
        if self.pos < 0:
            raise ValueError("ran off the start of the packed data")
        w = struct.unpack(">I", self.data[self.pos:self.pos + 4])[0]
        self.pos -= 4
        return w

    def bit(self):
        r = self.bits & 1
        self.bits >>= 1
        if self.bits == 0:
            w = self.word()
            self.crc ^= w
            r = w & 1
            self.bits = (1 << 31) | (w >> 1)
        return r

    def take(self, n):
        v = 0
        for _ in range(n):
            v = (v << 1) | self.bit()
        return v


def unpack(buf, size):
    ps = len(buf)
    crc = struct.unpack(">I", buf[ps - 8:ps - 4])[0]
    b = Bits(buf, ps - 8, crc)
    out = bytearray()
    while len(out) < size:
        if not b.bit():
            if not b.bit():
                n = b.take(3) + 1                      # literal run, 1..8 bytes
                for _ in range(n):
                    out.append(b.take(8))
                continue
            n, off = 2, b.take(8)                      # 2-byte copy, 8-bit offset
        else:
            c = b.take(2)
            if c == 3:
                n = b.take(8) + 9                      # literal run, 9..264 bytes
                for _ in range(n):
                    out.append(b.take(8))
                continue
            if c == 2:
                n = b.take(8) + 1
                off = b.take(12)
            elif c == 1:
                n, off = 4, b.take(10)
            else:
                n, off = 3, b.take(9)
        for _ in range(n):
            out.append(out[len(out) - off])
    if len(out) != size:
        raise ValueError(f"unpacked {len(out)} bytes, expected {size}")
    if b.crc != 0:
        raise ValueError("bad ByteKiller crc")
    out.reverse()
    return bytes(out)


RES_BASE = 0x44200000      # first resource; the pages end at 0x44140000, the font sits at 0x44480000
RES_LIMIT = 0x44480000
PACK_MAX = 65535           # the firmware's fread count is 16 bits


def layout(ents, blobs, dst):
    """Lay every resource out from RES_BASE (4-byte aligned, id order) and cut that image into
    packs of <= PACK_MAX bytes on resource boundaries: a pack is the exact RAM image of its span,
    padding included, so the loader copies each pack file to its base address."""
    addr, rows = RES_BASE, []
    for e in ents:
        rows.append((addr if e["size"] else 0, e["size"], e["type"]))
        addr += (e["size"] + 3) & ~3
    if addr > RES_LIMIT:
        raise SystemExit(f"resources end at {addr:#x}, past {RES_LIMIT:#x}")
    image = bytearray(addr - RES_BASE)
    for (a, n, _), e in zip(rows, ents):
        if n:
            image[a - RES_BASE:a - RES_BASE + n] = blobs[e["id"]]
    packs, start = [], RES_BASE                  # (base, length)
    for a, n, _ in rows:
        if n and a + n - start > PACK_MAX:
            packs.append((start, a - start))
            start = a
    packs.append((start, addr - start))
    for k, (b, n) in enumerate(packs):
        with open(os.path.join(dst, f"AWP{k:02X}.bin"), "wb") as f:
            f.write(image[b - RES_BASE:b - RES_BASE + n])
    return rows, packs, addr


def write_inc(path, ents, blobs):
    """awres.inc: the RES_*/PACK_* constants. awres_tab.s beside it: ResAddr (u32), ResSize (u16)
    and ResType (u8) per resource id, PackAddr (u32) and PackSize (u16) per pack file."""
    dst = os.path.dirname(path)
    rows, packs, end = layout(ents, blobs, dst)
    head = ["# GENERATED by tools/aw_extract.py from MEMLIST.BIN -- do not edit.",
            "# Every Another World resource, loaded by LoadGameData from the pack files",
            "# C:\\TECHNICS\\DATA\\AWPxx.AW (each the RAM image of a span of resources)."]
    open(path, "w").write("\n".join(head + [
        f".equ RES_COUNT,       {len(ents)}",
        f".equ RES_BASE,        {RES_BASE:#010x}",
        f".equ RES_END,         {end:#010x}     # first byte past the last resource",
        f".equ PACK_COUNT,      {len(packs)}", ""]))
    out = head + ["# The tables (the constants are in awres.inc).",
           "    .align  4",
           "ResAddr:                            # u32 per id: resource address (0 = empty resource)"]
    out += [f"    .long   {a:#010x}              # 0x{i:02X} {TYPES.get(t, t)}" for i, (a, n, t) in enumerate(rows)]
    out += ["PackAddr:                           # u32 per pack: RAM base its file is copied to"]
    out += [f"    .long   {b:#010x}              # AWP{k:02X}.AW" for k, (b, n) in enumerate(packs)]
    out += ["ResSize:                            # u16 per id: unpacked size in bytes"]
    out += [f"    .word   {n}" for _, n, _ in rows]
    out += ["PackSize:                           # u16 per pack: file length in bytes"]
    out += [f"    .word   {n}" for _, n in packs]
    out += ["ResType:                            # u8 per id: 0 sound 1 music 2 bitmap 3 palette 4 bytecode 5 video1 6 video2"]
    out += [f"    .byte   {t}" for _, _, t in rows]
    out += ["    .align  4", ""]
    open(os.path.join(dst, "awres_tab.s"), "w").write("\n".join(out))
    # the SD card's file list for kn7000_disassembly/tools/sd_addfile.py ("DOSPATH source" pairs);
    # the module builds the same AWPxx.AW names from the pack index
    pairs = ["C:\\TECHNICS\\DATA\\AWP%02X.AW %s" % (k, os.path.join(dst, "AWP%02X.bin" % k))
             for k in range(len(packs))]
    open(os.path.join(dst, "card.args"), "w").write("\n".join(pairs) + "\n")
    print(f"aw_extract: {len(packs)} packs, {end - RES_BASE} bytes at {RES_BASE:#x}..{end:#x}", file=sys.stderr)


def layout_consts(path):
    """The .equ constants of a platform include, or of a list of them read in order (decimal, hex,
    and + - * | of earlier ones)."""
    import re
    syms = {}
    lines = [ln for p in ([path] if isinstance(path, str) else path) for ln in open(p)]
    for line in lines:
        m = re.match(r"\s*\.equ\s+(\w+)\s*,\s*([^#]+)", line)
        if not m:
            continue
        expr = m.group(2).strip()
        if not re.fullmatch(r"[\w\s+*()|-]+", expr):
            continue
        try:
            py = re.sub(r"0x[0-9A-Fa-f]+|\d+|[A-Za-z_]\w*",
                        lambda t: t.group(0) if t.group(0)[0].isdigit() else str(syms[t.group(0)]), expr)
            syms[m.group(1)] = int(eval(py, {"__builtins__": {}}))
        except (KeyError, SyntaxError):
            pass
    return syms


def unpack_in_place(packed, size):
    """ByteKiller as cnv_main.s BkUnpack runs it in place: the packed bytes at the start of the
    destination, the output written backwards from its last byte over the same buffer (as the
    original engine, rawgl Resource::readBank). Returns the output, or raises ValueError when an
    output byte would overwrite input not yet read, or the result is wrong."""
    ps = len(packed)
    buf = bytearray(max(size, ps))
    buf[:ps] = packed
    pos = ps - 8                                     # the crc word; the size word after it is unused
    crc = struct.unpack_from(">I", buf, pos)[0]
    pos -= 4
    bits = struct.unpack_from(">I", buf, pos)[0]
    pos -= 4
    crc ^= bits
    out, left = size - 1, size

    def take(n):
        nonlocal bits, pos, crc
        v = 0
        for _ in range(n):
            r = bits & 1
            bits >>= 1
            if bits == 0:
                if pos < 0:
                    raise ValueError("ran off the start of the packed data")
                w = struct.unpack_from(">I", buf, pos)[0]
                pos -= 4
                crc ^= w
                r, bits = w & 1, (w >> 1) | 0x80000000
            v = (v << 1) | r
        return v
    while left > 0:
        lit, off = False, 0
        if not take(1):
            if not take(1):
                n, lit = take(3) + 1, True
            else:
                n, off = 2, take(8)
        else:
            c = take(2)
            if c == 3:
                n, lit = take(8) + 9, True
            elif c == 2:
                n = take(8) + 1
                off = take(12)
            elif c == 1:
                n, off = 4, take(10)
            else:
                n, off = 3, take(9)
        n = min(n, left)
        left -= n
        for _ in range(n):
            b = take(8) if lit else buf[out + off]
            if out <= pos + 3:                       # the next word still to read is at pos..pos+3
                raise ValueError(f"in-place unpack overwrites unread input at {out}")
            buf[out] = b
            out -= 1
    if crc != 0:
        raise ValueError("bad ByteKiller crc")
    return bytes(buf[:size])


def sound_bank(T, ents, raw, L):
    """The sample bank the effects DSP plays (src/dsp.s, tools/dsp_mixer.py; README-CNV.md "Sound"): every sound
    resource some part's bytecode plays (PLAY_SOUND), loads (LOAD) or uses as a music instrument (the modules its
    bytecode plays or loads), laid out as the DSP's SDRAM will hold it, Rice-coded by tools/dsp_bank.py into the
    card files AWSB0.AW, AWSB1.AW ... (decoded by the DSP), and the table AWBANK.AW that says where each sound is in
    SDRAM. The game sends the whole bank once (it stays in SDRAM until the power goes off; the bank's id, a CRC-32
    of the table and the samples, tells a later run that it is there, and the DSP's checksum of the SDRAM, compared
    with the one here, that it is intact).

    A sound resource: u16 BE len, u16 BE loop length (in words), 4 bytes, then the 8-bit signed samples: len*2
    played once, then loop*2 repeated (rawgl Mixer playSoundRaw, SfxPlayer handlePattern). In SDRAM: four samples a
    32-bit word, the first in the low byte, each sound from a word that is a whole number of copy steps
    (dsp_mixer.COPY_STEP words) past the bank's first, the words between two sounds zero; a music instrument's
    first four samples zeroed (rawgl prepareInstruments).

    AWBANK.AW (little-endian): "AWBK", u32 entries (one per resource id), u32 the bank's id, u32 words in all,
    u32 the bank's checksum (dsp_bank.checksum), u32 the card files AWSBn.AW, u32 0, u32 0; then per resource id
    20 bytes: u32 the DSP address of its first word (0: not in the bank), u32 samples in all (len*2 + loop*2), u32
    samples in the loop (0: none), u32 0, u32 its unpacked size with bit 31 set for a music instrument."""
    import aw_partinfo
    import dsp_bank
    import dsp_mixer
    sounds, insts = set(), set()
    for pid, name, pal, cod, v1, v2id in aw_partinfo.PARTS:
        code = raw(cod) if T[cod]["packed"] == T[cod]["size"] else unpack(raw(cod), T[cod]["size"])
        _, snd, mus, lds, _, _ = aw_partinfo.decode(code)
        sounds |= {i for i in snd | lds if 0 < i < len(ents) and T[i]["type"] == 0}
        for m in {i for i in mus | lds if 0 < i < len(ents) and T[i]["type"] == 1}:
            mod = raw(m) if T[m]["packed"] == T[m]["size"] else unpack(raw(m), T[m]["size"])
            for k in range(15):
                r = struct.unpack(">H", mod[2 + 4 * k:4 + 4 * k])[0]
                if 0 < r < len(ents) and T[r]["type"] == 0:
                    insts.add(r)
    ids = sorted(i for i in sounds | insts if T[i]["size"] >= 8)
    step = dsp_mixer.COPY_STEP
    at, tab, crc, image = 0, {}, 0, bytearray()
    for i in ids:
        e = T[i]
        data = raw(i) if e["packed"] == e["size"] else unpack(raw(i), e["size"])
        ln, lp = struct.unpack(">HH", data[:4])
        end, loop = 2 * (ln + lp), 2 * lp
        if not 0 < end <= len(data) - 8:
            raise SystemExit(f"aw_extract: sound 0x{i:02X}: header says {end} samples, the resource holds {len(data) - 8}")
        if len(raw(i)) >= 0x10000 or e["size"] >= 0x10000:      # src/dsp.s BankRead's staging space
            raise SystemExit(f"aw_extract: sound 0x{i:02X} is too large for the bank's staging space")
        words = (end + 4 * step - 1) // (4 * step) * step
        tab[i] = (dsp_mixer.BANK + at, end, loop, 0, e["size"] | (0x80000000 if i in insts else 0))
        crc = zlib.crc32(struct.pack("<IIII", i, dsp_mixer.BANK + at, end, loop), crc)
        crc = zlib.crc32(data[8:8 + end], crc)
        smp = bytearray(data[8:8 + end])
        if i in insts:
            smp[0:4] = bytes(min(4, len(smp)))
        image += smp + bytes(4 * words - len(smp))
        at += words
    if at > dsp_mixer.BANK_MAX:
        raise SystemExit(f"aw_extract: the sample bank needs {at} words of SDRAM; {dsp_mixer.BANK_MAX} are set aside")
    files, csum, blocks = dsp_bank.build(bytes(image))
    out = b"AWBK" + struct.pack("<IIIIIII", len(ents), crc, at, csum, len(files), 0, 0)
    for i in range(len(ents)):
        out += struct.pack("<IIIII", *tab.get(i, (0, 0, 0, 0, 0)))
    if len(out) > L["DSP_BANKTAB_MAX"]:
        raise SystemExit(f"aw_extract: AWBANK.AW is {len(out)} bytes; DSP_BANKTAB holds {L['DSP_BANKTAB_MAX']}")
    print(f"aw_extract: the DSP's sample bank: {len(ids)} sounds ({len(insts)} music instruments), "
          f"{sum(t[1] for t in tab.values()):,} samples in {at:,} SDRAM words, id {crc:08X}; coded "
          f"{4 * at:,} -> {sum(map(len, files.values())):,} bytes, {len(blocks)} blocks in {len(files)} files, "
          f"{sum(2 * len(b) for b in blocks):,} host-port halves, checksum {csum:08X}", file=sys.stderr)
    return out, files


def write_parts(path, src, ents, layout_inc, fonts):
    """The KN7APP.BIN build's per-part loading (cnv_main.s EnsurePart / LoadStep): awpart.inc and
    awpart_tab.s beside PATH, and the game files for the SD card in <dir>/sdfiles/ (sdfiles.lst).

    The card carries every resource the game draws or runs as its own file AWRxx.AW (xx = the id),
    holding the exact bytes MEMLIST.BIN points at in BANKxx: ByteKiller-packed or stored. The sounds the
    game plays are there too, for the effects DSP's sample bank (sound_bank: AWBANK.AW and the sound files,
    read once at the start, src/dsp.s); for the tone generator's MIDI notes, src/audio.s, the table
    tools/aw_sound_map.py makes (AWSND.AW). At a part switch the application reads the part's palette, bytecode
    and polygons and unpacks each in place, reads the bitmaps its bytecode LOADs (aw_partinfo.decode:
    LOAD takes an immediate id, so the linear sweep finds them all), which stay packed until LOAD draws
    one, and the music module its bytecode plays (0x07 in the intro, 0x8A in the final part), unpacked
    in place into MUSIC_BUF. The shared polygons (0x11), the font, the strings, AWSND.AW and AWBANK.AW are
    loaded once, at the start.

    Record (20 bytes): u32 name, u32 destination, u32 bytes to read, u32 unpacked size, u16 resource
    id (0xFFFF: not a resource), u8 flags (1 = unpack in place), u8 0. A list ends with name 0."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import aw_partinfo                              # the bytecode decoder beside this script
    dst = os.path.dirname(path)
    fdir = os.path.join(dst, "sdfiles")
    os.makedirs(fdir, exist_ok=True)
    T = {e["id"]: e for e in ents}
    L = layout_consts(layout_inc)
    area, area_end = L["PART_AREA"], L["PART_END"]

    def raw(i):
        e = T[i]
        with open(os.path.join(src, f"BANK{e['bank']:02X}"), "rb") as f:
            f.seek(e["offset"])
            return f.read(e["packed"])
    files, recs, lists = {}, [], []                 # name -> source bytes; records; (label, records)

    def rec(i, dest, inplace):
        e = T[i]
        r = raw(i)
        packed = e["packed"] != e["size"]
        if packed and inplace:                      # the build stops unless it unpacks right in place
            try:
                ok = unpack_in_place(r, e["size"]) == unpack(r, e["size"])
            except ValueError as err:
                raise SystemExit(f"aw_extract: resource 0x{i:02X} cannot be unpacked in place: {err}")
            if not ok:
                raise SystemExit(f"aw_extract: resource 0x{i:02X} unpacks differently in place")
        name = f"AWR{i:02X}.AW"
        files[name] = r
        return dict(name=name, dest=dest, read=len(r), size=e["size"], id=i, flags=1 if packed and inplace else 0)

    def place(ids_inplace, ids_packed, what):
        out, at = [], area
        for i in ids_inplace:
            out.append(rec(i, f"PART_AREA + 0x{at - area:05X}", True))
            at += (max(T[i]["packed"], T[i]["size"]) + 3) & ~3
        for i in ids_packed:
            out.append(rec(i, f"PART_AREA + 0x{at - area:05X}", False))
            at += (T[i]["packed"] + 3) & ~3
        if at > area_end:
            raise SystemExit(f"aw_extract: part {what} needs {at - area} bytes; PART_AREA holds {area_end - area}")
        return out, at - area
    # the global list: font, strings, the shared polygons
    glob = []
    for name, f, sym, n in (("AWFONT.AW", "anotherworld_chargen.rom", "AW_FONT", 768),
                            ("AWSTRIDX.AW", "str_index.rom", "AW_STRIDX", 2048),
                            ("AWSTRDAT.AW", "str_data.rom", "AW_STRDAT", 4096)):
        b = open(os.path.join(fonts, f), "rb").read()
        if len(b) != n:
            raise SystemExit(f"aw_extract: {f} is {len(b)} bytes, expected {n}")
        files[name] = b
        glob.append(dict(name=name, dest=sym, read=n, size=n, id=0xFFFF, flags=0))
    import aw_sound_map                             # each sound's KN7000 program, note, length (audio.s)

    def snd_header(i):
        e = T[i]
        return (raw(i) if e["packed"] == e["size"] else unpack(raw(i), e["size"]))[:4] if e["size"] else b""
    snd, _ = aw_sound_map.snd_table([TYPES.get(e["type"], e["type"]) for e in ents], snd_header)
    if len(snd) > L["SND_TAB_MAX"]:
        raise SystemExit(f"aw_extract: the sound table is {len(snd)} bytes; SND_TAB holds {L['SND_TAB_MAX']}")
    files["AWSND.AW"] = snd
    glob.append(dict(name="AWSND.AW", dest="SND_TAB", read=len(snd), size=len(snd), id=0xFFFF, flags=0))
    bank, bank_files = sound_bank(T, ents, raw, L)  # the effects DSP's sample bank (src/dsp.s)
    files.update(bank_files)
    files["AWBANK.AW"] = bank
    glob.append(dict(name="AWBANK.AW", dest="DSP_BANKTAB", read=len(bank), size=len(bank), id=0xFFFF, flags=0))
    v2 = T[0x11]
    if (max(v2["packed"], v2["size"]) + 3) & ~3 > area - L["VIDEO2_AT"]:
        raise SystemExit("aw_extract: the shared polygons do not fit before PART_AREA")
    glob.append(rec(0x11, "VIDEO2_AT", True))
    lists.append(("GlobalList", glob))
    need = {}
    for k, (pid, name, pal, cod, v1, v2id) in enumerate(aw_partinfo.PARTS):
        code = raw(cod) if T[cod]["packed"] == T[cod]["size"] else unpack(raw(cod), T[cod]["size"])
        _, _, mus, lds, bad, _ = aw_partinfo.decode(code)
        if bad:
            raise SystemExit(f"aw_extract: part {pid:04X}: {bad} undecodable bytecode ops")
        bms = sorted(i for i in lds if 0 < i < len(ents) and T[i]["type"] == 2)
        out, n = place([pal, cod, v1], bms, f"{pid:04X} {name}")
        need[pid] = n
        # the module the part's bytecode plays (PLAY_MUSIC, src/audio.s), into MUSIC_BUF, unpacked in place
        mods = sorted(i for i in mus if 0 < i < len(ents) and T[i]["type"] == 1)
        if len(mods) > 1:
            raise SystemExit(f"aw_extract: part {pid:04X} plays {len(mods)} modules; MUSIC_BUF holds one")
        for i in mods:
            if (max(T[i]["packed"], T[i]["size"]) + 3) & ~3 > L["MUSIC_MAX"]:
                raise SystemExit(f"aw_extract: module 0x{i:02X} does not fit MUSIC_BUF")
            out.append(rec(i, "MUSIC_BUF", True))
        lists.append((f"PartList{k}", out))
    part_ids = [p[0] for p in aw_partinfo.PARTS]    # 0x3E80..0x3E88; 0x3E89 shares 0x3E88's list
    head = ["# GENERATED by tools/aw_extract.py --parts from MEMLIST.BIN -- do not edit.",
            "# The KN7APP.BIN build's game files and what each part loads (aw_extract.py write_parts)."]
    open(path, "w").write("\n".join(head + [
        f".equ RES_COUNT,       {len(ents)}",
        f".equ PART_LISTS,      {len(part_ids)}     # lists for 0x{part_ids[0]:04X}..0x{part_ids[-1]:04X}",
        f".equ PART_NEED_MAX,   {max(need.values())}     # bytes of PART_AREA the largest part uses",
        f".equ LR_NAME,         0", f".equ LR_DEST,         4", f".equ LR_READ,         8",
        f".equ LR_SIZE,         12", f".equ LR_ID,           16", f".equ LR_FLAGS,        18",
        f".equ LR_LEN,          20", f".equ LR_INPLACE,      1", ""]))
    out = head + ["    .align  4", "PartLists:                          # u32 per part id 0x3E80..0x3E89"]
    out += [f"    .long   PartList{k}" for k in range(len(part_ids))] + [f"    .long   PartList{len(part_ids) - 1}"]
    for label, rs in lists:
        out.append(f"{label}:")
        for r in rs:
            out.append(f"    .long   fn_{r['name'].replace('.', '_')}, {r['dest']}, {r['read']}, {r['size']}")
            out.append(f"    .word   0x{r['id']:04X}")
            out.append(f"    .byte   {r['flags']}, 0")
        out.append("    .long   0, 0, 0, 0")
        out.append("    .word   0")
        out.append("    .byte   0, 0")
    out.append("ResPacked:                          # u32 per id: a bitmap's packed size (0 = stored as is)")
    out += [f"    .long   {e['packed'] if e['type'] == 2 and e['packed'] != e['size'] else 0}" for e in ents]
    out.append("ResType:                            # u8 per id: 0 sound 1 music 2 bitmap 3 palette 4 bytecode 5 video1 6 video2")
    out += [f"    .byte   {e['type']}" for e in ents]
    out.append("    .align  2")
    for name in sorted(files):
        out.append(f"fn_{name.replace('.', '_')}:")
        out.append(f'    .asciz  "{name}"')
        out.append("    .align  2")
    out += ["    .align  4", ""]
    open(os.path.join(dst, "awpart_tab.s"), "w").write("\n".join(out))
    for name, b in files.items():
        open(os.path.join(fdir, name), "wb").write(b)
    open(os.path.join(dst, "sdfiles.lst"), "w").write("".join(f"{n}\n" for n in sorted(files)))
    print(f"aw_extract: {len(files)} game files for the SD card, {sum(map(len, files.values()))} bytes; largest part "
          f"{max(need.values())} of {area_end - area} bytes ({', '.join(f'{p:04X} {n}' for p, n in need.items())})",
          file=sys.stderr)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    ents = memlist(os.path.join(src, "MEMLIST.BIN"))
    rows = ["id\ttype\tbank\toffset\tpacked\tsize\tcrc32"]
    blobs = {}
    for e in ents:
        if e["size"] == 0:
            data = b""
        else:
            with open(os.path.join(src, f"BANK{e['bank']:02X}"), "rb") as f:
                f.seek(e["offset"])
                raw = f.read(e["packed"])
            data = raw if e["packed"] == e["size"] else unpack(raw, e["size"])
        blobs[e["id"]] = data
        with open(os.path.join(dst, f"resource-0x{e['id']:02x}.bin"), "wb") as f:
            f.write(data)
        rows.append(f"0x{e['id']:02X}\t{TYPES.get(e['type'], e['type'])}\t{e['bank']:02X}\t{e['offset']}\t"
                    f"{e['packed']}\t{e['size']}\t{zlib.crc32(data):08X}")
    open(os.path.join(dst, "memlist.tsv"), "w").write("\n".join(rows) + "\n")
    if "--inc" in sys.argv:
        write_inc(sys.argv[sys.argv.index("--inc") + 1], ents, blobs)
    if "--parts" in sys.argv:
        a = sys.argv[sys.argv.index("--parts") + 1:]
        write_parts(a[0], src, ents, a[1], a[2])
    if "--list" in sys.argv:
        print("\n".join(rows))
    print(f"aw_extract: {len(ents)} resources -> {dst}", file=sys.stderr)


if __name__ == "__main__":
    main()
