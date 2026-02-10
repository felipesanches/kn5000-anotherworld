# Debug Progress Report: Grey Screen Investigation

**Date:** 2026-02-10
**Previous session:** Fixed SETUP_PALETTE palette index extraction (commit 45ef21a)

## Key Discovery: Grey Screen is Actually Correct Behavior

The "light grey screen" is **not a bug** — it's the AW palette being applied correctly:

- **Before setPalette:** VGA_Setup color 0 = (0,0,0) = pure black
- **After setPalette(1):** Palette 1 color 0 = (4,4,4) in VGA DAC = very dark grey
- The page buffers contain color index 0, so the screen shows dark grey

**Proof:** Running 55 instructions (including setPalette), then resetting DAC color 0 to (0,0,0) → screen goes back to black. This confirms the palette write works correctly.

## What Works

1. **SETUP_PALETTE** — Fully functional. Correctly reads palette resource data, computes pointer offsets, extracts R/G/B nibbles, scales 4-bit to 6-bit, writes to VGA DAC with auto-increment. Verified with:
   - All-black palette test → black ✓
   - All-red palette test → red ✓
   - Palette data pointer verification → reads correct byte (0x01) at palette 1 offset ✓
   - Color 0 reset after setPalette → black ✓

2. **VGA DAC writes** — Work correctly without delays (contrary to earlier hypothesis about bus timing)

3. **VM execution** — Runs correctly through at least 55 instructions (thread scheduling, bytecode parsing, opcode dispatch all work)

4. **condJmp (0x0A)** — Is fully implemented (despite code review saying otherwise). Variable-length encoding handled correctly (byte literal, 16-bit immediate, variable reference).

## Actual Problem: No Polygon Content Visible

The screen shows solid grey (correct palette color 0) but **no polygons or animations**. The VM continues executing but nothing gets drawn visibly.

### Possible Causes (to investigate)

1. **Polygon rendering hangs** — readAndDrawPolygon might enter an infinite loop on certain video data, halting VM execution

2. **Bytecode desync from unimplemented opcodes** — Some opcodes might not consume the correct number of bytes. Need to verify ALL stubs consume correct byte counts.

3. **Wrong page displayed** — Polygons might be drawn on a page that's never copied to VRAM by UPDATE_DISPLAY

4. **Video data interpretation bugs** — The 0x80 opcode computes `offset = ((opcode << 8) | fetch_byte()) * 2` and indexes into INTRO_VIDEO_1. If the offset or data interpretation is wrong, polygon data would be garbage.

5. **Page pointer corruption** — If CUR_PAGE_PTR_1 (draw target) points to the wrong memory, polygon fills write to incorrect locations

### Immediate Next Steps

1. **Check if VM is still running or hung** — Add a frame counter or visual indicator to UPDATE_DISPLAY to see if frames keep advancing after setPalette

2. **Verify all opcode stubs consume correct bytes** — Audit every opcode handler for correct byte consumption, especially:
   - 0x0C (resetThread) — 3 bytes
   - 0x12 (drawString) — 5 bytes
   - 0x13 (SUB) — 2 bytes
   - 0x14 (AND) — 3 bytes
   - 0x15 (OR) — 3 bytes
   - 0x16 (SHL) — 3 bytes
   - 0x17 (SHR) — 3 bytes

3. **Check opcode 0x19 (LOAD)** — Some LOAD calls have resourceId > 0x91 which should trigger part switching. If the stub doesn't handle this, the VM might try to switch to unavailable parts.

4. **Test if polygon rendering actually executes** — Add a visual indicator inside readAndDrawPolygon to confirm it's being called

## Binary Search Results (with proper PUSH/POP counter preservation)

| Instructions | Result | Notes |
|---|---|---|
| 10 | Black | Correct |
| 50 | Black | Correct |
| 52 | Black | Correct |
| 53 | Black | Correct |
| 54 | Black | Last instruction before setPalette |
| 55 | Grey | setPalette(1) changes color 0 to dark grey |
| (full loop) | Grey | Same grey, no content |

**Important:** Earlier tests without PUSH/POP gave misleading results because EXECUTE_INSTRUCTION clobbers DE (the loop counter).

## Bytecode Execution Trace (first 55 instructions)

### Frame 1 (Thread 0)
1. CALL 0xE7
2-3. fillVideoPage(1,0), fillVideoPage(2,0)
4. selectVideoPage(1)
5-7. blit(1), blit(0xFF), blit(2)
8. RET
9. movConst(0xFF, 1)
10. setVect(60, 0x7F)
11. movConst(0xF4, 0)
12. PAUSE → end of frame → CHECK_THREAD_REQUESTS commits thread 60

### Frame 2 (Thread 0)
13. playMusic
14-40. ~27 LOAD instructions (resource loading stubs)
41. playMusic
42-45. setVect(1, 0x22D5), setVect(2, 0x23B1), setVect(3, 0x22CC), setVect(60, 0x0094)
46. killThread → NEXT_THREAD finds thread 60

### Frame 2 (Thread 60, PC=0x7F)
47. addConst(0xC7, 1)
48. blit(0xFF)
49. selectVideoPage(0xFF)
50. condJmp(NE, var[0xFA], 0, 0x09B8)
51. copyVideoPage(0x40, 0xFF)
52. PAUSE → end of frame → commits threads 1,2,3,60

### Frame 3 (Thread 1, PC=0x22D5)
53. selectVideoPage(0)
54. fillVideoPage(0, 2)
55. **setPalette(1)** ← This is where the grey appears
56+. Video/polygon instructions (0x84, 0x84, 0x86, ...) — **NOT YET VERIFIED**

## Code State

- SETUP_PALETTE: Real code active (was temporarily disabled/replaced during debugging, now restored)
- Diagnostic: Removed, MAIN_LOOP running normally
- No uncommitted changes beyond the diagnostic removal
