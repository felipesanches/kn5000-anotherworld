# Attempt 38: Shorter Scan Delay + Guard Logging (2026-02-14)

## Problem with Attempt 37
The 3ms one-shot scan delay was **longer than the command cycle** (~1.5-2.5ms).
By the time button_scan_callback fired, the next E0 13 command's TX had already
started, setting `m_rx_waiting_for_start = false`. The guard silently returned
without logging, making it appear the callback never fired.

Evidence: 59 "self-clock TX complete" events (timer scheduled 59 times) but
ZERO "proactive" button change messages. The callback was firing but every
invocation hit the `!m_rx_waiting_for_start` guard.

## Fix
1. **Reduced delay from 3ms to 500µs**: The firmware processes the response in
   ~100µs (CPanel_RX_Process), then runs ~42 main loop iterations at ~25-40µs
   each. WaitTXReady for the next E0 13 is ~1.5ms after INTA deassertion.
   500µs puts the scan well past response processing but ~1ms before WaitTXReady.

2. **Added guard logging**: Every early return now logs the reason (not
   initialized, self_clocking, inta_asserted, TX active). This makes it
   immediately visible if scans are being blocked.

3. **Reduced retries from 2 to 1**: With the shorter cycle, 2 retries at
   500µs intervals would place the 3rd scan at 1500µs — right at WaitTXReady.
   1 retry gives scans at ~500µs and ~1000µs, both safely before WaitTXReady.

## Files Modified
- `kn5000_cpanel.cpp`:
  - `self_clock_callback`: delay 3ms → 500µs
  - `button_scan_callback`: added LOGMASKED for all guards, entry, and exhaustion;
    reduced retry limit from 2 to 1
  - `device_reset`: updated comment

## Expected Outcome
- button_scan_callback fires and actually scans (not blocked by guards)
- 2 scans per command cycle (~500µs and ~1000µs after INTA)
- Proactive button changes detected and delivered via INTA
- Guard logging shows exactly what happens on each scan invocation

## Risk
- MEDIUM: 500µs delay is based on estimated timing. If CPanel_RX_Process
  takes longer than expected, the scan might fire while firmware is still
  processing. But even then, the guards would block (m_inta_asserted might
  still be true, or m_rx_waiting_for_start false), not cause corruption.
- If the firmware processes FASTER than estimated, WaitTXReady could be
  earlier than 1.5ms. The 1000µs retry would still have ~500µs margin.
