# Attempt 36: Piggyback Button Changes on Command Responses (2026-02-14)

## Hypothesis
The timer-based proactive button scan (attempt 35) fires INTA at arbitrary times,
potentially during the firmware's WaitTXReady window. WaitTXReady checks PE.5 — if
HIGH (INTA asserted), it times out (480µs delay), retries up to 6 times, and
increments `CPANEL_TX_RX_FLAGS bits[7:6]`. When the main loop reaches LABEL_FC3E94
with bits[7:6] != 0, it RESETS the ring buffer pointers and SKIPS `CPanel_RX_Process`,
discarding all received button data.

This explains the intermittent input: buttons that change while the firmware is NOT
in WaitTXReady work fine; buttons that change during WaitTXReady are detected but
their data is discarded.

## Root Cause Analysis (from firmware disassembly)
1. **INTA_HANDLER** (FC442B): switches SC1 to slave mode, enables RX, sets state
   machine to RXByte1 → firmware correctly receives button packets via self-clocking
2. **CPanel_RX_Process** (FC3EB4): drains ring buffer, dispatches to ButtonPacket/
   SyncPacket handlers — works correctly when called
3. **LABEL_FC3E94**: checks `bits[7:6]` — if non-zero, RESETS ring buffer and SKIPS
   CPanel_RX_Process → all data lost
4. **WaitTXReady** (line 583): checks PE.5 → if HIGH, delays 480µs, retries,
   increments bits[7:6] → triggers the reset in step 3
5. **INTA disabled during TX**: firmware sets `INTEAB = 007h` during command
   transmission, `INTEAB = 005h` when idle

The race: button_scan_callback fires → idle_detect → INTA asserted → PE.5 HIGH →
firmware's WaitTXReady sees PE.5=HIGH → timeout → bits[7:6] incremented → main loop
resets ring buffer → button data discarded.

## Fix
Replaced timer-based proactive INTA with piggybacked button change detection:

1. **Removed** 10ms button_scan_timer start from device_reset()
2. **Added** `queue_button_changes()` helper that scans all 22 input ports (11
   segments × 2 panels) and queues button packets for any changed segments
3. **Called** queue_button_changes() from query command handlers (0x20/0x25,
   0xe0/0xe2/0xe3) after queuing the command response

This ensures button change packets ride the same INTA delivery cycle as the
command response. INTA only fires as part of the expected response to a command
the firmware just sent — never during WaitTXReady for the NEXT command.

The self-clocking mechanism's multi-packet delivery (pause every 2 bytes,
re-trigger INTA) handles the extra packets. send_button_packet() updates
m_last_button_state, so the just-queried segment won't be double-reported.

## Files Modified
- `kn5000_cpanel.h`: Added `queue_button_changes()` declaration
- `kn5000_cpanel.cpp`: Added queue_button_changes() implementation, called from
  query handlers, disabled button_scan_timer, updated button_scan_callback comment

## Expected Outcome
- Button changes detected on EVERY query command (E0 13 fires every ~42 main loop
  iterations → roughly every 10-50ms in steady state)
- ALL changes delivered reliably in one INTA burst (no WaitTXReady race)
- Firmware processes all packets from ring buffer (bits[7:6] stays 0)
- Some latency increase vs real hardware (changes detected at next query, not
  immediately), but should be responsive enough for UI use

## Risk
- LOW: Only changes WHEN button packets are queued, not HOW they're delivered.
  The INTA/self-clocking/multi-packet delivery mechanism is unchanged.
- If queue_button_changes() queues many packets (e.g., 10 segments changed),
  INTA stays asserted longer (~840µs for 10 packets). WaitTXReady has a 480µs
  timeout × 6 retries = ~3ms total — enough to wait for delivery to complete.
  However, each retry increments bits[7:6], so > 1 retry causes buffer reset.
  In practice, simultaneous changes across 5+ segments are extremely rare
  (user presses one button at a time).
