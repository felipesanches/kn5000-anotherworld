# Attempt 22: Defer INTTX1 to Trailing Rising Edge (2026-02-14)

## Hypothesis
Every byte's MSB (bit 7) was corrupted during serial TX. After the CPU's last falling edge (tx_clock→0), `need_clock` became false and the baud rate timer stopped. Between timer ticks, the INTTX1 ISR wrote SC1BUF (pre-outputting bit 0 of the NEW byte on TXD). When the timer resumed for the new byte, the cpanel sampled the new byte's bit 0 as the old byte's bit 7.

## Investigation
- Traced the full serial TX bit timing: falling edges output bits, rising edges trigger cpanel sampling
- Identified that INTTX fires on the falling edge when tx_clock_count reaches 0
- The ISR runs between timer ticks (MAME's event-driven scheduler), writing SC1BUF before the 8th rising edge
- This means cpanel never gets a clean rising edge to sample bit 7

## Fix
Added `m_tx_needs_trailing_edge` flag to `tmp94c241_serial.h/.cpp`:
- When tx_clock_count reaches 0 on falling edge: set flag instead of firing INTTX
- Include flag in `need_clock` check so timer generates one more rising edge
- On that rising edge: forward sclk_out_cb to cpanel (samples bit 7), THEN fire INTTX
- ISR writes SC1BUF after cpanel has sampled bit 7

## Files Modified
- `tmp94c241_serial.h`: Added `bool m_tx_needs_trailing_edge`
- `tmp94c241_serial.cpp`: Constructor, device_start/reset, sioclk rising/falling edge, timer_callback

## Outcome
**Major improvement!** No ERROR dialog, correct timing, many LEDs correct. But some specific LEDs wrong:
- FADE OUT on (should be off)
- PIANO off (should be on)
- Standard Rock correct
- LEDs change state at expected moments during boot

## Commit
`ae5891c`
