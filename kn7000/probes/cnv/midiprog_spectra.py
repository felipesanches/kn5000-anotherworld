#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# midiprog_spectra.py WAV LOG -- the reading of awcnv_midiprog.lua's recording: for each segment of its
# schedule (seconds after "game running at t=..." in LOG), the spectral flatness (1 noise, 0 tones),
# the five strongest peaks (Hz), the level in five slices (dBFS) and the first six harmonics of C4
# (261.6 Hz) relative to the first (dB): a square wave shows the even ones about 50 dB down.
import re
import sys
import wave

import numpy as np

w = wave.open(sys.argv[1]); sr = w.getframerate(); ch = w.getnchannels()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float).mean(axis=1)
t3 = float(re.search(r"game running at t=([\d.]+)", open(sys.argv[2]).read()).group(1))


def seg(a, b, label):
    s = x[int((t3 + a) * sr):int((t3 + b) * sr)]
    if len(s) == 0:
        print(label, "none")
        return
    S = np.abs(np.fft.rfft(s * np.hanning(len(s)))) + 1e-9
    f = np.fft.rfftfreq(len(s), 1 / sr)
    band = (f > 50) & (f < 8000)
    flat = np.exp(np.mean(np.log(S[band] ** 2))) / np.mean(S[band] ** 2)
    pk = []
    for i in np.argsort(S * band)[::-1]:
        if all(abs(f[i] - p) > 15 for p in pk):
            pk.append(f[i])
        if len(pk) == 5:
            break
    env = [20 * np.log10(np.sqrt(np.mean(c ** 2)) / 32768 + 1e-12) for c in np.array_split(s, 5)]
    h = [S[np.argmin(abs(f - k * 261.6))] for k in range(1, 7)]
    print(f"{label:28s} flat {flat:.3f} peaks {[round(p) for p in pk]} env {[round(e) for e in env]} "
          f"harm {[round(20 * np.log10(v / h[0])) for v in h]}")


for a, b, label in ((3.0, 3.9, "silence before"), (4.0, 5.0, "A PART 4 as is, C4"), (6.2, 7.2, "B PC 80 alone"),
                    (8.2, 9.2, "C 121/0/PC 80"), (10.2, 11.2, "D 0/0/PC 0"), (12.0, 12.45, "E ch10 key 42"),
                    (12.5, 12.95, "E ch10 key 38"), (13.0, 13.6, "E ch10 key 36"), (14.2, 14.65, "F 120/0/0 key 42"),
                    (14.7, 15.15, "F key 38"), (15.2, 15.8, "F key 36"), (16.2, 17.2, "G 121/0/PC 48"),
                    (18.3, 19.4, "after all notes off")):
    seg(a, b, label)
