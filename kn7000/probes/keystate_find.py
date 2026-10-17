#!/usr/bin/env python3
# Find RAM bits/bytes that track held notes exactly, from awkeystate.lua's snapshots.
#   python3 -I keystate_find.py <snapdir>
import sys, numpy as np
d = sys.argv[1]
names = ["idle0","kb84","idle1","kb48","kb48_52","kb52","idle2","mi84","idle3","mi48","mi48_52","mi52","idle4"]
S = {n: np.frombuffer(open(f"{d}/{n}.bin","rb").read(), dtype=np.uint8) for n in names}
BASE = 0x50000000
held = {"kb84":{84},"kb48":{48},"kb48_52":{48,52},"kb52":{52},"mi84":{84},"mi48":{48},"mi48_52":{48,52},"mi52":{52}}
def pattern(note, srcs):
    return [note in held.get(n,set()) and n[:2] in srcs for n in names]
for srcs,label in ((("kb",),"keybed only"),(("mi",),"MIDI only"),(("kb","mi"),"keybed OR MIDI")):
    print(f"== {label} ==")
    for note in (84,48,52):
        pat = pattern(note, srcs)
        # bit candidates: bit set exactly in pattern snapshots
        found=[]
        for bit in range(8):
            ok = np.ones(len(S["idle0"]), dtype=bool)
            for n,p in zip(names,pat):
                b = (S[n] >> bit) & 1
                ok &= (b == (1 if p else 0))
            for a in np.nonzero(ok)[0][:12]: found.append(f"{BASE+a:08X}.{bit}")
        # byte candidates: nonzero exactly in pattern snapshots
        ok = np.ones(len(S["idle0"]), dtype=bool)
        for n,p in zip(names,pat): ok &= ((S[n]!=0) == p)
        byt=[f"{BASE+a:08X}" for a in np.nonzero(ok)[0][:12]]
        print(f"  note {note}: bits {found[:12]}  bytes {byt}")
# list-style candidates: a byte EQUAL to the note number exactly while that note is held
print("== byte == note exactly while held ==")
for srcs,label in ((("kb",),"keybed only"),(("mi",),"MIDI only"),(("kb","mi"),"keybed OR MIDI")):
    for note in (84,48,52):
        pat = pattern(note, srcs)
        ok = np.ones(len(S["idle0"]), dtype=bool)
        for n,p in zip(names,pat): ok &= ((S[n]==note) == p)
        print(f"  {label:15s} note {note}: {[f'{BASE+a:08X}' for a in np.nonzero(ok)[0][:16]]}")
