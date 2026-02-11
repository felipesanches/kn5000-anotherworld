# Timer-Based Frame Timing

## Overview

The Another World VM uses a `PAUSE` routine (called from `BLIT_FRAMEBUFFER`, opcode 0x10) to pace frame display. The VM bytecode writes a value (typically 1-5) to `variable[0xFF]` specifying frame duration in 20ms slices. The reference implementation: `timeToSleep = var[0xFF] * 20ms - elapsedTime`.

This replaces the original fixed busy-loop PAUSE with hardware timer-based delays that respect the VM's requested frame duration.

## Hardware Timer Configuration

### Timer Cascade (T0/T1)

Setup in `src/boot_hw_init.asm`:

```
T01MOD = 0x1D:
  bits[1:0] = 01 → T0 clock = prescaler T1 output (CPU/8)
  bits[7:6] = 00 → 8-bit timer mode (T0 overflow cascades to T1)
  bit 0     = 1  → PRRUN (prescaler run) on real hardware

TREG0 = 10  → T0 divides by 10
TREG1 = 16  → T1 divides by 16

T16RUN = 0x80  → bit 7 enables prescaler (required for MAME)
T8RUN  = 0x03  → start T0 (bit 0) + T1 (bit 1)
```

### Tick Rate Calculation (MAME, 16 MHz)

```
CPU clock:     16 MHz (2 x 8 MHz XTAL in MAME kn5000 driver)
Prescaler T1:  16 MHz / 8 = 2,000,000 Hz
T0 output:     2 MHz / 10 = 200,000 Hz
T1 output:     200 kHz / 16 = 12,500 Hz
Tick period:   80 us
```

`TICKS_PER_SLICE = 250` (250 x 80us = 20ms per slice)

### Interrupt

- INTT1 fires at 12,500 Hz, increments 32-bit `SYSTEM_TICKS` counter
- Vector table entry 21 (offset 0x54) points to `INTT1_Handler`
- Interrupt priority level 6 (`INTET01 = 0xC0`)
- `EI 0` in ENTRY enables all interrupt priorities

## PAUSE Implementation

Located in `src/another_world_vm.asm`:

1. Reads `var[0xFF]` via `_read_vm_var` to get requested slices
2. Caps value to 1-5 range (sanity check)
3. Computes `target_ticks = slices * TICKS_PER_SLICE`
4. Computes `elapsed = SYSTEM_TICKS - FRAME_START_TICKS`
5. If elapsed >= target: frame overran, return immediately
6. Otherwise: poll `SYSTEM_TICKS` until elapsed >= target
7. DJNZ fallback counter (65536 iterations) exits if timer ISR never fires

Frame start time is recorded in two places:
- `ENTRY`: before `MAIN_LOOP` (initial frame)
- `NEXT_THREAD`: at end-of-frame boundary, after `UPDATE_DISPLAY`

## Overrun Detection

After `CALL PAUSE` in `BLIT_FRAMEBUFFER`, writes a visual indicator to VRAM:
- White pixel (color 0x0F) at position (319, 20) if frame overran
- Black pixel (color 0x00) at same position if on-time

RAM variables for diagnostics:
- `FRAME_OVERRAN` (byte): 1 if last frame exceeded budget
- `LAST_FRAME_TICKS` (word): elapsed ticks of last frame
- `FRAME_START_TICKS` (dword): tick count at frame start

## MAME vs Real Hardware Differences

| Aspect | MAME | Real TMP94C241F |
|--------|------|-----------------|
| CPU clock | 16 MHz (2x8 MHz XTAL) | 25 MHz (per CLKMOD=0x04) |
| Prescaler enable | T16RUN bit 7 only | T01MOD bit 0 (PRRUN) and/or T16RUN bit 7 |
| Prescaler divisions | T1=÷8, T4=÷32, T16=÷128 | T1=÷4, T4=÷16, T16=÷64 |
| T01MOD bit layout | bits[1:0]=T0CLK | bit0=PRRUN, bits[2:1]=T0CLK |
| TICKS_PER_SLICE | 250 (for 20ms) | ~49 (at 25 MHz with fc/64) |

Current code targets MAME. For real hardware, TICKS_PER_SLICE would need recalculation, and the T01MOD bit 0 PRRUN may suffice without T16RUN.

## Bugs Found During Implementation

### MAME DEC/JP NZ Bug (Critical)

`DEC 1, rr; JP NZ, label` does not work in MAME's TLCS-900 implementation. The DEC instruction does not set flags correctly, causing incorrect branch behavior (infinite loops or skipped loops). **Fix**: Use `DJNZ rr, label` which performs decrement-and-branch as a single instruction.

### Prescaler Not Enabled

Writing `T8RUN = 0x03` only starts T0/T1 timers but does NOT enable the prescaler in MAME. The prescaler requires `T16RUN bit 7 = 1`. Without it, `SYSTEM_TICKS` never increments and the DJNZ fallback fires every frame (~130ms), making the intro noticeably slow.

### W Register Clobber in NEXT_THREAD

`LD XWA, (SYSTEM_TICKS)` in the end-of-frame block clobbers W. The subsequent thread scan relies on W=0 for array index computation (`SLA 1, WA` / `EXTZ XWA`). **Fix**: Use `LD WA, 0` (not `LD A, 0`) after recording frame start time.

## Files Modified

| File | Changes |
|------|---------|
| `src/boot_hw_init.asm` | T0/T1 timer cascade setup, prescaler enable, INTT1 interrupt config |
| `src/main.asm` | INTT1_Handler ISR, timing RAM variables, vector table extended to entry 21 |
| `src/another_world_vm.asm` | Timer-based PAUSE, frame start recording, overrun indicator, EI 0 |
