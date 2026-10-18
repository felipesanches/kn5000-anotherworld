#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
"""addrmap.py -- where is a program-942 (SP7001) routine in program 941?

Matches the bytes of a 942 routine against the 941 image with every 32-bit absolute operand that
points into ROM, library or RAM masked out, and reports the unique 941 address. Images are mapped
as: program file offset X -> 0x48400000 + X; library 0x4C000000 + Y -> program offset LIB + Y,
where LIB is found by locating the 941 library start inside each image.
usage: python3 -I addrmap.py ADDR942 [LEN]       (ROM images from $DISASM_REPO/baserom)
"""
import os
import sys

ROMS = os.path.join(os.environ.get("DISASM_REPO", os.path.expanduser("~/compartilhado/kn7000_disassembly")), "baserom")
R941 = os.path.join(ROMS, "kn7000_program.rom")
R942 = os.path.join(ROMS, "kn7000_program_sp7001.rom")
d1, d2 = open(R941, "rb").read(), open(R942, "rb").read()
LIB941 = 0x3B8FD1
LIB942 = d2.find(d1[LIB941:LIB941 + 64])
assert LIB942 > 0


def off(a, lib):
    return lib + (a - 0x4C000000) if a >= 0x4C000000 else a - 0x48400000


def addr(o, lib):
    return 0x4C000000 + (o - lib) if lib <= o < lib + 0x40000 else 0x48400000 + o


def masked(b):
    out = bytearray(b)
    for i in range(len(b) - 3):
        v = int.from_bytes(b[i:i + 4], "little")
        if (v >> 24) in (0x48, 0x4C, 0x50, 0x90, 0x44, 0x84, 0x8C):
            out[i:i + 4] = b"\0\0\0\0"
    return bytes(out)


a = int(sys.argv[1], 16)
n = int(sys.argv[2]) if len(sys.argv) > 2 else 24
pat = d2[off(a, LIB942):off(a, LIB942) + n]
mp = masked(pat)
hits = [i for i in range(len(d1) - n) if d1[i] == pat[0] and masked(d1[i:i + n]) == mp]
print(f"942 {a:08X} (lib942 file offset {LIB942:#x}) -> 941 candidates:", [f"{addr(h, LIB941):08X}" for h in hits[:8]])
