# KN5000 Floppy Disc Research (2026-02-12)

## Boot Sector Investigation

### EB FE on TLCS-900 ≠ infinite loop
- x86: `JMP $` (infinite loop) — standard non-bootable FAT boot code
- TLCS-900: `SLL A, XHL` (shift left logical) — valid register manipulation
- Verified: `dasm900.cpp` lines 1336, 1175, 1780 (M_E8 group, mnemonic_e8[0xFE])
- Boot sector bytes are x86 code for PC FAT compatibility; TLCS-900 never reads them

### Firmware never reads sector 0
- All 9 FDC read calls use sector 33 (0x21) or higher
- `Detect_Disk_Type` at 0xEF42FE (line 140607): loads sector 0x21
- `Boot_DetectDiskType` at 0x9FBFC4 (line 1740): same
- No BPB check, no OEM ID check, no boot code execution

## Update Disc Format
- FAT12 filesystem, "Technics" OEM ID, standard 1.44MB BPB
- 8 disc type signatures at Table Data ROM 0x9FA000 (38 bytes each)
- Types 1-4: raw multi-disc program/table ROM
- Type 5: compressed custom data → Custom Data Flash (0x300000)
- Type 6: HDAE5000 extension → Flash at 0x280000
- Types 7-8: SLIDE4K compressed program/table ROM
- All handlers write to flash memory, none execute loaded code
- Post-update: infinite loop at 0xEF05E6 ("Turn On AGAIN!!")
- `String_Compare` `PUSHW 00E0h` parameter = buffer offset (224 bytes into sector buffer)
- Documentation: `../../kn5000-docs/system-update-discs.md`

## SSF Presentation Script System (Feature Demo)

### XML-based presentation format
- File: `hkst_55.ssf` at Table Data ROM 0x87FFF0 (metadata), 0x88000E (XML data)
- Source: `../../kn5000-roms-disasm/table_data/includes/hkst_55.ssf`
- 27 sequential `<ACT NO=n><SHOW OBJ="name">` actions
- Objects: ftdemo01-48, Accordion, Drawbar, Sdmixer
- Second SSF: `hkt_87.ssf` near boot vectors (table_data.asm line 3855)

### XML tag vocabulary (program ROM ~line 87475)
- Structure: `PRESENTATION`, `ACTION`, `ACT`
- Content: `SHOW`, `IMG`, `FONT`, `CENTER`, `BR`, `SONG`
- Attributes: `NAME`, `SRC`
- **`EXEC` tag** — suggests planned code execution within presentations

### Presentation handlers
- `AcPresentationControlProc` at line 309287 (0xF8450B)
- `AcPresentationBoxProc` at line 309070 (0xF842B4)
- `AcFdemoScreenProc` at line 308910 (0xF84149)
- Events: `EV_READPRESENTATION`, `EV_READACTION`, `EV_READSONG`

### Feature Demo assets (Table Data ROM)
- 6 BMP images (FTBMP01-06): Technics globe, subwoofers, floppy, surround, KN5000 rainbow
- Addresses: 0x880418 - 0x8BAFE6 (40-78 KB each)
- 48 named UI objects in Program ROM (lines 36978-42354)

### No floppy loading path
- SSF parser reads from hardcoded ROM addresses only
- No floppy disc type for presentations
- File I/O handles: MIDI, registrations, styles — NOT SSF
- Infrastructure was likely designed for floppy but never shipped

## Disc Image Creation Tool
- `tools/make_update_disc.py` — creates FAT12 update disc images
- `make disc` target builds type 7 (compressed program ROM) disc
- Supports type 6 (HDAE5000 extension) and type 7 (program ROM)
- Boot sector byte-for-byte matches original Technics v10 disc
