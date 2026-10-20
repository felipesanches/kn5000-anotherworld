#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# cnv_layout.py -- does AW.CNV's memory map keep to the RAM a style converter may use?
#
# Question it answers, for the STYLE CONVERT build (src/platformcnv.inc): does every region the
# game uses lie in [AW_LO, AW_HI) -- the work RAM the firmware leaves untouched while a converter
# runs, measured on program 893 (research-scratch aw-memory-plan/taps893_ranges.out) -- clear of the
# mailbox page the firmware writes, and clear of every other region? Does each vm.inc field lie in
# its block? Does AW.CNV itself end below the font (IMAGE_END_MAX)? Prints the map as an aligned
# Markdown table (README-CNV.md carries it) and exits 1 on any problem.
#
#   python3 -I tools/cnv_layout.py src/platformcnv.inc src/vm.inc build/AW.map build/AW.CNV
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aw_extract import layout_consts  # noqa: E402

inc, vminc, amap, image = sys.argv[1:5]
L = layout_consts(inc)
problems = []
# the vm.inc blocks: their fields' offsets, from the .equ lines
BLOCKS = {"VM_POLY_BASE": 0x200, "VM_INTERP_BASE": 0x1100, "VM_MISC_BASE": 0x1400}
for line in open(vminc):
    m = re.match(r"\s*\.equ\s+(\w+)\s*,\s*(VM_\w+_BASE)\s*\+\s*(0x[0-9A-Fa-f]+)", line)
    if m and int(m.group(3), 16) >= BLOCKS[m.group(2)]:
        problems.append(f"vm.inc {m.group(1)} at {m.group(2)} + {m.group(3)} is outside its 0x{BLOCKS[m.group(2)]:X}-byte block")
# where AW.CNV ends, from the assembler's map
end = None
for line in open(amap):
    a, name = line.split()
    if name == "cnv_image_end":
        end = int(a, 16)
size = os.path.getsize(image)
if end is None or end != L["CNV_BASE"] + size:
    problems.append(f"the map's cnv_image_end ({end}) is not CNV_BASE + the file's {size} bytes")
if end and end > L["IMAGE_END_MAX"]:
    problems.append(f"AW.CNV ends at 0x{end:08X}, past IMAGE_END_MAX 0x{L['IMAGE_END_MAX']:08X}")
regions = [  # name, start, end, what
    ("AW.CNV", L["CNV_BASE"], L["IMAGE_END_MAX"], f"code and tables ({size:,} bytes, to 0x{(end or 0):08X})"),
    ("AW_FONT", L["AW_FONT"], L["AW_FONT"] + 768, "the 8x8 font, from AWFONT.AW"),
    ("AW_STRIDX", L["AW_STRIDX"], L["AW_STRIDX"] + 2048, "string index, from AWSTRIDX.AW"),
    ("AW_STRDAT", L["AW_STRDAT"], L["AW_STRDAT"] + 4096, "strings, from AWSTRDAT.AW"),
    ("CNV_VARS", L["CNV_VARS"], L["CNV_VARS"] + 0x400, "the converter's and loader's variables"),
    ("FW_VARS", L["FW_VARS"], L["FW_VARS"] + 0x100, "what fwfind.s found, and its scratch"),
    ("VM_POLY_BASE", L["VM_POLY_BASE"], L["VM_POLY_BASE"] + BLOCKS["VM_POLY_BASE"], "rasterizer scratch"),
    ("VM_INTERP_BASE", L["VM_INTERP_BASE"], L["VM_INTERP_BASE"] + BLOCKS["VM_INTERP_BASE"],
     "VM variables, threads, call stack"),
    ("VM_MISC_BASE", L["VM_MISC_BASE"], L["VM_MISC_BASE"] + BLOCKS["VM_MISC_BASE"],
     "input, help, guard, note trackers"),
    ("RES_TAB", L["RES_TAB"], L["RES_TAB"] + 4 * 146, "where each resource is now"),
    ("HELP_BUF", L["HELP_BUF"], L["HELP_BUF"] + 64000, "help pages, stop screen, bitmap unpacking"),
    ("VIDEO2_AT", L["VIDEO2_AT"], L["PART_AREA"], "the shared polygons (0x11)"),
    ("PART_AREA", L["PART_AREA"], L["PART_END"], "the current part's files"),
] + [(f"PAGE_BITMAP_{k}", L[f"PAGE_BITMAP_{k}"], L[f"PAGE_BITMAP_{k}"] + 64000, f"VM page {k}") for k in range(4)]
lo, hi, mb, mbe = L["AW_LO"], L["AW_HI"], L["MAILBOX_PAGE"], L["MAILBOX_PAGE_END"]
for name, a, b, _ in regions:
    if a < lo or b > hi:
        problems.append(f"{name} 0x{a:08X}-0x{b - 1:08X} is outside AW_LO..AW_HI")
    if a < mbe and b > mb:
        problems.append(f"{name} 0x{a:08X}-0x{b - 1:08X} overlaps the mailbox page")
srt = sorted(regions, key=lambda r: r[1])
for (n1, a1, b1, _), (n2, a2, b2, _) in zip(srt, srt[1:]):
    if a2 < b1:
        problems.append(f"{n1} and {n2} overlap")
if not (L["CNV_BASE"] <= L["MAILBOX"] - 0 and mb <= L["MAILBOX"] < mbe):
    problems.append("the mailbox is not on the mailbox page")
if L["PAGE_BITMAP_1"] - L["PAGE_BITMAP_0"] != 0x10000 or any(
        L[f"PAGE_BITMAP_{k + 1}"] - L[f"PAGE_BITMAP_{k}"] != 0x10000 for k in range(3)):
    problems.append("the pages are not 0x10000 apart (interp.s GetPagePtr)")
rows = [("range", "what")] + [(f"`0x{a:08X}`-`0x{b - 1:08X}`", f"{n}: {w}") for n, a, b, w in srt]
rows.insert(1 + next(i for i, r in enumerate(srt) if r[1] > mb), (f"`0x{mb:08X}`-`0x{mbe - 1:08X}`",
            "the firmware's mailbox page (0x5031BC00..): never written by the game but the request"))
w = [max(len(r[i]) for r in rows) for i in range(2)]
print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(rows[0])) + " |")
print("|" + "|".join("-" * (x + 2) for x in w) + "|")
for r in rows[1:]:
    print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |")
for p in problems:
    print("cnv_layout: " + p)
print(f"cnv_layout: {len(problems)} problem(s)" if problems else
      f"cnv_layout: ok -- everything in 0x{lo:08X}-0x{hi - 1:08X}, off the mailbox page, no overlaps")
sys.exit(1 if problems else 0)
