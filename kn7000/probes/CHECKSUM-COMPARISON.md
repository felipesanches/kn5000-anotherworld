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

### Root cause: polygon overdraw (not the fill, not the inputs)

- **The fill rasterizer is provably identical.** `fill_fuzz.py` renders all 175
  real tick-2 city polygons through both ports of the algorithm → **0 pixels
  differ**. CalcStep, the 0x7FFF/0x8000 edge rounding, inclusive spans, special
  colours (0x10 blend, >0x10 copy-page0), the degenerate-point case, Scale,
  ReadVertices, the hierarchy traversal and the 0x80/0x40 opcode decode all match.
- **Per-polygon inputs are correct.** `awpolydump.lua` shows `poly#77`'s input
  (`color=4 cx=160 cy=78 w=255 h=95 pts=…`) is **byte-identical** to the reference.
- **VM variables are identical** at the frame start (`awvardump.lua`:
  `3c=4660 54=129 bc=16 c6=128 c7=1 dc=33 e4=20 f2=4000 ff=1`).
- **The hierarchy traversal is correct**: `awhiertrace`/`awchildtrace` show 22
  hierarchy nodes with childCounts matching the reference's multiset exactly, 240
  children, all valid offsets, depth 1 — no runaway recursion.
- Yet our port issues **far more FillPolygon calls per frame than the reference**
  (the reference draws ~175 for the city; our port draws the 175 correct ones
  **plus** garbage: thousands of harmless `n=2` no-ops and ~680 malformed polygons
  — real shapes at a wrong y, or truncated point counts). Those ~680 garbage polys
  **overdraw** correctly-rendered pixels — e.g. they corrupt 82 px of the
  correctly-drawn `poly#77` in the tick-3 frame.

So the rendering differences come from **excess top-level polygon draws
(overdraw)** — the drawing channel executes more VIDEO ops than it should within a
frame — not from the rasterizer, the polygon inputs, the hierarchy, or the VM
variables. Pinning the exact divergent bytecode branch needs a single-run
executed-PC trace of the drawing channel (next step; `FRAME_NO`-keyed tick
attribution jitters slightly across separate MAME runs, so it must be captured in
one run).
