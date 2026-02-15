# Attempt 42: Thinking Dump — INTRX1 Missing from Compiled Binary

## Starting point
Attempt 41 fixed right panel button swapping (residual byte fix in scNcr_w) and
added timestamp-based debounce. Right panel is fully working. Left panel and center
buttons still don't work.

## Investigation: Why don't left panel buttons work?

### CPanel_RX_Process call path
First I investigated the CPanel_RX_Process calling path in the original firmware.
Found it at LABEL_FC3E94 in the main program, gated by bits[7:6] of
CPANEL_TX_RX_FLAGS. The question was: do these bits cause data to be discarded?

Analysis shows bits[7:6] form a 2-bit counter: 0x40 → 0x80 → 0xC0 → 0x00. Counter
incremented at LABEL_FC485B in CPanel_InterruptPoll_MainLoop. Key insight: when
counter == 0x00, it STAYS at 0x00 (the ADD only fires when bits[7:6] != 0, as part
of initialization cycling). During normal operation, bits[7:6] are always 0x00, ring
buffer is NEVER reset. Dead end.

### WaitTXReady analysis
Previous session summary claimed "PE.5 goes HIGH, WaitTXReady increments bits[7:6]".
Found this is WRONG. WaitTXReady at lines 576-614 has its own separate counter
(CPANEL_COUNTER_DOWN_FROM_200, 200 iterations × DELAY_1500_LOOPS). It never touches
bits[7:6]. Another dead end.

### Input port verification
Checked all CPL_SEG7-10 (soft keys) input port definitions. All have PORT_CODE
bindings (keys 0-9, Q-Y, A-K, etc.). Ports are correctly defined and wired. Not the
issue.

### Log analysis: firmware never polls left panel after boot
Analyzed /mnt/shared/log.txt:
- Right panel: 97 presses → 23/30 produced LED reactions
- Left panel: 51 presses → 0/51 produced LED reactions
- Firmware NEVER polls left panel after boot (only E0 13 for right panel seg 3)
- Left panel rhythm buttons (should unconditionally light LEDs) also fail

This makes sense: the firmware receives left panel data via INTA (slave mode),
not via polling (master mode). If INTA data doesn't make it to the firmware,
left panel buttons would never work.

### Byte delivery verification
Both panels deliver bytes correctly via self-clock:
- Right seg 10: sent 0x0A/0x20, received 0x0A/0x20 ✓
- Left seg 8: sent 0x48/0x04, received 0x48/0x04 ✓

The CPU serial correctly assembles the bytes in SC1BUF. The question is:
does the firmware ever get notified?

### THE SMOKING GUN: INTRX1 never fires
Searched the log for interrupt-related messages:
- "RX byte received": 3523 matches ✓
- "INTRX": 0 matches ✗
- "pending set": 0 matches ✗
- "Trailing rising edge": 2585 matches ✓
- "Finished sending byte": 2585 matches ✓

The "INTRX pending set" logerror is at line 187 of sioclk() in
tmp94c241_serial.cpp, in the SAME `if (m_rx_clock_count == 0)` block as
"RX byte received" (line 182). If "RX byte received" fires 3523 times but
"INTRX pending set" fires 0 times, the compiled binary DOES NOT have the
INTRX1 flagging code.

Other sioclk() messages DO appear ("Trailing rising edge" 2585×, "Finished
sending byte" 2585×), confirming the binary has the TX handling but is missing
the RX interrupt code.

## Root cause

The user's compiled MAME binary has an **older version** of tmp94c241_serial.cpp
that:
1. Has TX handling (trailing edge, INTTX1 deferral) ✓
2. Logs "RX byte received" when a byte completes ✓
3. Does NOT set the INTRX1 interrupt flag (`m_int_reg[INTES1] |= 0x08`)
4. Does NOT have the "INTRX pending set" logerror

The INTRX1 flagging code was added to the source after the user's last compile.

## Why right panel works despite missing INTRX1

Right panel buttons work through a different mechanism:
- The firmware polls right panel via master-mode commands (E0 13)
- In master mode, the firmware drives SCLK via the baud rate timer
- TX and RX happen simultaneously on the same clock
- The firmware uses INTTX1 (which DOES fire — 2585 times in log) to know when
  a byte is complete, then reads SC1BUF for the received response
- INTTX1 code at line 146 IS present in the compiled binary

Left panel buttons rely on INTA slave-mode reception:
- The cpanel asserts INTA and drives SCLK (self-clock)
- The CPU only receives (no TX happening)
- The firmware needs INTRX1 to know when each RX byte arrives
- INTRX1 code is missing → firmware never gets notified → ring buffer stays
  empty → no events → no reactions

## Secondary concern: Timer interference during INTA transient

Analyzed whether the baud rate timer could interfere with cpanel self-clock
during INTA. The timer gate `(m_serial_mode & 3) == 0 && BIT(m_serial_control, 0)`
correctly blocks the timer when IOC=1 (slave mode). However, there's a brief
transient between INTA assertion (cpanel starts self-clocking) and the INTA_HANDLER
setting IOC=1 (~3-4µs at 16 MHz). During this window, the timer could inject
extra edges. Concluded this is a minor secondary issue, not the root cause.

## Fix

No code changes needed — the INTRX1 code is already in the source file at
lines 183-190 of tmp94c241_serial.cpp. The user just needs to rebuild MAME
with the current source.

The uncommitted changes in the MAME driver repo (424 lines added across 6 files)
need to be synced to `/mnt/shared/mame_driver/` and the user needs to recompile.
