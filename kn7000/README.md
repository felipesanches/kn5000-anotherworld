# Another World on the Technics SX-KN7000

A port of the Another World bytecode VM to the **Technics SX-KN7000** arranger
keyboard, as a sibling of the KN5000 version in this repository. Where the KN5000
build is a Toshiba TLCS-900 extension-board ROM, the KN7000 runs a Panasonic
MN10300 and has no expansion slot — so the game rides along with the keyboard's
**SP7001 "SD PLUG-iN"** firmware and loads from the SD card.

> **Status (2026-10-17): the VM runs the whole game's data; intro and lake verified.**
> The bytecode VM is pixel-identical to the reference (rustyworld) through the intro
> and the lake, and the lake is playable from the keybed, MIDI IN 1 and the panel.
> All 146 game resources are on the card and resident in RAM, and every part opens
> identically to the reference. Sound and music are not implemented yet. The plan for
> the rest of the game: [FULL-GAME-PLAN.md](FULL-GAME-PLAN.md).

> **MAME ONLY. Do not put this build on a real KN7000.** It keeps the game in the `0x44000000`
> window. MAME's upstream driver maps 16 MB of plain RAM there as a placeholder, but on a real
> KN7000 that window is chip select CS1, which is IC23 alone: the 256 KB battery-backed SRAM holding
> the panel settings and the 104 PANEL MEMORY records, repeating every 256 KB through the whole
> window (confirmed on the owner's unit on 2026-10-20). Every game write would land on the stored
> settings, and the firmware's POWER OFF would stamp the damage valid: in the overlay emulator,
> which models IC23, one 60 s session overwrote 1,945 of the 1,956 header bytes and 65,676 bytes of
> panel memories (kn7000_mame `notes/ic23-nvram-2026-10-20`). Its loader also stages the game in
> `0x50200000`, inside the user-memory pool where the firmware keeps the TPAD pads.
>
> It cannot simply move to the safe RAM the STYLE CONVERT build uses: that holds about 0.8 MB, the
> game needs 1.7 MB resident (0.5 MB without audio), and this build cannot load part by part, as the
> plug-in's file API works only during the plug-in load (below). So it stays MAME-only, and three
> things keep it there: `tools/ic23_guard.py` runs on it at every build and must find its 670
> references into IC23 and the pools (were it ever to call this build clean, the check itself would be
> broken); the Makefile refuses to build it without `MAME_ONLY=1`; and at run time the hook reads
> IC23 through `0x84000000` and starts nothing when its first KB repeats 256 KB further on, as it does
> on an instrument (`IsIC23` in `src/main.s`; in upstream MAME the placeholder does not repeat).
>
> **For a real instrument:** the same VM runs on a stock KN7000 (any program build: 893, 935, 941,
> 942) as `KN7APP.BIN`, an application of the SD loader `KN7LOAD.CNV` that STYLE CONVERT runs from
> the owner's floppy, with the game's files on the SD card and everything in the converter's own
> work RAM: [README-CNV.md](README-CNV.md).

## How it runs on the KN7000

The KN7000's firmware owns the LCD and is known to run outside code in two ways: the
SP7001 plug-in, which loads `TECHNICS\DATA\BASEEXT.XAP` from the SD card into RAM
and runs it, and the style converters (`.CNV`) that DISK MENU > STYLE CONVERT runs from a
floppy (the instrument build: [README-CNV.md](README-CNV.md)). This build uses the first (see [SP7001 Firmware](../../kn5000-docs/kn7000-sp7001-firmware.md)).
The port **rides along** with that plug-in rather than replacing it:

1. `technics-roms-disasm/kn7000/tools/xap_addon.py` places our module in `BASEEXT.XAP`'s
   unused tail and redirects the plug-in's entry (`XapEntry`) to our **hook**.
2. The hook runs on the firmware's loading task. It loads the game from the SD
   card (the file API works in this context) and starts a **task** of our own,
   then lets `XapEntry` continue so the plug-in still initialises normally.
3. Because the plug-in finishes, the firmware reaches its static SP7001 screen.
   On a static screen the firmware repaints only what changes, so our task's
   **full-frame blit to `0x9CE00000`** (640×240 RGB565) persists — we own the LCD.
4. Another World is 320×200; the VM renders into an 8-bit-indexed page in RAM, and
   the task blits it centred into the frame through a 16-colour palette.

Replacing `BASEEXT.XAP` outright does **not** work: the firmware then sits on its
"Initializing PLUG-iN System" screen (our stub plug-in never completes init) and
full-clears the frame every repaint, so a blit cannot win. Riding along avoids that.

## What is proven (and how)

Each fact was established in MAME; the read-only probes are in `probes/`.

| fact                                        | probe / result                                                                             |
|---------------------------------------------|--------------------------------------------------------------------------------------------|
| our code runs as a ride-along module        | the clock demo and this port boot and draw                                                 |
| a full-frame blit to `0x9CE00000` persists  | `probes/` full-frame fill covers the whole LCD                                             |
| the firmware heap is too small for the game | `heap_probe.lua`: ~15–31 KB free → load game data into a large RAM window                  |
| writable RAM windows (in MAME)              | `ram_probe.lua`: `0x44000000`, `0x4C000000`, work RAM `0x50000000–0x503FFFFF`, LCD `0x9C…` |
| **reading a file from the SD card**         | `sdread.lua`: `fopen`/`fread`/`fclose` return the exact file bytes                         |

### The SD file API (the key enabler)

The firmware exports a C-like file API to plug-ins; it is reachable both by name
(program 942: `fopen_api` `0x48585E2A`, `fread_api` `0x48585E50`, `fclose_api`
`0x48585E65`) and as methods on the framework object. Three things make it work:

- **Call it from the hook, not from our task.** On the firmware's loading task it
  works; from a task we create with `cre_tsk_X` it faults (no per-task C-runtime).
- **Single backslashes in the path.** `fopen_api("C:\TECHNICS\DATA\FILE.EXT",
  "rb")`. (Our assembler's `.asciz` does not process escapes, so write one `\`.)
- **Read into work RAM, not the `0x44000000` window.** The SD read cannot target
  the external-memory window; `fread_api(buf, FILE, 1, count)` with `buf` in
  `0x50000000–0x503FFFFF` returns the bytes. The loader then copies to `0x44…`
  (MAME's placeholder RAM; IC23 on an instrument, see the top).

## Building

Needs a checkout of `technics-roms-disasm` beside this repo (its `kn7000/` holds the
MN10300 assembler and the XAP/SD tools) and its extracted vendor `BASEEXT.XAP`:

    make -C ../../technics-roms-disasm/kn7000 baserom/sp7001_baseext.xap
    make MAME_ONLY=1 sp7001   # build/BASEEXT.XAP  (the vendor plug-in with our module added)
    make MAME_ONLY=1 card     # build/another_sd.img  (a copy of an SP7001 SD image with it)
    make MAME_ONLY=1 run      # boot MAME; press the orange SD CARD button to load it

A plain `make` builds the instrument build's SD card folder instead, `build/sdcard/` (README-CNV.md).

The vendor plug-in is not redistributed: the build adds our module to your own copy.

## Layout

| path               | what it is                                                     |
|--------------------|----------------------------------------------------------------|
| `src/platform.inc` | KN7000/SP7001 addresses and constants, with how each was found |
| `src/main.s`       | the platform layer: hook, task, load, the VM's platform hooks  |
| `probes/`          | read-only MAME probes that established the facts above         |

The instrument build (`KN7APP.BIN`: `src/cnv_main.s`, `src/fwfind.s`, `src/platformcnv.inc`) is
described in [README-CNV.md](README-CNV.md).

## Credits

Derived from the KN5000 Another World port (TLCS-900), itself derived from Fabien
Sanglard's Another World bytecode interpreter. Game data must be extracted from an
original copy of the game.
