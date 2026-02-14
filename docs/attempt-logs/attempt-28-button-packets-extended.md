# Attempt 28: Button Packets for Extended Segments + Restore Full Button States (2026-02-14)

## Hypothesis
The firmware's CPanel_RX_Process dispatches based on packet TYPE (bits 5-3 of response header). Sync (type 3) goes to CPanel_RX_SyncPacket which does nothing. Button (type 0) goes to CPanel_RX_ButtonPacket which stores data AND adds events to the event queue. Even with data=0x00, event presence may affect subsequent processing.

Two specific issues:
1. **Param 0x0B returns sync**: CPanel_PollStartup sends `20 0B`, processes response, then reads `STATE_OF_CPANEL_BUTTONS + 11`. With sync, offset 11 is never populated (no button packet handler fires). With a proper button packet, offset 11 gets written.
2. **0x2B/0xEB return sync**: CPanel_InitButtonState sends these, then calls CPanel_RX_ProcessWithFlag. With sync, the event queue stays empty. With full button states (22 bytes/panel), the event queue gets 11 entries per panel, which may affect subsequent firmware processing paths.

## Investigation Summary
- Firmware analysis: CPanel_RX_ButtonPacket stores data at `STATE_OF_CPANEL_BUTTONS + offset` AND adds 3 entries to event queue
- CPanel_RX_SyncPacket does neither — the packet type determines routing
- For param 0x0B, the response must NOT have the left panel flag (bit 6) in the header, so the firmware computes offset = 0x0B = 11 (not 0x1B = 27)
- CPanel_PollStartup polls param 0x0B in a loop, reads offset 11, checks bits 7,6 for encoder mode
- LED initialization table at EB7FEC is for LED test (all 0xFF), NOT boot defaults
- Set_LEDs at FC71B2 uses Protocol_values_for_LED_rows to map index→protocol value
- Firmware sends ONLY 2 LED commands total (no more after boot) — the state is final

## Fix
1. Return button packet for param 0x0B (without panel flag, so offset 11 is populated)
2. Restore 0x2B/0xEB to `send_all_button_states()` instead of sync
3. Keep sync for params 0x10, 0x11 (unknown format on real hardware)

## Files Modified
- `kn5000_cpanel.cpp`: query command handlers, 0x2B/0xEB handlers

## Expected Outcome
If event queue processing affects LED initialization decisions, more correct LED states.
If not, the deeper issue is firmware configuration (NVRAM/defaults), not cpanel protocol.
