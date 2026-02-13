# Control Panel INTA Mechanism — MAME Driver Update

**Date:** February 12, 2026
**Scope:** Enable the original KN5000 firmware's bidirectional serial protocol for control panel button input
**Outcome:** 2 bugs fixed, 1 architectural feature added (INTA self-clocking)

## Context

The original KN5000 firmware uses a **bidirectional serial protocol** to communicate with the control panel MCUs:

1. **CPU → Panel (master mode):** CPU drives SCLK via baud rate generator (IOC=0), sends 2-byte commands
2. **Panel → CPU (slave mode):** Panel asserts INTA pin, CPU switches to slave mode (IOC=1), panel drives SCLK and sends response bytes

The MAME cpanel HLE only supported the **CPU-always-master** approach used by the Another World VM (send dummy 0xFF bytes to clock in responses). The original firmware's INTA-triggered slave mode was not implemented.

## Architecture: Two Serial Modes

### Mode A — Dummy-byte (Another World VM)

```
VM code             CPU Serial              Control Panel HLE
──────              ──────────              ─────────────────
SC1BUF = cmd   ──►  TX: cmd byte
                     SCLK ─────────────────► sioclk(): receive cmd
SC1BUF = param ──►  TX: param byte
                     SCLK ─────────────────► sioclk(): receive param
                                              process_command() → queue response
SC1BUF = 0xFF  ──►  TX: dummy byte
                     SCLK ─────────────────► sioclk(): shift out response byte 1
SC1BUF = 0xFF  ──►  TX: dummy byte
                     SCLK ─────────────────► sioclk(): shift out response byte 2
SC1BUF read    ◄──  RX: button bitmap
```

CPU drives SCLK throughout. Response clocked out on CPU's clock.

### Mode B — INTA-triggered (Original Firmware)

```
Firmware            CPU Serial              Control Panel HLE
────────            ──────────              ─────────────────
SendCommand()  ──►  TX: cmd + param
                     SCLK ─────────────────► sioclk(): receive cmd+param
                                              process_command() → queue response
                                              idle_detect_timer starts (250µs)
                     [CPU stops driving SCLK]
                                              ... 250µs elapses ...
                                              idle_detect_callback():
                                                assert INTA ──────────► PE.5=1, INTA interrupt
INTA_HANDLER:                                   50µs delay
  IOC=1 (slave)                                 start self_clock_timer (250 kHz)
  RXE=1                                         self_clock_callback():
                                                  SCLK toggle ────────► sioclk(): RX bit
                     ◄─────────────────────────── ... 8 bits per byte ...
INTRX1_HANDLER:                                 [all bytes sent]
  RX byte → buffer                              deassert INTA ────────► PE.5=0
```

Panel drives SCLK during response. CPU is slave.

## Bug 1: Missing INTA Mechanism

### Problem

The cpanel HLE had no INTA output. In `kn5000.cpp`:

```cpp
//m_cpanel.sclk_out().set_inputline(m_maincpu, TLCS900_INTA);
// .set(m_maincpu->m_serial[1], FUNC(tmp94c241_serial_device::sioclk));
```

Both connections were commented out. The cpanel could never:
- Assert INTA to notify the CPU of pending response data
- Drive SCLK to clock out response bytes

The firmware's `CPanel_WaitTXReady` checked PE.5 (INTA pin), which was hardcoded to 0 in the PE port read (`set_constant(1)`), so commands could be sent. But `INTA_HANDLER` never fired, so the RX state machine never entered receive mode. The RX ring buffer stayed empty. `CPanel_RX_Process` found no data. Button states were never updated.

**Impact:** The original firmware could not detect any button presses.

### Fix

**kn5000_cpanel.h / .cpp:**

Added three timers and an INTA callback:

- **`m_inta_cb`**: Output callback connected to PE.5 and TLCS900_INTA interrupt
- **`m_idle_detect_timer`** (250µs one-shot): Fires when external SCLK has been idle, triggering INTA assertion and self-clocking
- **`m_self_clock_timer`** (250 kHz periodic): Drives SCLK from the cpanel side, one edge per fire (toggle)
- **`m_self_clocking`** flag: Prevents `sioclk()` from retriggering the idle timer during self-clocking (avoids feedback loop)

**Protocol flow:**

1. `process_command()` queues response → starts idle detect timer (250µs)
2. If CPU sends dummy bytes (AW VM):
   - Each clock edge retriggers idle timer → timer never fires
   - Response clocked out normally on CPU's clock
3. If CPU stops driving SCLK (original firmware):
   - Idle timer fires at 250µs
   - INTA asserted → CPU interrupt fires
   - Self-clock timer starts after 50µs delay (for ISR processing)
   - Self-clock drives SCLK at 125 kHz (250 kHz toggle rate)
   - CPU serial receives bytes via INTRX1
   - When TX complete → deassert INTA, stop self-clock

**kn5000.cpp:**

- Connected `cpanel.sclk_out()` → `serial[1].sioclk()` (was commented out)
- Connected `cpanel.inta()` → PE.5 bit + TLCS900_INTA interrupt
- PE port read now dynamic: `0x01 | (m_cpanel_inta ? 0x20 : 0x00)`

### Clock feedback prevention

Both CPU serial and cpanel forward SCLK to each other via callbacks:

```
CPU serial sioclk() → sclk_out_cb → cpanel sioclk() → sclk_out_cb → CPU serial sioclk()
```

The `if (m_sioclk_state == state) return;` guard in both `sioclk()` methods prevents infinite recursion. Each clock edge propagates exactly once through both devices.

### Timing constraints

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Idle detect timeout | 250µs | Longer than AW VM delay (191µs), shorter than firmware inter-command gap (~6ms) |
| Self-clock start delay | 50µs | ~800 CPU cycles — enough for INTA ISR to enable RX |
| Self-clock rate | 250 kHz (125 kHz SCLK) | Matches CPU serial timer behavior |

## Bug 2: Wrong Command Responses (0x25, 0xE2, 0xE3)

### Problem

The firmware's `CPanel_ReadAllButtons` sends:

| Command | Expected Response | HLE Response (before fix) |
|---------|-------------------|---------------------------|
| `0x25 0x01` | Button data, left panel seg 1 | Sync packet |
| `0xE2 0x04` | Button data, right panel seg 4 | Sync packet |
| `0x20 0x10` | Sync (status query) | Sync packet (correct) |
| `0xE2 0x11` | Sync (status query) | No response! |

Commands 0x25 and 0xE2/0xE3 are **variants** of the base query commands 0x20 and 0xE0 (different lower bits, same panel selection via bits 7-5). The HLE treated them as separate commands and returned sync packets instead of button data.

Additionally, params > 0x0A that weren't explicitly handled (like 0x11) produced no response at all, causing the firmware to stall waiting for data.

### Fix

Commands 0x25 dispatches like 0x20, and 0xE2/0xE3 dispatch like 0xE0:

```cpp
case 0x20:
case 0x25:  // variant, same dispatch
    if (param <= 0x0a)
        send_button_packet(param, true);  // left panel
    else
        send_sync_packet();  // status/encoder/unknown
    break;

case 0xe0:
case 0xe2:  // variant
case 0xe3:  // variant
    if (param <= 0x0a)
        send_button_packet(param, false);  // right panel
    else
        send_sync_packet();
    break;
```

All params now produce a response. Params 0x00 (ping) and 0x01-0x0A (segment queries) work as before. Params > 0x0A default to sync, covering status queries (0x0B, 0x10), encoder queries (0x0C-0x0E), and unknown params (0x11+).

## Compatibility

| Feature | AW VM | Original Firmware |
|---------|-------|-------------------|
| Command sending | Works (polled SC1BUF) | Works (interrupt state machine) |
| Response delivery | Dummy bytes (unchanged) | INTA + self-clock (new) |
| Button data | CPR_SEG4 + CPL_SEG4 | All 22 segments |
| 0x25 command | Not used | Now returns button data |
| 0xE2/0xE3 commands | Not used | Now returns button/sync data |
| INTA assertion | Timer retriggered, never fires | Fires at 250µs, enables RX |
| PF.6 (SCLK pin) | Hardcoded HIGH (OK for polled) | Hardcoded HIGH (OK — not checked during RX) |

## Files Modified

| File | Change |
|------|--------|
| `kn5000_cpanel.h` | Added INTA callback, idle/self-clock timers, self_clocking/inta_asserted state |
| `kn5000_cpanel.cpp` | INTA mechanism (idle detect + self-clock); fixed 0x25/0xE2/0xE3 command dispatch |
| `kn5000.cpp` | Connected cpanel SCLK→serial sioclk, INTA→PE.5+interrupt; dynamic PE read |
