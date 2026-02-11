# Plan: Fix Polygon Rendering Glitches

## Context

The Another World VM port on KN5000 shows a grey screen with correct palette but **no visible polygon content**. After analyzing the polygon rendering pipeline against the reference MAME HLE implementation, three bugs were found that cause incorrect rendering and potential memory corruption.

**File to modify:** `src/another_world_vm.asm`

## Bug #1: drawLine off-by-one (causes buffer overflow/corruption)

**Location:** `drawLineN` (line 101), `drawLineP` (line 140), `drawLineBlend` (line 167)

**Problem:** Loop count `HL = xmax - xmin` is used with `DJNZ HL`, which decrements-then-tests. This draws `xmax - xmin` pixels instead of `xmax - xmin + 1` (inclusive range).

**Critical case:** When `xmax == xmin` (single pixel), `HL = 0`. DJNZ decrements to `0xFFFF` (non-zero), causing 65,536 iterations — massive buffer overflow that corrupts all VM state. This is likely the root cause of the rendering failure.

**Fix:** Add `INC HL` after `SUB HL, (LINE_XMIN)` in all three functions:

- `drawLineN` line 101: `SUB HL, (LINE_XMIN)` → add `INC HL` after
- `drawLineP` line 140: `SUB HL, (LINE_XMIN)` → add `INC HL` after
- `drawLineBlend` line 167: `SUB HL, (LINE_XMIN)` → add `INC HL` after

## Bug #2: fillPolygon hliney > 199 jumps to wrong label

**Location:** `fillPolygon` line 716-717

**Problem:** When `HLINEY > 199`, the code jumps to `POLYGON_RASTER_LOOP` which continues processing the next polygon segment. The reference code does `return` (exits the entire fillPolygon function). This causes polygons that extend below the screen to continue rendering with wrong edge parameters, producing garbage.

**Current code:**
```asm
CPW (HLINEY), 199
JP GT, POLYGON_RASTER_LOOP    ; BUG: continues with next segment
```

**Fix:**
```asm
CPW (HLINEY), 199
JP GT, end_of_fillPolygon      ; EXIT: stop rendering this polygon
```

## Bug #3: drawPoint writes to wrong location and size

**Location:** `drawPoint` lines 181-192

**Problem (3 issues):**
1. Writes to hardcoded VRAM address `0x1A0000` instead of `CUR_PAGE_PTR_1` (page buffer)
2. `LD (XIX), BC` writes 2 bytes instead of 1 (writes color C + garbage B)
3. `LD WA, 0` doesn't clear upper XWA bits; subsequent `MUL XWA, 320` may use garbage upper bits (actually MUL XWA,DE does WA×DE→XWA so upper bits get overwritten — but XDE upper bits from `ADD XWA, XDE` are still garbage)

**Fix:** Replace with:
```asm
drawPoint:
    PUSH XIX
    LD XWA, 0
    LD WA, HL              ; XWA = y (zero-extended 32-bit)
    LD DE, 320
    MUL XWA, DE            ; XWA = y * 320
    EXTZ XDE               ; zero-extend x to 32-bit
    ADD XWA, XDE           ; XWA = y*320 + x
    LD XIX, (CUR_PAGE_PTR_1)
    ADD XIX, XWA
    LDB (XIX), C           ; write 1 byte (color)
    POP XIX
    RET
```

## Verification

1. `make clean && make` — must build without errors
2. `make test` — run in MAME, verify polygon content appears on screen after setPalette
3. The intro cinematic should show the Interplay logo and opening sequence polygons instead of a solid grey screen
