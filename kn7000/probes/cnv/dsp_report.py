#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
"""dsp_report.py OUT -- the verdict of run_dsp.sh's session (awcnv_dsp.lua): OUT/tap.txt (the state every 0.25 s),
OUT/events.txt (what was pressed and seen) and OUT/run.wav (MAME's -wavwrite). One line per check, then
"dsp_report: N of M checks". What each check reads:
  dead      the firmware's "DSP dead" flag (893 0x500066D8): 0 at every sample after 20 s (the boot leaves it 0
            when it has loaded the DSP; before that the byte reads 0xFF)
  setup     the first run: the mixer loaded and hooked, the whole bank sent (DV_BK_SENT 1, every word), the game task
            started on the DSP (DV_MODE 0); how long the setup took
  hooked    in the intro, DSP mode: PM 0x8080 = CALL (E0) (DB), PM 0x80A0 = CALL (E9) (DB); MSGR7 (E0's heartbeat) and
            HB9 (E9's) rising at 44,100 a second
  voices    in the intro, DSP mode: music voices (4-7) and sound-effect voices (0-3) seen sounding, the mix not 0,
            unit 0's and unit 9's returns not 0
  midi      no MIDI message sent while the mode is DSP or OFF; some while it is TG
  modes     TG: both slots back as the firmware had them (the boot's words), nothing hooked; DSP again: both hooked
  restored  after each quit: both slots as at boot, MSGR4-MSGR7 0, and DM 0xC003 (the reverb's per-frame store of I6)
            moving again
  again     "Continue Next?" YES and the game from the menu again: the bank not sent again (DV_BK_SENT 2)
  sound     the recording: the intro's DSP window loud, against the silence before the game (dBFS per window)
  music     the recording where only the music's voices (4-7) sounded (the tap's voice mask): loud too"""
import os
import statistics
import sys
import wave

import numpy as np

OUT = sys.argv[1]
cols = None
rows = []
for line in open(os.path.join(OUT, "tap.txt")):
    f = line.split()
    if cols is None:
        cols = f
        continue
    if len(f) != len(cols):
        continue
    r = {}
    for k, v in zip(cols, f):
        if k in ("part", "slot0", "slot9", "m4", "m5", "m6", "vmask", "c003"):
            r[k] = int(v, 16)
        elif k == "t":
            r[k] = float(v)
        else:
            r[k] = int(v)
    rows.append(r)
events = [(float(ln[:8]), ln[9:].rstrip()) for ln in open(os.path.join(OUT, "events.txt")) if ln[:8].strip()]


def ev(text, n=1):
    """the time of the n-th event that starts with text"""
    k = 0
    for t, s in events:
        if s.startswith(text):
            k += 1
            if k == n:
                return t
    return None


checks = []


def check(name, ok, detail):
    checks.append(ok)
    print(f"{name:9} {'PASS' if ok else 'FAIL'}  {detail}")


boot = rows[-1] if not rows else next((r for r in rows if r["t"] > 20), rows[0])
FW0, FW9 = boot["slot0"], boot["slot9"]
E0, E9 = 0x06BE04008200, 0x06BE04008296
live = [r for r in rows if r["t"] > 20]                 # (the boot sets the flag to 0 when it loads the DSP)
check("dead", bool(live) and all(r["dead"] == 0 for r in live),
      f"the dead flag 0 at {sum(1 for r in live if r['dead'] == 0)} of {len(live)} samples from the boot's end "
      f"({live[0]['t'] if live else 0:.1f}-{rows[-1]['t']:.1f} s); the firmware's slots then {FW0:012X}, {FW9:012X}")

t_intro, t_tg, t_off, t_dsp = ev("the intro starts"), ev("RIGHT 2: -> tone generator"), ev("RIGHT 2: -> off"), ev("RIGHT 2: -> DSP")
t_quit1, t_quit2 = ev("first quit"), ev("again quit")
start1 = next((r for r in rows if r["cv"] == 3), None)
bank = [r for r in rows if r["cv"] == 5 and (t_intro is None or r["t"] < t_intro)]   # the first game's DSP setup
words = max((r["bkdone"] for r in rows), default=0)
check("setup", start1 is not None and start1["mode"] == 0 and start1["bksent"] == 1 and start1["hooked"] == 3,
      f"bank sent {start1['bksent'] if start1 else '-'} ({words:,} words), hooked {start1['hooked'] if start1 else '-'}, "
      f"mode {start1['mode'] if start1 else '-'}; the DSP setup {bank[0]['t'] if bank else 0:.1f}-"
      f"{bank[-1]['t'] if bank else 0:.1f} s ({(bank[-1]['t'] - bank[0]['t']) if bank else 0:.1f} s): "
      f"{[s for t, s in events if s.startswith('first: the game task')]}")

intro = [r for r in rows if t_intro and t_tg and t_intro + 1 < r["t"] < t_tg - 0.5]
hb = [(b["m7"] - a["m7"]) / (b["t"] - a["t"]) for a, b in zip(intro, intro[1:]) if b["m7"] > a["m7"]]
hb9 = [(b["hb9"] - a["hb9"]) / (b["t"] - a["t"]) for a, b in zip(intro, intro[1:]) if b["hb9"] > a["hb9"]]
check("hooked", bool(intro) and all(r["slot0"] == E0 and r["slot9"] == E9 for r in intro)
      and hb and abs(statistics.median(hb) - 44100) < 500 and hb9 and abs(statistics.median(hb9) - 44100) < 500,
      f"{len(intro)} samples of the intro in DSP mode ({intro[0]['t'] if intro else 0:.1f}-{intro[-1]['t'] if intro else 0:.1f} s): "
      f"slots {E0:012X} / {E9:012X} in all; MSGR7 {statistics.median(hb) if hb else 0:,.0f}/s, HB9 "
      f"{statistics.median(hb9) if hb9 else 0:,.0f}/s (medians)")

vm = 0
for r in intro:
    vm |= r["vmask"]
mix = max((r["mixmax"] for r in intro), default=0)
o0 = max((r["out0max"] for r in intro), default=0)
o9 = max((r["out9max"] for r in intro), default=0)
nm = sum(1 for r in intro if r["vmask"] & 0xF0)
ns = sum(1 for r in intro if r["vmask"] & 0x0F)
check("voices", (vm & 0xF0) != 0 and (vm & 0x0F) != 0 and mix > 0 and o0 > 0 and o9 > 0,
      f"voices seen {vm:08b} (music in {nm}, effects in {ns} of {len(intro)} samples); peaks: mix {mix:,}, "
      f"unit 0's return {o0:,}, unit 9's {o9:,} (24-bit full scale 8,388,607); flushes {intro[-1]['flushes'] if intro else 0}, "
      f"MSGR6 busy {intro[-1]['busy'] if intro else 0}")


def sent_in(a, b):
    w = [r for r in rows if a < r["t"] < b]
    return (w[-1]["sent"] - w[0]["sent"]) if len(w) > 1 else 0


m_dsp = sent_in(t_intro + 1, t_tg - 0.5) if t_intro and t_tg else -1
m_tg = sent_in(t_tg + 1, t_off - 0.5) if t_tg and t_off else -1
m_off = sent_in(t_off + 1, t_dsp - 0.5) if t_off and t_dsp else -1
m_dsp2 = sent_in(t_dsp + 1, t_quit1 - 3) if t_dsp and t_quit1 else -1
check("midi", m_dsp == 0 and m_off == 0 and m_dsp2 == 0 and m_tg > 0,
      f"MIDI messages sent: DSP {m_dsp}, TG {m_tg}, OFF {m_off}, DSP again {m_dsp2}")

tg = [r for r in rows if t_tg and t_off and t_tg + 1 < r["t"] < t_off - 0.5]
dsp2 = [r for r in rows if t_dsp and t_quit1 and t_dsp + 1 < r["t"] < t_quit1 - 3]
check("modes", bool(tg) and all(r["slot0"] == FW0 and r["slot9"] == FW9 and r["hooked"] == 0 and r["mode"] == 1 for r in tg)
      and bool(dsp2) and all(r["slot0"] == E0 and r["slot9"] == E9 and r["hooked"] == 3 and r["mode"] == 0 for r in dsp2),
      f"TG: {len(tg)} samples, the firmware's slots and nothing hooked in all; DSP again: {len(dsp2)} samples, both hooked "
      f"in all; voices in DSP again {np.bitwise_or.reduce([r['vmask'] for r in dsp2]) if dsp2 else 0:08b}")

for name, tq in (("restored", t_quit1), ("restored2", t_quit2)):
    after = [r for r in rows if tq and tq < r["t"] < tq + 4]
    hooked = [r for r in rows if tq and tq - 4 < r["t"] < tq - 2.5]
    ok = bool(after) and all(r["slot0"] == FW0 and r["slot9"] == FW9 and r["m4"] == r["m5"] == r["m6"] == r["m7"] == 0
                             for r in after)
    c_after = len({r["c003"] for r in after})
    c_hooked = len({r["c003"] for r in hooked})
    check(name, ok and c_after > 4 and c_hooked <= 2,
          f"after the quit at {tq or 0:.1f} s: {len(after)} samples, slots as at boot, MSGR4-7 0 in all; DM 0xC003 "
          f"{c_hooked} value(s) in the samples before, {c_after} after (the reverb runs again)")

again = [r for r in rows if t_quit1 and r["t"] > t_quit1 + 8 and r["cv"] == 3]
check("again", bool(again) and again[0]["bksent"] == 2 and again[0]["hooked"] == 3 and again[0]["mode"] == 0,
      f"the second game: bank sent {again[0]['bksent'] if again else '-'} (2 = still in SDRAM), hooked "
      f"{again[0]['hooked'] if again else '-'}: {[s for t, s in events if s.startswith('again: the game task')]}")

w = wave.open(os.path.join(OUT, "run.wav"))
sr, ch = w.getframerate(), w.getnchannels()
x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float).mean(axis=1)


def db(a, b):
    s = x[int(a * sr):int(b * sr)]
    r = np.sqrt(np.mean(s ** 2)) if len(s) else 0
    return 20 * np.log10(r / 32768) if r > 0 else -240.0


quiet = db(20, 28)
win = [db(t, t + 1) for t in np.arange(t_intro + 1, t_tg - 1, 1.0)] if t_intro and t_tg else []
loud = sum(1 for v in win if v > quiet + 20)
tgw = [db(t, t + 1) for t in np.arange(t_tg + 1, t_off - 1, 1.0)] if t_tg and t_off else []
offw = [db(t, t + 1) for t in np.arange(t_off + 2, t_dsp - 1, 1.0)] if t_off and t_dsp else []
check("sound", bool(win) and loud >= len(win) // 2,
      f"before the game {quiet:.1f} dBFS; the intro on the DSP, 1 s windows: {loud} of {len(win)} more than 20 dB "
      f"above that, {min(win) if win else 0:.1f} to {max(win) if win else 0:.1f} dBFS; TG {min(tgw) if tgw else 0:.1f} to "
      f"{max(tgw) if tgw else 0:.1f}; OFF {min(offw) if offw else 0:.1f} to {max(offw) if offw else 0:.1f}")
music = [r for r in intro if r["vmask"] and not r["vmask"] & 0x0F]
mus_db = [db(r["t"] - 0.25, r["t"]) for r in music]
check("music", len(music) >= 4 and sum(1 for v in mus_db if v > quiet + 20) >= len(music) * 3 // 4,
      f"{len(music)} quarter-seconds of the intro with only the music's voices sounding: "
      f"{sum(1 for v in mus_db if v > quiet + 20)} of them more than 20 dB above the silence, "
      f"{min(mus_db) if mus_db else 0:.1f} to {max(mus_db) if mus_db else 0:.1f} dBFS")
print(f"dsp_report: {sum(checks)} of {len(checks)} checks")
