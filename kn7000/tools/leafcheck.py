#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# leafcheck.py -- does any routine entered with `call X, 0, 0` call something before it has moved
# sp? On the MN10300 such a `call` stores the return address at (sp) and leaves sp where it was,
# so a nested call or calls from the callee overwrites that slot and the final `rets` jumps into
# the weeds. That is how AW.CNV's first ByteKiller hung (GetBits called ReadBE). A routine may
# call others once it has made a frame: `movm [...], (sp)` or `add -N, sp`.
#
# The check is linear: from each call target's label to the next call target's label, it reports
# a call/calls seen while no frame has been made. Exit status 1 when it finds one.
#   python3 -I tools/leafcheck.py src/*.s
import re
import sys

LABEL = re.compile(r"^([A-Za-z_][\w.]*):")
CALL = re.compile(r"^\s*call\s+([A-Za-z_][\w.]*)\s*,\s*(?:0|\[\])\s*,\s*0\b")
ANYCALL = re.compile(r"^\s*calls?\s")
FRAME = re.compile(r"^\s*(movm\s+\[[^\]]*\]\s*,\s*\(sp\)|add\s+-\w+\s*,\s*sp)")

lines = [(f, n + 1, l.split("#")[0].rstrip()) for f in sys.argv[1:] for n, l in enumerate(open(f))]
targets = {m.group(1) for _, _, l in lines if (m := CALL.match(l))}
bad, routine, framed = 0, None, False
for f, n, l in lines:
    m = LABEL.match(l)
    if m and m.group(1) in targets:
        routine, framed = m.group(1), False
        continue
    if routine is None:
        continue
    if FRAME.match(l):
        framed = True
    elif ANYCALL.match(l) and not framed:
        print(f"{f}:{n}: {routine} is entered with `call ..., 0, 0` and calls before making a frame: {l.strip()}")
        bad += 1
print(f"leafcheck: {len(targets)} call targets, {bad} unsafe nested calls")
sys.exit(1 if bad else 0)
