#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# lcd_cost.py -- what would a frame's LCD stores cost on the instrument? (probes/cnv/README.md, "Speed")
#
# MAME counts the game's stores into the LCD frame per VM tick (awcnv_perf.lua: perf.tsv, lcd_w16 and
# lcd_w32) and its loads from it (lcd_r), but has no wait states. This prints, for each perf.tsv, the mean
# accesses per tick and what they cost at the times the ROM dumper's pass 9 measured on the owner's unit
# (technics-roms-disasm cnv_romdump, 2026-10-20: a 16-bit bus to the LCD frame, a 16-bit store 439 ns, a
# 32-bit store 888 ns, a 16-bit load 694 ns; the firmware leaves MEMCTR3, which covers the region, at
# 0x0424). Before that measurement the model was a guess: an access of (2 + waits) cycles of a 16 MHz bus
# clock, 4 or 7 waits (MEMCTR3 0x0424 or 0x0704 by the board strap); --model prints those too. Other
# figures (the game's own benchmark, the help screen's fourth page or AWPERFn.TXT) go in with --w16-ns,
# --w32-ns and --r16-ns.
#   python3 -I probes/cnv/lcd_cost.py OLD/perf.tsv NEW/perf.tsv [--model] [--w16-ns N --w32-ns N --r16-ns N]
import argparse
import csv


def means(path):
    rows = list(csv.DictReader(open(path), delimiter="\t"))
    n = len(rows)
    return n, {k: sum(float(r[k]) for r in rows) / n for k in ("lcd_w16", "lcd_w32", "lcd_r", "dt_ms")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv", nargs="+")
    ap.add_argument("--model", action="store_true", help="also the wait-state guess (16 MHz bus, 4 or 7 waits)")
    ap.add_argument("--w16-ns", type=float)
    ap.add_argument("--w32-ns", type=float)
    ap.add_argument("--r16-ns", type=float)
    a = ap.parse_args()
    models = [("pass 9", 439.3, 888.5, 693.6)]
    if a.model:
        models += [(f"guess, {w} waits", (2 + w) * 62.5, 2 * (2 + w) * 62.5, (2 + w) * 62.5) for w in (4, 7)]
    if a.w16_ns and a.w32_ns:
        models.append(("given", a.w16_ns, a.w32_ns, a.r16_ns or 0.0))
    head = ["perf.tsv", "ticks", "16-bit stores", "32-bit stores", "16-bit loads"] + [f"LCD ms per tick, {m[0]}" for m in models]
    rows = []
    for p in a.tsv:
        n, m = means(p)
        rows.append([p, str(n), f"{m['lcd_w16']:,.0f}", f"{m['lcd_w32']:,.0f}", f"{m['lcd_r']:,.0f}"]
                    + [f"{(m['lcd_w16'] * c16 + m['lcd_w32'] * c32 + m['lcd_r'] * r16) / 1e6:.2f}" for _, c16, c32, r16 in models])
    w = [max(len(r[i]) for r in [head] + rows) for i in range(len(head))]
    print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(head)) + " |")
    print("|" + "|".join("-" * (x + 2) for x in w) + "|")
    for r in rows:
        print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |")
    for name, c16, c32, r16 in models:
        print(f"lcd_cost: {name}: {c16:.0f} ns per 16-bit store, {c32:.0f} ns per 32-bit store, {r16:.0f} ns per 16-bit load")


if __name__ == "__main__":
    main()
