# Frame pacing: the Another World model (not a fixed delay)

Felipe asked why the game felt slower than other AW implementations. Measured
(`awpace.lua`, water part): **~97 ms/frame** = ~67 ms of VM/render work **+ a flat 30 ms
`DLY_TSK`** we bolted on every frame. That flat delay was non-authentic.

Real Another World paces each frame to `var[0xFF]` (PAUSE_SLICES, set by the bytecode) ×
20 ms, counting the work toward that period and sleeping only the remainder (rustyworld
`vm.rs`: `expected_delay = vars[0xFF] * 20ms`, then `sleep(expected_delay - elapsed)`).
The water part asks for `var[0xFF] = 4` → an 80 ms target (AW's deliberately slow
water-entry).

**Change (interp.s NextThread end-of-frame; vm.inc):** sleep `var[0xFF] * SLICE_MS −
elapsed`, where `elapsed` is this frame's work measured with the firmware's 1 kHz counter
`KERNEL_MS` (`0x500D3C68`, verified 999 ticks/s). Clamped to `[MIN_YIELD_MS, MAX_YIELD_MS]`
so the firmware (keybed/panel) always gets time and a bad slice count can't freeze us.
`SLICE_MS = 20` is authentic; lower it to run faster than the original.

Also rewrote `CopyPage`'s two copy loops from byte-at-a-time to **32-bit words** (pages are
0x10000-aligned and the scroll offsets are 320-aligned, so every copy is 4-byte aligned).
This cuts the per-frame work, which both speeds frames and leaves more time to yield.

Result: **~82 ms/frame**, matching the authentic 80 ms, down from 97 ms.

**Verification.** Rendering is unchanged by these edits: per-tick front-page CRCs are
identical to the pre-change (committed) build — `our[i] == base[i-1]` for 149/150 ticks, a
one-tick capture-alignment shift from the altered startup timing, same content
(`probes/awcksum.lua` + `cksum_pages.py`). The word-copy encodes to MAME's 32-bit
`mov (aM),Dn` / `mov Dn,(aM)` (opcodes 0x72/0x63), byte-exact with the old `movbu` loop.

Note: the intro-vs-`ref_checksums.log` divergence seen while verifying this change was a
separate pre-existing bug (the intro-skip reading the noisy `0x50149690` flag) — fixed, see
GAMEPLAY-BUGFIXES.md bug 3; the intro now matches the reference 100% again.
