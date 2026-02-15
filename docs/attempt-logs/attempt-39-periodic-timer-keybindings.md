# Attempt 39: Periodic Timer + Default Key Bindings (2026-02-14)

## Problem with Attempts 36-38
All three approaches reduced button change detection frequency dramatically compared to attempt 35's periodic timer:
- **Attempt 36 (piggyback-only)**: 8 detections vs 384 in attempt 35
- **Attempt 37 (one-shot 3ms)**: 0 proactive detections — 3ms delay exceeded the ~1.5ms command cycle, so scans always hit the `!m_rx_waiting_for_start` guard
- **Attempt 38 (one-shot 500µs)**: 60 scans ran, all found no changes — timing gap between last retry (1000µs) and next command (2000µs) missed the actual press

The key insight: **attempt 35's periodic timer was the best user experience** despite the WaitTXReady race. It provided the most detection events (384), and while some hit the race, many succeeded and produced visible GUI responses.

## Additional Insight: Missing Key Bindings
All 22 input port segments had `PORT_NAME` but **no `PORT_CODE`** — meaning ZERO default keyboard mappings. The user had to manually configure every button via MAME's Tab menu. This likely explains why "the vast majority of buttons do not seem to cause any effect" — most buttons simply weren't mapped to any keyboard key.

## Fix: Two-Part Approach

### Part 1: Revert to Periodic Timer (7ms)
- Changed `device_reset()` to start a 7ms periodic timer (~143 Hz)
- 7ms is coprime with likely command cycle times (~10-20ms) to reduce phase-lock risk
- Removed one-shot scheduling from `self_clock_callback`
- Simplified `button_scan_callback` to periodic style with guard logging
- Kept piggyback mechanism in query handlers for double coverage

### Part 2: Default PORT_CODE Key Bindings
Added keyboard mappings for the most useful navigation and UI buttons:

**LCD Navigation (8 UP/DOWN pairs):**
| Button | Key | Button | Key |
|--------|-----|--------|-----|
| UP 1   | Q   | DOWN 1 | A   |
| UP 2   | W   | DOWN 2 | S   |
| UP 3   | E   | DOWN 3 | D   |
| UP 4   | R   | DOWN 4 | F   |
| UP 5   | T   | DOWN 5 | G   |
| UP 6   | Y   | DOWN 6 | H   |
| UP 7   | U   | DOWN 7 | J   |
| UP 8   | I   | DOWN 8 | K   |

**Soft Keys (number row):**
| Button  | Key | Button   | Key |
|---------|-----|----------|-----|
| LEFT 1  | 1   | RIGHT 1  | 6   |
| LEFT 2  | 2   | RIGHT 2  | 7   |
| LEFT 3  | 3   | RIGHT 3  | 8   |
| LEFT 4  | 4   | RIGHT 4  | 9   |
| LEFT 5  | 5   | RIGHT 5  | 0   |

**Navigation & Menus:**
| Button        | Key    |
|---------------|--------|
| EXIT          | X      |
| DISPLAY HOLD  | Z      |
| PAGE UP       | PgUp   |
| PAGE DOWN     | PgDn   |
| HELP          | /      |
| OTHER PARTS   | O      |
| DEMO          | Enter  |
| START/STOP    | Space  |
| MENU: SOUND   | B      |
| MENU: CONTROL | N      |
| MENU: MIDI    | M      |
| MENU: DISK    | ,      |
| PIANO         | L      |

## Files Modified
- `kn5000_cpanel.cpp`:
  - `device_reset`: 7ms periodic timer (was one-shot scheduling)
  - `self_clock_callback`: removed one-shot scan scheduling
  - `button_scan_callback`: periodic style with guard logging
- `kn5000.cpp`:
  - Added PORT_CODE defaults to CPL_SEG7-10, CPL_SEG2, CPR_SEG2, CPR_SEG8, CPR_SEG10, CPL_SEG3

## Expected Outcome
- Default key bindings allow immediate button testing without MAME Tab menu configuration
- Periodic timer provides frequent change detection (like attempt 35)
- Guard logging shows exactly what happens on each scan invocation
- Combined piggyback + periodic gives comprehensive coverage

## Testing Notes
- **Important**: Delete MAME's saved input config (`cfg/kn5000.cfg`) before testing
  so it picks up the new PORT_CODE defaults instead of using cached (empty) mappings
- Key layout is designed for two-hand use: left hand on QWERT/ASDFG rows, right hand
  on YUIOP/HJKL rows, matching the KN5000's physical left/right LCD button layout

## Risk
- MEDIUM: The 7ms periodic timer may still phase-lock with the command cycle at
  certain MAME throttle speeds, triggering the WaitTXReady race. However, 7ms is
  coprime with 10ms, 15ms, and 20ms, reducing the chance.
- The key bindings are a best guess at which buttons produce visible feedback.
  Some buttons (sound group, rhythm) primarily affect audio, which the MAME driver
  doesn't emulate, so they won't produce visible changes even if correctly detected.
