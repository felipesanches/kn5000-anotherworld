# Another World on a stock KN7000, through the SD loader (no SP7001)

The same Another World VM as the SP7001 build ([README.md](README.md)), started a different way, the
one the owner's KN7000 runs all custom code with: **`KN7LOAD.CNV`**, the generic loader on his
existing write-protected floppy, loads an application, **`KN7APP.BIN`**, from the SD card. The game
is such an application. Nothing new goes on the floppy: the game and its files go on the SD card.

The loader is the ROM dumper's (technics-roms-disasm `kn7000/tools/cnv_romdump`), unchanged since
its release on 2026-10-19 (`KN7LOAD.CNV` SHA-1 `6b81f382fd29b9bc5a025854af0e20a194e68bec`). The
KN7000's DISK MENU > STYLE CONVERT runs it like any style converter. It finds the firmware's SD file
routines, reads `KN7APP.BIN` from the card's root folder, checks it and calls it on every converter
call. The game finds the rest of what it needs in the firmware by itself, so the same card serves
every program build we know: **893** (v1.3, the owner's), 935, **941** (v1.6) and 942.

> **Status (2026-10-20): runs in MAME on program 893 (`-bios v13`) and program 941 (`-bios v16`)
> through the owner's loader floppy, and leaves the instrument's stored data and the loader alone.**
> The game lives only in the work RAM STYLE CONVERT leaves to a converter, above the loader, loads
> each part's files from the SD card when the part starts, and refuses any write outside its own
> RAM. In the overlay emulator, which models IC23 (the battery-backed panel memories), a whole
> session ending with POWER OFF leaves IC23 and the user-memory pools byte-identical to a session
> that ran a do-nothing application instead, the next boot accepts them, and nothing but the loader
> wrote the loader's memory. Results and evidence: "How it was checked". **It has not run on a real
> KN7000 yet**: the first run's safeguards are under "Before the first run on the instrument".

Contents: [What goes where](#what-goes-where) · [Building](#building) · [Before the first run on the
instrument](#before-the-first-run-on-the-instrument) · [Playing it](#playing-it) · [How it works](#how-it-works) ·
[Memory](#memory) · [How it was checked](#how-it-was-checked) · [What MAME cannot
settle](#what-mame-cannot-settle) · [Limits](#limits) · [History](#history-the-awcnv-floppy-retired)

## What goes where

**The floppy: the one you already have.** It holds `KN7LOAD.CNV` alone, as released on 2026-10-19
(technics-roms-disasm `kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/`: `KN7LOAD.CNV` SHA-1
`6b81f382fd29b9bc5a025854af0e20a194e68bec`, the image `kn7load_floppy.img` SHA-1
`b7a67de602694fd2257d59ce4509ca154b0b3064`). Nothing is added to it or changed on it; keep its
write-protect tab at PROTECTED. Every MAME test below runs this very image.

**The SD card: everything in `build/sdcard/`, copied to the card's root folder.** `make sdcard`
writes exactly these 44 files there and nothing else (their sizes and SHA-1s: `build/sdcard.txt`):

| file(s)                              | bytes   | what                                                                        |
|--------------------------------------|---------|-----------------------------------------------------------------------------|
| `KN7APP.BIN`                         | 15,416  | the game: application header, platform layer, firmware search, VM, unpacker |
| `AWFONT.AW`                          | 768     | the 8x8 font (the KN5000 port's)                                            |
| `AWSTRIDX.AW`, `AWSTRDAT.AW`         | 6,144   | the string tables (the KN5000 port's)                                       |
| `AWR11.AW` ... `AWR91.AW` (40 files) | 563,528 | each resource the game draws or runs, as `MEMLIST.BIN` finds it in `BANKxx` |

All 44 names, as `ls build/sdcard` gives them:

    KN7APP.BIN   AWFONT.AW    AWSTRDAT.AW  AWSTRIDX.AW
    AWR11.AW     AWR12.AW     AWR13.AW     AWR14.AW     AWR15.AW     AWR16.AW     AWR17.AW     AWR18.AW
    AWR19.AW     AWR1A.AW     AWR1B.AW     AWR1C.AW     AWR1D.AW     AWR1E.AW     AWR1F.AW     AWR20.AW
    AWR21.AW     AWR22.AW     AWR23.AW     AWR24.AW     AWR25.AW     AWR26.AW     AWR27.AW     AWR28.AW
    AWR29.AW     AWR2A.AW     AWR2B.AW     AWR43.AW     AWR44.AW     AWR45.AW     AWR46.AW     AWR47.AW
    AWR48.AW     AWR49.AW     AWR53.AW     AWR7D.AW     AWR7E.AW     AWR7F.AW     AWR90.AW     AWR91.AW

585,856 bytes in all (`build/sdcard.txt`), well within the 126.5 MB free on the owner's card.
Each `AWRxx.AW` holds the exact bytes the original MS-DOS release's `MEMLIST.BIN` points at in its
`BANKxx` file, ByteKiller-packed or stored, for every palette, bytecode, polygon set and bitmap (the
sounds and music modules are left out: the port has no audio). They are made from your own copy of
the game by `make sdcard` (`tools/aw_extract.py --parts`), and the part tables inside `KN7APP.BIN`
are generated from the same `MEMLIST.BIN`, so the card must carry the files the same build wrote.
`KN7APP.BIN`'s SHA-1 for the build in this repository and the MS-DOS release in `../../MSDOS/`:
`b80b0205f2e6e52dcc876528115ff31680b090b7` with the launch-folder support (branch `launcher-folders`;
`b952c2aa839f249fb670390832eb936934e3e78f` before it, the binary the results below were taken with;
`build/sdcard.txt` lists it with the rest).

**With the program menu (2026-10-20): the game in a folder of its own, `AW\`.** The card's root
`KN7APP.BIN` can be the program menu (technics-roms-disasm `kn7000/tools/kn7menu`), which lists the
programs in the card's folders and starts the one picked as the loader would have. Its `make card`
puts this game in `AW\` (all 44 files of `build/sdcard/`, with a `MANIFEST.TXT` and an `ICON.BMP`)
beside the ROM dumper's passes 5 to 9, each in its folder, so nothing has to be swapped on the card any
more: copy the whole of kn7menu's `build/card/` to the card's root once. "Continue Next?" YES then
brings the menu back instead of a new game.

The game reads its files from the folder it was started from. The menu leaves a launch block at
`0x502E7F00` (the loader's contract, `kn7cnv.inc` `LB_*`) with the folder's 8.3 name; on its first call
the game copies the block's prefix, `AW\`, into `AW_PREFIX` (`cnv_main.s` `LaunchFolder`), and opens
every file as that prefix and its name (`AppPath`: `AW\AWR11.AW`), through the loader's `SV_OPEN` as
before. The loader zeroes the whole application area, the block included, before it loads anything,
so **the game still runs from the root without the menu**: the prefix stays empty and the names are the
old ones (below). Opening a file in a folder is the one thing this adds: the firmware's FAT library
walks the path, as it does for its own SD screens; from a converter that has run only in MAME so far
(probes/cnv/README.md, "Through the program menu").

**Without the menu: the root.** `KN7APP.BIN` and the game's files in the card's root, as before. The
card's root `KN7APP.BIN` is then the game; copy the one there first if it is something else. Only one
application is in the root at a time, since the loader always loads `C:\KN7APP.BIN`.

**Why the root was the first choice.** The loader empties the SD card's current folder around every
call, so names are looked up in `C:\`, and the root is where the loader itself reads `KN7APP.BIN` on the
owner's unit: the one way of reading the card that had already run on that instrument. The menu's
launch block now gives the game its folder without the optional `sdfmpath` service: a prefix in the
name needs nothing the loader may not have found.

## Building

As for the SD build (README.md: the MS-DOS release in `../../MSDOS/` and the KN5000 port's font and
string tables), with technics-roms-disasm beside this repository (`DISASM_REPO`: the assembler,
`sd_addfile.py`, and the loader's `tools/cnv_romdump`):

    make sdcard     # build/sdcard/ (also `make`): KN7APP.BIN and the 43 game files; build/sdcard.txt
    make app        # build/KN7APP.BIN alone: leafcheck, ic23_guard --loader ("clean"), assemble,
                    #   cnv_layout, then the loader's mkapp.py (header size and CRC-32)
    make kn7run     # the overlay emulator with the owner's loader floppy and a copy of the real
                    #   KN7000's SD card with build/sdcard/ added (BIOS=v13, the default: program 893;
                    #   BIOS=v16: 941); then DISK MENU, STYLE CONVERT, OK
    make fwfind     # tools/aw_find_fw.py: the game's firmware search over every program build

The build also checks that the loader it is laid out around is the owner's: `build/loader.ok`
compares `KN7LOAD.CNV` and its floppy image with the SHA-1s above. `tools/leafcheck.py` stops the
build when a routine entered with `call X, 0, 0` calls another before making a frame of its own; on
the MN10300 that nested call overwrites the return address.

## Before the first run on the instrument

It has run only in MAME. MAME runs the owner's own program 893 and the very floppy image above, but
not the real chip's timing nor the real card. So the first run is made with a record of IC23 (the
panel memories and settings) before and after, taken by the ROM dumper's SURVEY2 pass, which already
ran on the unit (technics-roms-disasm `kn7000/tools/cnv_romdump/releases/2026-10-20-survey2/`):

1. Back up the whole SD card on the computer as an image, as before the dumper's passes
   (`sudo dd if=/dev/sdX of=kn7000-sdcard-backup.img bs=1M status=progress`; check the device).
2. Copy the card's present `KN7APP.BIN` to the computer (above). Save the panel memories the usual
   way too.
3. **SURVEY2 before:** copy `sdcard-pass5-SURVEY2/KN7APP.BIN` (SHA-1 `24bdc35d...`) to the card's root
   as `KN7APP.BIN`; run it (DISK MENU > STYLE CONVERT > `KN7LOAD.CNV` > OK, as before); copy the
   files it writes (`R*.BIN`, `DUMPLIST.TXT`, 56 MB) into a folder `before/` on the computer and delete
   them from the card.
4. Copy everything in `build/sdcard/` to the card's root (this replaces `KN7APP.BIN` with the game's).
5. Play (next section): into at least one part switch, open HELP, quit with EXIT held and **NO**.
   Then switch the instrument off and on.
6. **SURVEY2 after:** put SURVEY2's `KN7APP.BIN` back in the root, run it, copy its files into
   `after/`.
7. Compare IC23, on the computer, from this repository's `kn7000/`:

       head -c 262144 before/R8400000.BIN > before-ic23.bin
       head -c 262144 after/R8400000.BIN > after-ic23.bin
       python3 -I probes/cnv/ic23_diff.py before-ic23.bin after-ic23.bin
       python3 -I probes/cnv/ic23_file.py after-ic23.bin

   The PANEL MEMORY store `0x824`-`0x30173` must show 0 differing bytes, and `ic23_file.py` must say
   `match=True` (the header checksum the firmware stamped at power-off). Bytes in the header (the live
   settings) may differ where a setting was changed: R1/R2 OCTAVE + / - and SUSTAIN keep doing their
   own job while the game runs (below). `cmp before/R5018000.BIN after/R5018000.BIN` compares the
   user-memory pools the same way; report any difference rather than judge it, since the firmware
   may change live data there between two power-ons.

If anything looks wrong, write the card image from step 1 back and restore the panel memories.

## Playing it

1. Switch on and wait for the main screen. Insert the floppy and the SD card.
2. **DISK MENU**, then **STYLE CONVERT** (left button 3). The list shows `KN7LOAD.CNV`. Press **OK**
   (right button 4).
3. The loader's screen flashes by. Then "LOADING ANOTHER WORLD" shows while a white bar along the
   bottom fills: six steps of the firmware search, then the font, the strings and the shared
   polygons. Then the splash starts. Whenever the game moves to another part, the picture stops for
   a moment while the bar fills again: the part's files are being read from the card.
4. The controls (the HELP screen shows them too, with the level codes):

   | game   | keybed (or MIDI IN 1) | panel                                  |
   |--------|-----------------------|----------------------------------------|
   | up     | Bb5 or B5             | R1/R2 OCTAVE +                         |
   | down   | A5                    | R1/R2 OCTAVE -                         |
   | left   | F5                    | PART SELECT LEFT                       |
   | right  | C6                    | PART SELECT RIGHT 1                    |
   | action | C4 or any key below   | SUSTAIN                                |
   | codes  |                       | OTHER PART & FR: the level code screen |
   | help   |                       | HELP; PAGE UP / PAGE DOWN turn pages   |
   | quit   |                       | hold EXIT for 1.5 s                    |

   **Prefer the keybed to the panel's up, down and action.** Those are R1/R2 OCTAVE + / - and SUSTAIN,
   and the firmware keeps doing their own job while the game runs: OCTAVE + / - shift the R1/R2
   octave, SUSTAIN switches sustain on and off. Those are ordinary setting changes, kept at power-off
   like any other (measured in MAME: `probes/cnv/awcnv_panelsettings.lua`); press them back afterwards
   if they matter. PART SELECT LEFT and RIGHT 1, HELP, OTHER PART & FR, PAGE DOWN and EXIT changed no
   setting in the tests.
5. **To quit, hold EXIT for 1.5 seconds.** The firmware shows a message box; press EXIT, and it asks
   **Continue Next?** **NO** (right button 4) returns to the main screen. **YES** (right button 3)
   makes the loader read `KN7APP.BIN` again and starts a new game from the beginning, firmware search
   included. A short EXIT press still closes the help screen.
6. If the firmware is one the game does not recognise, or a game file is missing or damaged, the
   screen says so ("AW: UNKNOWN FIRMWARE, STEP n", "AW: A GAME FILE IS MISSING OR BAD") and EXIT ends
   it; nothing has been written outside the game's RAM. Step 2 of the search is the loader's service
   table: "STEP 2" means the floppy's loader is not the one the game was built for. If `KN7APP.BIN`
   itself is missing or damaged, the loader says so on its own screen and ends after about 15 s.

## How it works

Traced in the firmware (technics-roms-disasm `kn7000/notes/style-converter.md`), in the loader's
source (`kn7000/tools/cnv_romdump/loader.s`, `kn7cnv.inc`) and measured in MAME (`probes/cnv/`):

- **STYLE CONVERT** zeroes `0x30000` bytes at `0x502B8000`, reads the chosen `.CNV` there whole, and
  calls its first byte (`calls (a0)`) on the firmware's **main task** (941 `0x48479929`, 893
  `0x48479766`). When the converter returns, the firmware reads a request from the mailbox at
  `0x5031BC00`, serves it, writes `0xFF` and calls again.
- **The loader** (`KN7LOAD.CNV`, 6,064 bytes) is that converter. On its first call it finds the
  firmware's SD file routines by searching the program flash (on the owner's 893 it found the fmm
  dispatch tables and called the SD backends directly), fills its **service table** at `0x502B9E00`,
  zeroes `0x502BA000`-`0x502E7FFF`, reads `C:\KN7APP.BIN` to `0x502BA000` in 16 KB pieces and checks its
  header (magic, loader ABI, link address, size, entry) and its CRC-32. From then on **every converter
  call goes through the loader to the application's entry**, with the SD card's current folder
  emptied around it (names are relative to `C:\`); the application sets the mailbox request itself.
  When it answers `0xFE` and "Continue Next?" is answered YES, the next call loads `KN7APP.BIN` afresh.
  The loader stays resident below `0x502BA000` all along: its code, its line buffer, its variables and
  the service table.
- **One step per call.** Every call of the game does one step and answers **request 5**, "show this
  text" (`LOADING ANOTHER WORLD`, then `HOLD EXIT TO QUIT`). The firmware keeps calling, about 20
  times a second, which parks the user interface on the converter: the firmware doesn't repaint the
  screen under the game and ignores EXIT, while the main task goes on decoding the panel and passing
  the keybed's notes to MIDI OUT, the two inputs the game reads (probe 2 in `probes/cnv/README.md`).
- **Finding the firmware** (`src/fwfind.s`, the first six calls). `KN7APP.BIN` carries no firmware
  address. It searches the program flash and the kernel library in RAM by code signatures, the way the
  loader does, and accepts a find only when it is unambiguous and cross-checked:

  | step | what                                          | found by                                                                                                                     |
  |------|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
  | 0    | the panel switch bitmaps                      | the panel decoder's two sites, which must agree (CPL = CPR + 0x30)                                                           |
  | 1    | the firmware's yield, the millisecond counter | the yield routine in the library and the tick handler, which must agree, and agree with the loader's own find of the counter |
  | 2    | SD open, read, close, the drive switch        | the loader's service table: magic `KN7S`, loader ABI 1, file access found                                                    |
  | 3    | `cre_tsk`, `sta_tsk`                          | the firmware's own "cre_tsk then sta_tsk(N, 0)" call sites: all must agree                                                   |
  | 4    | `exd_tsk`                                     | the firmware's tasks that end themselves: all must agree, a kernel stub                                                      |
  | 5    | the MIDI IN 1 and MIDI OUT 1 rings            | the library's per-port ring wrappers                                                                                         |

  `tools/aw_find_fw.py` runs the same searches (all but step 2) over every program image we have; the
  loader's `find_fw.py` runs the loader's:

  | what         | 893 (v1.3)   | 935 (v1.5)   | 941 (v1.6)   | 942 (SP7001) |
  |--------------|--------------|--------------|--------------|--------------|
  | cre_tsk      | `0x4C03D0B5` | `0x4C03D0C8` | `0x4C03D0C8` | `0x4C03D46B` |
  | sta_tsk      | `0x4C03D898` | `0x4C03D8AB` | `0x4C03D8AB` | `0x4C03DCD3` |
  | dly_tsk      | `0x4C03DD5C` | `0x4C03DD6F` | `0x4C03DD6F` | `0x4C03E295` |
  | exd_tsk      | `0x4C03D58E` | `0x4C03D5A1` | `0x4C03D5A1` | `0x4C03D944` |
  | kernel_ms    | `0x500C53F8` | `0x500C541C` | `0x500D3C58` | `0x500D3C68` |
  | panel_cpr    | `0x5006BE4C` | `0x5006BE50` | `0x5006BE50` | `0x5006BE60` |
  | panel_cpl    | `0x5006BE7C` | `0x5006BE80` | `0x5006BE80` | `0x5006BE90` |
  | midiin1_rxq  | `0x5001F020` | `0x5001F024` | `0x5001F050` | `0x5001F060` |
  | midiout1_txq | `0x5001F834` | `0x5001F838` | `0x5001F864` | `0x5001F874` |

  Step 2 takes the SD routines the loader found: on 893 its service table hands over the SD backends
  themselves (open `0x48564A88`, read `0x48564D70`, close `0x48564B4F`; the drive switch is the loader's
  no-op), the same `open` the loader reported on the owner's unit. The loader's `find_fw.py` finds
  the same kind of table in 935, 941 and 942.

  The 941 and 942 columns equal the addresses measured in MAME before; in MAME, the game's own search
  gives the 893 and 941 columns exactly (the session test prints them).
- **The global files** (the next four calls): the font, the string tables and the shared polygons
  (resource 0x11), one file per call. Then the game starts a task of its own (`cre_tsk` / `sta_tsk`,
  ids 10 then 9, priority 3) that runs the VM.
- **Parts on demand.** Like the original engine, the game holds one part at a time. At a part switch
  the game task asks for the new part (`EnsurePart`) and yields until it is there. Each converter call
  then reads one of the part's files from the card's root into the part area, with the loader's
  routines (the drive switch to the SD card and back around it, a no-op where the loader calls the SD
  backends directly) and in 16 KB pieces, as the loader reads `KN7APP.BIN`, and unpacks it in place,
  as the original engine does (`tools/aw_extract.py` checks at build time that every such resource
  unpacks right in place). The bitmaps a part's bytecode LOADs stay packed until LOAD draws one; they
  are unpacked into a buffer of their own (`BitmapData`). A part's loads start only once no panel
  button is down (or after about 5 s), so that a button's release never arrives while the main task
  is busy in a file read; a file that fails to load is tried again on the next call, up to three
  times, before the game stops and says so.
- **Quitting.** The entry watches EXIT. Once it has been held for 1.5 s, the game task ends itself at
  its next yield (`exd_tsk`), and the next call answers **0xFE**, which ends the conversion; the
  loader notes it. The firmware shows its message box, then "Continue Next?". YES makes the loader
  read `KN7APP.BIN` again, which starts a new game from the firmware search on. NO goes back to the
  main screen.

## Memory

Everything the game writes is in **`0x502BA000`-`0x50379FFF`**: the work RAM STYLE CONVERT leaves to a
converter, less the loader's resident area below it and the mailbox page. That range was measured
untouched by the firmware on program 893 in MAME through boot, idle, DISK MENU and a converter run
(research-scratch `aw-memory-plan/taps893_ranges.out`), and the acceptance tests below measure it
again while the game runs through the loader and reads the SD card. `src/platformcnv.inc` holds the
map, laid out around the loader's contract `kn7cnv.inc` (which the game includes);
`tools/cnv_layout.py` prints and checks it at every build:

| range                     | what                                                                                  |
|---------------------------|---------------------------------------------------------------------------------------|
| `0x502B8000`-`0x502B97AF` | KN7LOAD.CNV: the loader's image (6,064 bytes, SHA-1 6b81f382...)                      |
| `0x502B9C00`-`0x502B9C7F` | LV_STR: the loader's line buffer                                                      |
| `0x502B9D00`-`0x502B9DFF` | LOADER_VARS: the loader's variables and the saved SD folder                           |
| `0x502B9E00`-`0x502B9E6B` | SVC: the loader's service table (the game reads it)                                   |
| `0x502BA000`-`0x502BDFFF` | KN7APP.BIN: header, code and tables (15,416 bytes, to 0x502BDC38)                     |
| `0x502BE000`-`0x502BE2FF` | AW_FONT: the 8x8 font, from AWFONT.AW                                                 |
| `0x502BE300`-`0x502BEAFF` | AW_STRIDX: string index, from AWSTRIDX.AW                                             |
| `0x502BEB00`-`0x502BFAFF` | AW_STRDAT: strings, from AWSTRDAT.AW                                                  |
| `0x502C0000`-`0x502C03FF` | CNV_VARS: the entry's and the part loader's variables                                 |
| `0x502C0400`-`0x502C04FF` | FW_VARS: what fwfind.s found, and its scratch                                         |
| `0x502C0800`-`0x502C083F` | AW_PATHS: the game's folder, from the menu's launch block                             |
| `0x502C1000`-`0x502C11FF` | VM_POLY_BASE: rasterizer scratch                                                      |
| `0x502C2000`-`0x502C30FF` | VM_INTERP_BASE: VM variables, threads, call stack                                     |
| `0x502C4000`-`0x502C53FF` | VM_MISC_BASE: input, help, guard, note trackers                                       |
| `0x502C6000`-`0x502C6247` | RES_TAB: where each resource is now                                                   |
| `0x502C8000`-`0x502D79FF` | HELP_BUF: help pages, stop screen, bitmap unpacking                                   |
| `0x502E7F00`-`0x502E7FFF` | LB_ADDR: the program menu's launch block (kn7cnv.inc): read, never ours               |
| `0x502E8000`-`0x502EE3FF` | VIDEO2_AT: the shared polygons (0x11)                                                 |
| `0x502EE400`-`0x5031AFFF` | PART_AREA: the current part's files                                                   |
| `0x5031B000`-`0x5031BFFF` | the firmware's mailbox page (0x5031BC00..): never written by the game but the request |
| `0x50320000`-`0x5032F9FF` | PAGE_BITMAP_0: VM page 0                                                              |
| `0x50330000`-`0x5033F9FF` | PAGE_BITMAP_1: VM page 1                                                              |
| `0x50340000`-`0x5034F9FF` | PAGE_BITMAP_2: VM page 2                                                              |
| `0x50350000`-`0x5035F9FF` | PAGE_BITMAP_3: VM page 3                                                              |

What the game must never touch, and how that is checked:

- **IC23**, the 256 KB battery-backed SRAM with the panel settings and the 104 PANEL MEMORY records,
  is chip select CS1: `0x44000000`-`0x47FFFFFF`, and its uncached view `0x84000000`-`0x87FFFFFF`. It
  repeats every 256 KB through the whole chip select (A1-A17 only; confirmed on the owner's unit on
  2026-10-20), so any address there is the panel memories. The firmware writes it at any time and
  stamps a checksum over its header only at power-off: damage done during a session would be stamped
  valid (kn7000_mame `notes/ic23-nvram-2026-10-20`).
- **The user-memory pools**, `0x50180000`-`0x50297FFF` (and `0x90180000`-...): COMPOSER styles, pads
  and the other user data the firmware never clears and keeps across power-off.
- **The loader**, `0x502B8000`-`0x502B9FFF` (and `0x902B8000`-...): its code runs on every converter
  call, and its variables and service table must survive the game. The game only reads the service
  table.
- **Boot data** from `0x5037A000`, and 941's zlib arena `0x503B1000`-`0x503FFFFF`.

Three checks keep the game inside its range:

1. **At build time**, `tools/ic23_guard.py --loader` assembles the game with the toolchain's own
   assembler and records every value any expression produces (operands, data, constants, labels):
   none may lie in CS1 or the pools, and none in the loader's area but loads `mov (SVC + SV_x), reg`
   from its service table (9 of them: the table check of step 1 and 2). `make app` stops unless it
   says "clean"; `probes/cnv/guard_loader_selftest.s` proves the guard finds a store, an address taken,
   a byte load, the loader's variables or code, an address as data and an IC23 address.
   `tools/cnv_layout.py` checks the map above: every region inside `0x502BA000`-`0x50379FFF`, off the
   mailbox page and the loader's area, no overlaps, every `vm.inc` field inside its block, the image
   starting at `APP_BASE` with its header and ending below the font, `AW_LO` equal to the loader's
   `APP_BASE`, and the loader's own image (the owner's `KN7LOAD.CNV`), line buffer, variables and
   service table below `APP_BASE`.
2. **At run time**, every load destination is checked before the file is read (`GuardRange`: inside
   `0x502BA000`-`0x50379FFF`, clear of the mailbox page), every page the VM draws or copies on must be
   one of the four pages (`GuardPage`), and the VM's call stack must stay in its 512 bytes. A refused
   write is skipped, and the game stops at once with "ANOTHER WORLD STOPPED", the reason and the
   address on the LCD; EXIT then ends it as usual. The rasterizer already clips every span and point
   to the page; variables and threads are indexed with masks.
3. **In MAME**, write taps over CS1, the pools, the loader's area and the game's own RAM, through whole
   sessions on 893 and 941 (below).

The task's stack is the kernel's: `cre_tsk` allocates it and `exd_tsk` frees it.

## How it was checked

All in the overlay emulator (`kn7000-emulator`, binary md5 `2a8e2fce...`), which models IC23 as 256 KB
of NVRAM repeating through CS1 and runs the firmware's power-down from its POWER OFF input. `-bios v13`
is the owner's program 893 / table 80, from the owner's own dumps; `-bios v16` is program 941. Every
run boots with the owner's loader floppy image (`b7a67de6...`) and a copy of the real KN7000's SD card
with `build/sdcard/` added to its root. The commands, the scripts and what each check reads are in
`probes/cnv/README.md`; every number below comes from `probes/cnv/run_cnv_tests.sh` (`KN7APP.BIN`
`b952c2aa...`).

| check        | question                                                                      | 893, blank IC23           | 893, the owner's IC23     | 941, blank IC23           |
|--------------|-------------------------------------------------------------------------------|---------------------------|---------------------------|---------------------------|
| (a) guard    | does the game name any address in CS1, the pools or the loader? map in range? | clean; map ok             | (same build)              | (same build)              |
| (b) session  | a whole session (16 checks, below)                                            | 16 of 16                  | 16 of 16                  | 16 of 16                  |
| (c) ic23w    | any write into CS1 from the converter area, or past IC23's 256 KB?            | none, none                | none, none                | none, none                |
| (d) same     | IC23 after the game and POWER OFF = IC23 after a control run and POWER OFF?   | identical, checksum valid | identical, checksum valid | identical, checksum valid |
| (d) accepted | does the next boot find it valid, PANEL MEMORY store as it was?               | valid, store kept         | valid, store kept         | valid, store kept         |
| (e) pools    | `0x50180000`-`0x50297FFF` identical at POWER OFF, and no write there?         | identical, none           | identical, none           | identical, none           |
| (f) area     | any foreign write into the game's RAM while it runs?                          | none                      | none                      | none                      |
| (g) loader   | any write into the loader's area but the loader's own?                        | none                      | none                      | none                      |

The session's 16 checks: the loader ran the game, having found all seven of its services (`0x7F`),
and the game's firmware search found everything (on 893: from the loader's table SD open
`0x48564A88`, read `0x48564D70`, close `0x48564B4F`, the drive switch the loader's no-op `0x502B85BE`;
`cre_tsk` `0x4C03D0B5`, `sta_tsk` `0x4C03D898`, the yield `0x4C03DD5C`, `exd_tsk` `0x4C03D58E`, ms
counter `0x500C53F8`, panel `0x5006BE4C`, MIDI rings `0x5001F020` / `0x5001F834`: the `aw_find_fw.py`
column); the splash, the intro, a key skipping it to the lake; the panel's five game buttons and the
keybed's action; HELP (the VM pauses, PAGE DOWN turns the page, EXIT returns); the level codes HTDC
(the prison) and CLLD (the city, the largest part); quitting, "Continue Next?" YES (the loader reads
`KN7APP.BIN` again: a new game), quitting again and NO; no guard refusal and no load error; and each
part's resources, every time one became resident (8 times, 46 resources), byte for byte the
reference unpack. No panel press was lost and no file read failed in any of the three.

How long a part's files take to load in MAME (emulated time, from the sessions' `LD_MS`; one file
per converter call, about 20 calls a second; a real card's speed is not known), from the SD card
through the loader, and, for comparison, from the floppy with the retired `AW.CNV` (893):

| what                                     | files | bytes read | SD card: 893 blank / owner, 941 | floppy (AW.CNV) |
|------------------------------------------|-------|------------|---------------------------------|-----------------|
| font, string tables, shared polygons     | 4     | 25,776     | 831 ms (the intro run)          | 5.2 s           |
| the splash part (0x3E80, with 4 bitmaps) | 7     | 30,060     | 584 / 580, 584 ms               | 6.3-6.5 s       |
| the intro (0x3E81)                       | 3     | 64,176     | 836 / 827, 920 ms               | 5.6 s           |
| the lake (0x3E82)                        | 3     | 60,108     | 872 / 880, 884 ms               | 4.7 s           |
| the prison (0x3E83, with 2 bitmaps)      | 5     | 93,464     | 1,264 / 1,264, 1,264 ms         | 9.8 s           |
| the city (0x3E84, with 4 bitmaps)        | 7     | 129,892    | 1,624 / 1,624, 1,628 ms         | 13.2 s          |

- **The writes.** In the game runs, the firmware's own IC23 writes are the boot's and a few from its
  library (893 `0x4C01F310`-`0x4C01F39C`, 941 `0x4C01F325`-`0x4C01F3B1`: the settings OCTAVE and
  SUSTAIN change); none from the converter area. The game's RAM saw only the firmware zeroing the
  converter area when it loaded the loader (893 pc `0x48478E7D`, 941 `0x48479040`), the loader zeroing
  the application area (`0x502B8187`, at the start and after YES), and the SD reads of `KN7APP.BIN`
  and of the files the game asked for (893 `0x4854BA0D` and `0x4C003031`, 941 `0x4854C0E0` and
  `0x4C003046`), each inside its destination. The loader's area saw the firmware load `KN7LOAD.CNV`
  and then only the loader's own code, in the control runs as in the game runs. The stack pointer seen
  while the game's code runs (the game task's, and the main task's during converter calls) stays in
  `0x5038DD2C`-`0x503AD844`, the kernel's, outside the game's range. In the game runs nothing touched
  the pools after boot. (In the control runs, after NO, the firmware's own code (893 `0x48455812` and
  a copy at `0x4C003031`, 941 `0x484558DB` and `0x4C003046`) rewrote part of `0x501A5000`-`0x501A6FFF`;
  the pools still ended byte-identical to the game runs'. With `AW.CNV` as the control, it did not.)
- **The saved IC23s** are the same as with `AW.CNV` (SHA-1 prefixes `eb26c67b...` for 893 blank,
  `14f82423...` for the owner's, `bc2305dd...` for 941 blank): the route to the game changes nothing
  that is kept.
- **The intro, frame by frame**, on 893 through the loader: `probes/cnv/awcnv_cksum.lua` captures the
  displayed page at every VM tick; compared with rustyworld as for the SP7001 build
  (`probes/CHECKSUM-COMPARISON.md`): "captured 2613 frames (last tick 2612); part loads 3, load errors
  0, guard 0", and 2612 of 2612 frames identical to the reference, as with `AW.CNV`. The font, the
  strings and the shared polygons loaded in 831 ms there.
- **The firmware search on the instrument's own data.** `tools/aw_find_fw.py` finds the same 893
  addresses in the owner's program dump, and, with `--real-lib893`, in the library RAM the ROM
  dumper read from the instrument (equal to the boot's copy of the flash over its whole length).
- **The panel buttons.** While the game runs, the firmware still acts on R1/R2 OCTAVE + / - (the octave
  setting) and SUSTAIN (sustain on/off), the game's UP, DOWN and FIRE (`probes/cnv/awcnv_panelsettings.lua`,
  with `AW.CNV`; the session's `settings` check sees the same through the loader: FIRE changes header
  byte `0x03A`, UP and DOWN `0x6EA`); PART SELECT LEFT, RIGHT 1, RIGHT 2 and DISPLAY HOLD change
  nothing. The session therefore presses those in pairs that cancel, and checks that the settings end
  as they began.
- **What the tests found and fixed** (with `AW.CNV`, none of it a write outside the game's RAM, all of
  the fixes in `KN7APP.BIN` too): `probes/cnv/README.md`. The loader route needed no fix.

## What MAME cannot settle

- **Everything rests on the emulation of program 893.** The `-bios v13` program and table images are
  the owner's own dumps (cnv_romdump passes 1 and 2, checked byte for byte), and the kernel library
  the search reads in RAM is the boot's copy of that flash, so the firmware search's results should
  carry over unchanged; `tools/aw_find_fw.py` gives the same answers from the dump files alone, and
  with `--real-lib893` from the library RAM the SURVEY2 pass read on the instrument.
- **What has already run on the owner's unit:** the loader itself, unchanged (its search, its SD
  routines, reading `KN7APP.BIN` from the root in 16 KB pieces, calling an application on every
  converter call, request 1, ending the conversion with `0xFE`), in eight passes of the dumper.
- **What has not:** answering request 5 (the dumper parks with request 1), starting and ending a task
  of our own (`cre_tsk`, `sta_tsk`, `exd_tsk`), the firmware's yield routine, and reading more than
  one file per run from the card (one file per converter call, up to 55,476 bytes, the intro's
  polygons). MAME runs the same firmware code for all of them, but not the real chip's timing nor the
  real card's.
- **The card's speed.** How long a part's files take on the real card is unknown; in MAME see "How it
  was checked". Whether a panel event that comes in while the main task is in a file read is kept: in
  MAME one release was lost that way with the floppy, which is why loads wait for the panel to be let
  go.
- **The panel while parked.** Request 5 keeps the firmware on the converter's text screen, and the
  panel's switch bitmaps keep being updated. In MAME the firmware also acts on R1/R2 OCTAVE + / - and
  SUSTAIN there (above); other buttons may do the same on the instrument, which a changed setting
  after a session would show.
- **IC23, the pools and the loader are only measured in MAME.** The game names no address there and
  refuses any computed one outside its RAM, but the first run should still check the instrument's
  memory: "Before the first run on the instrument".

## Limits

- **No sound,** as in the SP7001 build.
- **Load pauses** at each part switch, up to 130 KB of files (the city).
- **One card per build.** `KN7APP.BIN`'s part tables name the files of the build that wrote them:
  copy the whole of `build/sdcard/` each time, never `KN7APP.BIN` alone.
- **YES restarts from scratch.** The loader reloads `KN7APP.BIN` for "Continue Next?" YES, so a new
  game repeats the firmware search and the global files before the splash.

## History: the AW.CNV floppy (retired)

Until 2026-10-20 the game was its own style converter, `AW.CNV`, on a floppy of its own with the 43
game files beside it, loaded at `0x502B8000` by STYLE CONVERT directly, with the floppy's file
routines found by its own search (`OpenHere`, `fmmread`, `fmmclose`). It passed the same acceptance
tests in MAME (`probes/cnv/README.md`), but it never went to the instrument: all custom code on the
owner's unit is started by `KN7LOAD.CNV` from the one write-protected floppy, and no other `.CNV` goes
on a floppy for it. It is retired, not kept as a MAME-only target: the loader route runs in MAME just
as well, and a second route would need its own guards and tests. Its last state is commit `dbc7a2c`
(`make floppy`, `src/cnv_main.s` linked at `0x502B8000`, `tools/make_cnv_floppy.py`).
