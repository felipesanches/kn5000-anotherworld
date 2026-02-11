# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Custom ROM development for the **Technics KN5000** arranger keyboard. ROMs can be tested in MAME's kn5000 driver and potentially installed on real hardware.

**Target Hardware:**
- CPU: Toshiba TMP94C241F (TLCS-900/H2), 32-bit CISC
  - 16 MHz (2 x 8 MHz XTAL)
- Display: MN89304 VGA-compatible LCD controller, 320x240 @ 8bpp
- Serial: SC0 for MIDI/Computer Interface, SC1 for Control Panel
- Memory: 2MB Program ROM at 0xE00000-0xFFFFFF, 512KB VRAM at 0x1A0000

## Build Commands

```bash
make          # Build maincpu ROM and create MAME ROM set (default)
make maincpu  # Build as standalone main CPU ROM (2MB, for MAME testing)
make extension# Build as HDAE5000 extension board ROM (512KB)
make build    # Build custom ROM only (out/custom_program.rom)
make romset   # Create complete MAME ROM set
make test     # Run in MAME emulator
make clean    # Remove build artifacts (preserves ROM set)
make distclean# Remove everything including ROM set
make check    # Verify tools and original ROMs are available
```

**Dual-target build:** Uses `ifdef TARGET_MAINCPU` / `ifdef TARGET_EXTENSION` conditional assembly in `src/main.asm`. The VM code in `src/another_world_vm.asm` is shared between both targets.

**Requirements:**
- ASL Macro Assembler at `../../tools/asl/asl`
- Original KN5000 ROMs at `/mnt/shared/kn5000_original_roms/kn5000/`
- Game resources in `src/resources/` and `src/` (see README for extraction)

**Output:**
- Build artifacts: `out/`
- MAME ROM set: `/mnt/shared/custom_kn5000_roms/anotherworld/kn5000/`

## Architecture

**Maincpu target** initializes at reset vector 0xFFFEE0, then:
1. Disables watchdog, sets up stack
2. Configures memory controller and DRAM
3. Initializes VGA display (320x240, 8bpp palette mode)
4. Jumps to VM ENTRY point

**Extension target** is loaded by the KN5000 firmware via the XAPR header and jumps directly to the VM ENTRY point.

**Memory layout differs by target:**
- **Maincpu:** RAM at 0x010000, page buffers at 0x020000-0x050000, offscreen at 0x060000 (in 1MB DRAM)
- **Extension:** RAM at 0x200000, page buffers at 0x240000-0x270000 (in 512KB extension SRAM)

**Key source files:**
- `src/main.asm` - Unified platform wrapper (conditional assembly for maincpu/extension)
- `src/another_world_vm.asm` - Another World bytecode VM (shared between targets)
- `src/includes/local_macros.inc` - TLCS-900 instruction macros for ASL

## Current Goal

**Fix both the Another World VM and the MAME KN5000 driver to achieve a fully playable game, while keeping the MAME driver compatible with the original KN5000 firmware.**

This is a dual-target effort:
- **VM code** (this repo): Implement missing features (input, sound, all game parts)
- **MAME driver** (`../../kn5000-roms-disasm/mame_driver/`): Fix emulation bugs discovered during VM development (serial, timers, etc.). All MAME changes must be validated against the original firmware behavior — the driver serves both our custom ROM and the stock KN5000 ROM.

The MAME driver files are at `../../kn5000-roms-disasm/mame_driver/` and are **editable**. You may edit anything needed in the MAME driver as long as changes are:
1. **Technically accurate** — consistent with TMP94C241 datasheets and KN5000 service manual
2. **Compatible with the original KN5000 firmware** — the stock ROM must continue to work correctly

Changes are manually copied to the user's full MAME source tree for building and testing.

Key MAME driver files:
- `src/devices/cpu/tlcs900/tmp94c241_serial.cpp/.h` — CPU serial channel emulation
- `src/mame/matsushita/kn5000_cpanel.cpp/.h` — Control panel HLE (button input)
- `src/mame/matsushita/kn5000.cpp` — Main driver (wiring, memory map, input ports)

## Reference Repositories

These sibling repositories contain essential reference material. **Do not modify them**, except for MAME driver files under `../../kn5000-roms-disasm/mame_driver/` (see Current Goal above for editing policy).

### Hardware Documentation: `../../kn5000-docs/`
| Topic | File | Key Information |
|-------|------|-----------------|
| Memory Map | `memory-map.md` | ROM/RAM addresses, VRAM at 0x1A0000, VGA at 0x170000 |
| Boot Sequence | `boot-sequence.md` | Two-stage boot, reset vector at 0xFFFEE0 |
| Display | `display-subsystem.md` | MN89304 VGA controller, palette setup |
| CPU | `cpu-subsystem.md` | TLCS-900/H2 architecture, SFR addresses |
| Serial | `serial-debugging-journey.md` | SC0/SC1 protocols, baud rates |
| Inter-CPU | `inter-cpu-protocol.md` | Main/Sub CPU communication via 0x120000 latch |

### Original ROM Disassembly: `../../kn5000-roms-disasm/`
| Component | File | Contains |
|-----------|------|----------|
| Main CPU Program | `maincpu/kn5000_v10_program.asm` | Full 2MB disassembly, UI/MIDI routines |
| VGA Init | `shared/vga_init.asm` | Original display initialization sequence |
| VGA Constants | `shared/vga_constants.asm` | Register definitions (copied to our vga.inc) |
| SFR Definitions | `shared/sfr_tmp94c241.asm` | CPU register addresses |
| CPU Macros | `tmp94c241.inc` | ASL instruction encoding macros |
| MIDI Serial | `maincpu/midi_serial_routines.asm` | SC0 TX/RX handlers |
| Sub CPU Boot | `subcpu/boot/kn5000_subcpu_boot.asm` | Sub CPU initialization |
| Symbols | `symbols/maincpu_symbols_reference.txt` | 39,125 named addresses |
| AW VM HLE | `mame_driver/src/devices/cpu/anotherworld/` | Reference C++ implementation of all opcodes |

### MAME HLE Reference
- Full commit: https://github.com/felipesanches/mame/commit/7cbb93bc3ee05f5ffdd083081530ac0daa2dfa84
- Local copy: `../../kn5000-roms-disasm/mame_driver/src/devices/cpu/anotherworld/`

### Assembler: `../../tools/asl/`
- `asl` - ASL Macro Assembler 1.42 Beta
- `p2bin` - Converts .p intermediate files to raw binary ROM

## TLCS-900 Assembly Notes

**ASL quirks for TMP94C241:**
- Use `cpu 96c141` directive
- Some instructions need macros (see `macros.inc`): `LDIR_94`, `LDA_XWA_IMM24`, `CALR`
- 24-bit addresses require special encoding macros
- Registers: XWA/XBC/XDE/XHL (32-bit), WA/BC/DE/HL (16-bit), A/B/C/D/E/H/L (8-bit)

**Memory access:**
```asm
ld (addr), value      ; Direct addressing (16-bit addr)
ld (XDE), A           ; Register indirect
LDA_XWA_IMM24 addr    ; Load 24-bit address into XWA
```

## Hardware Quick Reference

**VGA Display:**
- Base: 0x170000 (+ VGA port offset, e.g., 0x1703C8 for DAC)
- VRAM: 0x1A0000, linear framebuffer, 1 byte per pixel
- Palette: 6-bit RGB values via DAC registers

**Serial Port SC0 (MIDI):**
- SC0BUF (0xD0): Data buffer
- SC0CR (0xD1): Control (bit 1 = TX empty)
- SC0MOD (0xD2): Mode (0x29 = 8N1 with baud gen)
- BR0CR (0xD3): Baud rate (0x06 = 38400)

**Serial Port SC1 (Control Panel):**
- SC1BUF: Data buffer (write to send, read to receive in sync mode)
- SC1MOD = 0x00: Synchronous I/O mode, clock source = TO2 trigger (original firmware) or baud rate gen
- BR1CR = 0x14: 250 kHz (16 MHz / 16 / 4)
- SC1CR = 0x01: IOC=0 (master/internal clock), RXE=1 (receive enable)
- Protocol: 2-byte command (panel_cmd + segment), 2-byte response (header + button_bitmap)
- See [`docs/serial-cpanel-compatibility-2026-02-11.md`](docs/serial-cpanel-compatibility-2026-02-11.md) for MAME bugs and fixes

**Timers (T0/T1 cascade → INTT1 ISR):**
- 12,500 Hz tick rate (80µs/tick) at MAME's 16 MHz clock
- `TICKS_PER_SLICE = 250` (~20ms); PAUSE reads `var[0xFF]` for frame duration
- Prescaler requires `LD (T16RUN), 080h` — T8RUN alone is not enough in MAME
- See [`docs/timer-frame-timing.md`](docs/timer-frame-timing.md) for full details and MAME vs real hardware differences

**Boot Requirements:**
1. Disable watchdog: `ld (WDMOD), 0` then `ld (WDCR), 0xB1`
2. Configure memory controller (MSAR/MAMR registers)
3. Initialize DRAM with timing delays
4. Set stack pointer to internal RAM

## Another World VM Architecture

The VM interprets big-endian bytecode (Amiga/68k origin) on a little-endian TLCS-900 CPU.

**Bytecode execution:**
- `XIX` register points to current bytecode position during instruction execution
- `_end_of_EXECUTE_INSTRUCTION` recomputes `VM_PC` from `XIX` offset — XIX must point to bytecode
- `_after_PC_update` skips VM_PC recomputation — use when VM_PC was already set (JMP, CALL, RET, NEXT_THREAD)
- Opcodes that replace XIX with non-bytecode pointers (0x80, 0x40 video) must save VM_PC BEFORE the replacement and use `_after_PC_update`

**Thread model:**
- 64 threads, each with a PC slot in `THREADS_DATA` and activation state in `VM_IS_CHANNEL_ACTIVE`
- `pauseThread` saves requested_PC; `NEXT_THREAD` scans for next active thread
- `CHECK_THREAD_REQUESTS` commits requested_PC → PC at frame boundaries
- `INACTIVE_THREAD` (0xFFFE) marks unused thread slots

**Video pages:**
- 4 page buffers (320x240 @ 8bpp = 76,800 bytes each)
- Page IDs: 0-3 map directly; 0xFF = current back buffer; 0xFE = current front buffer
- `GET_PAGE_PTR` resolves page ID → 24-bit address

**Endianness:** All `fetch_word()` operations must byte-swap with `EX W, A` after reading via `LD WA, (XIX)`.

**Helper functions:**
- `_read_vm_var`: Input A=index, Output DE=value (clobbers XIY/XWA)
- `_write_vm_var`: Input A=index, DE=value (clobbers XIY/XWA)

**Reference implementation:** MAME HLE at `../../kn5000-roms-disasm/mame_driver/src/devices/cpu/anotherworld/`

**Resources (intro/part 1):**
- Bytecode: `src/resources/resource-0x18.bin`
- Palettes: `src/resources/resource-0x17.bin` (16 colors/palette, 2 bytes/color, 0x0RGB format)
- Video polygons: `src/resources/resource-0x19.bin` (video1), `resource-0x1a.bin` (video2)
- Screen bitmaps: `src/resources/resource-0x49.bin`, `resource-0x53.bin`

## TLCS-900 Pitfalls (Learned from Debugging)

**INC instruction encoding:** Only supports values 1, 2, 4, 8 (encoded in 2-bit field). ASL assembler silently accepts any value but encodes raw bits. MAME treats the 3-bit field literally (`value ? value : 8`), so `INC 3` "works" in MAME but is **undefined on real TMP94C241F**. Always use `ADD` for non-power-of-2 increments.

**Register clobbering:**
- `LD BC, WA` clobbers B — save B to stack first if needed later
- `POP WA` restores both W and A — don't follow with `LD A, W` (overwrites restored A)
- `LDIRW` uses XHL=src, XDE=dst, XBC=word_count (not XIX/XIY)

**Signed vs unsigned shifts:** `SRA` (arithmetic shift right) sign-extends; `SRL` (logical shift right) zero-fills. Use `SRL` for unsigned nibble extraction (e.g., extracting high nibble of a byte).

**MAME TLCS-900 bugs:**
- `DEC 1, rr; JP NZ` doesn't work — DEC doesn't set flags correctly. Use `DJNZ rr, label` instead.
- Prescaler requires T16RUN bit 7 (not just T8RUN). See [`docs/timer-frame-timing.md`](docs/timer-frame-timing.md).
- MAME's T01MOD register layout and prescaler divisions differ from the TMP94C241F datasheet.
- **Serial timer stops early:** `timer_callback` only checks `m_tx_clock_count`, missing the final rising edge needed for RX completion. Fix: also check `m_rx_clock_count != 8`.
- **Cpanel queue overwrites last bit:** When loading next byte from TX queue, pre-outputs bit 0 before CPU samples bit 7 of previous byte. Fix: use `tx_clock_count = 8`, defer bit 0 output to next falling edge.
- **Serial baud rate timer at half speed:** Timer fires at `m_hz` but toggles SCLK, so effective bit rate is `m_hz/2`. Not fixed yet — VM uses longer delay loop to compensate.

**AW palette → VGA DAC conversion:**
- AW format: 2 bytes/color, `0x0RGB`. Byte 0 low nibble = R, byte 1 high nibble = G, byte 1 low nibble = B
- VGA DAC expects 6-bit values (0-63) in R, G, B order; AW uses 4-bit (0-15)
- Must `SLA 2, A` to scale each channel from 4-bit to 6-bit

## Mandatory Policy: Conversation Logs

**Every Claude Code session that makes changes to this project MUST save its full conversation transcript before committing.** This is a mandatory policy for this project.

Procedure:
1. At the end of each session (before or alongside the commit), copy the current conversation JSONL file from `~/.claude/projects/-home-fsanches-devel-custom-kn5000-roms/` to `logs/`
2. Name the log file: `YYYY-MM-DD_short-description.jsonl`
3. If there was a separate planning session, save that too with a `_planning` suffix
4. Include the log files in the commit

Log directory: `logs/`

## Expanding This ROM

To add new features, study the corresponding routines in the disassembly:
- **Keyboard scanning:** `../../kn5000-roms-disasm/maincpu/cpanel_routines.asm`
- **Floppy disk:** `../../kn5000-roms-disasm/maincpu/fdc_routines.asm`
- **Sound generation:** Requires Sub CPU payload via inter-CPU protocol
- **MIDI:** `../../kn5000-roms-disasm/maincpu/midi_serial_routines.asm`
