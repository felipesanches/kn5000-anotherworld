#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# aw_partinfo.py -- what does each Another World part need from the engine?
#
# Decodes every part's bytecode linearly (operand sizes as the original engine / rawgl reads
# them; AW bytecode carries no inline data, so a linear sweep visits every instruction) and
# reports, per part: its resources, the opcodes it uses, and every resource its code references
# -- sounds (0x18 PLAY_SOUND), music (0x1A PLAY_MUSIC), loads (0x19: bitmaps, sounds, music,
# part switches) -- and whether it reads var 0xF4 (the music player's sync mark) or 0xDA (the
# last typed character, password entry). Emits a Markdown table, aligned.
#   python3 -I tools/aw_partinfo.py build/res [--compact]   (after aw_extract.py; --compact counts
#   the sound ids instead of listing them)
import sys

PARTS = [  # id, name, palette, code, video1, video2 -- rustyworld GAME_PARTS / rawgl
    (0x3E80, "protection", 0x14, 0x15, 0x16, 0x00),
    (0x3E81, "intro", 0x17, 0x18, 0x19, 0x00),
    (0x3E82, "water", 0x1A, 0x1B, 0x1C, 0x11),
    (0x3E83, "prison", 0x1D, 0x1E, 0x1F, 0x11),
    (0x3E84, "city", 0x20, 0x21, 0x22, 0x11),
    (0x3E85, "arena", 0x23, 0x24, 0x25, 0x00),
    (0x3E86, "baths", 0x26, 0x27, 0x28, 0x11),
    (0x3E87, "final", 0x29, 0x2A, 0x2B, 0x11),
    (0x3E88, "password", 0x7D, 0x7E, 0x7F, 0x00),
]
NAMES = {0x00: "movConst", 0x01: "mov", 0x02: "add", 0x03: "addConst", 0x04: "call", 0x05: "ret",
         0x06: "yield", 0x07: "jmp", 0x08: "installTask", 0x09: "jnz", 0x0A: "condJmp",
         0x0B: "setPalette", 0x0C: "changeTasks", 0x0D: "selectPage", 0x0E: "fillPage",
         0x0F: "copyPage", 0x10: "updateDisplay", 0x11: "killTask", 0x12: "drawString",
         0x13: "sub", 0x14: "and", 0x15: "or", 0x16: "shl", 0x17: "shr", 0x18: "playSound",
         0x19: "load", 0x1A: "playMusic"}
FIXED = {0x00: 3, 0x01: 2, 0x02: 2, 0x03: 3, 0x04: 2, 0x05: 0, 0x06: 0, 0x07: 2, 0x08: 3, 0x09: 3,
         0x0B: 2, 0x0C: 3, 0x0D: 1, 0x0E: 2, 0x0F: 2, 0x10: 1, 0x11: 0, 0x12: 5, 0x13: 2, 0x14: 3,
         0x15: 3, 0x16: 3, 0x17: 3, 0x18: 5, 0x19: 2, 0x1A: 5}


def decode(code):
    pc, ops, sounds, music, loads, bad = 0, {}, set(), set(), set(), 0
    reads = set()                                       # variables the code reads
    while pc < len(code):
        op = code[pc]; pc += 1
        if op & 0x80:                                   # polygon from video1, background
            ops["poly80"] = ops.get("poly80", 0) + 1
            pc += 3
        elif op & 0x40:                                 # polygon, positioned / zoomed
            ops["poly40"] = ops.get("poly40", 0) + 1
            pc += 2                                     # offset
            if op & 0x30 == 0x10:
                reads.add(code[pc])
            pc += {0x00: 2, 0x10: 1, 0x20: 1, 0x30: 1}[op & 0x30]
            if op & 0x0C == 0x04:
                reads.add(code[pc])
            pc += {0x00: 2, 0x04: 1, 0x08: 1, 0x0C: 1}[op & 0x0C]
            if op & 0x03 == 0x01:
                reads.add(code[pc])
            pc += {0x00: 0, 0x01: 1, 0x02: 1, 0x03: 0}[op & 0x03]
        elif op == 0x0A:
            ops["condJmp"] = ops.get("condJmp", 0) + 1
            m = code[pc]; reads.add(code[pc + 1]); pc += 2
            if m & 0x80:
                reads.add(code[pc])
            pc += 1 if m & 0x80 else (2 if m & 0x40 else 1)
            pc += 2
        elif op in FIXED:
            ops[NAMES[op]] = ops.get(NAMES[op], 0) + 1
            if op == 0x18:
                sounds.add((code[pc] << 8) | code[pc + 1])
            elif op == 0x1A:
                music.add((code[pc] << 8) | code[pc + 1])
            elif op == 0x19:
                loads.add((code[pc] << 8) | code[pc + 1])
            elif op in (0x01, 0x09):                    # mov dst,src / jnz var
                reads.add(code[pc + 1] if op == 0x01 else code[pc])
            elif op in (0x02, 0x13):                    # add/sub dst,src
                reads.update((code[pc], code[pc + 1]))
            elif op in (0x03, 0x14, 0x15, 0x16, 0x17):  # addConst/and/or/shl/shr var,imm
                reads.add(code[pc])
            pc += FIXED[op]
        else:
            bad += 1
    return ops, sounds, music, loads, bad, reads


def main():
    res = sys.argv[1]
    types = {}
    for line in open(f"{res}/memlist.tsv").read().split("\n")[1:]:
        if line:
            c = line.split("\t")
            types[int(c[0], 16)] = c[1]
    rows = [("part", "name", "pal/code/vid1/vid2", "code bytes", "opcodes used", "sounds",
             "music", "bitmaps loaded", "other loads", "switches to", "reads F4/DA", "bad ops")]
    allops = set()
    for pid, name, pal, cod, v1, v2 in PARTS:
        code = open(f"{res}/resource-0x{cod:02x}.bin", "rb").read()
        ops, snd, mus, lds, bad, rd = decode(code)
        allops |= set(ops)
        bm = sorted(i for i in lds if i < 0x92 and types.get(i) == "bitmap")
        other = sorted(i for i in lds if i < 0x92 and types.get(i) != "bitmap")
        sw = sorted(i for i in lds if i >= 0x3E80)
        h = lambda s: ",".join(f"{i:02X}" for i in sorted(s)) or "-"
        rows.append((f"{pid:04X}", name, f"{pal:02X}/{cod:02X}/{v1:02X}/{v2:02X}" if v2 else f"{pal:02X}/{cod:02X}/{v1:02X}/-",
                     str(len(code)), str(len(ops)), h(snd), h(mus), h(bm), h(other),
                     ",".join(f"{i:04X}" for i in sw) or "-",
                     ("F4" if 0xF4 in rd else "-") + "/" + ("DA" if 0xDA in rd else "-"), str(bad)))
    if "--compact" in sys.argv:                         # sound / other-load lists -> counts
        keep = [0, 1, 2, 3, 5, 6, 7, 9, 10]
        rows = [tuple(r[i] if k == 0 or i not in (5,) else str(len(r[i].split(",")) if r[i] != "-" else 0)
                      for i in keep) for k, r in enumerate(rows)]
        rows[0] = ("part", "name", "pal/code/vid1/vid2", "code bytes", "sound ids", "music", "bitmaps",
                   "switches to", "reads F4/DA")
    w = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    fmt = lambda r: "| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |"
    print(fmt(rows[0]))
    print("|" + "|".join("-" * (x + 2) for x in w) + "|")
    for r in rows[1:]:
        print(fmt(r))
    print(f"\nopcodes used across all parts: {len(allops)} ({', '.join(sorted(allops))})")


if __name__ == "__main__":
    main()
