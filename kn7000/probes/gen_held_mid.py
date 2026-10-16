#!/usr/bin/env python3
# Make a tiny Standard MIDI File that holds C4+G4+E4 (note-ons, no note-off) after a ~22 s
# delay, to feed MAME's -midiin1 and confirm MIDI-IN notes reach the KN7000 TG voice
# allocator (the held-note state the Another World module reads). See awmiditest.lua.
#   python3 gen_held_mid.py held.mid
#   .../kn7000 kn7000 -bios sp7001 -rompath ... -harddisk another_sd.img -midiin1 held.mid ...
import struct, sys
def vlq(n):
    b=[n&0x7F]; n>>=7
    while n: b.append((n&0x7F)|0x80); n>>=7
    return bytes(reversed(b))
div=480
ev=bytearray()
ev+=vlq(0)+bytes([0xFF,0x51,0x03])+struct.pack(">I",500000)[1:]  # 120 bpm
ev+=vlq(21120)+bytes([0x90,0x3C,0x64])  # ~22 s: note on C4, held
ev+=vlq(400)+bytes([0x90,0x43,0x64])    # G4
ev+=vlq(400)+bytes([0x90,0x40,0x64])    # E4
ev+=vlq(8000)+bytes([0xFF,0x2F,0x00])   # keep alive, end of track
trk=b"MTrk"+struct.pack(">I",len(ev))+bytes(ev)
open(sys.argv[1] if len(sys.argv)>1 else "held.mid","wb").write(
    b"MThd"+struct.pack(">IHHH",6,0,1,div)+trk)
