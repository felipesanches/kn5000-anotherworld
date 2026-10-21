#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
"""round3_report.py OUT -- what run_round3.sh's session (awcnv_round3.lua) shows: the bank's timing (OUT/bank.txt; the
second start's, which finds the bank there, OUT/bank2.txt),
and, in a full session, the level of the recording (OUT/run.wav) in each "keys window": the instrument's own sound
of a held key with the keybed sound on (on1, on2), off (off), and after the quit (after). The game's own sound is
OFF during on1/off/on2, and the game has left before "after"."""
import os
import re
import sys
import wave

import numpy as np

OUT = sys.argv[1]
for name in ("bank.txt", "bank2.txt"):
    bank = os.path.join(OUT, name)
    if os.path.exists(bank):
        print(f"# {name}")
        print(open(bank).read().rstrip())
wins = []
for ln in open(os.path.join(OUT, "events.txt")):
    m = re.search(r"keys window (\S+) ([\d.]+) ([\d.]+)", ln)
    if m:
        wins.append((m.group(1), float(m.group(2)), float(m.group(3))))
wav = os.path.join(OUT, "run.wav")
if wins and os.path.exists(wav):
    w = wave.open(wav)
    sr, ch = w.getframerate(), w.getnchannels()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float).mean(axis=1)
    for name, t0, t1 in wins:
        s = x[int(t0 * sr):int(t1 * sr)]
        rms = np.sqrt(np.mean(s ** 2)) if len(s) else 0.0
        db = 20 * np.log10(rms / 32768) if rms > 0 else -999.0
        print(f"keys window {name:6s} {t0:8.2f}-{t1:8.2f} s: {db:7.1f} dBFS, peak {np.max(np.abs(s)) if len(s) else 0:6.0f}")
