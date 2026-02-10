# Code Review: Polygon Rendering Glitches (2026-02-10)

Thorough review of `src/another_world_vm.asm` against the reference C++ implementation
([Fabien Sanglard's AW-VM](https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/video.cpp)).

## Bug #1: `drawPoint` clobbers x coordinate (DEFINITE BUG)

**Location:** `drawPoint` lines 184-196

**Problem:** `LD DE, 320` overwrites DE, which held the x coordinate. Then `EXTZ XDE`
zero-extends 320 (not x), and `ADD XWA, XDE` computes `y*320 + 320` instead of `y*320 + x`.

Every single-pixel point is drawn at the wrong x position.

**Fix:** Save DE (x) before loading 320 into DE for multiply, restore after.

## Bug #2: Opcode 0x40 zoom case 3 — video2 not selected (WRONG POLYGONS)

**Location:** `_0x40_zoom_case3` (line ~1391) and `readAndDrawPolygonHierarchy` (line ~863)

**Problem:** The reference sets `m_useSegVideo2 = true` for zoom case 3, using video2 as the
polygon data source. Our code always uses `INTRO_VIDEO_1`. The `INTRO_VIDEO_2` data IS
available (bincluded), just never referenced.

Both places that resolve polygon data pointers are affected:
- Opcode 0x40 handler: `LD XIX, INTRO_VIDEO_1`
- Hierarchy function: `ADD XIX, INTRO_VIDEO_1`

**Fix:** Add a `CUR_VIDEO_DATA` variable (DD), default to `INTRO_VIDEO_1`, set to
`INTRO_VIDEO_2` in zoom case 3. Reference it in both the 0x40 handler and hierarchy.
Reset back to VIDEO_1 after the opcode completes.

## Bug #3: `readVertices` uses signed shift on unsigned product (LATENT)

**Location:** `readVertices` and `readAndDrawPolygonHierarchy` — all `SRAW 6, WA` occurrences

**Problem:** `SRAW 6, WA` performs a signed arithmetic shift right. The product `byte * zoom`
is unsigned (0 to 65025). When the product exceeds 32767 (bit 15 set), SRAW sign-extends,
giving a wrong negative result.

**Impact:** Only manifests when `byte * zoom > 32767`, i.e., zoom > 128 with large vertex
bytes. For the default zoom 0x40 (64), max product is 255 * 64 = 16320, well under 32767.
**Harmless for the intro** but would be wrong for later game parts with non-default zoom.

**Fix (for future):** Use `SRL 2, XWA` + `SRL 4, XWA` (shift 32-bit result right by 6
unsigned) instead of `SRAW 6, WA`.

## Verified Correct (no issues found)

- `CALC_LINE_XMAX_AND_XMIN` — correct signed comparison and sort
- `fillPolygon` clipping — matches reference bounds checks exactly
- `calcStep` — correct DIV/MULS/SLA logic, parameter order matches reference
- `readAndDrawPolygonHierarchy` — stack frame offsets all verified correct
- `CPT1/CPT2` 32-bit addition with carry — carry preserved across `LD` (flags unaffected)
- CUR_LINE recomputed each segment from HLINEY — incremental +320 is correct
- Draw function pointer (XHL) preserved by PUSH/POP across draw calls
- Color (C register) preserved through fillPolygon raster loop for drawLineN case
- Thread management (NEXT_THREAD, CHECK_THREAD_REQUESTS) — correct
