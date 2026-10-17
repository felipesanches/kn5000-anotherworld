# Per-frame checksum comparison vs a reference VM

Grounding mechanism for finding where our KN7000 Another World port's rendering
diverges from a faithful reference, frame by frame.

## Reference choice

`another-world-vm-gui` is a **control-flow** reference only: its framebuffer uses
Pillow's float polygon fill, can't resolve variable-driven polygon positions
(falls back to canvas centre), and doesn't render text. Useless for pixels.

The pixel reference is **rustyworld** (https://github.com/EdMcBane/rustyworld, a
faithful Rust AW port with Fabien Sanglard's exact integer scanline fill). It is
fed the **original MSDOS data** (`~/compartilhado/MSDOS/`, uppercase
`MEMLIST.BIN` + `BANK0*` — the self-consistent set), whose unpacked resources
`0x11/0x17/0x18/0x19` are **byte-identical** to the resources our port runs
(verified). So both VMs execute the same bytecode/polygons/palette — any frame
divergence is pure rendering/VM-logic, not data.

Reference harness (in scratch, not committed here — it's a modified clone):
`~/compartilhado/tmp/kn7000-aw-reference/rustyworld/`. The diff + build/run recipe
are saved in `~/compartilhado/research-scratch/kn7000-aw-reference/`. Key mods:
`src/vm.rs` adds `run_headless()` (drives the intro part 0x3E81, no throttle,
stops at the 0x3E82 part-switch) and seeds var 0x3C = 0x1234 to match our port;
`src/bin/refcksum.rs` writes one `"<tick> <crc32hex>"` line per VM tick (CRC-32 of
the 64000-byte front page). Build: `cargo build --no-default-features --bin refcksum`.

## Our side

- `awcksum.lua` — write-tap on `FRAME_NO` (0x4408007C) captures the displayed
  page (`CUR_PAGE_2`) once per VM tick via `space:read_range`, appends 64000 raw
  index bytes to a `.bin` + a tick `.idx`.
- `cksum_pages.py` — CRC-32s each frame → `"<tick> <crc32hex>"` (zlib IEEE, same
  polynomial as rustyworld's `refcksum`).
- `compare_frames.py` — diffs the two logs: match count, first divergence,
  diverging tick ranges.
- `awpolydump.lua` — write-tap on `POLY_YMAX` dumps the exact inputs our port
  feeds `FillPolygon` per tick (colour, cx, cy, w, h, points), to diff against
  the reference's polygon stream.

Diagnostic replays/analysis (scratch, `~/compartilhado/research-scratch/kn7000-aw-reference/`):
`fill_fuzz.py` (ports BOTH fill algorithms to Python and compares), `recon_t3.py`,
`locate_diff.py`, `pick_dataset.py`, and the one-off asm-trace lua probes.

### Reproduce

```
# reference log
cd ~/compartilhado/tmp/kn7000-aw-reference/run
REF_BIN=... refcksum ref_checksums.log 6000
# our log
cd ~/compartilhado/kn5000-anotherworld/kn7000 && make card
AWCK_BIN=/path/our.bin AWCK_IDX=/path/our.idx AWCK_MAX=2650 \
 ../../mame-pr/kn7000 kn7000 -bios sp7001 -rompath ../../technics_romsets \
 -harddisk build/another_sd.img -autoboot_script probes/awcksum.lua -str 330 -window -nothrottle
python3 -I probes/cksum_pages.py /path/our.bin /path/our.idx our_checksums.log
python3 -I probes/compare_frames.py our_checksums.log ref_checksums.log
```

## Findings (2026-10-16)

- Reference intro = **2612 frames** (ends at LOAD 0x3E82). Frame pacing and tick
  alignment are **perfect** — run-length structure of the checksum streams is
  identical, so tick N is the same logical frame on both sides.
- **455 / 2612 frames (17%) are pixel-identical**, including a 375-frame run
  (563–937). The divergence is **content-dependent**: polygon-dense scenes differ,
  simpler/text scenes match exactly.
- Each diverging frame differs by only **~0.2% of pixels** (~100–150 of 64000),
  scattered, swapping between adjacent colour indices — the "small pixel
  imperfections" reported. 143/149 at the first content frame fall inside drawn
  polygons; 82 of them land on one correctly-shaped polygon (`poly#77`).

### Root cause: DrawPoint writes to y*288 instead of y*320 (vm.s)

Everything *except* point rendering is byte-identical to the reference, verified
by elimination:

- **Control flow is identical** — same 63 instructions at the city tick, same
  opcodes (VM_PC write-tap trace); the drawing channel kills itself at the same pc.
- **Hierarchy traversal is correct** — 22 nodes, childCounts matching the
  reference's multiset exactly, 240 children, depth 1 (`awhiertrace`/`awchildtrace`).
- **VM variables are identical** at the frame start (`awvardump.lua`).
- **The draw-set is identical** — 270 FillPolygon calls (175 non-point + 95
  point), in the **same order**, with the **same colours and bounding boxes**
  (`awseq.lua` → 0 mismatches vs the reference's `P2` dump).
- **The scanline fill is correct** — a faithful replay of the exact 270-polygon
  draw list (`replay270.py`) reproduces the reference page **pixel-perfectly (0
  diff)**; a per-polygon pixel-write trace of a converging sliver (fill#2) is
  **113/113 exact**. (An earlier "overdraw of ~3930 polygons" reading was a
  measurement artifact: the POLY_YMAX tap shared a 32-bit word with HLINEY, so it
  also fired on every scanline; likewise the per-scanline X1 tap read stale values
  on the first scanline. Both were false — ignore them.)

The real bug: comparing each polygon's actual PAGE_0 pixel coverage against the
correct algorithm (`awpixall.lua` + per-fill set diff) shows the **only**
divergent fills are the **point polygons** (90/270), each writing its single pixel
to the **wrong offset**. `DrawPoint` (vm.s) computes `y*320` as `asl 8` (`y*256`)
plus a shift-add intended to be `y*64` — but the loop had only **five** `add a2,a2`
doublings (`a2 = y*32`), giving `y*256 + y*32 = y*288`. So a point at (cx,cy) landed
at offset `y*288 + cx`, i.e. pixel `((y*288+cx) % 320, (y*288+cx) // 320)`.

Confirmed exactly: point (195,83) → `83*288+195 = 24099` → pixel (99,75); point
(203,82) → `23819` → (139,74); point (203,77) → `22379` → (299,69) — each matching
our port's wrong pixel. **Fix:** add the sixth `add a2,a2` so `a2 = y*64` and
`d0 = y*256 + y*64 = y*320`.

This accounts for the whole signature: only point-heavy frames differ,
by a scattered handful of single pixels whose colour varies with where the stray
pixel lands in the gradient — the "~0.2%/frame imperfections."

Also found (latent, not triggered in the intro): `DrawPoint` ignores the
blend/copy draw-functions (always writes the raw DRAW_COLOR), so a point polygon
with colour 0x10 (blend) or >0x10 (copy-from-page0) would render wrong too.

### Second bug: DRAW_STRING x-origin off by one column

After the DrawPoint fix, matching frames went 17% → 77.5%; the first remaining
divergence moved to tick 1120 (the IDENTIFICATION title), a tight strip
(x[169..285] y[16..22]) with a symmetric 2↔5 colour swap — a horizontal **text
shift of 8 px**. `DrawString` (vm.s) computed `x = 8*(col-1)` (`add -1,d1; asl 3`),
but the original VM uses `x = 8*col` (Fabien's drawChar indexes the page at
`col*8`; rustyworld likewise). The `-1` shifted every string 8 px (one column)
left. Fix: drop the `add -1,d1`. This fixes the remaining lab/text-scene ranges
(1120–1897) that use DRAW_STRING. (17% → 93.6%.)

### Third bug: DrawChar clips the rightmost column/row

After the DRAW_STRING fix the only residue (3 ranges, 167 frames) was 4–18 px
clustered at the right edge (x≈312–317). `DrawChar` rejected `x >= 312` and
`y >= 192`, but a glyph at col 39 (x=312) fits exactly in [312,319] and one at
y=192 fits in [192,199] — the original clips `col <= 39`, `y <= 192`. Fix:
`cmp 312`→`cmp 313`, `cmp 192`→`cmp 193` (allow x≤312, y≤192).

## Gameplay differential replay (2026-10-17)

The method above drives the **intro** (no input). To ground **gameplay**, feed BOTH VMs the
same recorded inputs and diff per frame — Felipe's idea: "run the other VM implementation with
the log of input events; both should behave identically."

- **Record inputs.** `awmonitor.lua` (passive, while you play) writes `aw-inputs.csv`: the six
  applied hero vars (0xFC,0xE5,0xFB,0xFD,0xFA,0xFE) per frame. `research-scratch/awgen.lua`
  does the same from a scripted run.
- **Reference side.** rustyworld gains `Vm::run_replay()` + a `replaycksum` bin
  (`research-scratch/kn7000-aw-reference/replay-mods/`): it OVERRIDES the hero vars from the csv
  each tick (instead of reading a device) and continues through part switches, writing the same
  `<tick> <crc32hex>` stream. Keyed frame-1 so its tick matches awcksum's tick = FRAME_NO-1.
- **KN7000 side.** `awreplay.lua` replays the csv into the port deterministically — a write-tap
  on var[0xFE] overrides the six hero vars right after `ReadInput` sets them — and captures the
  page per tick (awcksum format). `awgen.lua` captures the pages inline for a scripted run.
- **Compare.** `cksum_pages.py` + `compare_frames.py`, exactly as for the intro.

**Validated:** a scripted intro-skip + water-part up+action capture (231 frames) matched
**231/231 (100%)** KN7000 vs rustyworld — the pipeline is correct and the water-part VM is
pixel-faithful to the reference for that input. Any future divergence localizes a real VM bug.

### Reproduce (scripted)
```
cd ~/compartilhado/kn5000-anotherworld/kn7000 && make card
AWCK_MAX=230 ../../mame-pr/kn7000 kn7000 -bios sp7001 -rompath ../../technics_romsets \
  -harddisk build/another_sd.img -autoboot_script ~/compartilhado/research-scratch/awgen.lua -str 299 -window -nothrottle
cd ~/compartilhado/tmp/kn7000-aw-reference/run && \
  .../replaycksum ~/compartilhado/tmp/aw-inputs.csv ~/compartilhado/tmp/replay_checksums.log 231
cd ~/compartilhado/kn5000-anotherworld/kn7000 && \
  python3 -I probes/cksum_pages.py ~/compartilhado/tmp/awgen_pages.bin ~/compartilhado/tmp/awgen_pages.idx ~/compartilhado/tmp/kn7000_checksums.log && \
  python3 -I probes/compare_frames.py ~/compartilhado/tmp/kn7000_checksums.log ~/compartilhado/tmp/replay_checksums.log
```

### Played session: divergence found at frame 210 — in the REFERENCE (2026-10-17)

A varied scripted play session (`research-scratch/awplay.lua`: swim up+action, run right from
the beast, rapid L↔R switches with overlaps, run+jump taps, a left+down diagonal, opposite-key
brushes, run left, jump taps while running — 381 frames) first matched only 214/381, diverging at
**tick 210**, the screen transition after running right off the first land screen.

**Both VMs are deterministic**, and this is how it was proven: with the aligned convention
(KN7000 end-of-frame-T state = rustyworld start-of-tick-T+1), *all 256 VM variables were
bit-identical on both sides through game-frame 209*. The split at 210 was therefore a genuine
implementation difference, reproducible on every run.

**Localizing it:** rustyworld's `DUMP_TICK` per-opcode PCT trace vs the KN7000's `TRACE_BUF`
(dumped by `awplay.lua`) for the same tick. Frame 209 was identical (17 ops; `setvec 44→153`,
`setvec 43→5481`, `changeThreadsState(0,0x3f,resume)`, `changeThreadsState(20,22,kill)`). At 210
rustyworld ran **2009 ops — threads 0–6, 8–10, 18 each executing the same 48 ops from pc 0** —
while the KN7000 ran 137 with those threads dormant and the real scene-change handlers (43/44)
drawing the new screen.

**Root cause — a rustyworld bug.** Its `ChanStatus` had only `Running(pc)` and `Paused(pc)`: no
dead state. `Kill` (0x11) and `stop()` (deletes) set `Paused(0)`, so the scene-change's
resume-all resurrected every killed thread at pc 0 and re-ran the part's main init mid-game
(resetting Lester's X to 0, later a spurious 35-frame restart blank). The original — and the
KN7000's `OpKillThread`/`DELETE_THREAD` → `PC=0xFFFF` — never revive a killed thread.

**Fix** (reference side, `research-scratch/kn7000-aw-reference/replay-mods/`): a
`ChanStatus::Stopped` state; kill/delete → `Stopped`; pause/resume only move
`Running`↔`Paused`. **Result: play 381/381 (100%) and intro 2612/2612 (100%).** The KN7000 VM is
pixel-faithful across the whole input repertoire the reported bugs involved; the discrepancy was
the reference's.
