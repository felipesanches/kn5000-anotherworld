# Attempt 32 - Thinking Dump (2026-02-14)

## Starting Point

Attempt 31 (NVRAM factory defaults) was partially successful: eliminated the "ERROR in
back-up SRAM" message, proving NVRAM validation now passes. But LEDs are still partially
wrong (Standard Rock=on good, Fade Out=on bad, Piano=off bad).

Deep log analysis in the previous session found the root cause: serial desynchronization
at log line 63340 when the firmware writes two padding bytes back-to-back.

## The Back-to-Back Write Problem

The firmware's INTTX ISR sends 7 bytes per command: `45, 05, CMD, 03, PARAM, 03, 03`.
At state 5 (after byte 5 completes), the ISR writes BOTH byte 6 and byte 7 (both 0x03
padding) in one invocation. This relies on real TMP94C241 hardware having TX double
buffering:

Real hardware:
1. ISR writes byte 6 → buffer → shift register (idle) → starts transmitting
2. ISR writes byte 7 → buffer (shift register busy with byte 6)
3. Byte 6 finishes → byte 7 auto-loads from buffer → transmits
4. Byte 7 finishes → INTTX → ISR done

MAME before fix:
1. ISR writes byte 6 → shift register directly, pre-outputs bit 0
2. ISR writes byte 7 → OVERWRITES shift register, clears skip_first_falling
3. Cpanel misses bit 0 of byte 6, receives shifted bitstream → permanent desync
4. All subsequent commands garbled

## Why the Desync is Permanent

After the cpanel's RX bit boundary shifts by 1, every subsequent byte is assembled
from the wrong bit positions. Commands with responses trigger INTA → idle detect →
self-clock resync, which fixes the boundary. But LED commands have NO response (by
design — they're fire-and-forget). So after the first LED command's padding bytes
cause the desync, all subsequent non-INTA commands are garbled.

The "C0 42" that appeared to be a second LED command was actually garbled data from
the desync that happened to fall in the LED command range. Only `C2 01` (Standard Rock)
was a genuine command.

## Design Decisions

### INTTX Timing: Keep Trailing Edge
On real TMP94C241, INTTX fires on buffer→shift register transfer. For idle writes,
this is immediate. I considered changing to immediate INTTX but decided against it —
the trailing edge timing is battle-tested through attempts 1-31 and changing it risks
new regressions.

Instead: INTTX stays at trailing edge. Auto-load happens at the same trailing edge,
after INTTX. The CPU hasn't run the ISR yet (we're in a timer callback), so both the
INTTX flag and the auto-loaded shift register are visible when the CPU next runs.

### was_idle Check: Three Conditions
Original: `was_idle = (m_tx_clock_count == 0)`
New: `was_idle = (m_tx_clock_count == 0 && !m_tx_needs_trailing_edge && !m_tx_skip_first_falling)`

The additional checks prevent direct-loading when:
- `m_tx_needs_trailing_edge`: Byte finished shifting but receiver hasn't sampled bit 7
  yet. Pre-outputting bit 0 of a new byte would corrupt bit 7.
- `m_tx_skip_first_falling`: Bit 0 was just pre-output and hasn't been sampled yet.
  Overwriting would lose it.

In practice, writes during these windows only happen in the back-to-back case, which
is exactly what we're fixing.

### Auto-load: Pre-output + Skip
After auto-loading at the trailing rising edge:
1. Pre-output bit 0 of the new byte via m_txd_cb
2. Set skip_first_falling = true (next falling edge must not shift)
3. Receiver samples bit 0 on the next rising edge

This matches the same pattern as direct-load when sioclk_state is HIGH.

### No need_clock Change
The invariant holds: buffer fills only when was_idle is false, which means at least one
of the existing need_clock conditions is true. Adding m_tx_buffer_full would be
redundant but harmless.

### tx_start_cb: PFFC at Auto-load Time
The PFFC state is checked at auto-load time, not at buffer-write time. This is correct
because PFFC determines whether the byte reaches the panel on real hardware — what
matters is the state when the byte starts transmitting, not when it was queued.

## Expected Byte Flow After Fix

Command C2 01 (LED Standard Rock row 2, bit 0):
```
Byte 1: 45 (sync)     → direct load (idle) → shift out → INTTX
Byte 2: 05 (length)   → direct load (idle) → shift out → INTTX
Byte 3: C2 (cmd)      → direct load (idle) → shift out → INTTX
Byte 4: 03 (padding)  → direct load (idle) → shift out → INTTX
Byte 5: 01 (param)    → direct load (idle) → shift out → INTTX
Byte 6: 03 (padding)  → direct load (idle) → starts shifting
Byte 7: 03 (padding)  → BUFFER (busy)      → auto-loads after byte 6 → shift out
```

Both bytes 6 and 7 transmit correctly. Cpanel receives `03 03` (two padding bytes),
not garbled data. Next command starts clean.

## If This Works
- All LED commands delivered correctly to cpanel
- Correct LED pattern on boot
- Serial link stays synchronized through entire boot sequence
- No more garbled commands after LED fire-and-forget commands

## If This Doesn't Work
1. The desync might have a different root cause than the back-to-back writes
2. There might be additional places where MAME's serial timing differs from real hardware
3. The LED commands themselves might be wrong (firmware sending wrong row/bit data)
4. The cpanel HLE might have bugs in LED command handling
