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
# file list for sd_addfile.py (<out>/card.args).
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
    if "--list" in sys.argv:
        print("\n".join(rows))
    print(f"aw_extract: {len(ents)} resources -> {dst}", file=sys.stderr)


if __name__ == "__main__":
    main()
