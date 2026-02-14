# Attempt 26: Enable LED Diagnostic Logging (2026-02-14)

## Hypothesis
After exhaustive analysis proving the serial bit-level protocol is correct (no corruption in any scenario), the remaining LED issues must be caused by either:
1. The firmware sending different LED data than expected
2. Our LED bit-to-pin mapping being wrong
3. A non-serial MAME issue

## Investigation Summary
- Traced all 5 serial bit corruption scenarios: first byte, byte transitions, phantom bytes, rx_clock_count reset, trailing edge timing — ALL CORRECT
- Verified that trailing rising edge is the SAME edge as byte completion (not an extra edge)
- Confirmed phantom byte accept/reject mechanism works correctly with deferred flags
- Verified self-clocking bit timing
- Firmware analysis: no LED commands during early boot; LEDs set after GUI load by default config

## Fix
Enabled LOG_LEDS in VERBOSE macro to see all LED commands in MAME log output.

## Files Modified
- `kn5000_cpanel.cpp`: Added LOG_LEDS to VERBOSE define

## Expected Outcome
User checks MAME log for lines like:
```
LED command: row=C0 data=XX
LED command: row=01 data=XX
```
This tells us whether the firmware sends correct data (mapping issue) or wrong data (firmware behavior issue).

## Commit
`4257679`
