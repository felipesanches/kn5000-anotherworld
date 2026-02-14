# Attempt 27: Remove Spurious Sync for Unknown Commands (2026-02-14)

## Hypothesis
After analyzing the MAME log from attempt 26, the root cause of remaining LED issues is clear:
- The firmware sends only 2 LED commands during boot: `C2 01` and `C0 42`
- Row 0x01 (PIANO) is NEVER sent — that's why PIANO LED is off
- 9 unknown commands (`E1 80`, `60 20`, `30 14`, `3C 10`, `3E 11`x5) hit the default case
- The default case sends sync responses, delivered via INTA self-clocking
- These spurious syncs disrupt the firmware's serial state machine, causing it to:
  - Set wrong LED values (FADE OUT on when it shouldn't be)
  - Skip LED commands it would otherwise send (PIANO row never sent)

The unknown commands are likely LCD display, encoder config, or 7-segment updates that the real panel MCU processes silently (no response).

## Log Evidence
Full boot command sequence from `/mnt/shared/log.txt`:
```
1F DA (init → sync)
1F 1A (init → sync)
1D 00 (init → sync)
DD 03 (init → sync)
1E 80 (init → sync)
20 0B (query → sync)
20 0B (query → sync)
25 01 (query → button)
E2 04 (query → button)
20 10 (query → sync)
E2 11 (query → sync)
[gap]
20 00 (ping → sync)
E0 00 (ping → sync)
2B 00 (button init → sync)
EB 00 (button init → sync)
20 10 (query → sync)
E3 10 (query → sync)
C2 01 (LED: Standard Rock ON ✓)
E1 80 (UNKNOWN → spurious sync!)   ← PROBLEM
C0 42 (LED: FADE OUT + COMPOSER:MENU)
60 20 (UNKNOWN → spurious sync!)   ← PROBLEM
30 14 (UNKNOWN → spurious sync!)   ← PROBLEM
3C 10 (UNKNOWN → spurious sync!)   ← PROBLEM
3E 11 (UNKNOWN → spurious sync! x5) ← PROBLEM
```

## Fix
Changed the default case in `process_command()` to NOT send any response for unrecognized commands. Only known init/query commands send responses.

## Files Modified
- `kn5000_cpanel.cpp`: default case in process_command() switch

## Expected Outcome
Without spurious sync responses for unknown commands:
- Firmware's serial state machine is never disrupted by unexpected RX data
- Firmware may send MORE LED commands (including row 0x01 for PIANO)
- FADE OUT bit in row 0xC0 may not be set

If this causes ERROR dialog (meaning some unknown command DID need a response), we'll add that specific command back.
