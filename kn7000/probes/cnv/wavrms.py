#!/usr/bin/env python3
"""wavrms.py WAV T0 T1 [STEP] : RMS (dBFS) and peak of a MAME -wavwrite recording in windows of STEP s
(default 0.25) from T0 to T1 (seconds of emulated time), plus the dominant frequency of each window."""
import sys, wave
import numpy as np
w = wave.open(sys.argv[1]); sr = w.getframerate(); ch = w.getnchannels()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float).mean(axis=1)
t0, t1 = float(sys.argv[2]), float(sys.argv[3]); st = float(sys.argv[4]) if len(sys.argv) > 4 else 0.25
print(f"# {sys.argv[1]}: {len(x)/sr:.1f} s at {sr} Hz, {ch} ch")
t = t0
while t < t1 and int(t*sr) < len(x):
    s = x[int(t*sr):int((t+st)*sr)]
    rms = np.sqrt(np.mean(s**2)) if len(s) else 0
    db = 20*np.log10(rms/32768) if rms > 0 else -999
    S = np.abs(np.fft.rfft(s)); f = np.fft.rfftfreq(len(s), 1/sr)[np.argmax(S)] if len(s) else 0
    print(f"{t:7.2f} {db:7.1f} dBFS peak {np.max(np.abs(s)) if len(s) else 0:6.0f} f {f:7.1f} Hz")
    t += st
