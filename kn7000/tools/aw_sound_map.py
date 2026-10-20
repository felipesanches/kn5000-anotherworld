#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# aw_sound_map.py -- which KN7000 sound plays each Another World sound resource?
#
# The KN7APP.BIN build plays the game's sound effects and music as MIDI on the KN7000's own tone
# generator (src/audio.s): it never outputs the samples. Each AW sound resource (8-bit PCM after an
# 8-byte header: length and loop length in 16-bit words) becomes either a GM drum key on MIDI channel
# 10, or a GM program at a MIDI note. SOUNDS below is that choice, made by ear-less judgement from each
# sample's analysis (length, spectral flatness, peak, autocorrelation f0: the comment on each row), by
# the first-pass rule of research-scratch kn7000-aw-sound/awsndclass.py, then by hand for the music
# instruments (2026-10-20). It is a table to tune on the instrument, not a measurement.
#
#   kind 'D', key, 0   -- GM drum key (MIDI channel 10), whatever the frequency asked
#   kind 'M', prog, n  -- GM program prog (0-based), sounding note n when the sample would play at
#                         8363 Hz (Amiga period 428, the music player's C-3); PLAY_SOUND's frequency
#                         index f (rawgl freqTable: semitones, f = 20 is 10,559 Hz, 4 semitones above
#                         8363 Hz) plays note n + f - 16, a module note of period p plays n + the
#                         semitones from 428 to p
#   absent             -- silent (resources the bytecode never plays)
#
# The table src/audio.s reads, SND_TAB, is the game file AWSND.AW on the card (tools/aw_extract.py
# --parts puts it in the global list, beside the font): per resource id (RES_COUNT of them) 4 bytes,
#   u8 program (0x80 = drum, 0xFF = none), u8 note (or drum key), u16 LE duration in ms at 8363 Hz
#   (0xFFFF = the sample loops: the note is held until the game stops it).
# The durations come from the resource headers of your own copy of the game, so the file is made at
# build time and never committed. Run alone, this lists the table:
#
#   python3 -I tools/aw_sound_map.py build/res
import os
import sys

# GM programs used (0-based): 38 Synth Bass 1, 39 Synth Bass 2, 11 Vibraphone, 14 Tubular Bells,
# 50 Synth Strings 1, 89 Pad 2 (warm), 115 Woodblock, 116 Taiko, 118 Synth Drum, 122 Seashore,
# 127 Gunshot. GM drum keys: 35 bass drum, 36 kick, 38 snare, 41 low floor tom, 42 closed hi-hat.
SOUNDS = {
    # ---- the music modules' instruments (0x07 intro, 0x8A final), chosen by hand ----
    0x01: ('M',  50,  64),  # intro melody / final chords: 0.80 s loop, tonal, f0 335 Hz (0.95)
    0x02: ('D',  35,   0),  # intro beat: 1.41 s low boom, peak 168 Hz, f0 42 Hz
    0x03: ('M',  39,  40),  # intro bass line: 3.24 s loop, peak 84 Hz
    0x04: ('M',  14,  68),  # 2.14 s decaying, tonal 400 Hz: a bell
    0x05: ('M',  11,  64),  # 0.46 s pluck, the timbre of 0x01, f0 335 Hz (0.96)
    0x06: ('D',  42,   0),  # intro hi-hat: 0.40 s noise
    0x80: ('M',  38,  40),  # final bass: 0.75 s, f0 83 Hz (0.96)
    0x81: ('D',  42,   0),  # final hi-hat: 0.24 s, centroid 3238 Hz
    0x82: ('D',  36,   0),  # final kick: 0.13 s, peak 60 Hz
    0x83: ('D',  38,   0),  # final snare: 0.48 s noise, centroid 2034 Hz
    # ---- sound effects: the first-pass rule (awsndclass.py), Taiko and Synth Drum notes clamped ----
    0x08: ('M',  89,  60),  # 1.18 s loop, flat 0.11, centroid 1298 Hz
    0x09: ('M', 116,  48),  # 1.34 s, flat 0.05, peak 192 Hz
    0x0A: ('M', 122,  60),  # 1.34 s, flat 0.34 (noise), centroid 1544 Hz
    0x0B: ('M', 115,  64),  # 0.13 s, tonal, f0 335 Hz (0.98)
    0x0C: ('M', 127,  60),  # 0.74 s, flat 0.38, centroid 2243 Hz
    0x0D: ('D',  41,   0),  # 0.17 s, flat 0.09, peak 118 Hz
    0x0E: ('M', 116,  48),  # 0.61 s, flat 0.01, peak 244 Hz
    0x0F: ('D',  41,   0),  # 0.23 s, flat 0.01, peak 168 Hz
    0x10: ('M',  89,  60),  # 2.65 s loop, flat 0.13, centroid 1225 Hz
    0x2C: ('D',  38,   0),  # 0.10 s, flat 0.27, centroid 1792 Hz
    0x2D: ('M', 118,  60),  # 0.92 s, flat 0.15, peak 340 Hz
    0x2E: ('D',  38,   0),  # 0.27 s, flat 0.25, centroid 1699 Hz
    0x2F: ('M', 127,  60),  # 0.80 s, flat 0.43, centroid 2460 Hz
    0x30: ('M', 116,  48),  # 1.60 s, flat 0.03, peak 208 Hz
    0x31: ('M', 116,  48),  # 0.63 s, flat 0.00, peak 220 Hz
    0x32: ('M', 116,  48),  # 0.75 s, flat 0.01, peak 204 Hz
    0x33: ('D',  38,   0),  # 0.07 s, flat 0.36
    0x35: ('D',  41,   0),  # 0.05 s, flat 0.13, peak 181 Hz
    0x36: ('M', 116,  48),  # 0.98 s, flat 0.03, peak 104 Hz
    0x37: ('M', 118,  72),  # 0.60 s, flat 0.01, f0 523 Hz (0.79)
    0x38: ('M', 118,  77),  # 0.67 s, flat 0.00, f0 697 Hz (0.69)
    0x39: ('M', 116,  48),  # 0.43 s, flat 0.25, peak 60 Hz
    0x3A: ('D',  41,   0),  # 0.10 s, flat 0.00, peak 39 Hz
    0x3B: ('D',  38,   0),  # 0.01 s, flat 0.45
    0x3C: ('M', 116,  48),  # 0.60 s, flat 0.17, peak 264 Hz
    0x3D: ('D',  38,   0),  # 0.21 s, flat 0.31
    0x3E: ('M', 116,  48),  # 1.03 s, flat 0.04, peak 140 Hz
    0x3F: ('D',  42,   0),  # 0.15 s, flat 0.30, centroid 2736 Hz
    0x40: ('M', 116,  48),  # 0.57 s, flat 0.19, peak 96 Hz
    0x41: ('M', 118,  60),  # 0.30 s, flat 0.08, peak 560 Hz
    0x42: ('D',  41,   0),  # 0.15 s, flat 0.21, peak 167 Hz
    0x4A: ('D',  42,   0),  # 0.11 s, flat 0.35, centroid 2223 Hz
    0x4B: ('M', 127,  60),  # 0.61 s, flat 0.37, centroid 1751 Hz
    0x4C: ('D',  41,   0),  # 0.15 s, flat 0.03, peak 189 Hz
    0x4D: ('D',  41,   0),  # 0.18 s, flat 0.05, peak 143 Hz
    0x4E: ('D',  41,   0),  # 0.07 s, flat 0.04, peak 98 Hz
    0x4F: ('D',  38,   0),  # 0.19 s, flat 0.29
    0x50: ('M', 116,  48),  # 0.79 s, flat 0.05, peak 116 Hz
    0x51: ('D',  38,   0),  # 0.03 s, flat 0.44
    0x52: ('M', 116,  48),  # 0.49 s, flat 0.20, peak 56 Hz
    0x54: ('M', 116,  48),  # 2.71 s, flat 0.01, peak 264 Hz
    0x55: ('D',  38,   0),  # 0.29 s, flat 0.31, centroid 1844 Hz
    0x56: ('M', 116,  48),  # 1.35 s, flat 0.09, peak 60 Hz
    0x57: ('M', 127,  60),  # 0.65 s, flat 0.48, centroid 2056 Hz
    0x58: ('D',  42,   0),  # 0.17 s, flat 0.50, centroid 2303 Hz
    0x59: ('M',  89,  40),  # 1.09 s loop, flat 0.02, peak 164 Hz, f0 41 Hz (0.77)
    0x5A: ('M', 116,  48),  # 0.97 s, flat 0.06, peak 152 Hz
    0x5B: ('M', 116,  48),  # 0.40 s, flat 0.15, peak 84 Hz
    0x5C: ('D',  42,   0),  # 0.16 s, flat 0.47, centroid 2204 Hz
    0x5D: ('M', 127,  60),  # 0.67 s, flat 0.47, centroid 1949 Hz
    0x5E: ('D',  42,   0),  # 0.06 s, flat 0.41, centroid 2520 Hz
    0x5F: ('D',  42,   0),  # 0.24 s, flat 0.43, centroid 2483 Hz
    0x60: ('D',  38,   0),  # 0.03 s, flat 0.44
    0x61: ('M',  89,  54),  # 1.76 s loop, flat 0.00, f0 190 Hz (0.75)
    0x62: ('M', 127,  60),  # 0.53 s, flat 0.35, centroid 2526 Hz
    0x63: ('M', 127,  60),  # 0.63 s, flat 0.29, centroid 1723 Hz
    0x64: ('M', 127,  60),  # 0.32 s, flat 0.26, centroid 1693 Hz
    0x65: ('D',  41,   0),  # 0.09 s, flat 0.06, peak 81 Hz
    0x66: ('M',  89,  60),  # 1.18 s loop, flat 0.11, centroid 1298 Hz
    0x67: ('M', 127,  60),  # 0.58 s, flat 0.45, centroid 2218 Hz
    0x68: ('M',  89,  40),  # 2.86 s loop, flat 0.01, peak 124 Hz
    0x69: ('M', 116,  40),  # 4.96 s, flat 0.00, peak 168 Hz, f0 83 Hz
    0x6A: ('M', 122,  60),  # 1.42 s loop, flat 0.42 (noise), centroid 1702 Hz
    0x6B: ('M', 122,  60),  # 2.50 s, flat 0.30, centroid 1815 Hz
    0x6C: ('M', 127,  60),  # 0.61 s, flat 0.37, centroid 1751 Hz
    0x6D: ('M', 116,  48),  # 0.63 s, flat 0.00, peak 220 Hz
    0x6E: ('M', 116,  48),  # 2.71 s, flat 0.01, peak 264 Hz
    0x6F: ('M', 118,  60),  # 2.09 s, flat 0.23, centroid 2734 Hz
    0x70: ('M', 116,  53),  # 0.41 s, flat 0.08, f0 171 Hz (0.55)
    0x71: ('M', 118,  60),  # 0.30 s, flat 0.19, peak 696 Hz
    0x72: ('M', 116,  48),  # 0.78 s, flat 0.15, peak 116 Hz
    0x73: ('M', 118,  60),  # 1.16 s, flat 0.19, peak 604 Hz
    0x74: ('M', 127,  60),  # 1.11 s, flat 0.36, centroid 1673 Hz
    0x75: ('M', 118,  60),  # 0.58 s, flat 0.21, peak 1260 Hz
    0x76: ('M', 115,  89),  # 0.06 s, flat 0.18, f0 1394 Hz (0.68)
    0x77: ('D',  41,   0),  # 0.18 s, flat 0.01, peak 205 Hz
    0x78: ('D',  41,   0),  # 0.13 s, flat 0.23, peak 249 Hz
    0x79: ('D',  38,   0),  # 0.27 s, flat 0.25, centroid 1699 Hz
    0x7A: ('M', 116,  48),  # 0.63 s, flat 0.05, peak 84 Hz
    0x7B: ('M', 116,  48),  # 2.06 s, flat 0.14, peak 200 Hz
    0x7C: ('D',  38,   0),  # 0.21 s, flat 0.42, centroid 1824 Hz
    0x84: ('M',  89,  48),  # 3.16 s loop, flat 0.04, peak 108 Hz
    0x88: ('M', 118,  60),  # 1.12 s, flat 0.15, peak 1312 Hz
    0x8B: ('M',  89,  48),  # 2.43 s loop, flat 0.25, peak 44 Hz
    0x8C: ('M', 116,  48),  # 2.08 s, flat 0.05, peak 156 Hz
    0x8D: ('M', 118,  60),  # 1.26 s, flat 0.24, peak 1477 Hz
    0x8E: ('M', 122,  60),  # 1.95 s, flat 0.53 (noise), centroid 2205 Hz
}


def snd_table(types, header):
    """AWSND.AW: types[i] = the resource's type name, header(i) = its first 4 bytes (unpacked) or
    b"" -> (bytes, listing lines)."""
    out, lines = bytearray(), []
    for i, typ in enumerate(types):
        m = SOUNDS.get(i)
        d = header(i) if typ == "sound" else b""
        if m is None or len(d) < 4:
            if typ == "sound" and len(d) >= 4:
                print(f"aw_sound_map: sound 0x{i:02X} has no mapping: silent", file=sys.stderr)
            out += bytes((0xFF, 0, 0, 0))
            continue
        ln, lp = (d[0] << 8 | d[1]) * 2, (d[2] << 8 | d[3]) * 2
        ms = 0xFFFF if lp else min(0xFFFE, max(1, ln * 1000 // 8363))
        kind, a, n = m
        prog, note = (0x80, a) if kind == 'D' else (a, n)
        out += bytes((prog, note, ms & 0xFF, ms >> 8))
        lines.append(f"0x{i:02X}  {'drum key' if kind == 'D' else 'program '} {a:3d}  note {note:3d}  "
                     f"{'held (loops)' if lp else str(ms) + ' ms'}")
    return bytes(out), lines


def main():
    res = sys.argv[1]
    rows = [line.split("\t") for line in open(os.path.join(res, "memlist.tsv")).read().split("\n")[1:] if line]
    types = [r[1] for r in rows]
    _, lines = snd_table(types, lambda i: open(os.path.join(res, f"resource-0x{i:02x}.bin"), "rb").read(4))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
