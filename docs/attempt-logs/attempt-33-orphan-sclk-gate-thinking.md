# Attempt 33 - Thinking Dump (2026-02-14)

## Starting Point

Attempt 32 (TX double buffering) fixed LEDs. But button presses have no effect on the
GUI. The firmware boots fully (no ERROR, correct LEDs, GUI displays), but the cpanel
polling loop is broken after initialization.

## Why TX/RX Counters Desynchronize

In synchronous serial mode, TX and RX share the same clock edges. TX counts 7 falling
edges (after skip_first_falling) + 1 trailing rising edge = 8 cycles. RX counts on
every rising edge, 8 down to 0, then resets to 8. If they start on the same edge,
they finish on the same edge.

But they DON'T always start on the same edge. The RX counter is free-running: it
continuously counts 8 rising edges, assembles a byte, resets, and starts the next
cycle. It doesn't "start" when TX starts. The RX cycle may be at count 3 when a new
TX byte begins, meaning the RX will complete 3 rising edges before the TX's 8th rising
edge, then immediately start a new 8-count cycle that overlaps with the TX byte.

Example from the log:
- Auto-load at trailing rising edge (line 65791): tx_clock=7, but rx_clock=2→1
  (the trailing rising edge also decremented RX)
- The auto-loaded byte needs 16 edges (8 falling + 8 rising) to transmit
- RX needs only 1 more rising edge to complete its current cycle
- After RX completes (rising edge 1), it resets to 8 and starts a new 8-count cycle
- TX finishes after rising edge 8, but by then RX is at count 1 (started new cycle
  and counted 7 edges = 8 - 1)
- Timer keeps running for the remaining RX edge(s)

This mismatch is normal and harmless on real hardware (PFFC gates the SCLK pin).
In MAME, the orphan edges reach the cpanel.

## Why Not Gate on PFFC Directly

The existing code comment warned against PFFC gating:
> "We do NOT gate on PFFC here because that causes clock desync: during PFFC-off
> phases, TO2 toggles our internal m_sioclk_state without forwarding to the slave"

Although TO2 is now a no-op, the baud rate timer still toggles m_sioclk_state during
PFFC-off phases. If we gate sclk_out_cb on PFFC, the cpanel's clock state freezes
while the CPU's internal state keeps toggling. When PFFC is re-enabled, the states
may be out of sync, causing the cpanel to miss an edge (1→1 = no transition).

The TX activity gate avoids this: phantom bytes (PFFC off, TX active) still forward
their edges, keeping the cpanel's clock state in sync. Only truly orphan edges
(TX idle, RX still counting) are blocked.

## Edge Case Analysis

### Trailing rising edge with auto-load
1. tx_active = true (m_tx_needs_trailing_edge = true)
2. sclk_out_cb(1) forwarded to cpanel — cpanel samples bit 7 ✓
3. Trailing handler: INTTX fires, auto-load from buffer, tx_clock=7, skip=true
4. tx_active remains true for all subsequent edges ✓

### Last byte, no buffer
1. Trailing rising edge: tx_active = true (trailing flag) → forwarded
2. After trailing handler: tx_clock=0, trailing=false, skip=false, buffer=false
3. Next timer edge: tx_active = false → NOT forwarded (orphan) ✓
4. CPU's internal RX still processes (the if(m_rx_clock_count) block runs) ✓

### INTA self-clock (cpanel drives SCLK to CPU)
- The cpanel's self-clock calls CPU's sioclk() directly via the sclk pin callback
- In this path, TX is idle (tx_active = false), so sclk_out_cb is NOT called
- This is correct: the cpanel doesn't need its own clock echoed back
- The CPU's RX processes normally on the externally-driven edges

### need_clock with orphan edges
- need_clock still includes (m_rx_clock_count != 8)
- Timer still fires for orphan edges (CPU's internal RX needs them)
- But sclk_out_cb is gated, so cpanel doesn't see them
- This is correct: the internal shift register and INTRX still work

## Garbled Command Pattern

The "07 06" pattern seen 14 times at the end of the log corresponds to the firmware's
cpanel polling loop (CPanel_InterruptPoll_MainLoop) being stuck in a garbled state.
The 1-bit shift means every subsequent command's 2 bytes are assembled from the wrong
bit positions. 0x07 is not a valid command in the protocol (LED indices map 0-14 to
values C0,C1,C2,C3,C4,C8,00,01,02,03,04,08,0A,0B,0C).

With the orphan edge gate, the cpanel stays synchronized, and real commands
(0x20/0x25/0x2B/0xE0/0xE2/0xE3/0xEB for buttons, 0xC0-0xC8/0x00-0x0C for LEDs)
will be decoded correctly.

## If This Works
- Button queries reach cpanel → responses sent via INTA → firmware reads button state
- GUI reacts to button presses in MAME
- Full cpanel polling loop operational (3× LED update, 1× button scan alternation)

## If This Doesn't Work
1. The cpanel might need changes to process button queries differently
2. The INTA timing might not work for steady-state button responses (only verified
   during init)
3. The firmware might use a different button query pattern in the polling loop
   vs initialization
4. There might be additional desync sources besides the RX orphan edges
