#!/usr/bin/env python3
# Key schedule for awpartkeys.lua on the level-code screen (0x3E88): enter a code on its letter
# grid with the keybed D-pad (F5 left, C6 right, A5 down, Bb5 up) and action (C3), then OK.
# The grid (seen on the screen): row 0 = B C D F G H OK, row 1 = J K L R T X DEL; the cursor
# starts on F. Prints AW_KEYS.   python3 -I probes/gen_code_keys.py [CODE=HTDC]
import sys
code = (sys.argv[1] if len(sys.argv) > 1 else "HTDC").upper()
grid = {c: (0, i) for i, c in enumerate("BCDFGH")}
grid.update({c: (1, i) for i, c in enumerate("JKLRTX")})
grid["OK"] = (0, 6)
pos, t, ev = (0, 3), 3.0, []
def press(note):
    global t
    ev.extend([f"{t:.2f}:{note}:1", f"{t + 0.3:.2f}:{note}:0"]); t += 0.7
for target in list(code) + ["OK"]:
    r, c = grid[target]
    while pos[0] < r: press(81); pos = (pos[0] + 1, pos[1])
    while pos[0] > r: press(82); pos = (pos[0] - 1, pos[1])
    while pos[1] < c: press(84); pos = (pos[0], pos[1] + 1)
    while pos[1] > c: press(77); pos = (pos[0], pos[1] - 1)
    press(48)
print(",".join(ev))
