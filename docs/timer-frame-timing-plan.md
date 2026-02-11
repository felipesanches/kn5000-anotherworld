# Plan: Timer-Based Frame Timing with Overrun Detection

## Context

The Another World intro plays slowly in some scenes. The current frame timing uses a fixed busy-wait loop (`PAUSE`) that ignores the VM's `variable[0xFF]` (pause slices), which specifies how many 20ms slices each frame should display. Additionally, there's no way to identify which frames exceed their time budget, making performance optimization blind.

**Goal:** Use TMP94C241F hardware timers for precise frame pacing, and add visible diagnostics for frame overruns.

## How AW Frame Timing Should Work (Reference)

The VM bytecode writes a value (typically 1-5) to variable `0xFF` specifying frame duration in 20ms slices:
- 1 slice = 20ms (50 Hz), 2 slices = 40ms (25 Hz), etc.

The reference implementation: `timeToSleep = var[0xFF] * 20ms - elapsedTime`. If elapsed > target, the frame overran (no sleep).

Currently, `PAUSE` is a fixed ~65K-iteration busy-loop called from `BLIT_FRAMEBUFFER` (opcode 0x10). It doesn't read var 0xFF and has no concept of elapsed time.

## Files to Modify

- `src/boot_hw_init.asm` — Add T0/T1 timer cascade initialization
- `src/main.asm` — Add INTT1 ISR, extend vector table, add RAM variables
- `src/another_world_vm.asm` — Rewrite PAUSE, record frame start time, add overrun indicator

## Step 1: Timer Hardware Setup (`src/boot_hw_init.asm`)

Add T0/T1 cascade timer initialization (same config as original KN5000 firmware). At the end of boot_hw_init.asm, before the implicit return:

```asm
; === 8-bit Timer Setup (T0/T1 cascade for system tick) ===
LD (T01MOD), 01dh       ; T0: T32 clock (fSYS/32), T1: cascade from T0
LD (T02FFCR), 000h      ; No flip-flop
LD (TREG0), 00ah        ; T0 divides by 10
LD (TREG1), 010h        ; T1 divides by 16
LD (TRDC), 000h         ; No double-buffer
SET 1, (T8RUN)          ; Start T0+T1

; Enable INTT1 interrupt at priority level 6
LD (INTET01), 0C0h      ; bits [7:5] = 110 = level 6, INTT0 disabled
```

**Tick rate at 16 MHz:** fSYS/8 = 2,000,000 Hz → ÷10 (T0) → ÷16 (T1) = **12,500 Hz** (80 µs per tick).

**20ms = 250 ticks.** Pre-computed constant: `TICKS_PER_SLICE EQU 250`

## Step 2: Interrupt Handler and Vector Table (`src/main.asm`)

**ISR** (minimal, placed before or after `Default_Handler`):

```asm
INTT1_Handler:
    PUSH XWA
    LD XWA, (SYSTEM_TICKS)
    INC 1, XWA              ; 32-bit increment
    LD (SYSTEM_TICKS), XWA
    POP XWA
    RETI
```

**Extend vector table** from 8 entries to 22 (covers through offset 0x54 = INTT1):

```asm
ORG 0FFFF00h
VECTOR_TABLE:
    dd 00FFFEE0h           ; 0x00: Reset
    dd Default_Handler     ; 0x04
    dd Default_Handler     ; 0x08
    dd Default_Handler     ; 0x0C
    dd Default_Handler     ; 0x10
    dd Default_Handler     ; 0x14
    dd Default_Handler     ; 0x18
    dd Default_Handler     ; 0x1C
    dd Default_Handler     ; 0x20
    dd Default_Handler     ; 0x24
    dd Default_Handler     ; 0x28: INT0
    dd Default_Handler     ; 0x2C: INT4
    dd Default_Handler     ; 0x30: INT5
    dd Default_Handler     ; 0x34: INT6
    dd Default_Handler     ; 0x38: INT7
    dd Default_Handler     ; 0x3C: reserved
    dd Default_Handler     ; 0x40: INT8
    dd Default_Handler     ; 0x44: INT9
    dd Default_Handler     ; 0x48: INTA
    dd Default_Handler     ; 0x4C: INTB
    dd Default_Handler     ; 0x50: INTT0
    dd INTT1_Handler       ; 0x54: INTT1 ← our timer ISR
```

**Add RAM variables** (after `CUR_VIDEO_DATA` in the RAM section):

```asm
SYSTEM_TICKS:        DD ?   ; 32-bit tick counter (ISR-incremented, ~4883 Hz)
FRAME_START_TICKS:   DD ?   ; Tick count at frame start
LAST_FRAME_TICKS:    DW ?   ; Elapsed ticks of last frame (for diagnostics)
FRAME_OVERRAN:       DB ?   ; 1 if last frame exceeded budget, 0 otherwise
```

## Step 3: Enable Interrupts (`src/another_world_vm.asm`)

Change `EI 06` (disables all maskable interrupts) to `EI 0` (accepts all priority levels):

```asm
ENTRY:
    EI 0    ; Enable interrupts (was EI 06 = disabled)
```

This is safe because only INTT1 has a non-zero priority (level 6). All other interrupt sources default to priority 0 (disabled) after reset.

## Step 4: Record Frame Start Time (`src/another_world_vm.asm`)

In `NEXT_THREAD`, at the end-of-frame boundary (after `CHECK_THREAD_REQUESTS`, before `UPDATE_DISPLAY`), record the frame start time for the **next** frame:

```asm
; == END OF FRAME ==
LDB (CURRENT_THREAD), 0
CALL CHECK_THREAD_REQUESTS
LD A, 0FEh
CALL UPDATE_DISPLAY

; Record frame start time for next frame
LD XWA, (SYSTEM_TICKS)
LD (FRAME_START_TICKS), XWA

LD A, 0
```

Also initialize `FRAME_START_TICKS` in `ENTRY` (before `MAIN_LOOP`):

```asm
LD XWA, (SYSTEM_TICKS)
LD (FRAME_START_TICKS), XWA
```

## Step 5: Rewrite PAUSE (`src/another_world_vm.asm`)

Replace the fixed busy-loop with timer-based delay that reads VM variable 0xFF:

```asm
TICKS_PER_SLICE EQU 98     ; ~20ms at 4882.8 Hz tick rate

PAUSE:
    ; Read VM variable 0xFF (pause slices)
    PUSH XIX                ; save bytecode pointer
    LD A, 0FFh
    CALL _read_vm_var       ; DE = var[0xFF] (number of 20ms slices)

    ; Compute target ticks = slices * TICKS_PER_SLICE
    ; If slices == 0, use default of 1
    CP DE, 0
    JP NE, _pause_has_slices
    LD DE, 1
_pause_has_slices:
    LD WA, TICKS_PER_SLICE
    MUL XWA, DE             ; XWA = target_ticks (32-bit, but fits 16-bit)
    LD (LAST_FRAME_TICKS), WA  ; save target for reference (temporary, overwritten below)
    PUSH XWA                ; save target_ticks

    ; Compute elapsed = SYSTEM_TICKS - FRAME_START_TICKS
    LD XWA, (SYSTEM_TICKS)
    LD XDE, (FRAME_START_TICKS)
    SUB XWA, XDE            ; XWA = elapsed ticks

    ; Check for overrun
    POP XDE                 ; XDE = target_ticks
    CP XWA, XDE
    JP UGE, _pause_overrun  ; elapsed >= target → overrun

    ; Wait for remaining time
    LD XBC, XDE             ; XBC = target_ticks
_pause_wait:
    LD XWA, (SYSTEM_TICKS)
    LD XDE, (FRAME_START_TICKS)
    SUB XWA, XDE            ; XWA = elapsed
    CP XWA, XBC
    JP ULT, _pause_wait     ; keep waiting if elapsed < target

    ; Frame completed on time
    LD (LAST_FRAME_TICKS), WA   ; store actual elapsed
    LDB (FRAME_OVERRAN), 0
    POP XIX
    RET

_pause_overrun:
    ; Frame took longer than budget
    LD (LAST_FRAME_TICKS), WA   ; store actual elapsed
    LDB (FRAME_OVERRAN), 1
    POP XIX
    RET
```

## Step 6: Overrun Visual Indicator (`src/another_world_vm.asm`)

After `CALL PAUSE` in `BLIT_FRAMEBUFFER`, add a simple visual indicator — write a colored pixel at the top-right corner of the VGA framebuffer. Red (color index depends on current palette) for overrun, black for on-time:

```asm
; After CALL PAUSE in BLIT_FRAMEBUFFER:
LD A, (FRAME_OVERRAN)
CP A, 0
JP EQ, _no_overrun_indicator
; Overrun: write bright pixel at (319, 0)
LDB (001a0000h + 20*320 + 319), 0Fh   ; color 15 (white in most palettes)
JP _end_overrun_indicator
_no_overrun_indicator:
LDB (001a0000h + 20*320 + 319), 00h   ; color 0 (background)
_end_overrun_indicator:
```

This writes directly to VRAM at the top-right pixel after the blit, so it's visible on screen without affecting the page buffers.

## Verification

1. `make clean && make` — must build without errors
2. `make test` — run in MAME:
   - Verify the intro still plays correctly (timer didn't break anything)
   - Check if frame pacing feels more natural (scenes that were too slow should now use var 0xFF timing)
   - Look for white pixel flashes at top-right corner indicating frame overruns
3. In MAME debugger: examine `SYSTEM_TICKS` to verify timer is incrementing, `LAST_FRAME_TICKS` for frame durations, `FRAME_OVERRAN` for overrun detection
