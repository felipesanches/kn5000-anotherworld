# Attempt 31: NVRAM Factory Defaults Initialization (2026-02-14)

## Hypothesis
MAME initializes NVRAM (nvram2 at 0x1E0000) with all zeros. The firmware validates
the NVRAM header (expects "KN5000 SOUND RAM") and checksum, which ALWAYS fails with
all-zero data. This failure:
1. Sends error to Sub-CPU ("ERROR in back-up SRAM")
2. Sub-CPU payload is never transferred
3. System initialization is incomplete
4. LED states are wrong (only 2 of 15 rows set)

On real hardware, NVRAM is pre-programmed with factory defaults at the factory.

## What This Tests
If factory defaults produce correct LEDs, the root cause was NVRAM initialization.
The firmware would proceed through the normal boot path with valid NVRAM, including
Sub-CPU payload transfer, and all LED rows would be initialized from factory settings.

## Fix
Changed NVRAM initialization in kn5000.cpp from `DEFAULT_ALL_0` to `DEFAULT_CUSTOM`
with a handler that:
1. Copies 0x72A6 bytes from program ROM offset 0x0A0150 (v10 factory defaults)
2. Computes checksum: CPL of sum of 0x24B8 LE words from offset 0x10
3. Stores checksum at NVRAM offset 0x72A8

The factory defaults data was found by searching the program ROM for "KN5000 SOUND RAM"
header occurrences (2 found: 0x0A0150 = factory defaults, 0x0ED56C = validation reference).

## Files Modified
- `kn5000.cpp`: NVRAM initialization with factory defaults from program ROM

## Expected Outcome
- No "ERROR in back-up SRAM" message
- Sub-CPU payload transfer succeeds
- All 15 LED rows initialized from factory defaults
- Correct LED pattern on boot

## Risk
- Factory defaults offset 0x0A0150 is v10-specific; other BIOS versions may differ
- If 0x0A0150 is not actually factory defaults, NVRAM will have wrong data but
  checksum will pass (firmware won't show error, but behavior may be unexpected)
- Users with existing corrupted nvram2.nv files will need to delete them
