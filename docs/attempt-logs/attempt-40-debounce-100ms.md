# Attempt 40: Button Debounce (100ms Minimum Hold) (2026-02-14)

## Root Cause Analysis

Log analysis of attempt 39 revealed a clear pattern:

| Button Type | Panel | Hold Duration | Lines Between Press/Release | Firmware Reaction |
|---|---|---|---|---|
| PART SELECT (held) | Right seg 4 | Seconds | 1243-2389 | LED commands sent |
| PART SELECT (tapped) | Right seg 4 | Instant | 99 | None |
| Navigation UP/DOWN | Left seg 8 | Instant | 99 | None |
| MENU: DISK | Right seg 10 | Instant | 99 | None |

**ALL working button interactions had long hold times (1243+ lines between
press/release). ALL non-working interactions had 99-line gaps (press and
release detected on consecutive scans).**

### What happens with a 99-line gap:

1. Scan timer fires → detects press (e.g., `00→40`) → queues packet
2. idle_detect fires (50µs) → INTA asserted → self-clocking starts
3. Self-clocking completes (~128µs) → INTA deasserted → press delivered
4. **IMMEDIATELY** next scan fires (overdue periodic timer) → detects
   release (`40→00`) → queues packet
5. idle_detect fires → INTA asserted AGAIN → release delivered

The firmware has only ~250µs between the press INTA and the release INTA.
In that time it must:
- Return from INTA_HANDLER
- Resume main loop
- Reach CPanel_InterruptPoll_MainLoop
- Call CPanel_RX_Process (check bits[7:6] first)
- Process the press packet (ButtonPacketHandler)
- Trigger button callback
- Update display/LEDs (which involves WaitTXReady + serial TX)

The release INTA fires during this processing — potentially during
WaitTXReady for LED commands. PE.5 goes HIGH, WaitTXReady increments
bits[7:6], and the next main loop iteration resets the ring buffer.

On real hardware, physical buttons have a minimum press duration of ~50ms
(human finger physiology). The firmware has ample time to process the press
before the release arrives.

## Fix

After detecting a button change, delay the next scan by 100ms instead of
the regular 7ms. This gives the firmware time to fully process the press
event before the release is detected.

```cpp
// In button_scan_callback, after detecting a change:
m_button_scan_timer->adjust(attotime::from_msec(100), 0, attotime::from_msec(7));
```

The timer resumes 7ms periodic scanning after the 100ms delay.

## Evidence from Log

- 352 proactive changes detected (176 press/release pairs)
- 290 INTA delivery cycles completed successfully
- 0 piggybacking events (periodic timer did all detection)
- 71 scans skipped by guards (69 TX active, 2 INTA/self-clocking)
- Both panels delivered correctly (CPU receives bytes: e.g., `0x48 0x40`
  for left seg 8, `0x04 0x02` for right seg 4)
- Right seg 4 long holds → `C4 00` LED command follows delivery
- Left seg 8 / right seg 10 short taps → only `E0 13` follows (no reaction)

## Files Modified
- `kn5000_cpanel.cpp`: Added 100ms debounce delay after change detection
  in `button_scan_callback`

## Expected Outcome
- Button taps produce a 100ms gap between press and release INTAs
- Firmware has ~2500 main loop iterations to process the press
- LED commands, display updates, and menu switches complete before release
- Same behavior as real hardware button presses (~50-100ms minimum)
- PART SELECT (already held for seconds) unaffected

## Risk
- LOW: 100ms is the same order of magnitude as real button presses.
  Human perception of "responsive" is under 200ms.
- Edge case: if the user presses a button and releases within 100ms,
  the release won't be detected until the 100ms timer fires. Then the
  next 7ms scan detects it. Total worst-case delay: ~107ms. Acceptable.
- Navigation UP/DOWN buttons that should auto-repeat when held: the first
  press is detected immediately, then after 100ms the release check fires.
  If the key is still held, no release is detected, and subsequent scans
  at 7ms continue to see "no change" (key still held = same state). The
  auto-repeat would come from the firmware's own repeat logic, not from
  the cpanel HLE generating repeated press events.
