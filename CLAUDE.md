# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Custom ROM development for the **Technics KN5000** arranger keyboard. ROMs can be tested in MAME's kn5000 driver and potentially installed on real hardware.

**Target Hardware:**
- CPU: Toshiba TMP94C241F (TLCS-900/H2), 25 MHz, 32-bit CISC
- Display: MN89304 VGA-compatible LCD controller, 320x240 @ 8bpp
- Serial: SC0 for MIDI/Computer Interface, SC1 for Control Panel
- Memory: 2MB Program ROM at 0xE00000-0xFFFFFF, 512KB VRAM at 0x1A0000

## Build Commands

```bash
make          # Build all ROMs (output: build/custom_program.rom)
make clean    # Remove build artifacts
make check    # Verify ASL assembler is available
make test     # Show MAME testing instructions
```

**Requirements:** ASL Macro Assembler at `../tools/asl/asl`

## Architecture

The ROM initializes at reset vector 0xFFFEE0, then:
1. Disables watchdog, sets up stack
2. Configures memory controller and DRAM
3. Initializes VGA display (320x240, 8bpp palette mode)
4. Draws graphics to framebuffer at 0x1A0000
5. Configures SC0 serial port for computer interface

**Key source files:**
- `src/main.asm` - Boot code, hardware init, display/serial routines
- `src/includes/sfr.inc` - CPU Special Function Register definitions
- `src/includes/vga.inc` - VGA controller register definitions
- `src/includes/macros.inc` - TLCS-900 instruction macros for ASL

## Reference Repositories (Read-Only)

These sibling repositories contain essential reference material. **Do not modify them; all changes go in this repo only.**

### Hardware Documentation: `../kn5000-docs/`
| Topic | File | Key Information |
|-------|------|-----------------|
| Memory Map | `memory-map.md` | ROM/RAM addresses, VRAM at 0x1A0000, VGA at 0x170000 |
| Boot Sequence | `boot-sequence.md` | Two-stage boot, reset vector at 0xFFFEE0 |
| Display | `display-subsystem.md` | MN89304 VGA controller, palette setup |
| CPU | `cpu-subsystem.md` | TLCS-900/H2 architecture, SFR addresses |
| Serial | `serial-debugging-journey.md` | SC0/SC1 protocols, baud rates |
| Inter-CPU | `inter-cpu-protocol.md` | Main/Sub CPU communication via 0x120000 latch |

### Original ROM Disassembly: `../kn5000-roms-disasm/`
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

### Assembler: `../tools/asl/`
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

**Serial Port SC0:**
- SC0BUF (0xD0): Data buffer
- SC0CR (0xD1): Control (bit 1 = TX empty)
- SC0MOD (0xD2): Mode (0x29 = 8N1 with baud gen)
- BR0CR (0xD3): Baud rate (0x06 = 38400)

**Boot Requirements:**
1. Disable watchdog: `ld (WDMOD), 0` then `ld (WDCR), 0xB1`
2. Configure memory controller (MSAR/MAMR registers)
3. Initialize DRAM with timing delays
4. Set stack pointer to internal RAM

## Expanding This ROM

To add new features, study the corresponding routines in the disassembly:
- **Keyboard scanning:** `../kn5000-roms-disasm/maincpu/cpanel_routines.asm`
- **Floppy disk:** `../kn5000-roms-disasm/maincpu/fdc_routines.asm`
- **Sound generation:** Requires Sub CPU payload via inter-CPU protocol
- **MIDI:** `../kn5000-roms-disasm/maincpu/midi_serial_routines.asm`
