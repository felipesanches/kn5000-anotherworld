# KN7000 port — platform probes

Read-only MAME probes that measured the KN7000 facts the port relies on. Run against
`kn7000 -bios sp7001` (program 942). A clean PR MAME build needs `-str N`, not
`-skip_gameinfo`, or the autoboot script never starts.

| probe            | question it answers                                   | result (2026-10-16)                                                        |
|------------------|-------------------------------------------------------|----------------------------------------------------------------------------|
| `heap_probe.lua` | how much the firmware heap (`malloc_X`) can give      | ~31 KB free after boot, ~15 KB once the SD screen is open — too small for the game, so game data is loaded into a large RAM window instead |
| `ram_probe.lua`  | which large RAM windows an app can write              | writable: `0x44000000`, `0x4C000000`, `0x50000000–0x503FFFFF` (work RAM), `0x9CE00000` (LCD, 640×240 RGB565). Not writable: `0x56000000`, `0x96800000`, `0x45000000`, flash `0x48000000` |

Work RAM `0x50000000–0x503FFFFF` is definitely real and the firmware uses it heavily; the
library at `0x4C000000` runs from RAM, so the CPU fetches instructions from RAM — the VM can
be loaded from the SD card and executed. `0x44000000` is mapped as 16 MB of RAM by the MAME
driver; its real-hardware size is not yet confirmed, so a real-instrument build must verify it.
