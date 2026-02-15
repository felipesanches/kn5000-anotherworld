# Attempt 42: INTRX1 Missing from Compiled Binary (2026-02-14)

## Root Cause

The user's compiled MAME binary is outdated. The INTRX1 interrupt flagging code
(`m_int_reg[INTES1] |= 0x08; m_check_irqs = 1`) exists in the source file
(`tmp94c241_serial.cpp` lines 183-190) but is NOT present in the compiled binary.

### Evidence

Log analysis of `/mnt/shared/log.txt` (271,868+ lines):

| Log message | Source line | Count | Status |
|---|---|---|---|
| "RX byte received" | sioclk() line 182 | 3,523 | Present in binary |
| "INTRX pending set" | sioclk() line 187 | 0 | **MISSING from binary** |
| "Trailing rising edge" | sioclk() line 145 | 2,585 | Present in binary |
| "Finished sending byte" | sioclk() line 217 | 2,585 | Present in binary |

Lines 182 and 187 are in the SAME `if (m_rx_clock_count == 0)` block. The fact
that "RX byte received" fires 3,523 times but "INTRX pending set" fires 0 times
proves the compiled binary has an older version of this code that logs the byte
but doesn't set the interrupt flag.

### Why Right Panel Works But Left Panel Doesn't

- **Right panel**: Firmware polls via master-mode commands (E0 13). Uses INTTX1
  interrupt (which IS in the binary — 2,585 firings) to know when TX/RX
  completes, then reads SC1BUF.
- **Left panel**: Relies on INTA slave-mode reception. Cpanel drives SCLK
  (self-clock). CPU only receives, no TX. Firmware needs INTRX1 to know when
  each RX byte arrives → INTRX1 missing → firmware never notified → no events.

## Fix

**No code changes needed.** The source already has the correct INTRX1 code.
The user must rebuild MAME with the current source files.

The MAME driver repo has 424 lines of uncommitted changes across 6 files
(accumulated from attempts 27-41). These need to be synced and recompiled.

## Files (no changes this attempt)

The source is already correct. This attempt documents the root cause finding.

## Verification Steps

After rebuilding, the log should show:
1. "INTRX pending set" appearing after each "RX byte received" during INTA sessions
2. Left panel button presses producing LED reactions
3. Soft key (CPL_SEG7-10) button presses entering sub-menus

## Expected Outcome

- Left panel and center buttons should start working
- Soft keys around the screen should respond (enter sub-menus in Sound menu etc.)
- Both panels should have reliable input (right panel was already working)

## Compatibility

No driver changes — fully compatible with original firmware.
