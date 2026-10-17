# Input precision: re-architected from scratch (2026-10-17)

Felipe: "input is still messed up" after the newest-wins + note-remap fixes, and asked for
the principled approach even at a performance cost. This is the end-to-end re-evaluation of
how the port reads the keybed, what the real limits are, and what was tried.

## The ideal source — and why it is blocked on this platform

The authoritative, instant, ghost-free key signal is the **make/break FIFO** the two TG LSIs
feed the CPU at `0x98050004` (sub) / `0x98040004` (main). Each key transition is one word:
`low = key index (bit7 = make/break)`, `high = velocity` (`awfifotap.lua` decodes it; a
note-on is `vel 0x64` bit7 clear, a note-off `vel 0xFF` bit7 set — see
`notes/keybed-fifo-makebreak.md`). Reading key state from this stream would have no
voice-allocation latency, no release tail, and no ghosting.

**The module cannot use it**, for two independent hard reasons:

1. **The firmware owns the FIFO and drains it preemptively.** `awfiforate.lua`: the firmware
   reads `0x98050004` **500 times/second**. `awfifogap.lua`: the maximum gap between reads is
   **4 ms**, even during the VM's ~67 ms work phase — so it is interrupt/high-priority, not a
   cooperative task the module could starve by not yielding. If the module also read the FIFO
   it would steal events (split the stream → stuck notes). `awfifopc.lua`: the reads happen at
   firmware PC `0x48448092` / `0x484480A6`.
2. **The decoder is in read-only flash, so it cannot be hooked.** The one point that sees
   every event is the decoder `0x4844812d` (called from both the note-on `0x4844811a` and
   note-off `0x484480ea` paths with `d0` = key byte incl. bit7, `d1` = velocity). It lives at
   `0x48448…` in program flash (`0x48000000+`, not writable — `ram_probe.lua`), so an inline
   hook to mirror events into a module bitmap is impossible. The decoder also keeps no
   persistent per-key table — it writes a transient per-event record and hands off to the
   voice allocator.

So the only key state the module can read is the firmware's **voice-allocator** state in work
RAM — which is exactly what `ReadInput` already reads.

## The current source (the active-voice ring) is already optimal

`awlat2.lua` (2 ms resolution, using the 500 Hz FIFO poll as the clock) measured each RAM
signal's latency per edge:

| signal                         | press→appears | release→clears |
|--------------------------------|---------------|----------------|
| active-voice ring `0x500D1050` | **~6 ms**     | **~6 ms**      |
| held-voice mask `0x500D288C`   | ~44 ms        | ~82 ms         |

The ring is **symmetric and ~6 ms on both edges** — the fastest and cleanest RAM signal, and
the one `ReadInput` walks. The held-mask is far slower (its 82 ms release is the original
"extra kick"). There is no better RAM source to switch to.

Other checks, all clean:
- **No pollution.** `awringpure.lua`: 0/99 no-key frames in the water part had any voice —
  the game/firmware sounds nothing that would be misread as a key.
- **Ghosting is a same-scan artifact, not a human one.** `awfifotap.lua`: pressing C3+C6+Ab5
  *staggered* (as a human does) allocates all three voices (`held={48,84,80}`). The earlier
  "ghosting" only appeared when a probe pressed keys in the *same* instant.
- **Ordering is correct.** `ReadInput` runs at the end-of-frame boundary right before the new
  frame's threads execute (NextThread), i.e. the AW `updateInput()` position — fresh input,
  one tick of latency, as in the original.
- **Taps are captured, direction is correct.** `awhumanplay.lua`: rapid random-phase play
  registered 8/8 quick jump-taps. The apparent "wrong-direction frames" were a probe-phase
  artifact — `awwrongframes.lua` shows the ring is correct (e.g. `ring={84}`) while the
  *applied* var still reads the previous frame's value, because the probe sampled the var
  before that frame's `ReadInput` had run.

## What was tried for more precision — and reverted

**Sub-frame input polling** (poll the ring several times per frame from the opcode loop and
between inter-frame sleep chunks, OR-ing every press into an accumulator folded in at the next
`ReadInput`, so a press/release entirely inside one frame is never dropped). This is the
"accept a performance cost for precision" approach.

**Result: prohibitively slow, reverted.** With the sleep chunked into `POLL_MS` slices,
`DLY_TSK` rounds each small slice up to an RTOS tick and the frame ballooned. Even after
dropping the chunking and keeping only a per-opcode poll gate, the game could no longer reach
the water part within 130 s of emulated time — the per-opcode overhead on AW's millions of
bytecode-loop iterations is too much. Baseline (reverted) pace is **83.3 ms/frame**
(`awreach.lua`), the authentic ~12 fps water pace (`var[0xFF]=4 × 20 ms`). The once-per-frame
read is the right tradeoff; the overhead buys a guarantee (no dropped sub-frame tap) that the
measurements show was not actually being violated.

## Conclusion

The input **signal** is handled correctly and about as precisely as this platform allows: the
ring is 6 ms-fresh and symmetric, unpolluted, correctly mapped, read at the right point, with
newest-key-wins on overlaps. The ideal (instant FIFO events) is blocked by read-only flash and
the preemptive 500 Hz firmware FIFO drain. The residual "feel" is **inherent**: Another World
reads input once per frame, and the water part's authentic pace is ~83 ms (12 fps), so there is
~1 frame of input granularity by design.

The only lever left for a more responsive *feel* is a **faster frame pace** (lower `SLICE_MS`
or a smaller `var[0xFF]`), which makes the whole game run faster — i.e. trading authenticity
for responsiveness. That is a product choice, not a bug fix.

## The actual "wrong direction" bug — found after, and fixed

The signal analysis above is about *latency/source* and holds. But Felipe pinned the symptom:
**wrong direction, intermittent, on both the keybed and USB-MIDI** (which both feed the same
ring). That is not a signal problem — it was the **newest-key-wins** heuristic in the derive.
It assumed the ring is ordered oldest→newest (newest at the tail). `awringorder.lua` disproved
it: the voice allocator reuses freed slots, so after sustained play the ring is in *slot*
order, and **~15 % of overlaps are mis-ordered** (`newest=+1 right`, but `ring={84,77}` → the
walk picks left). Newest-wins therefore flipped Lester the wrong way intermittently.

**Fix:** resolve opposing keys with **no recency** — a sticky rule. The ring walk just ORs
held bits; the derive gives one direction alone the axis, keeps the **last-applied** direction
(`PREV_*_BITS`) while both are held, and 0 for neither. `awsticky.lua`: brush-proof (0 flips)
and clean switches resolve correctly. See GAMEPLAY-BUGFIXES.md "Bug 1 … sticky rule". This is
why the earlier `awhumanplay`/`awwrongframes` runs looked clean — they did not churn the
allocator enough to scramble the ring order the way sustained play does.

### Probes
`awfifotap.lua`, `awfiforate.lua`, `awfifopc.lua`, `awfifogap.lua`, `awlat2.lua`,
`awringpure.lua`, `awhumanplay.lua`, `awwrongframes.lua`, `awringorder.lua`, `awsticky.lua`,
`awreach.lua`, `awtiming.lua` (research-scratch). Firmware addresses from `kn7000_disassembly`
(unidasm, base `0x48400000`).
