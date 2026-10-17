#!/usr/bin/env python3
# Turn an awmonitor raw events file (K lines, source midi) back into a Standard MIDI File with the
# same timing and velocities, so a played session can be re-performed exactly via -midiin1.
# In this driver an SMF on -midiin1 starts playing at emu time 10.0 s, so file time = emu - 10.
#   python3 -I events_to_mid.py <aw-session-events.csv> <out.mid> [offset_s=10.0]
import struct, sys
src, dst = sys.argv[1], sys.argv[2]; off = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
def vlq(n):
    b=[n&0x7F]; n>>=7
    while n: b.append((n&0x7F)|0x80); n>>=7
    return bytes(reversed(b))
evs=[]
for l in open(src):
    c=l.strip().split(',')
    if c[0]=='K' and c[-1]=='midi':
        evs.append((float(c[1])-off, int(c[3]), int(c[4]), int(c[5])))
TPS=960  # 120 bpm, 480 ppq
ev=bytearray(vlq(0)+bytes([0xFF,0x51,0x03])+struct.pack(">I",500000)[1:]); last=0
for t,n,on,v in evs:
    tk=max(last,int(round(t*TPS))); ev+=vlq(tk-last)+bytes([0x90 if on else 0x80, n, (v if on else v) & 0x7F]); last=tk
ev+=vlq(10*TPS)+bytes([0xFF,0x2F,0x00])
open(dst,"wb").write(b"MThd"+struct.pack(">IHHH",6,0,1,480)+b"MTrk"+struct.pack(">I",len(ev))+bytes(ev))
print(f"{len(evs)} events -> {dst} (last at file t={evs[-1][0]:.2f}s)")
