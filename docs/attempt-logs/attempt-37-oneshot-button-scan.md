# Attempt 37: One-Shot Button Scan from INTA Deassertion (2026-02-14)

## Problem with Attempt 36 (Piggyback-Only)
Attempt 36 piggybacked button change detection on command responses in
`process_command()`. This eliminated the WaitTXReady race but dramatically
reduced detection frequency: only 8 piggyback events (4 press/release pairs)
vs 384 proactive changes in attempt 35's timer approach. The firmware only
sends E0 13 every ~42 main loop iterations (~10-20ms), so button changes
between queries were completely missed.

## Problem with Attempt 35 (Periodic Timer)
The 10ms periodic timer phase-locked with the E0 13 command cycle (~10ms),
consistently firing ~388 lines before the next E0 13 command — right in the
WaitTXReady danger zone. Every proactive INTA hit WaitTXReady, incrementing
the retry counter and causing ring buffer resets.

## Analysis: Why Phase-Lock Occurs
A periodic timer at P ms and a command cycle at C ms will eventually
phase-lock when P ≈ C. With both at ~10ms, the timer fire point drifts
slowly relative to the command cycle until it settles in the WaitTXReady
window (~300µs before each command). Once locked, every proactive INTA
hits the race.

## Fix: One-Shot Scheduling from INTA Deassertion
Instead of a periodic timer, schedule a one-shot button scan 3ms after each
INTA deassertion in `self_clock_callback`. This anchors the scan to a
known-safe reference point: INTA just deasserted, meaning the firmware
successfully received data. The next WaitTXReady is ~10-20ms away (42 main
loop iterations). 3ms puts the scan early in that safe zone.

### Retry mechanism
If no button changes are found, reschedule once more (3ms later). Up to
2 retries for a total of 3 scans per command cycle (at ~3ms, ~6ms, ~9ms
after INTA deassertion). This catches buttons pressed during the cycle
without drifting into the WaitTXReady danger zone at ~10-20ms.

### Self-sustaining loop
When a button change IS detected, the scan queues packets and triggers
idle_detect → INTA → self-clock delivery → INTA deassertion → new scan
scheduled. This creates a natural feedback loop: each delivery schedules
the next scan.

## Combined Approach
Both mechanisms work together:
1. **Piggyback** (from attempt 36): queue_button_changes() in query handlers
   catches changes that happen to coincide with E0 13 commands
2. **One-shot scan**: catches changes between commands with 3ms resolution
3. **Self-sustaining**: proactive INTA delivery → scan → delivery → scan

## Files Modified
- `kn5000_cpanel.h`: Added `m_scan_retry_count` member
- `kn5000_cpanel.cpp`:
  - `self_clock_callback`: schedule button_scan 3ms after INTA deassertion
  - `button_scan_callback`: full implementation with guards, retry logic
  - `device_reset`: updated comment, added m_scan_retry_count init
  - Constructor: added m_scan_retry_count initializer + save_item

## Expected Outcome
- Button changes detected within 3-9ms of INTA deassertion (vs 10ms random)
- No phase-lock race with WaitTXReady (anchored to INTA, not periodic)
- Combined piggyback + one-shot gives comprehensive coverage
- Self-sustaining scan loop ensures continuous monitoring

## Risk
- LOW: The 3ms delay after INTA deassertion is well within the safe zone.
  Even with the fastest main loop (10ms cycle), the 3rd retry at ~9ms
  finishes delivery by ~9.3ms, leaving ~700µs before WaitTXReady.
- If the main loop is extremely fast (< 9ms between E0 13), the 3rd
  retry could approach WaitTXReady. The retry limit (2) caps exposure.
- Edge case: if no commands are ever sent after boot, no scans are
  scheduled. But the firmware always sends E0 13 in steady state.
