# Attempt 30 - Thinking Dump (2026-02-14)

## Starting Point

Attempts 27-29 exhaustively proved that neither protocol CONTENT nor TIMING affects the
firmware's LED decisions:
- Attempt 27: Removed spurious sync for unknowns → no effect
- Attempt 28: Extended button packets + restored full states → no effect
- Attempt 29: Reduced inter-packet gap 200µs→20µs → no effect (delivery faster but same LEDs)

The firmware sends the SAME 2 LED commands (C2 01, C0 42) regardless of what the cpanel
responds or when. The LED decisions are deterministic based on firmware internal state.

## Key Realization: HAVING Responses May Be Worse Than NO Responses

The user saw correct LEDs "many iterations ago" — likely before INTA was implemented.
Without INTA, the original firmware gets NO responses at all. The firmware's
initialization runs entirely from NVRAM/factory defaults, without any button events.

With INTA, button events ARE delivered (all zeros = "no buttons pressed"). The
application processes these events. Even though the data is "no change" (0x00),
the EVENT PROCESSING ITSELF may have side effects:

1. CPanel_RX_ButtonPacket generates 3 event queue entries per segment
2. Event queue entries include a DELTA (new XOR old) — which is 0x00 for zeros
3. Application event handlers may still run for zero-delta events
4. These handlers might clear LED state (e.g., "no sound selected" → clear PIANO LED)

## Firmware Initialization Without Responses

CPanel_SendInitSequence (init commands):
- Sends 1F DA, 1F 1A, 1D 00, DD 03, 1E 80
- NO CPanel_RX_Process after any of them — just DELAY_3000_LOOPS
- Firmware doesn't check for init responses → safe to skip

CPanel_PollStartup (20 0B poll loop):
- CPanel_RX_Process finds empty ring buffer → returns
- STATE_OF_CPANEL_BUTTONS[11] = 0x00 → encoder mode 0x0C
- Two consecutive reads: 0x0C == 0x0C → exits loop after 2 iterations

CPanel_ReadAllButtons (25 01, E2 04, 20 10, E2 11):
- CPanel_RX_Process finds empty ring buffer for each
- STATE_OF_CPANEL_BUTTONS stays all zeros
- CPanel_CheckSpecialCombos: all zeros → no special combos → normal boot

CPanel_InitButtonState (2B 00, EB 00, 20 10, E3 10):
- CPanel_RX_ProcessWithFlag finds empty ring buffer
- Event queue stays empty
- Application never receives button events

Main poll loop:
- WaitTXReady checks PE.5 → always LOW (no INTA) → returns immediately
- CPanel_RX_Process finds nothing → returns
- Application processes LED queue → sends whatever was queued during init

## Why This Might Fix FADE OUT Too

FADE OUT (row 0xC0 bit 6) might be set because:
1. NVRAM all-zeros → firmware reads some config byte as 0x00
2. 0x00 interpreted as "FADE OUT enabled" (inverted logic or default)
3. Firmware writes 0x42 (MENU + FADE OUT) to LED queue

But wait — if this is purely NVRAM-based, removing cpanel responses won't help.
The firmware would still read the same NVRAM values.

Unless the button events from cpanel queries OVERRIDE the NVRAM-based values.
For example:
- NVRAM says "FADE OUT = OFF" → LED pattern would be 0x02 (MENU only)
- Button event for CPL_SEG1 = 0x00 → "FADE OUT button not pressed"
- Application interprets "not pressed" as "FADE OUT = ON" (toggle behavior?)
- LED pattern changes to 0x42 (MENU + FADE OUT)

This seems unlikely but not impossible — toggle button logic can be counterintuitive.

## If This Works

If no-responses produce correct LEDs:
1. The root cause is INTA-delivered button events affecting LED initialization
2. Fix: suppress responses during boot, enable after LED initialization completes
3. Or: suppress only button-related responses (2B, EB, button queries)
4. Or: respond with a different packet type that doesn't generate events (sync?)

But attempt 28 tested sync vs button packets for 2B/EB with no effect...
Unless the issue is sync responses for OTHER commands (init, ping) also generating
unexpected behavior via the sync packet handler.

## If This Doesn't Work

If no-responses still produce wrong LEDs:
- The LED issue is 100% firmware-internal (NVRAM, sub-CPU, timing)
- No cpanel change can fix it
- Need to investigate NVRAM initialization: does the firmware detect all-zero NVRAM
  as corrupt and load factory defaults? Or does the checksum accidentally pass?
- May need to provide pre-initialized NVRAM data or fix NVRAM detection logic
