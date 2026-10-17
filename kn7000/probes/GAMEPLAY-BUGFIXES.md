# Two gameplay bugs fixed (2026-10-16)

Felipe played the water part and reported two unrelated problems: (1) key presses
sometimes produce the wrong input effect, and (2) the dynamic elements (Lester, slugs)
periodically vanish for a while, leaving only the background, then come back. Both are
fixed in `src/interp.s` / `src/vm.inc`. Each diagnosis below has a probe here that
reproduces it.

## Bug 1 — input mix-ups: a key occasionally reads as the wrong direction/action

The keybed read scans the TG voice-allocator held-slot bitmap `0x500D288C` and reads each
held slot's note at `0x500D1278 + slot*0x2C + 0x0C`. Two refinements, after measuring what
`ReadInput` actually sees at its once-per-VM-frame (~30 ms) sampling rate:

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
- **Cancel opposing directions.** The held bitmap lags physical key-up by ~1 frame
  (firmware key-up processing; `awrelease.lua` shows the bit clearing ~50 ms after
  release). So releasing left while pressing right briefly shows **both** for one frame,
  and the derive's RIGHT-beats-LEFT (and DOWN-beats-UP) rule would jerk the wrong way for
  that frame. When both bits of an axis are set, `ReadInput` now zeroes that axis (a
  1-frame neutral instead of a wrong direction). Diagonals (non-opposing bits) are
  untouched — verified: F5+A5 → left+down (`FD=06`), F5+C6 → neutral, Ab5+A5 → neutral
  (`awcancel.lua`).

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
