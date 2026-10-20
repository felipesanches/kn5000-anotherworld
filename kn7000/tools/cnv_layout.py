#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# cnv_layout.py -- does KN7APP.BIN's memory map keep to the RAM a style converter may use, clear of
# the loader that runs it?
#
# Question it answers, for the KN7APP.BIN build (src/platformcnv.inc, with the loader's contract
# kn7cnv.inc): does every region the game uses lie in [AW_LO, AW_HI) -- the work RAM the firmware
# leaves untouched while a converter runs, measured on program 893 (research-scratch
# aw-memory-plan/taps893_ranges.out) -- clear of the mailbox page the firmware writes, clear of the
# loader's resident area [CNV_BASE, APP_BASE) (KN7LOAD.CNV's code, line buffer, variables and service
# table), and clear of every other region? Is AW_LO the loader's APP_BASE, and does platformcnv.inc
# leave the contract's names to kn7cnv.inc? Do the loader's own pieces (its image, given as
# LOADER.CNV, its line buffer, variables and service table) lie below APP_BASE? Does each vm.inc field
# lie in its block? Does KN7APP.BIN start at APP_BASE with its header and end below the font
# (IMAGE_END_MAX)? Prints the map as an aligned Markdown table (README-CNV.md carries it) and exits 1
# on any problem.
#
#   python3 -I tools/cnv_layout.py KN7CNV.INC src/platformcnv.inc src/vm.inc build/kn7app.map \
#       build/kn7app.bin [LOADER.CNV]
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aw_extract import layout_consts  # noqa: E402

import hashlib  # noqa: E402

cinc, inc, vminc, amap, image = sys.argv[1:6]
loader_cnv = sys.argv[6] if len(sys.argv) > 6 else None
C = layout_consts(cinc)                      # the contract alone
L = layout_consts([cinc, inc])               # what the assembler sees: kn7cnv.inc, then platformcnv.inc
problems = []
twice = sorted(set(C) & set(layout_consts(inc)))
if twice:
    problems.append(f"platformcnv.inc defines the contract's names again: {', '.join(twice)}")
if L["AW_LO"] != C["APP_BASE"]:
    problems.append(f"AW_LO 0x{L['AW_LO']:08X} is not the loader's APP_BASE 0x{C['APP_BASE']:08X}")
sv_end = C["SVC"] + max(v for k, v in C.items() if k.startswith("SV_")) + 4
lsize = os.path.getsize(loader_cnv) if loader_cnv else None
loader = [  # the loader's resident pieces (kn7cnv.inc, loader.s): name, start, end, what
    ("KN7LOAD.CNV", C["CNV_BASE"], C["CNV_BASE"] + (lsize or 0x1C00),
     f"the loader's image ({lsize:,} bytes, SHA-1 {hashlib.sha1(open(loader_cnv, 'rb').read()).hexdigest()[:8]}...)"
     if lsize else "the loader's image (at most 0x1C00 bytes: its Makefile)"),
    ("LV_STR", C["LOADER_VARS"] - 0x100, C["LOADER_VARS"] - 0x80, "the loader's line buffer"),
    ("LOADER_VARS", C["LOADER_VARS"], C["LOADER_VARS"] + 0x100, "the loader's variables and the saved SD folder"),
    ("SVC", C["SVC"], sv_end, "the loader's service table (the game reads it)"),
]
for name, a, b, _ in loader:
    if a < C["CNV_BASE"] or b > C["APP_BASE"]:
        problems.append(f"the loader's {name} 0x{a:08X}-0x{b - 1:08X} is not below APP_BASE")
if lsize and lsize > C["LOADER_VARS"] - 0x100 - C["CNV_BASE"]:
    problems.append(f"the loader's image ({lsize} bytes) reaches its line buffer")
# the vm.inc blocks: their fields' offsets, from the .equ lines
BLOCKS = {"VM_POLY_BASE": 0x200, "VM_INTERP_BASE": 0x1100, "VM_MISC_BASE": 0x1400}
for line in open(vminc):
    m = re.match(r"\s*\.equ\s+(\w+)\s*,\s*(VM_\w+_BASE)\s*\+\s*(0x[0-9A-Fa-f]+)", line)
    if m and int(m.group(3), 16) >= BLOCKS[m.group(2)]:
        problems.append(f"vm.inc {m.group(1)} at {m.group(2)} + {m.group(3)} is outside its 0x{BLOCKS[m.group(2)]:X}-byte block")
# where AW.CNV ends, from the assembler's map
end = head = None
for line in open(amap):
    a, name = line.split()
    if name == "cnv_image_end":
        end = int(a, 16)
    if name == "AppHeader":
        head = int(a, 16)
size = os.path.getsize(image)
img = open(image, "rb").read(0x18)
if head != C["APP_BASE"] or img[:4] != b"KN7A" or int.from_bytes(img[0x14:0x18], "little") != C["APP_BASE"]:
    problems.append(f"the image does not start at APP_BASE with its header (AppHeader {head}, magic {img[:4]!r})")
if int.from_bytes(img[4:8], "little") != C["LOADER_ABI"]:
    problems.append("the header's loader ABI is not kn7cnv.inc's LOADER_ABI")
if end is None or end != C["APP_BASE"] + size:
    problems.append(f"the map's cnv_image_end ({end}) is not APP_BASE + the file's {size} bytes")
if end and end > L["IMAGE_END_MAX"]:
    problems.append(f"KN7APP.BIN ends at 0x{end:08X}, past IMAGE_END_MAX 0x{L['IMAGE_END_MAX']:08X}")
regions = [  # name, start, end, what
    ("KN7APP.BIN", C["APP_BASE"], L["IMAGE_END_MAX"], f"header, code and tables ({size:,} bytes, to 0x{(end or 0):08X})"),
    ("AW_FONT", L["AW_FONT"], L["AW_FONT"] + 768, "the 8x8 font, from AWFONT.AW"),
    ("AW_STRIDX", L["AW_STRIDX"], L["AW_STRIDX"] + 2048, "string index, from AWSTRIDX.AW"),
    ("AW_STRDAT", L["AW_STRDAT"], L["AW_STRDAT"] + 4096, "strings, from AWSTRDAT.AW"),
    ("CNV_VARS", L["CNV_VARS"], L["CNV_VARS"] + 0x400, "the entry's and the part loader's variables"),
    ("FW_VARS", L["FW_VARS"], L["FW_VARS"] + 0x100, "what fwfind.s found, and its scratch"),
    ("AW_PATHS", L["AW_PATHS"], L["AW_PATHS"] + L["AW_PATHS_LEN"], "the game's folder, from the menu's launch block"),
    ("VM_POLY_BASE", L["VM_POLY_BASE"], L["VM_POLY_BASE"] + BLOCKS["VM_POLY_BASE"], "rasterizer scratch"),
    ("VM_INTERP_BASE", L["VM_INTERP_BASE"], L["VM_INTERP_BASE"] + BLOCKS["VM_INTERP_BASE"],
     "VM variables, threads, call stack"),
    ("VM_MISC_BASE", L["VM_MISC_BASE"], L["VM_MISC_BASE"] + BLOCKS["VM_MISC_BASE"],
     "input, help, guard, note trackers"),
    ("RES_TAB", L["RES_TAB"], L["RES_TAB"] + 4 * 146, "where each resource is now"),
    ("HELP_BUF", L["HELP_BUF"], L["HELP_BUF"] + 64000, "help pages, stop screen, bitmap unpacking"),
    ("VIDEO2_AT", L["VIDEO2_AT"], L["PART_AREA"], "the shared polygons (0x11)"),
    ("PART_AREA", L["PART_AREA"], L["PART_END"], "the current part's files"),
    ("LB_ADDR", C["LB_ADDR"], C["LB_ADDR"] + C["LB_LEN"], "the program menu's launch block (kn7cnv.inc): read, never ours"),
] + [(f"PAGE_BITMAP_{k}", L[f"PAGE_BITMAP_{k}"], L[f"PAGE_BITMAP_{k}"] + 64000, f"VM page {k}") for k in range(4)]
lo, hi, mb, mbe = L["AW_LO"], L["AW_HI"], L["MAILBOX_PAGE"], L["MAILBOX_PAGE_END"]
for name, a, b, _ in regions:
    if a < lo or b > hi:
        problems.append(f"{name} 0x{a:08X}-0x{b - 1:08X} is outside AW_LO..AW_HI")
    if a < mbe and b > mb:
        problems.append(f"{name} 0x{a:08X}-0x{b - 1:08X} overlaps the mailbox page")
    if a < C["APP_BASE"] and b > C["CNV_BASE"]:
        problems.append(f"{name} 0x{a:08X}-0x{b - 1:08X} overlaps the loader's resident area")
srt = sorted(regions, key=lambda r: r[1])
for (n1, a1, b1, _), (n2, a2, b2, _) in zip(srt, srt[1:]):
    if a2 < b1:
        problems.append(f"{n1} and {n2} overlap")
if not (mb <= C["MAILBOX"] < mbe):
    problems.append("the mailbox is not on the mailbox page")
if L["PAGE_BITMAP_1"] - L["PAGE_BITMAP_0"] != 0x10000 or any(
        L[f"PAGE_BITMAP_{k + 1}"] - L[f"PAGE_BITMAP_{k}"] != 0x10000 for k in range(3)):
    problems.append("the pages are not 0x10000 apart (interp.s GetPagePtr)")
rows = [("range", "what")] + [(f"`0x{a:08X}`-`0x{b - 1:08X}`", f"{n}: {w}") for n, a, b, w in loader + srt]
rows.insert(1 + len(loader) + next(i for i, r in enumerate(srt) if r[1] > mb), (f"`0x{mb:08X}`-`0x{mbe - 1:08X}`",
            "the firmware's mailbox page (0x5031BC00..): never written by the game but the request"))
w = [max(len(r[i]) for r in rows) for i in range(2)]
print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(rows[0])) + " |")
print("|" + "|".join("-" * (x + 2) for x in w) + "|")
for r in rows[1:]:
    print("| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |")
for p in problems:
    print("cnv_layout: " + p)
print(f"cnv_layout: {len(problems)} problem(s)" if problems else
      f"cnv_layout: ok -- everything in 0x{lo:08X}-0x{hi - 1:08X}, off the mailbox page and the loader's "
      f"0x{C['CNV_BASE']:08X}-0x{C['APP_BASE'] - 1:08X}, no overlaps")
sys.exit(1 if problems else 0)
