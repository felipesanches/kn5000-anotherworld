# Attempt 32: TX Double Buffering (2026-02-14)

## Hypothesis
The serial desynchronization after LED commands is caused by MAME's serial TX lacking
double buffering. The real TMP94C241 has both a TX buffer register and a TX shift register.
CPU writes go to the buffer; if the shift register is idle, the buffer auto-transfers
immediately; if busy, data waits until the current byte finishes.

MAME's `scNbuf_w()` directly overwrites the shift register, so when the firmware writes
two bytes back-to-back (padding bytes 6 and 7 of the 7-byte command cycle), the second
write corrupts the first byte mid-transmission.

## What This Tests
If TX double buffering eliminates the serial desync, all LED commands will be received
correctly by the cpanel HLE, and the correct LED pattern should appear on boot.

## Root Cause Analysis (from log.txt)
- Line 63340: `buf write: 03 (was_idle=1)` -- first padding byte after LED command
- Line 63344: `buf write: 03 (was_idle=0)` -- second byte overwrites shift register
- Line 63346: `skip_first_falling = 0` -- cleared by second write (was 1 from first)
- Line 63402: cpanel assembles `0x81` instead of `0x03` (shifted bit boundary)
- All subsequent commands garbled as `3E 11` (permanent desync)

The `C0 42` LED command seen in earlier attempts was NOT a real command -- it was garbled
data from the desync that accidentally fell in the LED command range. Only `C2 01`
(Standard Rock, row 2) was a genuine LED command.

## Fix
Added TX double buffering to `tmp94c241_serial.cpp`:

1. **New members**: `m_tx_buffer` (uint8_t) and `m_tx_buffer_full` (bool)

2. **scNbuf_w()**: When TX is busy (`was_idle=false`), store data in buffer instead of
   overwriting shift register. `was_idle` now checks all three conditions: `tx_clock_count==0`,
   `!tx_needs_trailing_edge`, `!tx_skip_first_falling`.

3. **sioclk() trailing rising edge**: After firing INTTX for the completed byte, if
   `m_tx_buffer_full`, auto-load: transfer buffer to shift register, signal tx_start_cb
   with current PFFC state, pre-output bit 0, set skip_first_falling.

4. **Timer**: No changes needed -- `need_clock` is already true when buffer is full
   (invariant: buffer fills only when at least one clock condition is active).

## Files Modified
- `tmp94c241_serial.h`: Added `m_tx_buffer` and `m_tx_buffer_full` members
- `tmp94c241_serial.cpp`: TX double buffering in scNbuf_w() and sioclk()

## Expected Outcome
- Back-to-back writes (bytes 6-7) correctly buffered: byte 6 transmits, byte 7 waits
- No shift register corruption, no skip_first_falling clobbering
- Cpanel receives all bytes correctly (no desync)
- All LED commands (not just the first) decoded correctly
- Correct LED pattern: Piano=on, Standard Rock=on, Fade Out=off

## Risk
- LOW: The change is strictly additive (new buffer pathway) and preserves existing
  behavior for single-byte writes (was_idle=true path unchanged)
- INTTX timing unchanged for shift-register-loaded bytes
- Auto-loaded bytes get their own INTTX at their trailing edge
- AW VM unaffected (uses single-byte writes with delays between them)
