# Attempt 31 - Thinking Dump (2026-02-14)

## Starting Point

Attempts 27-30 exhaustively proved that cpanel RESPONSE CONTENT, TIMING, and even
PRESENCE/ABSENCE of responses have zero effect on the firmware's LED commands. The
firmware always sends the same 2 LED commands (C2 01, C0 42).

Attempt 30 (no responses) revealed a critical clue: the user saw the "ERROR" message
AND LEDs were "partially correct, partially incorrect". This error message is
"ERROR in back-up SRAM" — triggered when NVRAM validation fails.

## Root Cause Analysis

### NVRAM Validation Flow (LABEL_FEF950)

The firmware validates NVRAM at 0x1E0000:
1. Compares 16-byte header against ROM reference at 0xEED56C
2. Expected header: ASCII "KN5000 SOUND RAM"
3. Checksums 0x24B8 little-endian words (18,800 bytes) from NVRAM+0x10
4. Compares one's complement of sum against stored checksum at NVRAM+0x72A8
5. If BOTH pass → InterCPU_E1_Bulk_Transfer (sends NVRAM data to Sub-CPU)
6. If EITHER fails → LABEL_FEF993 → error message to Sub-CPU

### Current Problem in MAME

MAME initializes nvram2 with `DEFAULT_ALL_0`:
```cpp
NVRAM(config, "nvram2", nvram_device::DEFAULT_ALL_0);
```

All-zero NVRAM fails header validation (not "KN5000 SOUND RAM") → error path →
Sub-CPU payload never transferred → incomplete system initialization.

### Where Are Factory Defaults?

Searched the 2MB program ROM for "KN5000 SOUND RAM":
- **0x0A0150** — Factory defaults data (header + 29,350 bytes of settings)
- **0x0ED56C** — Validation reference copy (header only, followed by function pointers)

The factory defaults copy routine at LABEL_F6BE07 (line 282310):
1. Source: `(3D5Ch) + 0x16C00` — dynamic base from config table + offset
2. Checks source header against RAM reference at 0xE3BA
3. Copies 0x72A6 bytes to NVRAM at 0x1E0000
4. Calls LABEL_FF0506 to compute and store checksum

This routine is NOT called automatically on validation failure. It's a separate
"factory reset" function. On real hardware, NVRAM is pre-programmed at the factory.

### Checksum Verification

For the data at ROM offset 0x0A0150:
- Sum of 0x24B8 LE words from offset +0x10: 0x7815
- CPL (one's complement): 0x87EA
- This is the checksum that should be stored at NVRAM+0x72A8

## The Fix

Initialize nvram2 with factory defaults from the program ROM using MAME's
`nvram_device::DEFAULT_CUSTOM` callback mechanism:

1. Register custom handler: `NVRAM(config, "nvram2").set_custom_handler(...)`
2. In the handler:
   a. Clear all NVRAM to zero
   b. Copy 0x72A6 bytes from ROM offset 0x0A0150 (v10 factory defaults)
   c. Compute checksum (sum of 0x24B8 LE words from offset 0x10, CPL)
   d. Store checksum at offset 0x72A8

After NVRAM init:
- Header check passes ("KN5000 SOUND RAM" matches)
- Checksum passes (computed matches stored)
- InterCPU_E1_Bulk_Transfer proceeds (Sub-CPU gets initialized)
- Sub-CPU returns acknowledgment → main CPU continues with full initialization
- LED settings loaded from factory defaults → correct LED pattern

## What About NVRAM Persistence?

MAME's nvram_device saves NVRAM to disk (kn5000/nvram2.nv). The DEFAULT_CUSTOM
handler only runs on FIRST boot (when no .nv file exists). Subsequent boots load
the saved NVRAM, preserving any user changes.

If the user already has a corrupted .nv file from previous runs, they may need to
delete it to trigger factory defaults initialization. But for a fresh MAME install
or after deleting the nvram directory, this will work correctly.

## Risk Assessment

LOW-MEDIUM:
- The factory defaults offset 0x0A0150 is specific to v10 firmware
- Other ROM versions (v5-v9) may have factory defaults at different offsets
- For now, only v10 is handled (it's the default BIOS)
- The checksum is computed from the ROM data, not hardcoded, so it's self-consistent
- If the ROM data at 0x0A0150 is actually something else (not factory defaults),
  NVRAM will contain wrong data, but the checksum will still pass → firmware won't
  show the error, but settings may be wrong
- AW VM is unaffected (it doesn't use NVRAM)

## If This Works

- The "ERROR in back-up SRAM" message should disappear
- Sub-CPU initialization should proceed normally
- LED initialization should use factory default settings → correct LED pattern
- All 15 LED rows should be initialized properly (not just 2)

## If This Doesn't Work

If LEDs are still partially wrong:
1. The factory defaults at 0x0A0150 might not be the right data
2. The Sub-CPU transfer might need additional NVRAM data beyond 0x72AA
3. There might be additional initialization steps that depend on other factors
4. The LED issue might involve the Sub-CPU's response to the bulk transfer
