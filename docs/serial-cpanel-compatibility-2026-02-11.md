# Serial Control Panel Protocol — MAME Compatibility Review

**Date:** February 11, 2026
**Scope:** VM polled serial protocol vs MAME `tmp94c241_serial` and `kn5000_cpanel` HLE devices
**Outcome:** 3 critical bugs found and fixed

## Context

The Another World VM needs to read physical buttons from the KN5000 control panel to provide player input (UP/DOWN/LEFT/RIGHT/ACTION). The control panel communicates with the main CPU via SC1 synchronous serial I/O at 250 kHz, using a 2-byte command / 2-byte response protocol.

The VM implementation uses a simple **polled** approach (write SC1BUF, delay, read SC1BUF) rather than the original firmware's interrupt-driven state machine. This review checks whether the MAME serial device and cpanel HLE device correctly support this protocol.

## Architecture Overview

```
VM code                CPU Serial Device           Control Panel HLE
──────                 ─────────────────           ─────────────────
LD (SC1BUF), A  ──►  scNbuf_w()
                       │ pre-output bit 0
                       │ tx_clock_count = 7
                       ▼
                      timer_callback()
                       │ toggles SCLK
                       ├── rising edge ──────────►  sioclk(1): sample RXD
                       │   sample cpanel TXD
                       ├── falling edge ─────────►  sioclk(0): output TXD
                       │   output next TX bit
                       │   ... 8 bit cycles ...
                       ▼
LD A, (SC1BUF)  ◄──  scNbuf_r() = m_rx_buffer
```

**Signal wiring** (from `kn5000.cpp`):
- `serial[1].txd` → `cpanel.rxd` (CPU sends commands to panel)
- `serial[1].sclk_out` → `cpanel.sioclk` (CPU generates clock)
- `serial[1].tx_start` → `cpanel.tx_start` (byte boundary sync)
- `cpanel.txd` → `serial[1].rxd` (panel sends responses to CPU)

## Bug 1: CPU Serial Timer Stops Before RX Completes

**File:** `tmp94c241_serial.cpp`, `timer_callback()` (line 280)

### Problem

The timer condition only checks `m_tx_clock_count`:

```cpp
if (m_hz && m_tx_clock_count && (...))
    sioclk(m_sioclk_state ^ 1);
```

In synchronous I/O mode, TX and RX happen simultaneously on the same clock. TX needs 7 falling edges (bits 1-7, after pre-outputting bit 0). RX needs 8 rising edges (bits 0-7). The clock alternates: R, F, R, F, ... giving us paired edges.

After 14 toggles (7 rising + 7 falling), `tx_clock_count` reaches 0 on the last falling edge. But `rx_clock_count` is still 1 — it needs one more rising edge to complete the byte.

**With the timer condition `m_tx_clock_count > 0` being false, the timer stops.** The 8th rising edge never happens. The CPU's `m_rx_buffer` is never updated. The cpanel's `process_received_byte` is never called.

**Impact:** Neither the CPU nor the cpanel ever receives a complete byte. The entire serial protocol is non-functional.

### Fix

Add `m_rx_clock_count != 8` to the timer condition:

```cpp
bool need_clock = (m_tx_clock_count > 0) || m_tx_skip_first_falling || (m_rx_clock_count != 8);
if (m_hz && need_clock && (...))
    sioclk(m_sioclk_state ^ 1);
```

After TX completes, the timer continues for one more toggle (rising edge), completing RX. Then `rx_clock_count` resets to 8 and `need_clock` becomes false.

### Verification trace

Starting with `sioclk_state = 0`, `tx_clock_count = 7`, `rx_clock_count = 8`:

| Toggle | Edge | TX count | RX count | Notes |
|--------|------|----------|----------|-------|
| 1 | R | 7 | 7 | RX samples bit 0 |
| 2 | F | 6 | 7 | TX outputs bit 1 |
| 3 | R | 6 | 6 | RX samples bit 1 |
| ... | ... | ... | ... | ... |
| 13 | R | 1 | 1 | RX samples bit 6 |
| 14 | F | **0** | 1 | TX outputs bit 7, TX complete |
| 15 | **R** | 0 | **0** | **RX samples bit 7, RX complete** |

Without the fix, toggle 15 never happens. With the fix, the timer generates it because `rx_clock_count = 1 != 8`.

## Bug 2: Cpanel Queue Byte Loading Overwrites Last Bit

**File:** `kn5000_cpanel.cpp`, `sioclk()` falling edge handler (line 163)

### Problem

When the cpanel sends multi-byte responses (e.g., a 2-byte button packet: header + state), the second byte is queued via `send_byte()`. When the first byte finishes transmitting on a falling edge, the queue loader immediately pre-outputs bit 0 of the next byte:

```cpp
if (m_tx_clock_count == 0) {
    if (!m_tx_queue.empty()) {
        m_tx_shift_register = m_tx_queue.front();
        m_tx_queue.pop();
        m_tx_clock_count = 7;
        m_txd_cb(m_tx_shift_register & 1);  // BUG: overwrites bit 7!
    }
}
```

This `m_txd_cb()` call overwrites bit 7 of the previous byte on the TXD line **before the CPU can sample it** on the next rising edge. The CPU receives a corrupted byte (bit 7 of the header is replaced with bit 0 of the state byte).

### Fix

When loading from the queue, use `tx_clock_count = 8` (full byte, no pre-output) and let the next falling edge output bit 0 naturally:

```cpp
if (m_tx_clock_count == 0) {
    if (!m_tx_queue.empty()) {
        m_tx_shift_register = m_tx_queue.front();
        m_tx_queue.pop();
        m_tx_clock_count = 8;  // Full 8 bits, no pre-output
        // Don't call m_txd_cb — bit 7 of previous byte stays on the line
    }
}
```

A new branch handles the `tx_clock_count == 8` case on the next falling edge:

```cpp
if (m_tx_clock_count == 8) {
    // First bit of chained byte — output bit 0 without shifting
    m_txd_cb(m_tx_shift_register & 1);
    m_tx_clock_count--;  // 8 → 7
} else {
    // Normal: shift then output
    m_tx_shift_register >>= 1;
    m_txd_cb(m_tx_shift_register & 1);
    m_tx_clock_count--;
}
```

### Why the initial `send_byte()` pre-output is correct

When `send_byte()` is called on an idle channel, it pre-outputs bit 0 and sets `tx_clock_count = 7`. This is correct because:
- The pre-output makes bit 0 available before any clock edges
- `m_tx_skip_first_falling` prevents the falling edge from advancing to bit 1 prematurely
- The CPU samples bit 0 on the first rising edge

The bug only occurs during back-to-back bytes where bit 7 of byte N hasn't been sampled yet when byte N+1 is loaded.

## Bug 3: VM Delay Loop Too Short

**File:** `another_world_vm.asm`, `_cpanel_send_byte`

### Problem

The MAME baud rate timer fires at `m_hz = 250,000 Hz`. Since each fire toggles the clock once, the effective SCLK frequency is 125 kHz (2 toggles per bit). One byte (8 bits) requires 16 toggles at 4 us each = **64 us**.

The original delay loop used `LD A, 080h` (128 iterations). At approximately 750 ns per iteration (DEC + JR on TLCS-900 at 16 MHz), this gives ~48 us — shorter than the 64 us needed.

### Fix

Increased to `LD A, 0FFh` (255 iterations) = ~191 us, providing ample margin.

### Note on timer rate

The MAME timer fires at the baud rate (250 kHz) but should fire at 2x the baud rate (500 kHz) to generate the correct SCLK frequency. This is a separate issue that makes serial communication 2x slower than real hardware. It doesn't break correctness for either the original firmware (interrupt-driven) or our VM (polled with sufficient delay), so it is left unfixed for now to minimize risk to existing behavior.

## Additional Fix: SC1CR Receive Enable

**File:** `boot_hw_init.asm`

Changed `LD (SC1CR), 000h` to `LD (SC1CR), 001h` to set the RXE (receive enable) bit, matching the original firmware's `CPanel_InitHardware`. While MAME's serial device doesn't check this bit, it's needed for correctness on real hardware.

## Full Protocol Trace (4-byte exchange)

After all fixes, a complete segment query works as follows:

**Byte 1** — VM sends command (e.g., 0xE0), cpanel is idle:
- CPU TX: 0xE0, cpanel TX: 0xFF (idle)
- Cpanel receives 0xE0 → stores as cmd_buffer[0]
- CPU receives 0xFF (discarded by VM)

**Byte 2** — VM sends parameter (e.g., 0x04), cpanel is idle:
- CPU TX: 0x04, cpanel TX: 0xFF (idle)
- Cpanel receives 0x04 → cmd_buffer[1], triggers `process_command()`
- `send_button_packet()` queues 2-byte response (header + state)
- Cpanel pre-outputs bit 0 of header, sets skip_first_falling
- CPU receives 0xFF (discarded by VM)

**Byte 3** — VM sends 0xFF (dummy), cpanel sends header:
- CPU TX: 0xFF, cpanel TX: header byte
- At byte end, cpanel loads state from queue (tx_clock_count = 8, no pre-output)
- CPU receives header (discarded by VM)

**Byte 4** — VM sends 0xFF (dummy), cpanel sends state:
- CPU TX: 0xFF, cpanel TX: state byte (button bitmap)
- CPU receives state → **VM reads this as the button bitmap**

## Compatibility with Original Firmware

All three fixes are backward-compatible with the original KN5000 firmware:

1. **Bug 1 (timer):** The original firmware was also affected — it uses INTRX1 interrupt which requires RX completion. With the fix, both INTTX1 and INTRX1 fire correctly.

2. **Bug 2 (queue):** The original firmware triggers multi-byte responses (e.g., `send_all_button_states` sends 22 bytes). Every byte boundary was corrupted. The fix ensures clean transitions.

3. **Bug 3 (delay):** Only affects our VM's polled approach, not the interrupt-driven original firmware.

## Files Modified

| File | Change |
|------|--------|
| `tmp94c241_serial.cpp` | timer_callback: add `m_rx_clock_count != 8` condition |
| `kn5000_cpanel.cpp` | sioclk falling edge: queue loads use tx_clock_count=8, no pre-output; handle tx_clock_count==8 case |
| `another_world_vm.asm` | _cpanel_send_byte delay: 0x80 → 0xFF |
| `boot_hw_init.asm` | SC1CR: 000h → 001h (enable RX) |
