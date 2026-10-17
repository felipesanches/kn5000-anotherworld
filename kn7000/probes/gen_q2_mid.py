#!/usr/bin/env python3
# SMF for awkeystate.lua: 84 on 9.0-9.3; 48 on 9.6-10.0; 52 on 9.8-10.2 (file time; plays at +10 s).
import struct, sys
def vlq(n):
    b=[n&0x7F]; n>>=7
    while n: b.append((n&0x7F)|0x80); n>>=7
    return bytes(reversed(b))
ev=bytearray(vlq(0)+bytes([0xFF,0x51,0x03])+struct.pack(">I",500000)[1:]); last=0
for t,raw in [(9.0,[0x90,84,0x64]),(9.3,[0x80,84,0x40]),(9.6,[0x90,48,0x64]),(9.8,[0x90,52,0x64]),(10.0,[0x80,48,0x40]),(10.2,[0x80,52,0x40])]:
    tk=int(t*960); ev+=vlq(tk-last)+bytes(raw); last=tk
ev+=vlq(int(14*960)-last)+bytes([0xFF,0x2F,0x00])
open(sys.argv[1],"wb").write(b"MThd"+struct.pack(">IHHH",6,0,1,480)+b"MTrk"+struct.pack(">I",len(ev))+bytes(ev))
