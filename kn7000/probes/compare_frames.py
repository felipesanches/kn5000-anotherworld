#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# Diff two per-frame checksum logs ("<tick> <crc32hex>" per line): our KN7000
# port (probes/cksum_pages.py) vs the reference VM (rustyworld refcksum). Both
# are keyed by VM tick/frame number, so comparison is tick-for-tick. Reports the
# count that match, the FIRST diverging frame (the one to investigate), and the
# contiguous ranges of divergence -- the grounding to localize rendering bugs.
#
#   python3 -I compare_frames.py <ours.log> <reference.log>
import sys

def load(path):
    d = {}
    for line in open(path):
        line = line.split()
        if len(line) >= 2:
            d[int(line[0])] = line[1].lower()
    return d

def ranges(ticks):
    ticks = sorted(ticks)
    out = []
    for t in ticks:
        if out and t == out[-1][1] + 1:
            out[-1][1] = t
        else:
            out.append([t, t])
    return out

def main():
    ours = load(sys.argv[1])
    ref = load(sys.argv[2])
    common = sorted(set(ours) & set(ref))
    if not common:
        print("no common ticks!"); return
    lo, hi = common[0], common[-1]
    diffs = [t for t in common if ours[t] != ref[t]]
    match = len(common) - len(diffs)
    print(f"ours={len(ours)} frames, ref={len(ref)} frames, "
          f"common ticks {lo}..{hi} ({len(common)})")
    print(f"  match:  {match}/{len(common)}  ({100*match/len(common):.2f}%)")
    print(f"  differ: {len(diffs)}")
    only_ours = sorted(set(ours) - set(ref))
    only_ref = sorted(set(ref) - set(ours))
    if only_ours:
        print(f"  ticks only in ours: {len(only_ours)} (e.g. {only_ours[:5]})")
    if only_ref:
        print(f"  ticks only in ref:  {len(only_ref)} (e.g. {only_ref[:5]})")
    if not diffs:
        print("  ALL COMMON FRAMES IDENTICAL.")
        return
    print(f"  FIRST divergence at tick {diffs[0]}: "
          f"ours={ours[diffs[0]]} ref={ref[diffs[0]]}")
    rs = ranges(diffs)
    print(f"  diverging ranges ({len(rs)}):")
    for a, b in rs[:40]:
        print(f"    {a}..{b}" + (f"  ({b-a+1} frames)" if b > a else ""))
    if len(rs) > 40:
        print(f"    ... and {len(rs)-40} more ranges")

if __name__ == "__main__":
    main()
