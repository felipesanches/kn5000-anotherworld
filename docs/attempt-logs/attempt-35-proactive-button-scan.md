# Attempt 35: Proactive Button Change Detection (2026-02-14)

## Hypothesis
The serial protocol is fully working — commands decode correctly, button packets
are delivered via INTA/self-clocking, and the CPU correctly receives them. However,
the firmware's steady-state polling loop only queries **right panel segment 3**
(`E0 13` every 42 iterations). Button changes on any other segment are never
reported to the CPU.

On real hardware, the two Mitsubishi M37471M2196S panel MCUs continuously scan
their button matrices and proactively push change notifications via INTA to the
CPU — independent of CPU-initiated queries. The firmware relies on this push model
for comprehensive button coverage; the periodic `E0 13` poll is supplementary.

## Evidence (from log.txt, 74,012 lines)
- 38 total commands, 15 of which are `E0 13` (right panel segment 3)
- After initialization + GUI loading, only `E0 13` is sent in steady state
- No `CPanel_ScanButtons` commands (25/E2) appear after initialization
- No `CPanel_InitButtonState` commands (2B/EB) appear after initialization
- Button responses are correctly delivered: CPU receives `03 00` (seg 3, state 0)
- No garbled commands, rx_count always 8 at tx_start (orphan fix working)

## Fix
Added `m_button_scan_timer` to the cpanel HLE that fires every 10ms (100 Hz).
The callback scans all 22 input ports (11 segments × 2 panels), compares with
`m_last_button_state`, and queues button packets for changed segments. The
existing idle_detect → INTA → self-clocking mechanism delivers the packets.

Guards prevent conflicts:
- Skip if not initialized (firmware hasn't finished init sequence)
- Skip if self_clocking or inta_asserted (firmware busy processing response)
- Skip if !rx_waiting_for_start (CPU actively transmitting)

Also enabled LOG_BUTTONS in VERBOSE mask for debugging.

## Files Modified
- `kn5000_cpanel.h`: Added `m_button_scan_timer`, `button_scan_callback` declaration
- `kn5000_cpanel.cpp`: Timer allocation, 10ms periodic start in device_reset,
  button_scan_callback implementation, LOG_BUTTONS enabled

## Expected Outcome
- Button presses on ANY segment are detected within 10ms
- Change packets are pushed to the CPU via INTA (same as real hardware MCUs)
- Firmware's CPanel_RX_ButtonPacket handler processes the change notification
- GUI updates in response to button state changes

## Risk
- LOW: The scan timer is completely independent of the serial state machine.
  It only queues packets when the bus is idle (all guards check for idle state).
  The existing INTA/self-clock delivery mechanism is unchanged.
- If button_scan_callback queues packets at the wrong time (e.g., overlapping
  with a command response), the guards (self_clocking, inta_asserted,
  rx_waiting_for_start) prevent conflicts.
