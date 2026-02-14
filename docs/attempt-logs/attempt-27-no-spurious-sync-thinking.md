# Attempt 27 - Thinking Dump (2026-02-14)

## Starting Point

Attempt 26 enabled LOG_LEDS and produced a diagnostic log (`/mnt/shared/log.txt`, 65835 lines). The log revealed the root cause of remaining LED issues.

## Key Discovery: Only 2 LED Commands in Entire Boot

Grepping the log for `LED command:` returned only:
- `LED command: row=C2 data=01` (Standard Rock ON — correct)
- `LED command: row=C0 data=42` (COMPOSER:MENU + FADE OUT ON — FADE OUT is wrong!)

Row 0x01 (PIANO) is NEVER sent by firmware. On real hardware, PIANO LED is on at boot, meaning the firmware must send row 0x01 with bit 0 set. In MAME, something prevents this.

## Key Discovery: 9 Unknown Commands Generate Spurious Sync

Grepping for `Unknown command` found:
- `E1 80` (1 time)
- `60 20` (1 time)
- `30 14` (1 time)
- `3C 10` (1 time)
- `3E 11` (5 times)

All hit the default case which calls `send_sync_packet()`.

## Analysis: What Are These Unknown Commands?

Analyzing command byte structure:
- `E1 80`: bits 7-5 = 0b111 = right panel range. Close to E0/E2/E3 (queries) but E1 is not a known query. Param 0x80 is far outside button segment range (0-10). Likely a right-panel LCD or display command.
- `60 20`: bits 7-5 = 0b011 = left panel. Not in any known command range. Could be LCD display.
- `30 14`: bits 7-5 = 0b001 = left panel. Could be 7-segment or encoder config.
- `3C 10`: bits 7-5 = 0b001 = left panel. Same range as 0x30.
- `3E 11`: bits 7-5 = 0b001 = left panel. Repeats 5 times — could be writing to multiple LCD positions.

These all appear AFTER the LED commands in the boot sequence. They're configuration commands that the real panel MCU processes silently (no response expected).

## Analysis: How Spurious Syncs Disrupt Firmware

When an unknown command arrives, our default case queues a sync response. The sequence:

1. Firmware sends `E1 80` (a "fire and forget" command, no response expected)
2. Firmware's TX state machine sends phantom byte (SM_TXComplete)
3. After phantom byte, our idle_detect fires (50µs sliding window)
4. INTA asserted, self-clocking delivers sync bytes
5. Firmware's INTA handler fires, receives unexpected sync data
6. Firmware's internal protocol state is now wrong
7. Firmware sends next command (`C0 42`) but its state machine may be in a different state

The unexpected sync can cause:
- Firmware to take different code paths in LED initialization
- Some LED commands to be skipped entirely (like row 0x01 for PIANO)
- Wrong data values in LED commands (FADE OUT bit set when it shouldn't be)

## Analysis: Why Serial Protocol is CORRECT But LED State is Wrong

This is the key insight from attempts 22-26: the serial bit-level protocol is exhaustively verified correct. No corruption in any scenario (first byte, byte transitions, phantom bytes, self-clocking, scNcr_w resets). The problem is at the APPLICATION level — we're sending correct responses but at the WRONG TIME (to commands that don't expect them).

The firmware's serial state machine processes responses asynchronously via INTA. If an unexpected INTA fires while the firmware is between commands (during its LED initialization routine), the INTA handler processes the sync and potentially modifies state that the LED routine depends on.

## Decision: Remove Default Sync Response

The fix is simple: change the default case to not send any response. This is safe because:
1. All known commands that need responses have explicit cases (init, query, button init)
2. LED commands already have explicit cases with no response
3. If any unknown command actually needs a response, we'll see an ERROR dialog immediately
4. The 9 unknown commands are very likely "fire and forget" panel configuration

## Alternative Hypothesis Considered: Wrong Bit Mapping

Could our LED bit-to-pin mapping be wrong? The firmware sends `C0 42`:
- Bit 1 (0x02) → COMPOSER: MENU — correct, this IS on at boot on real hardware
- Bit 6 (0x40) → FADE OUT — incorrect, this should NOT be on at boot

But this doesn't explain PIANO never being sent. The firmware's internal state is wrong, not our mapping. If the firmware correctly initialized, it would send:
- Row 0xC0 with bit 1 set, bit 6 clear (COMPOSER: MENU on, FADE OUT off)
- Row 0x01 with bit 0 set (PIANO on)

The spurious syncs from unknown commands are the most likely cause of the firmware's wrong initialization state.

## What Could Go Wrong

If one of the "unknown" commands (E1, 60, 30, 3C, 3E) actually expects a response:
- The firmware would timeout waiting for it
- "ERROR in CPU data transmission" dialog would appear
- We'd need to add that specific command back with a proper response

Risk level: LOW — these commands appear in a batch after LED commands and before the sequence ends. The firmware doesn't show ERROR with the current code (where all unknowns get sync), so the sync isn't PREVENTING an error. It's CAUSING unwanted behavior. Removing it should be neutral or beneficial.
