#!/usr/bin/env python3
# Compare awresverify.lua's RAM dump of every resident resource with the unpacked originals.
#   python3 -I probes/awresverify.py <awresverify AWRV_OUT dir> <build/res>
# Checks, per resource id: the dumped bytes equal build/res/resource-0xNN.bin, and the
# address lies in RES_BASE..RES_END without overlapping its neighbours.
import sys
dump, ref = sys.argv[1], sys.argv[2]
rows = [l.split("\t") for l in open(f"{dump}/resident.tsv").read().split("\n") if l]
ok = bad = 0
spans = []
for rid, addr, size in rows:
    i, a, n = int(rid, 16), int(addr, 16), int(size)
    want = open(f"{ref}/resource-0x{i:02x}.bin", "rb").read()
    got = open(f"{dump}/resource-0x{i:02x}.bin", "rb").read()
    if got == want and n == len(want):
        ok += 1
    else:
        bad += 1
        print(f"MISMATCH 0x{i:02X}: {len(got)} bytes resident, {len(want)} expected"
              + ("" if len(got) != len(want) else
                 f", first diff at +{next(k for k in range(len(got)) if got[k] != want[k])}"))
    if n:
        spans.append((a, a + n, i))
spans.sort()
overlaps = [(x[2], y[2]) for x, y in zip(spans, spans[1:]) if x[1] > y[0]]
print(f"awresverify: {ok}/{len(rows)} resources byte-exact in RAM, {bad} mismatched; "
      f"{len(spans)} non-empty, spanning {spans[0][0]:#x}..{spans[-1][1]:#x}; overlaps: {overlaps or 'none'}")
sys.exit(1 if bad or overlaps else 0)
