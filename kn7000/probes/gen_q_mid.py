#!/usr/bin/env python3
# SMF for awmidiq.lua: C6 on/off then a running-status pair (A5 on, A5 on-vel-0) on channel 1.
# File time t plays at emu time t+10 s in this driver. 120 bpm / 480 ppq -> 960 ticks/s.
import struct, sys
def vlq(n):
    b=[n&0x7F]; n>>=7
    while n: b.append((n&0x7F)|0x80); n>>=7
    return bytes(reversed(b))
ev=bytearray(vlq(0)+bytes([0xFF,0x51,0x03])+struct.pack(">I",500000)[1:]); last=0
for t,raw in [(4.0,[0x90,84,0x64]),(4.5,[0x80,84,0x40]),(5.0,[0x90,81,0x64]),(5.5,[0x90,81,0x00])]:
    tk=int(t*960); ev+=vlq(tk-last)+bytes(raw); last=tk
ev+=vlq(int(12*960)-last)+bytes([0xFF,0x2F,0x00])
open(sys.argv[1],"wb").write(b"MThd"+struct.pack(">IHHH",6,0,1,480)+b"MTrk"+struct.pack(">I",len(ev))+bytes(ev))
