# Attempt 24: Remove Spurious INTTX from scNmod_w (2026-02-14)

## Hypothesis
`scNmod_w` (SC1MOD write handler) fired a spurious INTTX interrupt on every mode register write. The firmware writes SC1MOD at the start of every TX sequence (SM_StartTX). A spurious INTTX could cause the TX state machine to advance prematurely (thinking byte 1 finished before it started), corrupting specific command bytes.

## Investigation
- Found `m_cpu->m_int_reg[INTES1] |= 0x80; m_cpu->m_check_irqs = 1;` in scNmod_w
- On real TMP94C241, writing the mode register configures serial mode but does NOT trigger transmit-complete interrupt
- The firmware writes SC1MOD in SM_StartTX before every command sequence

## Fix
Removed the INTTX flag set and m_check_irqs from scNmod_w. Added comment explaining why.

## Files Modified
- `tmp94c241_serial.cpp`: scNmod_w function

## Outcome
**No change** — exact same result as attempts 22-23. The spurious INTTX was not the cause.

## Analysis
The spurious INTTX likely didn't cause issues because:
- It fired before SC1BUF was written (tx_clock_count=0, was_idle=true)
- The firmware's INTTX handler checks state and only writes SC1BUF when there's data to send
- At the point of SC1MOD write, the TX state machine hasn't queued anything yet

## Commit
`a855fcd`
