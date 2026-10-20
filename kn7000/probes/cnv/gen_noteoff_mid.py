#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# gen_noteoff_mid.py OUT.mid -- the MIDI IN 1 half of awcnv_noteoff.lua: an SMF for MAME's -midiin1
# (file time t plays at emulated time t + 10 s in this driver, probes/gen_q_mid.py), on channel 5:
# emu 77.0 bank 121/0 + program 80, 77.2-78.2 G4; emu 80.0 bank 121/0 + program 0, 80.2-81.2 A4.
import struct
import sys


def vlq(n):
    b = [n & 0x7F]
    n >>= 7
    while n:
        b.append((n & 0x7F) | 0x80)
        n >>= 7
    return bytes(reversed(b))


ev = bytearray(vlq(0) + bytes([0xFF, 0x51, 0x03]) + struct.pack(">I", 500000)[1:])
last = 0
for t, raw in [(77.0, [0xB4, 0, 121]), (77.0, [0xB4, 32, 0]), (77.0, [0xC4, 80]), (77.2, [0x94, 67, 100]),
               (78.2, [0x84, 67, 64]), (80.0, [0xB4, 0, 121]), (80.0, [0xB4, 32, 0]), (80.0, [0xC4, 0]),
               (80.2, [0x94, 69, 100]), (81.2, [0x84, 69, 64])]:
    tk = int((t - 10) * 960)
    ev += vlq(tk - last) + bytes(raw)
    last = tk
ev += vlq(int(76 * 960) - last) + bytes([0xFF, 0x2F, 0x00])
open(sys.argv[1], "wb").write(b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) + b"MTrk" + struct.pack(">I", len(ev)) + bytes(ev))
