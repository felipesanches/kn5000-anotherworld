#!/usr/bin/env python3
# Fit awloadtime.lua's per-file timings: seconds per file = overhead + bytes / rate.
#   python3 -I probes/awloadtime_fit.py <loadtime.txt> <build/res>
# loadtime.txt has one fread-start time per line (the font, the string index, the string data,
# then each pack AWPkk) and a final "<time> done"; a file's time is the gap to the next line.
import os, sys
lines = [l.split() for l in open(sys.argv[1]) if l.strip()]
times = [float(c[0]) for c in lines]
packs = sorted(f for f in os.listdir(sys.argv[2]) if f.startswith("AWP") and f.endswith(".bin"))
sizes = [768, 2048, 4096] + [os.path.getsize(os.path.join(sys.argv[2], f)) for f in packs]
if len(times) != len(sizes) + 1:
    sys.exit(f"expected {len(sizes) + 1} timestamps (files + done), got {len(times)}")
ys = [b - a for a, b in zip(times, times[1:])]
n = len(sizes); mx = sum(sizes) / n; my = sum(ys) / n
b = sum((x - mx) * (y - my) for x, y in zip(sizes, ys)) / sum((x - mx) ** 2 for x in sizes)
a = my - b * mx
print(f"{n} files ({n - 3} packs), {sum(sizes)} bytes in {sum(ys):.2f} s: overhead {a * 1000:.0f} ms per "
      f"file, data {1 / b / 1024:.0f} KiB/s; small files took {', '.join(f'{y * 1000:.0f}' for y in ys[:3])} ms")
