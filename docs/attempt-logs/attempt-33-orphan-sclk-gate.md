# Attempt 33: Filter Orphan SCLK Edges (2026-02-14)

## Hypothesis
After the TX double buffering fix (attempt 32), LEDs work correctly but button presses
have no effect. The root cause is a second serial desynchronization that occurs later
in the boot sequence — after the LED initialization burst, the firmware's cpanel polling
loop produces garbled commands ("07 06" repeating), preventing button queries from
ever reaching the cpanel HLE.

The desync is caused by "orphan" SCLK edges: after the last TX byte completes, the
CPU's free-running RX counter still has 1-2 edges remaining before reaching its
8-boundary. The timer drives those extra edges (because `need_clock` includes
`m_rx_clock_count != 8`), and `sclk_out_cb` unconditionally forwards them to the
cpanel. The cpanel's RX starts counting a new byte from these orphan edges, shifting
byte boundaries by 1 bit.

On real TMP94C241 hardware, PFFC is disabled at this point (PORT_F=0x03, bit 6=0),
so the SCLK output pin is high-impedance — orphan edges don't reach the panel.

## Evidence (from log.txt, 71,750 lines — before this fix)
- Line 65848: Trailing rising edge fires, CPU rx_clock=2 (before decrement → 1 after)
- Line 65849: INTTX fires, TX done (tx_clock=0, trailing=false)
- Line 65850-65851: Timer drives orphan falling edge (need_clock=true due to rx_clock=1)
- Line 65852-65853: Timer drives orphan rising edge → cpanel starts new byte (rx_count 8→7)
- Line 65855: CPU RX completes (rx_clock 1→0→8), timer stops
- Line 65861: Next real byte (sync 0x45) starts, but cpanel is at rx_count=7 → DESYNC
- Lines 66207+: All commands garbled as "07 06" (14 occurrences until end of log)

## Failed Approach: Gate sclk_out_cb on TX Activity (REVERTED)
Initially tried gating `sclk_out_cb` on `tx_active` in the CPU's `sioclk()`:
```cpp
bool tx_active = (m_tx_clock_count > 0) || m_tx_skip_first_falling
              || m_tx_needs_trailing_edge || m_tx_buffer_full;
if (tx_active)
    m_sclk_out_cb(state);
```

**This caused a BIG REGRESSION**: many wrong LEDs and "ERROR in CPU data transmission".

**Root cause of regression**: When orphan edges are not forwarded, the cpanel's internal
`m_sioclk_state` freezes at its last value (e.g., 1). When the next real byte starts,
the CPU forwards state=1 (rising) → cpanel sees 1→1 (same state) → `if (m_sioclk_state
== state) return;` → **missed edge**. This permanently shifts byte boundaries.

This is exactly the clock desync the existing sioclk() comment warned about: "during
PFFC-off phases, m_sioclk_state keeps toggling without forwarding to the slave, so
the slave's state becomes stale and it misses edges when forwarding resumes."

## Working Approach: Cpanel-Level RX Gating
Instead of blocking edges at the CPU level, filter them at the cpanel level using
`m_rx_waiting_for_start`. All edges still reach the cpanel (keeping clock state
in sync), but the cpanel ignores RX bit counting between bytes:

1. After completing a byte → set `m_rx_waiting_for_start = true`
2. Orphan edges arrive → cpanel receives them (m_sioclk_state stays in sync)
   but does NOT count them as RX bits
3. `tx_start()` fires for the next byte → clear `m_rx_waiting_for_start`
4. Next rising edge → cpanel starts counting the new byte from rx_count=8

No clock state desync because all edges are forwarded. No orphan bit counting
because the cpanel only counts between tx_start signals.

## Files Modified
- `tmp94c241_serial.cpp`: REVERTED attempt to gate sclk_out_cb (restored unconditional forwarding)
- `kn5000_cpanel.h`: Added `m_rx_waiting_for_start` member
- `kn5000_cpanel.cpp`: Set waiting flag on byte completion, clear in tx_start(),
  check in sioclk() rising edge before counting RX bits

## Expected Outcome
- Cpanel clock state stays in sync (all edges forwarded)
- Orphan edges between bytes are ignored (waiting flag blocks RX counting)
- Byte boundaries always aligned to tx_start signals
- Button queries decode correctly → input works

## Risk
- LOW: The change only affects when the cpanel starts/stops counting RX bits.
  All clock edges still propagate normally. No timing changes to TX, INTTX, or INTA.
- Phantom bytes: tx_start(0) clears waiting → cpanel counts 8 bits → rejects
  the assembled byte (accept_next_byte=false). Orphan edges after phantom byte
  are gated by waiting=true.
- Self-clocking overlap: if phantom byte partially overlaps with self-clocking,
  some bits are missed (m_self_clocking check). After self-clocking ends, orphan
  edges complete the phantom byte (waiting still false from tx_start). Once
  complete, waiting=true prevents further counting. The garbled phantom byte
  is rejected. Next real byte starts cleanly.
