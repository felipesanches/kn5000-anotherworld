# KN7000 port — platform probes

Read-only MAME probes that measured the KN7000 facts the port relies on. Run against
`kn7000 -bios sp7001` (program 942). A clean PR MAME build needs `-str N`, not
`-skip_gameinfo`, or the autoboot script never starts.

| probe                                         | question it answers                                         | result (2026-10-16) |
|-----------------------------------------------|-------------------------------------------------------------|---|
| `heap_probe.lua`                              | how much the firmware heap (`malloc_X`) can give            | ~31 KB free after boot, ~15 KB once the SD screen is open — too small for the game, so game data is loaded into a large RAM window instead |
| `ram_probe.lua`                               | which large RAM windows an app can write                    | writable: `0x44000000`, `0x4C000000`, `0x50000000–0x503FFFFF` (work RAM), `0x9CE00000` (LCD, 640×240 RGB565). Not writable: `0x56000000`, `0x96800000`, `0x45000000`, flash `0x48000000` |
| `fileapi.lua`                                 | the framework object's file-method pointers                 | `framework+0x2E1C` slots `+0x2D0/+0x2D8/+0x2DC` are `fopen_api`/`fread_api`/`fclose_api` |
| `sdread.lua` + `sdread.s`                     | does reading a file from the SD card work?                  | **yes** — from the hook, single-backslash path, buffer in work RAM: the exact file bytes appear |
| `awpanelmap.lua`                              | each panel button's bit in the firmware switch-shadow       | debounced, level-held bitmap: CPR_SEGn at `0x5006BE60+n`, CPL/CPC at `0x5006BE90+n`, bit = `1 << SWn`. See [PANEL-INPUT.md](PANEL-INPUT.md) |
| `awcombo.lua`                                 | (superseded) same-frame combo with per-frame re-press       | collapses to one bit — but that was test churn, see below |
| `awcombo2.lua`, `awstagger.lua`               | do staggered (human) two-button holds coexist?              | **yes** — all four diagonals + move+fire register and persist; only two changes in the *same* 4 ms scan collapse (not reachable by hand) |
| `awdiag.lua`                                  | each button alone vs same-frame pairs                       | every button registers alone; same-frame pairs collapse (scan-timing artifact) |
| `awinputverify.lua`                           | do the panel buttons write the right hero variables?        | all five single-button cases match rustyworld's `update_player` exactly |
| `awmove.lua`                                  | does holding a direction change the game output?            | **yes** — displayed-page checksums diverge by direction (none vs UP vs LEFT) |
| `awnotediff.lua`, `awkeycal.lua`              | (wrong region) keybed held-note in `0x50148000..`           | nothing stable there — only phase caches; superseded by the probes below |
| `awnodes.lua`, `awnode2.lua`, `awkeyread.lua` | can a plug-in read held keybed notes?                       | **yes, polyphonic** — held-slot bitmap `0x500D288C` + note at `0x500D1278+slot*0x2C+0x0C`; 3 notes read at once in-game. See [PLUGIN-INPUT-INTERFACES.md](PLUGIN-INPUT-INTERFACES.md) |
| `awkbdmap.lua`                                | does the keybed gameplay mapping write the right hero vars? | **yes** — F5 left, C6 right, A5 down, Ab5/Bb5 up, C4/bass action; move+fire together, all match the oracle |
| `awmiditest.lua` + `gen_held_mid.py`          | do USB-MIDI-IN notes reach the game's keybed read?          | **yes** — a SMF on `-midiin1` shows C4/G4/E4 in the TG held mask; a controller drives the game like the keys |

Work RAM `0x50000000–0x503FFFFF` is definitely real and the firmware uses it heavily; the
library at `0x4C000000` runs from RAM, so the CPU fetches instructions from RAM — the VM can
be loaded from the SD card and executed. `0x44000000` is mapped as 16 MB of RAM by the MAME
driver; its real-hardware size is not yet confirmed, so a real-instrument build must verify it.
