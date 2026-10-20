#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# lcd_cost.py -- what would a frame's LCD stores cost on the instrument? (probes/cnv/README.md, "Speed")
#
# MAME counts the game's stores into the LCD frame per VM tick (awcnv_perf.lua: perf.tsv, lcd_w16 and
# lcd_w32), but has no wait states. The firmware programs the bus controller for the region the LCD
# frame lies in (0x98000000-0x9FFFFFFF, the DSP's latch and data port too: MEMCTR3 at 0x32000026) to
# 0x0424 or 0x0704, depending on a board strap it reads at 0x98070000 (941 0x484D7111), and raises it
# to 0x0924 around each DSP data-port access: bits 8-12 look like a wait count (4, 7; 9 for the DSP).
# This prints, for each perf.tsv, the mean stores per tick and their cost under a model: an access is
# (2 + waits) cycles of the bus clock, a 32-bit store on a 16-bit bus two accesses. Neither the bus
# clock nor the width is known for the LCD region: the defaults (16 MHz, 16 bits) are a guess. With
# --w16-ns/--w32-ns (the instrument's own benchmark, the help screen's fourth page or AWPERF.TXT) the
# measured costs replace the model.
#   python3 -I probes/cnv/lcd_cost.py OLD/perf.tsv NEW/perf.tsv [--bus-mhz 16] [--w16-ns N --w32-ns N]
import argparse
import csv


def means(path):
    rows = list(csv.DictReader(open(path), delimiter="\t"))
    n = len(rows)
    return n, {k: sum(float(r[k]) for r in rows) / n for k in ("lcd_w16", "lcd_w32", "lcd_r", "dt_ms")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv", nargs="+")
    ap.add_argument("--bus-mhz", type=float, default=16.0)
    ap.add_argument("--w16-ns", type=float)
    ap.add_argument("--w32-ns", type=float)
    a = ap.parse_args()
    cyc = 1000.0 / a.bus_mhz
    models = [(f"{w} waits, {a.bus_mhz:g} MHz, 16-bit bus", (2 + w) * cyc, 2 * (2 + w) * cyc) for w in (4, 7)]
    if a.w16_ns and a.w32_ns:
        models.append(("measured on the instrument", a.w16_ns, a.w32_ns))
    head = ["perf.tsv", "ticks", "16-bit stores", "32-bit stores"] + [f"ms per tick: {m[0]}" for m in models]
    rows = []
    for p in a.tsv:
        n, m = means(p)
        rows.append([p, str(n), f"{m['lcd_w16']:,.0f}", f"{m['lcd_w32']:,.0f}"]
                    + [f"{(m['lcd_w16'] * c16 + m['lcd_w32'] * c32) / 1e6:.1f}" for _, c16, c32 in models])
    w = [max(len(r[i]) for r in [head] + rows) for i in range(len(head))]
    print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(head)) + " |")
    print("|" + "|".join("-" * (x + 2) for x in w) + "|")
    for r in rows:
        print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |")
    for name, c16, c32 in models:
        print(f"lcd_cost: {name}: {c16:.0f} ns per 16-bit store, {c32:.0f} ns per 32-bit store")


if __name__ == "__main__":
    main()
