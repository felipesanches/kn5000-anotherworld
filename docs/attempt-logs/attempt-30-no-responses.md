# Attempt 30: Diagnostic — No Responses to Any Command (2026-02-14)

## Hypothesis
The user saw correct LEDs in an earlier iteration, possibly before INTA was implemented.
Without INTA, the original firmware received NO responses to any cpanel command. The
firmware gracefully handles empty RX ring buffers — CPanel_RX_Process and
CPanel_RX_ProcessWithFlag just return when there's no data.

In the no-response scenario:
- CPanel_PollStartup: STATE_OF_CPANEL_BUTTONS[11] stays 0x00, encoder mode = 0x0C,
  two consecutive reads agree → passes after 2 iterations
- CPanel_ReadAllButtons: no button data → all zeros → no special combos
- CPanel_InitButtonState: no button events → event queue empty
- Application initializes LEDs PURELY from NVRAM/factory defaults

With INTA responses, button events (all zeros) may trigger application code paths that
CLEAR or OVERRIDE NVRAM-based LED defaults. For example, a "no button pressed" event
for the sound group might be interpreted as "no sound selected" → PIANO LED not set.

## What This Tests
If the no-response path produces correct LEDs, it confirms that INTA-delivered responses
interfere with the firmware's LED initialization. The fix would then be to either:
1. Not respond to specific commands during initialization
2. Respond with data that doesn't trigger unwanted event processing
3. Delay responses until after LED initialization completes

## Fix
Commented out ALL send_sync_packet(), send_button_packet(), and send_all_button_states()
calls for init, query, and button-init commands. Only LED commands are still processed.
No bytes are ever queued → INTA never fires → firmware runs in no-response mode.

## Files Modified
- `kn5000_cpanel.cpp`: process_command() — all non-LED responses suppressed

## Expected Outcome
If LEDs are correct: INTA responses are the root cause of wrong LED initialization.
If LEDs are still wrong: the issue is purely firmware-internal (NVRAM, sub-CPU data, etc.)
and cannot be fixed from the cpanel HLE.

## Risk
"Error in CPU data transmission" dialog may appear. If it does, the firmware IS checking
for responses, and we'd need to find which specific commands require responses.
