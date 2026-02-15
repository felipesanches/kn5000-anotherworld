# Attempt 41: Residual Byte Fix + Proper Debounce (2026-02-14)

## Root Cause Analysis

Detailed analysis of the attempt 40 log (271,868 lines) revealed two distinct bugs:

### Bug 1: Residual Byte Corruption (Button Swapping)

**12 out of 331 button-triggered INTA sessions (3.3%) delivered corrupted data
to the CPU**, causing button identity swapping and state degradation.

#### Mechanism

The MAME CPU serial's `scNcr_w()` unconditionally resets `m_rx_clock_count = 8`
whenever SC1CR is written. The firmware's INTRX1 ISR handlers
(CPanel_SM_RXByte1, CPanel_SM_RXByteN) write SC1CR (`OR (SC1CR), 001h` /
`AND (SC1CR), 0fdh`) between received bytes to maintain IOC=1 / SCLKS=0.

The race condition:

1. Byte 1 completes: `rx_clock_count = 0 → 8`, INTRX1 flagged
2. Self-clock continues: falling edge (cpanel outputs byte 2 bit 0)
3. Rising edge: `rx_clock_count 8 → 7` (byte 2 bit 0 sampled correctly)
4. **Between clock edges**: CPU processes INTRX1 ISR, writes SC1CR →
   `scNcr_w()` resets `rx_clock_count = 8` (overwrites 7!)
5. Rising edge: `rx_clock_count 8 → 7` again (bit 1 is sampled as bit 0)

Result: Byte 2 completes 1 bit short (`rx_clock_count = 2` when self-clock
stops). The next INTA session's first clock edges complete the stale byte,
producing a **residual byte** with deterministic corruption:

```
residual = (previous_data_byte >> 1) | (next_header_bit0 << 7)
```

All 12 corrupted sessions matched this formula exactly. Example:
- Right seg 8 data `0x08` → residual `0x04` → interpreted as right seg 4
  (ENTERTAINER) header → **"Sound button opened Entertainer"**

#### Fix

On real TMP94C241 hardware, writing SCxCR configures control bits (IOC, SCLKS,
parity) but does NOT abort an in-progress RX reception. The RX shift register
has its own bit counter that completes independently.

**Removed `m_rx_clock_count = 8` from `scNcr_w()`.** The rx_clock_count is
managed exclusively by the `sioclk()` handler (reset to 8 after byte
completion). SC1CR writes no longer interfere with ongoing reception.

### Bug 2: Debounce Bypass via Piggyback Scanning

The attempt 40 debounce (`m_button_scan_timer->adjust(100ms, ...)`) only
delayed the periodic timer. But `queue_button_changes()` — called from
every query handler (E0 13 polling, ~every 1.7ms) — still scanned for
changes and detected key releases immediately, producing press+release
INTAs ~250µs apart despite the 100ms debounce.

#### Fix

Replaced timer-adjust debounce with timestamp-based suppression:
- Added `m_debounce_until` (attotime) member
- After detecting a change: `m_debounce_until = now + 100ms`
- Both `button_scan_callback` and `queue_button_changes` check
  `machine().time() < m_debounce_until` and return early if active

This ensures ALL change detection is suppressed for 100ms, regardless of
which mechanism would detect the release (periodic timer or piggyback).

## Files Modified

- `tmp94c241_serial.cpp`: Removed `m_rx_clock_count = 8` from `scNcr_w()`
- `kn5000_cpanel.h`: Added `attotime m_debounce_until` member
- `kn5000_cpanel.cpp`:
  - Added `save_item(NAME(m_debounce_until))` in `device_start()`
  - Added `m_debounce_until = attotime::zero` in `device_reset()`
  - Added debounce check at top of `button_scan_callback`
  - Added debounce check at top of `queue_button_changes`
  - Changed debounce trigger from timer adjust to timestamp

## Evidence from Log

### Residual Byte Corruption (12 cases)

| Session | Segment | Data | Next Header | Residual | Firmware Sees |
|---------|---------|------|-------------|----------|---------------|
| S192 | right 10 | 0x20 | 0x0A | 0x10 | seg 16 (invalid) |
| S208 | right 10 | 0x04 | 0x0A | 0x02 | seg 2 |
| S250 | left 9 | 0x80 | 0x49 | 0xC0 | left seg 0 |
| S266 | left 9 | 0x40 | 0x49 | 0xA0 | left seg 0 |
| S401 | right 8 | 0x08 | 0x08 | 0x04 | **seg 4 = ENTERTAINER** |
| S406 | right 8 | 0x10 | 0x08 | 0x08 | seg 8 |

### Debounce Bypass (all 165 press-release pairs)

- 115/165 (69.7%) had exactly 99-line gaps (one scan interval = 7ms)
- 99-line gap = piggyback detection on next E0 13 query (~1.7ms)
- No gap exceeded what timer-only debounce would produce

## Expected Outcome

- **No more button swapping**: Bytes arrive to CPU without corruption
- **No more state degradation**: Cumulative ring buffer corruption eliminated
- **Reliable button response**: 100ms gap between press/release INTAs gives
  firmware ample time to process each event
- **Build error resolved**: hdae5000.cpp already has 3-arg API fix in local
  copy; resync fixes the stale build tree

## Compatibility

- **Original firmware**: SC1CR writes in INTA_HANDLER always occur at byte
  boundaries (rx_count=8), so removing the reset has no effect. The debounce
  is new behavior but matches real hardware (physical buttons held 50-100ms).
- **AW VM**: No SC1CR writes during reception (dummy-byte approach). Debounce
  doesn't affect VM input (uses own serial protocol, not INTA).

## Risk

- LOW: The `scNcr_w` fix aligns MAME behavior with real TMP94C241 hardware
  (SCxCR writes don't abort ongoing RX). No known firmware behavior depends
  on the reset.
- LOW: The debounce is timestamp-based, consistent across all code paths,
  and matches real hardware button timing.
