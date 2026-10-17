#!/usr/bin/env python3
# Key schedule for awpartkeys.lua: rock the prison cage -- alternate F5 (left) and C6 (right),
# 0.4 s each, for 16 s, starting 4 s after the part starts. Prints AW_KEYS.
ev, t = [], 4.0
for i in range(40):
    n = 77 if i % 2 == 0 else 84
    ev += [f"{t:.2f}:{n}:1", f"{t + 0.35:.2f}:{n}:0"]
    t += 0.4
print(",".join(ev))
