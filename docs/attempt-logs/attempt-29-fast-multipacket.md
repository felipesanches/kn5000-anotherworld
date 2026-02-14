# Attempt 29: Fast Multi-Packet Delivery (20µs gap instead of 200µs) (2026-02-14)

## Hypothesis
The firmware's CPanel_InitButtonState calls CPanel_RX_ProcessWithFlag to process
0x2B/0xEB responses, but waits only 3×DELAY_6_TICKS (~1.44ms) before running the
processing loop. With a 200µs inter-packet gap, self-clocking takes ~3ms for 22 bytes
(11 two-byte packets). This means only ~5 of 11 segments are delivered before processing
runs — the rest arrive later and are processed WITHOUT the flag.

On real hardware, the panel MCU delivers 22 bytes continuously at 250kHz SCLK (~704µs).
All bytes arrive well within the firmware's wait, so CPanel_RX_ProcessWithFlag sees
all 11 segments with flag bit 2 set.

CPanel_RX_ProcessWithFlag sets bit 2 of CPANEL_TX_RX_FLAGS before entering the dispatch
loop. If this flag affects downstream event processing (even though marked "UNUSED?" in
the disassembly), partial vs. full processing with the flag could change behavior.

Additionally, with 200µs gap timing:
- CPanel_RX_ProcessWithFlag processes partial data (5 segments)
- WaitTXReady blocks for ~1.5ms while remaining delivery completes
- Total 0x2B cycle: ~3ms instead of ~1.5ms on real hardware

## Timing Analysis

### Current (200µs gap):
Per packet: 20µs (INTA ISR delay) + 64µs (2 bytes at 125kHz) + 200µs (gap) = 284µs
11 packets: 11 × 284µs = 3124µs
Plus initial: 50µs (idle_detect) + 20µs (ISR) + 64µs (first packet) = 134µs
Total: ~3.1ms >> 1.44ms firmware wait

### New (20µs gap):
Per packet: 20µs (INTA ISR delay) + 64µs (data) + 20µs (gap) = 104µs
Packet 1: 50µs (idle_detect) + 20µs (ISR) + 64µs = 134µs
Packets 2-11: 10 × 104µs = 1040µs
Total: 134 + 1040 = ~1.17ms < 1.44ms firmware wait

## Fix
Changed self_clock_callback's inter-packet re-trigger delay from 200µs to 20µs.
20µs = 320 CPU cycles at 16MHz — more than enough for the INTA ISR to write SC1CR.

## Files Modified
- `kn5000_cpanel.cpp`: self_clock_callback inter-packet gap

## Expected Outcome
All 22 bytes from 0x2B/0xEB arrive before CPanel_RX_ProcessWithFlag processes them.
If flag bit 2 of CPANEL_TX_RX_FLAGS affects event processing, this ensures correct
behavior matching real hardware. Also reduces WaitTXReady blocking and overall boot time.
