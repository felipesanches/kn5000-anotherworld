#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# aw_find_fw.py -- does AW.CNV's run-time firmware search (src/fwfind.s) find the right routines and
# RAM addresses in every KN7000 program build we have?
#
# AW.CNV carries no firmware address: on its first call it looks for what it needs in the program
# flash (0x48400000-0x487FFFFF) and in the kernel library the boot copies to RAM at 0x4C000000, the
# way the ROM dumper's loader does (technics-roms-disasm kn7000/tools/cnv_romdump, which ran on the
# owner's program 893). This script runs the SAME searches, with the same acceptance rules, over the
# program images, and prints what each build gives. Rules (fwfind.s implements exactly these):
#
#   open      OpenHere (open a file in the current drive + folder, as STYLE CONVERT's own load does):
#             a masked code signature, exactly one hit; its last call must enter fmmopen (found below)
#             after fmmopen's 5-byte prologue
#   fmm       the dumper's FindFileSig: the drive switch (one hit), fmmopen within 4 KB after it, and
#             fmmclose / fmmread among the dispatchers there whose dispatch table is fmmopen's + 12 /
#             + 0x3C and whose drive byte is the switch's (one hit each)
#   cre/sta   firmware call sites "mov N, d0; mov X, a0; call cre_tsk; mov N, d0; clr d1; call sta_tsk"
#             (both targets in the library 0x4C000000-0x4C03FFFF): at least two, all naming the same two
#             routines, each starting with a kernel entry stub ("add -4, sp; mov d1, (0, sp)")
#   exd       call sites "clr d0; movbu d0, (X); call exd_tsk; ret": at least two, all agreeing, a stub,
#             neither cre_tsk nor sta_tsk
#   dly       the routine the firmware yields with (adds d0 to the millisecond counter and rotates the
#             ready queue until then): a masked signature in the library RAM, one hit, its three
#             counter operands equal
#   ms        the kernel's 1 kHz tick handler (the dumper's signature): one hit, its two counter
#             operands equal, and equal to dly's counter
#   panel     the panel decoder's two "mov CPR, a0 ... mov CPL, a0" sites: one hit each, the same
#             two bitmaps, CPL = CPR + 0x30, in work RAM
#   rings     the library's per-port MIDI ring wrappers: one hit; MIDI IN 1 receive and MIDI OUT 1
#             transmit ring headers, in work RAM, IN below OUT
#
#   python3 -I tools/aw_find_fw.py [--roms DIR] [--real-lib893 FILE]
# DIR: the overlay emulator's roms/kn7000 (its v1.3 images are the owner's own dumps). FILE: the
# owner's library RAM as the ROM dumper's SURVEY2 pass read it from 0x4C000000 on the instrument
# (private: technics_roms roms/kn7000/real_dump_v1.3_b893/pass5-run1/R4C00000.BIN); with it, 893's
# library searches run on the real RAM instead of the boot's copy of the flash, and the script
# reports whether the two agree.
import argparse
import os
import struct
import sys

BASE, LIB = 0x48400000, 0x4C000000
BUILDS = [  # name, even half, odd half (IC17 = bytes 0-1, IC16 = bytes 2-3 of each 32-bit word)
    ("893 (v1.3)", "kn7000_program_even_v1.3_b893.ic17", "kn7000_program_odd_v1.3_b893.ic16"),
    ("935 (v1.5)", "kn7000_program_even_v1.5_b935.ic17", "kn7000_program_odd_v1.5_b935.ic16"),
    ("941 (v1.6)", "kn7000_program_even_v1.6_b941.ic17", "kn7000_program_odd_v1.6_b941.ic16"),
    ("942 (SP7001)", "kn7000_program_even_sp7001_b942.ic17", "kn7000_program_odd_sp7001_b942.ic16"),
]
# Where the boot copies the library from (LibRomImageBase); located per image by its first 16 bytes.
LIB_HEAD = bytes.fromhex("cff0f8fec800fccd0000f03f4218461c")
LIB_LEN = 0x40000


def sig(text):
    """'X' = 4 masked bytes (an absolute operand), '??' = 1 masked byte, else a hex byte."""
    out = []
    for t in text.split():
        out += [None] * 4 if t == "X" else [None] if t == "??" else [int(t, 16)]
    return out


# The signatures fwfind.s carries (same bytes, same masks).
SIG = {
    "open": sig("cf 30 fa fe 64 ff 47 b0 93 3e 22 10 98 fc dd X cd ?? ?? 00 00 98 fc dd X cd ?? ?? 00 00"
                " 98 9d cd ?? ?? 00 00 5d b0 98 cd ?? ?? 30 24 df 30 a4"),
    "ext": sig("81 15 a5 03 c2 08 fc 82 X de 00 00 00 fc 82 X de 00 00 fc a8 X de 00 00"),
    "fmmopen": sig("cf 30 f8 fe e4 97 fc de X 3d 21 10 85 f4 db f0 42 49 f0 51 45 44 d9 fc a8 X 3d 54 21 10"
                   " f3 a1 9d f0 f2 df 30 24"),
    "close": sig("f8 fe ec fc dd X 3c 20 08 85 f4 db f0 41 45 f0 50 41 44 d9 fc a8 X 3c 54 20 08 f3 80"
                 " f0 f0 df 00 14"),
    "rw": sig("cf a0 f8 fe e4 82 fc de X 3d 21 10 85 f4 db f0 42 49 f0 51 45 44 d9 fc a8 X 3d 54 21 10"
              " f3 91 88 f0 f1 df a0 24"),
    "cresta": sig("fc dc X dd X 00 00 80 ?? 04 dd X 00 00"),
    "exd": sig("fc 82 X dd X 00 00 df"),
    "dly": sig("cf a0 f8 fe f0 fc a6 X e2 fc a4 X a2 c7 ?? 00 81 cd ?? ?? 00 00 fc a4 X a2 c5 ?? 00 df a0 18"),
    "tick": sig("cf 80 f8 fe f0 fc a4 X 40 fc 81 X f8 ec 01 c8 09 dd X 80 0c fa fc ff f7 cb cb"
                " fc ac 18 01 00 34 fa e0 00 ff f8 e4 01 fc 83 18 01 00 34"),
    "panel1": sig("fc dc X f1 d8 f8 e0 c0 c8 08 fc dc X f1 d8 f8 e0 0f f1 60 f0 40 f0 5c"),
    "panel2": sig("fc dc X f8 ef c0 c8 08 fc dc X f8 b8 10 85 0f f2 0d f1 64"),
    "rings": sig("2c ff 03 fc 83 X de 00 00 f8 fe f0 fc dc X 14 cd ?? ?? 30 08 df 00 10"
                 " f8 fe f0 fc dc X 14 cd ?? ?? 30 08 df 00 10"),
}
STUB = bytes.fromhex("f8fefc4600")          # a kernel entry stub: add -4, sp; mov d1, (0, sp)


def find(mem, base, s, lo, hi):
    """Every address in [lo, hi) where s matches (fwfind.s FindSig, over the same range)."""
    first, hits, start = s[0], [], lo - base
    while True:
        i = mem.find(bytes([first]), start, hi - base)
        if i < 0:
            return hits
        if i + len(s) <= len(mem) and all(b is None or mem[i + k] == b for k, b in enumerate(s)):
            hits.append(base + i)
        start = i + 1


class Mem:
    def __init__(self, flash, lib):
        self.flash, self.lib = flash, lib

    def at(self, a):
        return (self.flash, BASE) if BASE <= a < BASE + len(self.flash) else (self.lib, LIB)

    def u8(self, a):
        m, b = self.at(a)
        return m[a - b]

    def u32(self, a):
        m, b = self.at(a)
        return struct.unpack_from("<I", m, a - b)[0]

    def s32(self, a):
        m, b = self.at(a)
        return struct.unpack_from("<i", m, a - b)[0]

    def s16(self, a):
        m, b = self.at(a)
        return struct.unpack_from("<h", m, a - b)[0]

    def bytes(self, a, n):
        m, b = self.at(a)
        return m[a - b:a - b + n]

    def find(self, name, lo, hi):
        m, b = self.at(lo)
        return find(m, b, SIG[name], lo, hi)


def work_ram(a):
    return 0x50000000 <= a <= 0x503FFF00


def search(mem):
    """fwfind.s, step by step. Returns {name: value} and a list of failures."""
    r, fail = {}, []
    FL, FH = BASE, BASE + 0x3FFF00            # the program flash, as fwfind.s scans it
    # --- the fmm layer (the dumper's FindFileSig) ---
    ext = mem.find("ext", FL, FH)
    if len(ext) == 1:
        e = ext[0]
        drive = mem.u32(e + 8)
        op = mem.find("fmmopen", e, e + 0x1000)
        if len(op) == 1 and mem.u32(op[0] + 28) == drive and mem.u32(e + 18) == drive == mem.u32(e + 27):
            topen = mem.u32(op[0] + 8)
            r["fmmopen"] = op[0]

            def disp(name, toff, dist, doff):
                ok = [h for h in mem.find(name, e, e + 0x1000)
                      if mem.u32(h + toff) == topen + dist and mem.u32(h + doff) == drive]
                return ok[0] if len(ok) == 1 else None
            r["fmmclose"], r["fmmread"] = disp("close", 5, 12, 25), disp("rw", 8, 0x3C, 28)
    for k in ("fmmopen", "fmmclose", "fmmread"):
        if not r.get(k):
            fail.append(k)
    # --- OpenHere, tied to fmmopen ---
    oh = mem.find("open", FL, FH)
    if len(oh) == 1:
        call = oh[0] + 46
        tgt = (call + mem.s16(call + 1)) & 0xFFFFFFFF
        if r.get("fmmopen") and tgt == r["fmmopen"] + 5:
            r["open"] = oh[0]
    if not r.get("open"):
        fail.append("open")
    # --- cre_tsk / sta_tsk from the firmware's own call sites ---
    pairs, sites = set(), 0
    for h in mem.find("cresta", FL, FH):
        if mem.u8(h - 2) != 0x80 or mem.u8(h - 1) != mem.u8(h + 14):
            continue
        cre = (h + 6 + mem.s32(h + 7)) & 0xFFFFFFFF
        sta = (h + 16 + mem.s32(h + 17)) & 0xFFFFFFFF
        if LIB <= cre < LIB + LIB_LEN and LIB <= sta < LIB + LIB_LEN:
            pairs.add((cre, sta))
            sites += 1
    if len(pairs) == 1 and sites >= 2:
        cre, sta = next(iter(pairs))
        if mem.bytes(cre, 5) == STUB and mem.bytes(sta, 5) == STUB:
            r["cre_tsk"], r["sta_tsk"] = cre, sta
    if not r.get("cre_tsk"):
        fail.append("cre_tsk/sta_tsk")
    # --- exd_tsk ---
    tg = []
    for h in mem.find("exd", FL, FH):
        if mem.u8(h - 1) != 0x00:
            continue
        t = (h + 6 + mem.s32(h + 7)) & 0xFFFFFFFF
        if LIB <= t < LIB + LIB_LEN:
            tg.append(t)
    if len(tg) >= 2 and len(set(tg)) == 1 and mem.bytes(tg[0], 5) == STUB \
            and tg[0] not in (r.get("cre_tsk"), r.get("sta_tsk")):
        r["exd_tsk"] = tg[0]
    else:
        fail.append("exd_tsk")
    # --- dly_tsk and the millisecond counter ---
    dl = mem.find("dly", LIB, LIB + LIB_LEN - 0x100)
    if len(dl) == 1 and mem.u32(dl[0] + 7) == mem.u32(dl[0] + 14) == mem.u32(dl[0] + 30):
        tk = mem.find("tick", FL, FH)
        ms = mem.u32(dl[0] + 7)
        if len(tk) == 1 and mem.u32(tk[0] + 7) == mem.u32(tk[0] + 14) == ms and work_ram(ms):
            r["dly_tsk"], r["kernel_ms"] = dl[0], ms
    if not r.get("dly_tsk"):
        fail.append("dly_tsk/kernel_ms")
    # --- the panel switch bitmaps ---
    p1, p2 = mem.find("panel1", FL, FH), mem.find("panel2", FL, FH)
    if len(p1) == 1 and len(p2) == 1:
        a = (mem.u32(p1[0] + 2), mem.u32(p1[0] + 15))
        b = (mem.u32(p2[0] + 2), mem.u32(p2[0] + 13))
        if a == b and a[1] == a[0] + 0x30 and work_ram(a[0]):
            r["panel_cpr"], r["panel_cpl"] = a
    if not r.get("panel_cpr"):
        fail.append("panel")
    # --- the MIDI rings ---
    rg = mem.find("rings", FL, FH)
    if len(rg) == 1:
        rx, tx = mem.u32(rg[0] + 17), mem.u32(rg[0] + 35)
        if work_ram(rx) and work_ram(tx) and rx < tx:
            r["midiin1_rxq"], r["midiout1_txq"] = rx, tx
    if not r.get("midiin1_rxq"):
        fail.append("rings")
    return r, fail


def load(roms, even, odd):
    e, o = open(os.path.join(roms, even), "rb").read(), open(os.path.join(roms, odd), "rb").read()
    out = bytearray(len(e) * 2)
    out[0::4], out[1::4], out[2::4], out[3::4] = e[0::2], e[1::2], o[0::2], o[1::2]
    return bytes(out)


# What the existing builds used, measured in MAME (README-CNV.md, platform941.inc, platform.inc).
KNOWN = {
    "941 (v1.6)": dict(open=0x48531AC5, fmmread=0x48532463, fmmclose=0x485323BC, cre_tsk=0x4C03D0C8,
                       sta_tsk=0x4C03D8AB, dly_tsk=0x4C03DD6F, exd_tsk=0x4C03D5A1, kernel_ms=0x500D3C58,
                       panel_cpr=0x5006BE50, panel_cpl=0x5006BE80, midiin1_rxq=0x5001F050,
                       midiout1_txq=0x5001F864),
    "942 (SP7001)": dict(sta_tsk=0x4C03DCD3, dly_tsk=0x4C03E295, exd_tsk=0x4C03D944, cre_tsk=0x4C03D46B,
                         kernel_ms=0x500D3C68, panel_cpr=0x5006BE60, panel_cpl=0x5006BE90,
                         midiin1_rxq=0x5001F060, midiout1_txq=0x5001F874),
}
KEYS = ["open", "fmmread", "fmmclose", "cre_tsk", "sta_tsk", "dly_tsk", "exd_tsk", "kernel_ms",
        "panel_cpr", "panel_cpl", "midiin1_rxq", "midiout1_txq"]


def main():
    ap = argparse.ArgumentParser(description="AW.CNV run-time firmware search, over every program build")
    ap.add_argument("--roms", default=os.path.expanduser("~/compartilhado/kn7000-emulator/roms/kn7000"))
    ap.add_argument("--real-lib893")
    a = ap.parse_args()
    cols, bad = {}, 0
    for name, even, odd in BUILDS:
        flash = load(a.roms, even, odd)
        i = flash.find(LIB_HEAD)
        lib = flash[i:i + LIB_LEN] if i >= 0 else b""
        if name.startswith("893") and a.real_lib893:
            real = open(a.real_lib893, "rb").read()
            n = next((k for k, (x, y) in enumerate(zip(real, lib)) if x != y), len(lib))
            print(f"893: the instrument's library RAM equals the boot's copy of the flash for its first "
                  f"0x{n:X} bytes; searching the instrument's", file=sys.stderr)
            lib = real
        r, fail = search(Mem(flash, lib))
        known = KNOWN.get(name, {})
        cell = {}
        for k in KEYS:
            v = r.get(k)
            s = f"`0x{v:08X}`" if v else "NOT FOUND"
            if k in known and v != known[k]:
                s += f" (measured 0x{known[k]:08X}!)"
                bad += 1
            cell[k] = s
        cols[name] = cell
        bad += len(fail)
        if fail:
            print(f"{name}: not found: {', '.join(fail)}", file=sys.stderr)
    names = [b[0] for b in BUILDS]
    rows = [["what"] + names] + [[k] + [cols[n][k] for n in names] for k in KEYS]
    w = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    fmt = lambda r: "| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |"
    print(fmt(rows[0]))
    print("|" + "|".join("-" * (x + 2) for x in w) + "|")
    for r in rows[1:]:
        print(fmt(r))
    print("\naw_find_fw: " + ("every build: everything found; the 941 and 942 values agree with the addresses"
                              " measured in MAME" if not bad else f"{bad} problem(s)"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
