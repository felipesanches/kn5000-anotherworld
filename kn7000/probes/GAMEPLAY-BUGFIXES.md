# Two gameplay bugs fixed (2026-10-16)

Felipe played the water part and reported two unrelated problems: (1) key presses
sometimes produce the wrong input effect, and (2) the dynamic elements (Lester, slugs)
periodically vanish for a while, leaving only the background, then come back. Both are
fixed in `src/interp.s` / `src/vm.inc`. Each diagnosis below has a probe here that
reproduces it.

## Bug 1 — input mix-ups: a key occasionally reads as the wrong direction/action

**Cause.** The keybed read scans the TG voice-allocator held-slot bitmap `0x500D288C` and
reads each held slot's note at `0x500D1278 + slot*0x2C + 0x0C`. At note-on the firmware
sets a slot's held bit **~1 VM frame before it writes that slot's note field**. During
that one frame the slot reads either **note 0** (a fresh slot) → classified as action
(`<= 60`), or the **stale note left from the slot's previous use** → a wrong direction.
`ReadInput` runs once per VM frame (~30 ms) and only *occasionally* samples that narrow
transient — hence "sometimes a different effect, but close to correct."

`awinput_bug.lua` catches it directly (water part, rapid presses): e.g.
`down={F5} held={64:0} mask=80` (fresh slot 64, note 0 → spurious action) and
`down={C6} held={76:77}` (slot 76 still shows the previous F5's note 77 → a left flash
when C6/right was pressed).

**Fix.** A per-slot 2-frame debounce (`vm.inc`: `KBD_PREV_MASK`, `KBD_STABLE`;
`interp.s` passes A/B of the keybed scan): a slot's note is read only after its held bit
has persisted a full VM frame — by then the note field is correct — so the 1-frame
allocation transient is never acted on. Note 0 is also ignored defensively.
`awinput_fix3.lua` quantifies it: press-context wrong-direction glitch-frames drop from
(raw) to **0** with the debounce.

**Residual (not a wrong direction).** The held bitmap lags physical key-up by ~1 VM
frame (firmware key-up processing), so a released direction lingers ~30 ms — the *correct*
direction, slightly extended (`awrelease.lua` shows the sounding mask clearing ~50 ms
after key-up). That is firmware latency the ride-along module can't remove; it only
causes a brief overlap when switching keys very fast, not a wrong input.

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
