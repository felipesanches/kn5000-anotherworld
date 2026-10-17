#!/usr/bin/env python3
# Where did the KN7000's input handling differ from the canonical AW handling of the SAME presses?
#
# Rebuilds, from awmonitor's raw events file, the keys the player held at each ReadInput (tick),
# resolves them the way rustyworld's Vm::process_input does (RIGHT beats LEFT, DOWN beats UP), and
# compares with the hero vars the KN7000 actually applied (awmonitor's inputs file; row F drives
# tick F-1). Prints the disagreeing tick runs with the session time, so they can be found while
# watching the reference (replaywatch) and the KN7000.
#   python3 -I raw_vs_applied.py ~/compartilhado/tmp/aw-<session>   (prefix of the two files)
import sys
pre = sys.argv[1]
def bits(n):
    if n <= 0: return 0
    if n <= 60: return 0x80
    return {77: 2, 81: 4, 84: 1, 82: 8, 83: 8}.get(n, 0)
held = set(); raw = {}; t0 = None
for l in open(pre + '-events.csv'):
    c = l.strip().split(',')
    if c[0] == 'K':
        (held.add if c[4] == '1' else held.discard)(int(c[3]))
    elif c[0] == 'R':
        t = float(c[1]); t0 = t if t0 is None else t0
        b = int(c[4])
        for n in held: b |= bits(n)
        raw[int(c[2])] = (b, c[3], t - t0)
kn = {}
for l in open(pre + '-inputs.csv'):
    c = l.strip().split(',')
    if c[0].isdigit() and int(c[0]) >= 1: kn[int(c[0]) - 1] = (int(c[2]), int(c[3]), int(c[6]))
def canon(b): return (1 if b & 1 else (-1 if b & 2 else 0), 1 if b & 4 else (-1 if b & 8 else 0), 1 if b & 0x80 else 0)
def name(b): return '+'.join(n for m, n in ((2, 'LEFT'), (1, 'RIGHT'), (8, 'UP'), (4, 'DOWN'), (0x80, 'ACTION')) if b & m) or '-'
def vname(v):
    lr, ud, a = v; s = []
    if lr < 0: s.append('LEFT')
    if lr > 0: s.append('RIGHT')
    if ud < 0: s.append('UP')
    if ud > 0: s.append('DOWN')
    if a: s.append('ACTION')
    return '+'.join(s) or '-'
game = [t for t in sorted(raw) if raw[t][1] not in ('0000', '3E81') and t in kn]   # every playable part
diffs = [t for t in game if canon(raw[t][0]) != kn[t]]
runs = []
for t in diffs:
    if runs and t == runs[-1][1] + 1: runs[-1][1] = t
    else: runs.append([t, t])
print(f"gameplay ticks (all parts after the intro): {len(game)}; KN7000 applied != canonical handling of the held keys: "
      f"{len(diffs)} ticks in {len(runs)} runs")
for a, b in runs:
    print(f"  {raw[a][2]:6.1f}s  ticks {a:4d}-{b:4d} ({b-a+1:2d} frames): you held {name(raw[a][0]):<14}"
          f" reference applies {vname(canon(raw[a][0])):<14} KN7000 applied {vname(kn[a])}")
