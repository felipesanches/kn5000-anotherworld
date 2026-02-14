# Attempt 28 - Thinking Dump (2026-02-14)

## Starting Point

Attempt 27 removed spurious sync from unknown commands — same result. Log analysis confirmed the command sequence is IDENTICAL regardless of sync/no-sync for unknown commands. The firmware's LED initialization is deterministic.

## Key Discovery: Packet Type Matters for Firmware Dispatch

The firmware's CPanel_RX_Process dispatches based on bits 5-3 of the first received byte:
```
Type 0,1: CPanel_RX_ButtonPacket → stores in STATE_OF_CPANEL_BUTTONS, adds 3 event entries
Type 2: CPanel_RX_EncoderPacket → encoder delta processing
Type 3-5: CPanel_RX_SyncPacket → does nothing (just advances pointers)
Type 6,7: CPanel_RX_MultiBytePacket → complex variable-length processing
```

When we return sync (type 3, header=0x18) for params > 0x0A, the firmware routes to SyncPacket handler which does NOTHING. No data stored, no events generated. But for button queries, the firmware expects ButtonPacket processing (stores data, generates events).

## Deep Firmware Trace: CPanel_PollStartup

```asm
CPanel_ButtonPollLoop:
    Send 20 0B              ; Query left panel, param 0x0B
    CPanel_RX_Process       ; Process response
    LD A, (STATE + 11)      ; Read offset 11
    Check bits 7,6          ; Determine encoder mode
    Compare with previous   ; Loop until stable
```

For offset 11 to be populated, the response MUST be a button packet (type 0) that stores at offset 11. With sync, offset 11 stays at 0x00 (never written). With button packet (data=0x00), offset 11 = 0x00 (written). Same value, but the PROCESSING differs (event queue gets entries).

## Header Encoding for Extended Segments

CPanel_RX_ButtonPacket computes storage offset:
```asm
AND W, 04fh              ; Keep bit 6 + lower 4 bits
BIT 006h, W              ; Test panel flag (bit 6)
JR Z, skip               ; If right panel, offset = segment
SUB W, 030h              ; If left panel, offset = segment + 0x10
```

For `20 0B` (left panel) returning header 0x4B (with panel flag):
- W = 0x4B & 0x4F = 0x4B, bit 6 set → 0x4B - 0x30 = 0x1B (27)
- Stores at offset 27, NOT 11!

For `20 0B` returning header 0x0B (WITHOUT panel flag):
- W = 0x0B & 0x4F = 0x0B, bit 6 clear → offset = 0x0B (11)
- Stores at offset 11 ✓

The real panel MCU must return the packet without the left panel flag for param 0x0B, even though the command is addressed to the left panel. This is intentional — segment 0x0B is an "absolute" hardware status register that maps to a fixed offset regardless of panel.

## LED Table Analysis: EB7FEC is NOT Boot Defaults

Read the actual ROM data at offset EB7FEC:
```
Row 0: 0xFF (all on)    Row 5: 0x01 (just bit 0)
Row 1: 0xFF             Row 6: 0xFF
Row 2: 0xFF             Row 7: 0xFF
Row 3: 0x3F             Row 8-10: 0xFF
Row 4: 0xFF             Row 11-14: various
```

These are "all LEDs on" patterns (constrained by physical LED count per row). This is the LED TEST table, not boot defaults. LABEL_FB7C31 sets LEDs from this table (test mode), LABEL_FB7C60 clears all LEDs to 0 (also using this table for iteration).

## Firmware LED Decisions are Configuration-Based

Set_LEDs at FC71B2:
- Input: WA = row index (0-14), C = pattern byte
- Looks up protocol value from Protocol_values_for_LED_rows
- Stores [protocol_value, pattern] and queues for TX

The pattern byte comes from the firmware's internal configuration state, built during boot from:
1. Custom data ROM (IC19 at 0x300000) — factory defaults
2. Backup SRAM (nvram2 at 0x1E0000) — user settings

In MAME, nvram2 starts as ALL ZEROS (DEFAULT_ALL_0). The firmware should detect this as corrupt (checksum mismatch) and initialize from factory defaults. If this initialization works correctly, LED defaults should match real hardware.

## Root Cause Assessment

After 27 attempts, the serial protocol is exhaustively verified correct. The remaining LED issues are most likely caused by:

1. **Firmware configuration initialization** — NVRAM starts all-zero, firmware may not properly reinitialize defaults in MAME
2. **Missing sub-CPU communication** — some settings may depend on sub-CPU data that isn't available in MAME
3. **Missing inter-CPU latch** — firmware reads 0x120000 for sub-CPU data, may get wrong values
4. **Different timing** — some initialization paths may be timing-dependent

These are NOT cpanel protocol issues. The cpanel serial protocol is correct and commands are properly received and processed.

## Decision: Try Button Packets Anyway

Even though the root cause is likely not cpanel-related, returning proper button packets is the CORRECT behavior for the cpanel HLE:
1. Params 0x0B should return button packets (verified from firmware code)
2. 0x2B/0xEB should return button states (even if data is 0x00)
3. Event queue population may have subtle effects on firmware processing

If this doesn't fix LEDs, the next investigation should focus on NVRAM initialization and firmware configuration code, not cpanel protocol.
