# Attempt 26 - Thinking Dump (2026-02-14)

## Starting Point

Attempts 22-25 all give the same result: most LEDs correct, FADE OUT on (should be off), PIANO off (should be on), Standard Rock correct. Trailing edge fix (attempt 22) was the big improvement. Subsequent changes (INTA gap, spurious INTTX, sync-only 0x2B/0xEB) had zero effect.

## Dead End 1: Multi-packet INTA gap

Hypothesis: During send_all_button_states, 200us INTA gaps allow WaitTXReady to pass.
Why it failed: Even replacing all button data with sync (attempt 25) gave same result. Multi-packet delivery is completely irrelevant.

## Dead End 2: Spurious INTTX from scNmod_w

Hypothesis: scNmod_w fires INTTX when SC1MOD is written.
Why it failed: The spurious INTTX fires before SC1BUF is written, so the ISR has nothing to send. No corruption.

## Deep Analysis: Trailing Edge Causing Extra Clock Edges?

I spent significant time analyzing whether the trailing rising edge causes a 1-bit shift in the cpanel's RX:

1. When tx_clock_count reaches 0 on falling edge, m_tx_needs_trailing_edge is set
2. Timer continues (need_clock includes trailing flag)
3. Next edge is rising → sclk_out_cb(1) forwards to cpanel → cpanel enters RX handler
4. QUESTION: Does this extra rising edge start the next byte prematurely?

Initial analysis said YES: rx_clock_count was 8 (byte completed on previous rising edge), so this trailing edge would decrement to 7, starting the next byte. Every byte would be corrupted with a 1-bit rotation.

BUT THEN I REALIZED: The 8th rising edge (that completes the byte) IS the trailing rising edge! They're the same edge!

Proof by counting: scNbuf_w sets tx_clock_count=7. After 1 skipped falling + 7 real fallings = 8 falling edges, tx_clock_count reaches 0. That's on the 8th falling edge. The 8th rising edge both:
- Completes the cpanel byte (rx_clock_count 1→0→8)
- Handles the trailing edge (fires INTTX)

After this: rx_clock_count=8, tx_clock_count=0, trailing=false → need_clock=false → timer STOPS.

The next byte starts fresh when the ISR writes SC1BUF. No extra edges. NO 1-bit shift.

This was a major dead end that took a lot of analysis to resolve. The serial protocol IS correct.

## Dead End 3: Phantom Byte Bit Corruption

Traced the full phantom→real→real→phantom sequence:
1. Phantom byte: tx_start(0) → accept=false → rejected ✓
2. Real byte 1: tx_start(1) → accept=true → accepted ✓
3. Real byte 2: tx_start(1) → accept=true → accepted ✓
4. Trailing phantom: tx_start(0) → accept=false → rejected ✓

All deferred/immediate application logic is correct. No corruption.

## Dead End 4: Self-Clocking Bit Corruption

Traced the full self-clocking mechanism:
- self_clock_callback toggles clock → CPU sioclk → CPU sclk_out → cpanel sioclk
- Falling: cpanel outputs TX bit → sets CPU's m_rxd
- Rising: CPU captures m_rxd → shifts into RX register
- All 8 bits correctly transmitted and received

Also verified byte boundary counting during self-clocking: first byte (tx_count=7 + skip) gets 8 cpanel falling edges and 8 CPU rising edges. Second byte (chained, tx_count=8) also gets 8+8. Correct.

## Dead End 5: scNcr_w Mid-Byte Reset

scNcr_w resets rx_clock_count to 8 unconditionally. But firmware only writes SC1CR at byte boundaries (after INTRX1 or before starting TX). No mid-byte corruption.

## Dead End 6: Baud Rate Timer Double-Clocking During Self-Clock

Hypothesis: If firmware clears IOC after 2-byte packet, baud rate timer could generate extra edges during self-clocking.
Analysis: need_clock would be false (tx_clock_count=0, rx_clock_count=8) at the start of self-clocking. Timer doesn't generate edges. Even if rx_clock_count decrements during self-clocking, the timer's (mode&3)==0 check would block it IF IOC is set (INTA handler sets IOC=1).

## Dead End 7: Response Accumulation from Unknown Commands

If firmware sends commands not in our switch, default case sends sync. Sync accumulates, delivered via INTA, potentially interfering. But WaitTXReady blocks during INTA, so no overlap. Sync processed and discarded by firmware.

## Dead End 8: LED Commands Lost During Self-Clock

If self-clocking overlaps with next command's TX, the command bytes are lost (RX skipped during self_clocking=true). But WaitTXReady prevents firmware from sending during INTA. No overlap.

## Key Finding: Firmware LED Analysis

Explore agent found: firmware does NOT send explicit LED commands during early boot. Only sends:
- Init commands (0x1F, 0x1D, 0xDD, 0x1E) with sync responses
- Button queries (0x2B, 0xEB)

LEDs only change AFTER GUI loads, driven by firmware's default configuration code (not analyzed by agent).

## Key Finding: Serial Protocol is CORRECT

Exhaustive bit-level analysis confirms no corruption in any scenario:
- First byte: pre-output + skip mechanism correct
- Byte transitions: trailing edge is same edge as byte completion, no extra edge
- Phantom bytes: correctly rejected
- Self-clocking: correctly timed
- scNcr_w: only at byte boundaries

## Conclusion

The remaining LED issues are NOT serial corruption. Possible causes:
1. Firmware sends different LED data than expected (verified correct on real hardware, might differ in MAME due to different timing/initialization)
2. Our LED bit mapping is wrong for specific rows
3. Some non-serial MAME issue

## Decision: Enable LED Logging

Since the serial protocol is verified correct, I need to see what LED command bytes the firmware actually sends. Enabled LOG_LEDS in VERBOSE macro. The user needs to check MAME's log output for lines like "LED command: row=C0 data=XX" to determine if the data values match expectations.
