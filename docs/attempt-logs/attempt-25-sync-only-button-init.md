# Attempt 25: Replace send_all_button_states with Sync (2026-02-14)

## Hypothesis
Diagnostic change to isolate whether multi-packet self-clocking delivery (22 bytes in 11 INTA cycles) was the cause of remaining LED issues. Since all button ports default to 0x00, a sync response gives the same net result (firmware's button state array stays at initialized default).

## Investigation
- Attempts 23-24 failed to fix the issue by modifying delivery mechanism
- Need to determine if the issue is in the multi-packet delivery itself or elsewhere
- All button ports configured with IP_ACTIVE_HIGH, default 0x00 — no phantom presses
- Individual button queries (0x20/0x25/0xE0/0xE2) still return real data

## Fix
Replaced `send_all_button_states(true/false)` with `send_sync_packet()` for commands 0x2B/0xEB.

## Files Modified
- `kn5000_cpanel.cpp`: 0x2B and 0xEB command handlers

## Outcome
**No change** — exact same result as attempts 22-24. Multi-packet delivery is NOT the cause.

## Key Conclusion
The remaining LED issues (FADE OUT on, PIANO off, etc.) are **completely unrelated** to:
- INTA gap timing during multi-packet delivery
- Spurious INTTX from scNmod_w
- The 0x2B/0xEB button state initialization command

The issue must be in one of:
1. Bit-level corruption in specific serial bytes (LED commands or query responses)
2. Firmware behavior difference we don't understand
3. Command processing/response generation for other commands
4. Something entirely non-serial

## Commit
`f14e1d5`
