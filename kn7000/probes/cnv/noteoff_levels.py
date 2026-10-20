#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# noteoff_levels.py WAV -- awcnv_noteoff.lua's reading: for each of its four notes, the level (dB, the
# FFT magnitude at the note's fundamental, Hann window) in 0.5 s windows from its note-on to 2.5 s
# after its note-off. A note whose level falls by tens of dB after the note-off was released.
import sys
import wave

import numpy as np

w = wave.open(sys.argv[1]); sr = w.getframerate(); ch = w.getnchannels()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float).mean(axis=1)
NOTES = [("ring, program 80, C4", 70.2, 71.2, 261.63), ("ring, program 0, E4", 73.2, 74.2, 329.63),
         ("MIDI IN, program 80, G4", 77.2, 78.2, 392.00), ("MIDI IN, program 0, A4", 80.2, 81.2, 440.00)]
for name, on, off, f0 in NOTES:
    row = []
    for t in np.arange(on, off + 2.5, 0.5):
        s = x[int(t * sr):int((t + 0.5) * sr)]
        S = np.abs(np.fft.rfft(s * np.hanning(len(s))))
        f = np.fft.rfftfreq(len(s), 1 / sr)
        k = (f > f0 * 0.98) & (f < f0 * 1.02)
        row.append(f"{t - off:+.1f}s {20 * np.log10(S[k].max() + 1e-9):5.1f}")
    print(f"{name:26s} (offset from note-off) " + "  ".join(row))
