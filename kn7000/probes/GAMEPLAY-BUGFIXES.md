# Two gameplay bugs fixed (2026-10-16)

Felipe played the water part and reported two unrelated problems: (1) key presses
sometimes produce the wrong input effect, and (2) the dynamic elements (Lester, slugs)
periodically vanish for a while, leaving only the background, then come back. Both are
fixed in `src/interp.s` / `src/vm.inc`. Each diagnosis below has a probe here that
reproduces it.

## Bug 1 — input mix-ups: a key occasionally reads as the wrong direction/action

The keybed read walks the TG active-voice **ring** from `0x500D1050` (per link `L`: note at
`L-4`, next at `L`) — see the "fast signal" note below; it originally scanned the slower
held-slot bitmap `0x500D288C`. Refinements, after measuring what `ReadInput` actually sees
at its once-per-VM-frame sampling rate:

**What is NOT the problem (a false lead I first chased).** Sub-frame probing suggested a
slot's held bit is set ~1 frame before its note field is written, so a fresh slot would
read note 0 (→ action) or a stale note (→ wrong direction). But at true VM-frame
granularity the note is **already correct** the first frame a slot appears
(`awalloc.lua`: `APPEAR+0 slot65 note=77`, `slot67 note=84` — never stale). A single key
also sounds exactly one voice with the right note, no arranger chord/harmony/layer
(`awvoices.lua`: C2→36, C3→48, C4→60, F5→77, A5→81, C6→84). So the stale/fresh transient
is sub-frame noise the game never samples. A first attempt at a per-slot 2-frame debounce
to filter it was **wrong and reverted**: it added a second frame of lag on top of the
firmware's, which shifts short taps into their release phase and drops them — strictly
worse.

**The real refinements:**
- **Skip note 0.** A slot momentarily reads note 0 only while unallocated; note 0 would
  classify as action (`<= 60`), so a slot with note 0 is skipped. Cheap guard.
- **Opposing directions: a STICKY rule (the real overlap fix — 2026-10-17).** This went
  through three wrong turns before landing. (1) An *opposing-cancel* that zeroed an axis when
  both bits were set — made Lester **stop** mid-switch (`awoverlap2.lua`: F5+C6 → `LR=0`
  neutral for the whole overlap). Reverted. (2) **Newest-key-wins** via the ring's order — the
  active-voice ring was *assumed* allocation-ordered (oldest at head, newest at tail), so the
  walk overwrote each axis's bit to let the most-recently-pressed key win. It passed clean
  2-key tests but **the assumption is false**: the voice allocator reuses freed slots, so after
  churn the ring is in *slot* order, not press order. `awringorder.lua` found **~15 % of
  overlaps mis-ordered** (`newest=+1 right` but `ring={84,77}` → walk picks left) — i.e.
  intermittent **wrong direction**, which is exactly what Felipe reported ("wrong direction,
  intermittent, on both the keybed and USB-MIDI"). Reverted. (3) The fix that holds: resolve
  each axis with **no recency at all**. The ring walk just ORs every held bit; the derive then
  applies a sticky rule per axis — **one direction alone wins; both held keeps the
  last-applied direction (`PREV_*_BITS`) until a key is released; neither = 0**. Deterministic
  and brush-proof: `awsticky.lua` — holding right with a left brush stays right, holding left
  with a right brush stays left (**0 flips**), and a clean right→left switch resolves `+1`
  then `−1`. Diagonals (different axes) keep both, and the mask `var[0xFD]/[0xFE]` is the
  **resolved** mask (one bit per axis + action, like a joystick that cannot hold opposing
  directions). Mapping + run+jump combos unchanged — `awkbdmap.lua` 10/10 (`FD=89`/`FD=8a`).
  `PREV_*_BITS` are cleared on reset and on every part switch.
- **Fast, symmetric key signal (the real cut to the "extra kick").** The sustain bitmap
  `0x500D288C` is *set* on key-down in ~17 ms but *cleared* on key-up in ~50 ms (variable
  33–50). That asymmetry is the stray kick: a released direction lingers while you switch.
  The TG's active-voice **ring** (head `0x500D1050`) clears a released note in ~17 ms —
  **symmetric** with key-on (`awringlat.lua`, 4 trials) — and is polyphonic/per-note
  (C4+G4 → {60,67}; release C4 → {67} within a frame, `awring.lua`). Switching `ReadInput`
  to walk the ring (bounds + node cap against a bad pointer) roughly **halves** the
  wrong-direction frames on deliberate switches — clean A/B via the same applied-mask tap:
  sustain = 23/99, ring = 13/99 (`awstray.lua`). Found by the fast-signal investigation
  (`research-scratch/awkeyscan*/awcheck/awring*`). Caveats: the ring is *sounding* voices
  (cleared fast here because the AW keybed sound has ~0 release; a long-release patch could
  keep a voice ringed) and reflects all sounding voices (part-filter needed in general;
  during AW nothing else sounds); head `0x500D1050` is the class-0 ring, correct for the AW
  keybed sound. It does not *eliminate* the kick — the residual ~13/99 is the 1-frame
  sampling quantization at the 80 ms water pace, which no key signal removes.

**Residual — the one remaining oddity ("an extra kick on direction change").** Measured
(`awlatency.lua`): a press appears in the held mask in **~17 ms**, but a release takes
**~50 ms** (~1.5 game frames) to clear — the firmware's note-off is slower than its
note-on. So after kicking in one direction, that direction lingers ~1-2 frames after you
let go, which reads as one extra "kick" just as you press the next direction. There is no
faster release signal exposed: the "gone" mask `0x500D287C` never sets for these voices
and the voice node enters release at the same ~50 ms, not sooner (`awgone.lua`); and the
module can't hurry the firmware's note-off without yielding another whole frame, which
would slow the game. It is a ~1-frame artifact on direction changes, not a wrong
direction, and there is no clean fix that preserves diagonals (a switch like up->left
can't be told apart from a deliberate up+left diagonal at the moment the new key appears).

Tested and rejected (so it isn't re-attempted): the ~50 ms note-off latency does **not**
depend on how we yield. Measured it the same (~50 ms) with the old flat 30 ms yield, the
new ~60 ms AW-paced yield, and a version that split the per-frame sleep into 8 ms chunks to
schedule the firmware's keybed task more often — all identical. It is a fixed firmware
property. And it can't be shrunk by running faster: the 50 ms is absolute, so a shorter
frame makes it span *more* frames (worse). Only a *longer* frame (slower game) makes the
50 ms a smaller fraction of one frame and hides the lingering — the crispness/speed
trade-off. At the authentic 80 ms water pace it is an occasional one-frame extra kick.

Also tested and rejected: **symmetrising the edges by delaying the key-ON** (hold a pressed
bit ~33 ms before applying it, so press+delay ~= the 50 ms key-off). The intent was to make
both edges land together on a switch. Implemented it clock-based (per-bit on-time in
KERNEL_MS, so taps survive the 50 ms release tail) and measured the real symptom — frames
showing the *old* direction while the *new* one is intended — over rapid UP<->LEFT switches:
it got **worse**, 17 -> 32 such frames. Reason: the stray kick is the slow *release*
lingering, not the fast press; delaying the press just makes the new direction appear later,
*lengthening* the window where only the stale old direction shows. Reverted. The firmware's
~50 ms key-off is the real limit and there is no module-side fix that keeps diagonals.

## Bug 2 — dynamic elements periodically disappear (background stays)

**Cause.** `CopyPage` resolved a copy source page wrongly. Another World's copyVideoPage
treats the source id as: `0xFE` = front, `0xFF` = back, **everything else = id & 3**; the
`0x80` bit is *not* a page bit — it means "copy shifted vertically by `VAR_SCROLL_Y`
(var `0xF9`)". Our old `GetPagePtr` compared the id against 0/1/2/3 exactly and fell
through to **page 0** for anything else, and `CopyPage` stripped only `0x40` (keeping
`0x80`) and ignored the scroll.

The water part's per-frame scroll loop (disassembled by `awdis.py` from the real
`resource-0x1b.bin` / `AWBYTE2.AW`) does:

```
@0x01A9  COPY src=0xFF(back) dst=0x03            ; save the composited scene (bg + sprites) -> page 3
@0x01AC  COPY src=0x83       dst=0xFF  VSCROLL   ; restore page 3, scrolled, into the back buffer
```

`src=0x83` means page `0x83 & 3 = 3`, scrolled. With the bug, `GetPagePtr(0x83)` returned
**page 0 (the bare backdrop)**, so every scroll frame overwrote the back buffer with the
background and threw away the accumulated dynamic layer — the sprites vanished. It is
cyclic because the bytecode mode-switches between this scrolling-composite loop and a
simpler loop (`src=0x40` = page 0, which repaints sprites directly), so the sprites come
back when the mode changes. The intro never uses an `0x80`-flagged copy, which is why only
water gameplay showed the fault.

**Fix.** `GetPagePtr` now resolves any non-`0xFE/0xFF` id as `PAGE_BITMAP_0 + (id & 3)*0x10000`
(so `0x83`→page 3), and `CopyPage` honours the `0x80` scroll flag (reads `var[0xF9]`,
shifts the copy by that many rows up/down, clamped to 199) with a self-copy guard
(`src==dst` → no-op, needed once scroll is real for the `src=0xC0 dst=0x00` self-copy).

**Verification.** `awcopytrace.lua` taps `CopyPage` live in the water part and shows the
new resolution: `src=0x40 → page 0`, `src=0x03 → page 3` (so `src=0x83 → page 3` by the
same `&3` path; before the fix those non-0..3 ids all went to page 0). The exact
`src=0x83` scroll copy happens in a later, progression-gated scroll room than a scripted
entry reaches, so the end-to-end "sprites stay" is best confirmed in play; the page-id
resolution and the bytecode evidence (`awdis.py`) pin the cause and the fix.

### Probes
`awinput_bug.lua`, `awrelease.lua`, `awinput_fix3.lua` (bug 1); `awdis.py` (bug-2 bytecode
evidence — run `python3 awdis.py <resource-0x1b.bin>`), `awcopytrace.lua` (bug-2 live page
resolution). Oracle: rustyworld `video.rs` `PageSelector::from` / `copy_page`, `vm.rs`
opcode `0xF` + `VAR_SCROLL_Y`.

## Bug 3 — the intro skipped immediately, with no key pressed (2026-10-17)

**Cause.** The intro-skip read `0x50149690` as "a keybed key is held". That address is a
noisy firmware "activity" flag (metronome-adjacent): `awskipbug.lua` shows it toggling to
`0x0001` from frame 2 with **no key pressed**, so the intro fired its own fire-to-skip and
was already in the water part (`0x3E82`) by frame 6. This was also the intro-vs-reference
checksum divergence flagged in PACING.md — same root cause.

**Fix.** Base the skip on the TG held-slot bitmap (`TG_HELD_MASK` = `0x500D288C`, 16 bytes)
— the same reliable signal gameplay uses. `ReadInput`'s intro branch ORs the 16 bytes;
fire is set only when some bit is set (a real held key). The held mask stays 0 with no key
(`awskipbug.lua`).

**Verified.** No key for 6 s → stays in the intro; then C4 → water in 0.15 s
(`awskipok.lua`). And the intro now matches `ref_checksums.log` **100%** again (0/151
mismatches, `awcksum.lua` + `cksum_pages.py`) — the divergence is gone.

## Bug 4 — run+jump lost the jump: keybed matrix ghosting on the up note (2026-10-17)

**Symptom (Felipe's scenario).** Hold *action* (a bass note) to run, hold *right* (C6) for
direction, and tap *up* (the old Ab5) to jump while running — the jump never happened.

**Cause — not the VM, the keybed.** Reading the firmware held-slot bitmap `0x500D288C`
directly (`awrun_diag.lua`, not just the active-voice ring) showed the firmware *itself*
never reports the up key when another key is held:

| held | firmware held notes |
|------|---------------------|
| C3 + C6 (action + right)        | `{48,84}` ✓ |
| C3 + C6 + **Ab5** (+ up)        | `{48,84}` — **Ab5 dropped** |
| C6 + **Ab5**                    | `{84}` — **Ab5 dropped** |
| F5 + A5 + C3 (left+down+action) | `{48,77,81}` ✓ all three |

So it is **not** a voice/polyphony limit (three keys coexist in the last row) and not the
module — it is **keybed scan-matrix ghosting**: note Ab5 (80) is masked whenever another key
shares its matrix lines. A sweep of candidate up notes against both running combos
(`awupnote.lua`) found Ab5(80), Bb5(82), Db6(85), Eb6(87) all ghost, while **B5(83), D6(86),
E6(88)** survive the action+direction holds cleanly. (This is faithfully-emulated hardware
behaviour; whether a real KN7000 keybed masks the identical set is untested — the hardware is
abroad.)

**Fix.** Remap *up* from Ab5/Bb5 to **B5 (`KBD_UP_NOTE_A`) / D6 (`KBD_UP_NOTE_B`)** in
`vm.inc`. Run-and-jump now registers all three inputs at once — `awkbdmap.lua` has it as a
permanent regression: `C3+C6+B5 (run-R-jump)` → `FC=1 E5=ffff FB=ffff FD=89 FA=1` and
`C3+F5+B5 (run-L-jump)` → `FC=ffff E5=ffff FB=ffff FD=8a FA=1`, both pass, alongside the 8
single-key/move+fire cases. The dynamic tap test (`awrunjump2.lua`) confirms the B5 jump
enters the ring (`{48,84,83}`) while action+right stay held.

**The ghosting is timing-dependent (follow-up, Felipe: "can't escape the lake tentacles
with action+up").** The lake escape is a swim-up: holding *up* keeps Lester rising and he
reaches land; **no input drowns him** (the "PRESS BUTTON … / ACCESS CODE" continue screen),
reaction window ~3–6 s (`awwatch.lua` under no/`up`/`actup` holds and `AW_DELAY`; snapshots
in `awswimshot.lua`). `action+up` delivers the right vars, sustained (`awactionup.lua`:
`FA=1 E5=-1`), and *does* escape in a clean test — but a wider sweep (`awbassghost.lua`,
`awbassghost2.lua`) shows up-note ghosting against **three-or-more-key** holds is **not
deterministic**: the same `D6 + C3+E3+G3` triad ghosted in one run and not another, because
masking depends on the order keys hit the scan. So holding *action* (especially a loose bass
*chord*) together with *up* can intermittently drop the up — matching "can't *seem* to".
**B5** survived every combo tested (most robust); D6/E6 ghost on some. **Two keys or fewer
never ghost** (a rectangle needs ≥3), so the robust play for a single input is one key, and
for the lake swim specifically: **hold only up (B5)** — action is not needed to swim. This is
a usage property of the real keybed matrix, not a code bug; the B5 mapping is already the
most robust up note, so no code change followed.

### Probes (bugs 1 & 4)
`awinput_bug.lua`, `awrelease.lua`, `awinput_fix3.lua` (early bug-1 leads); `awoverlap2.lua`
(opposing-cancel → neutral-stop), `awoverlap3.lua` (newest-key-wins both directions),
`awdiag_nw.lua` (diagonals under newest-wins); `awrun_diag.lua` (ghosting isolated via the
firmware held mask), `awupnote.lua` (ghost-free up-note sweep), `awrunjump2.lua` (dynamic
run+jump), `awkbdmap.lua` (mapping + run+jump regression). The last three live in
`research-scratch/` except `awkbdmap.lua`. Oracle: rustyworld `update_player`.
