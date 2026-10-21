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
> wrote the loader's memory. Results and evidence: "How it was checked". **It ran on the owner's KN7000
> on 2026-10-20, very slowly**; the build here blits only what changed, paints the border once and
> measures its own speed on the instrument ("Speed").

Contents: [What goes where](#what-goes-where) · [Building](#building) · [Before the first run on the
instrument](#before-the-first-run-on-the-instrument) · [Playing it](#playing-it) · [How it works](#how-it-works) ·
[Sound](#sound) · [Speed](#speed) · [Memory](#memory) · [How it was checked](#how-it-was-checked) · [What MAME cannot
settle](#what-mame-cannot-settle) · [Limits](#limits) · [History](#history-the-awcnv-floppy-retired)

## What goes where

**The floppy: the one you already have.** It holds `KN7LOAD.CNV` alone, as released on 2026-10-19
(technics-roms-disasm `kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/`: `KN7LOAD.CNV` SHA-1
`6b81f382fd29b9bc5a025854af0e20a194e68bec`, the image `kn7load_floppy.img` SHA-1
`b7a67de602694fd2257d59ce4509ca154b0b3064`). Nothing is added to it or changed on it; keep its
write-protect tab at PROTECTED. Every MAME test below runs this very image.

**The SD card: everything in `build/sdcard/`, copied to the card's root folder.** `make sdcard`
writes exactly these 141 files there and nothing else (their sizes and SHA-1s: `build/sdcard.txt`):

| file(s)                              | bytes   | what                                                                                                         |
|--------------------------------------|---------|--------------------------------------------------------------------------------------------------------------|
| `KN7APP.BIN`                         | 31,756  | the game: application header, platform layer, firmware search, VM, unpacker, speed measurement, sound        |
| `AWFONT.AW`                          | 768     | the 8x8 font (the KN5000 port's)                                                                             |
| `AWSTRIDX.AW`, `AWSTRDAT.AW`         | 6,144   | the string tables (the KN5000 port's)                                                                        |
| `AWSND.AW`                           | 584     | each sound's KN7000 program, note and length, for the tone generator mode ("Sound"; `tools/aw_sound_map.py`) |
| `AWBANK.AW`                          | 2,936   | where each sound of the DSP's sample bank goes in its SDRAM, and the bank's id ("Sound"; `aw_extract.py`)    |
| `AWR07.AW` ... `AWR91.AW` (42 files) | 566,944 | each resource the game draws, runs or plays as music, as `MEMLIST.BIN` finds it in `BANKxx`                  |
| `AWR01.AW` ... `AWR8E.AW` (93 files) | 574,084 | each sound the game plays, as `MEMLIST.BIN` finds it in `BANKxx`: the DSP's sample bank                      |

1,183,216 bytes in all (`build/sdcard.txt` lists every name, size and SHA-1), well within the 126.5 MB free on
the owner's card.
Each `AWRxx.AW` holds the exact bytes the original MS-DOS release's `MEMLIST.BIN` points at in its
`BANKxx` file, ByteKiller-packed or stored, for every palette, bytecode, polygon set and bitmap, the
two music modules (`AWR07.AW` the intro's, `AWR8A.AW` the final part's) and, since the DSP build, the
93 sounds the game plays (its sample bank: "Sound"). They are made from your own copy of the game by
`make sdcard` (`tools/aw_extract.py --parts`), and the part tables inside `KN7APP.BIN` and `AWBANK.AW`
are generated from the same `MEMLIST.BIN`, so the card must carry the files the same build wrote.
`KN7APP.BIN`'s SHA-1 for the build in this repository and the MS-DOS release in `../../MSDOS/`:
`a2fbbaa6c660020757b543878fc2a6cdc46ba3f2` (the DSP sound build; `build/sdcard.txt` lists it with the rest; the build before it, the
first sound build, tone generator only, was `97fbd9e6...`, which Felipe's KN7000 played).

**With the program menu (2026-10-20): the game in a folder of its own, `AW\`.** The card's root
`KN7APP.BIN` can be the program menu (technics-roms-disasm `kn7000/tools/kn7menu`), which lists the
programs in the card's folders and starts the one picked as the loader would have. Its `make card`
puts this game in `AW\` (all 47 files of `build/sdcard/`, with a `MANIFEST.TXT` and an `ICON.BMP`)
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

    make sdcard     # build/sdcard/ (also `make`): KN7APP.BIN and the 46 game files; build/sdcard.txt
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

These were the safeguards for the first run on the owner's unit (2026-10-20; it ran). MAME runs the
owner's own program 893 and the very floppy image above, but not the real chip's timing nor the real
card. The speed build adds one thing the earlier one never did: at each quit it writes a new
`AWPERFn.TXT` to the card's root, so back the card up first as in step 1. So the first run is made with a record of IC23 (the
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
   bottom fills: eight steps of the firmware search, then the font, the strings, the sound tables and
   the shared polygons. Then, the first time after the instrument was switched on, "LOADING ANOTHER
   WORLD: SOUNDS" and the bar again, slowly: the game's samples going into the effects DSP ("Sound"; in
   MAME 26 s). Then the splash starts. Whenever the game moves to another part, the picture stops for
   a moment while the bar fills again: the part's files are being read from the card.
4. The controls (the HELP screen shows them too, with the level codes):

   | game   | keybed (or MIDI IN 1, channels 1-3) | panel                                   |
   |--------|-------------------------------------|-----------------------------------------|
   | up     | Bb5 or B5                           | R1/R2 OCTAVE +                          |
   | down   | A5                                  | R1/R2 OCTAVE -                          |
   | left   | F5                                  | PART SELECT LEFT                        |
   | right  | C6                                  | PART SELECT RIGHT 1                     |
   | action | C4 or any key below                 | SUSTAIN                                 |
   | codes  |                                     | OTHER PART & FR: the level code screen  |
   | help   |                                     | HELP; PAGE UP / PAGE DOWN turn pages    |
   | sound  |                                     | PART SELECT RIGHT 2: DSP / TG / off     |
   | speed  |                                     | PAGE UP: the overlay on / off ("Speed") |
   | blit   |                                     | PAGE DOWN: the new blit / the old one   |
   | quit   |                                     | hold EXIT for 1.5 s                     |

   **Prefer the keybed to the panel's up, down and action.** Those are R1/R2 OCTAVE + / - and SUSTAIN,
   and the firmware keeps doing their own job while the game runs: OCTAVE + / - shift the R1/R2
   octave, SUSTAIN switches sustain on and off. Those are ordinary setting changes, kept at power-off
   like any other (measured in MAME: `probes/cnv/awcnv_panelsettings.lua`); press them back afterwards
   if they matter. PART SELECT LEFT and RIGHT 1, HELP, OTHER PART & FR, PAGE UP, PAGE DOWN and EXIT
   changed no setting in the tests, and the firmware drew nothing on the LCD for them. **Do not press
   DISPLAY HOLD**: once in MAME it made the firmware repaint its screen and stop calling the game for
   good, so that EXIT could no longer end it (`probes/cnv/README.md`, "Speed").
5. **To quit, hold EXIT for 1.5 seconds.** The game writes its speed figures to a new file in the
   card's root (`AWPERF0.TXT`, then `AWPERF1.TXT`, ...: "Speed"). The firmware shows a message box; press EXIT, and it asks
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
- **Finding the firmware** (`src/fwfind.s`, the first eight calls). `KN7APP.BIN` carries no firmware
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
  | 6, 7 | the effects DSP's host-port routines          | DSPTONE's search, one signature a call (`src/dsp.s` DspFind); not found: the game goes on with the tone generator ("Sound")  |

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
- **The global files** (the next six calls): the font, the string tables, the two sound tables
  (`AWSND.AW`, `AWBANK.AW`) and the shared polygons (resource 0x11), one file per call. Then, when the
  effects DSP's routines were found, its mixer and the sample bank ("Sound"). Then the game starts a task
  of its own (`cre_tsk` / `sta_tsk`, ids 10 then 9, priority 3) that runs the VM.
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

## Sound

The sound has three modes, and **PART SELECT RIGHT 2** cycles through them: **DSP samples** (the game's own
sounds, played by the instrument's effects DSP), **tone generator** (the KN7000's own voices over MIDI, the first
iteration) and **off**: DSP, then tone generator, then off, then DSP again (off goes to the tone generator when
the DSP cannot be used). The first page of the HELP screen shows the mode in its last line: "NOW: DSP SAMPLES",
"NOW: TONE GENERATOR" or "NOW: OFF", with "NO DSP n" after it when the DSP was given up (n below). The game
starts in the DSP mode when it could set the DSP up, else in the tone generator's. In every mode the module
player runs and writes its sync marks into var 0xF4 as before, so the intro keeps its timing.

### The DSP mode (iteration 2, 2026-10-21): the game's own samples

**On the instrument (2026-10-21, Felipe's report, `KN7APP.BIN` `a2fbbaa6...`, program 893):** the sounds play
perfectly, with REVERB on and with REVERB off (on is a little louder); the game's level is close to a piano note's;
nothing garbled or stuck; no "NO DSP" shown; reverb and chorus both came back after quitting. The bank's first
load felt slow (26 s in MAME; not timed on the unit).

The KN7000's tone generators play only their wave ROMs, so sound of the game's own has to come from the effects
DSP (IC306, an ADSP-21065L with 1M words of SDRAM), which the firmware host-boots and keeps running its own
effects kernel. Iteration 1, DSPTONE (technics-roms-disasm `kn7000/tools/dsptone`), put a program of ours into
it through the firmware's own host-port routines, as one effect unit of that kernel, and it played on Felipe's
KN7000 on 2026-10-21 (a 440 Hz tone and a PCM sweep from SDRAM; heartbeat 44,087 frames a second; the reverb
back after STOP). The game does the same with a sample mixer (`tools/dsp_mixer.py` builds it, `src/dsp.s` drives
it):

- **The bank, once.** Every sound the game plays (PLAY_SOUND, LOAD, or a music instrument): 93 of the release's
  sound resources, 684,980 samples, as their own card files (`AWRxx.AW`), with `AWBANK.AW` saying where each goes.
  At the start, after the global files, the converter reads each file into `PART_AREA`, unpacks it there and
  sends its samples to the DSP: 256 words at a time into a staging buffer in the DSP's internal memory, which
  the mixer copies into SDRAM, 8 words a frame. Four 8-bit samples go in a word: 171,576 words of SDRAM from
  `0x70000` (the kernel's delay rings end at `0x69D3F`; DSPTONE's PCM at `0x70000` played on the unit). The host
  port moves one 16-bit half per DSP frame, 88 KB a second at best, so this is the slow part: "LOADING ANOTHER
  WORLD: SOUNDS" and the load bar while it runs, 200 ms of it per converter call; in MAME 25.9 s. It is done once
  per power-on: the mixer leaves a marker in DSP memory ("AWSB" and the bank's id, a CRC-32 of its layout and
  samples), and a later run (YES at "Continue Next?", or the game started again from the menu) that finds it
  sends nothing (in MAME its DSP setup took 0.1 s). The whole bank rather than a part's sounds at each part
  switch: one wait, no pause added to the part switches, and no list of which part needs which sound.
- **The mixer.** 162 SHARC instructions at PM `0x8200`, eight voices: PLAY_SOUND's four channels on voices 0-3
  and the music's four on 4-7, as rawgl's mixer and module player keep them apart (the tone generator mode does
  the same with its note slots). Per voice: a start in SDRAM, a 16.16 position and step (PLAY_SOUND's
  frequency, `freqTable`, or the module's Amiga period, 7,159,092 / (2 x period) Hz, over 44,100 frames a
  second), the end, the loop (a sound plays its first part once and repeats its loop part, as the original's
  mixer) and the volume (0-63). The nearest sample, no interpolation; the sum times 128, so one voice at full
  volume peaks at -18 dBFS. It costs at most about 650 of the 1,360 instruction cycles a frame has (all eight
  voices sounding, a command and a copy step in one frame; 10 a silent voice, 39 a sounding one), less than the
  reverb and the chorus it stands in for.
- **Commands.** The game task fills a five-word record per voice (start, step, end, loop, volume) and a mask
  (start, change step and volume, stop) in RAM; at every poll (each VM thread switch and every 4 ms of a yield)
  it waits until the mixer has taken the last mask (MSGR6 reads 0), uploads the records that changed into DSP
  memory and writes the mask to MSGR6. The mixer applies it at its next frame and writes MSGR6 = 0. A sound
  effect or a row's notes so cost 20 to 100 DSP frames of host traffic (0.5-2.3 ms).
- **Where it is heard.** The mixer sits in two of the kernel's unit slots: unit 0 (PM `0x8080`, normally the
  panel REVERB), whose return is unit 0's input plus the mix, and unit 9 (PM `0x80A0`, normally the CHORUS),
  whose return is the mix alone. The tone generator mixes unit 0's return into the DAC only while REVERB is on
  (the crossfade `0x803A`; DSPTONE needed REVERB on). The CHORUS has no return register (kn7000_mame
  `notes/effect-return-routing.md`: its button moves only its send), so unit 9's return should be heard whatever
  REVERB and CHORUS are: that is the path for REVERB off, and **it has not been heard on the unit yet**. With
  REVERB on, both paths carry the mix, so it may sound about 6 dB louder than with REVERB off. The reverb and
  the chorus are off while the game's sound is on the DSP (their programs are not run; the keybed's notes go
  through dry). MAME mixes unit 9's return only while the CHORUS is on, so the MAME check below hears unit 0's.
- **Putting it back.** Leaving the DSP mode with RIGHT 2, quitting (before the game answers 0xFE), a failure
  while it is being set up, and the firmware ending the converter some other way (the game task notices that
  the converter has not been called for 5 s) all stop the voices and put both slots back as they were found,
  each read back, with MSGR4-MSGR7 at 0 and the external port's channel 8 as found: the firmware's reverb and
  chorus run again at once (their programs were never touched). The help screen, a part switch and LOAD 0 only
  stop the voices. Coming back to the DSP mode hooks the slots again.
- **Safety, as DSPTONE.** Only the firmware's own host-port routines (found by DSPTONE's search, two more steps
  of the game's firmware search: 8 in all), with their lock, their per-frame handshake and their "DSP dead"
  guard: `tools/ic23_guard.py` now also refuses any reference to the port's addresses (`0x98000000`,
  `0x9C000000`). Before it touches anything: the dead flag, the kernel downloaded, SYSCON, channel 8, both slots
  read back as the kernel's "CALL (0x8xxx) (DB)" (a slot an earlier program of ours left pointing at PM
  `0x8100`-`0x82FF` is put back first). The mixer and its variables are read back and compared before the
  hook. No M0-M7 (the 893 and 941 kernels set them differently). The dead flag is checked at every step; if the
  firmware ever sets it, the game goes on with the tone generator ("NO DSP 10" or "12").

**Trying it on the instrument** (it has run only in MAME; DSPTONE, which it builds on, ran on the unit):

1. Before starting: **REVERB on** (its lamp lit), MAIN VOLUME low to moderate, and a few notes played to hear
   the reverb and the chorus as they are.
2. Start the game from the menu. The first time after switching on, "LOADING ANOTHER WORLD: SOUNDS" and the
   bar stay a while (26 s in MAME; the card and the chip decide here). Later starts skip it.
3. In the intro you should hear the original game's own sounds: its music and its effects, not the instrument's
   voices. HELP's first page shows "NOW: DSP SAMPLES" in its last line; "NO DSP n" there means the DSP was not
   used (n above): note n.
4. Then with **REVERB off**: quit, switch REVERB off on the main screen, start the game again (quick now). Is it
   heard, and how loud against REVERB on? That decides which of the two paths the instrument mixes.
5. PART SELECT RIGHT 2: the tone generator (the first iteration's GM sound), again: off, again: the DSP.
6. Quit (EXIT held), then play a few notes: the reverb and the chorus should be as before the game.

What to report: whether the game's own sounds were heard with REVERB on and with it off; how loud against your
notes; anything garbled, clicking or stuck (a sound that keeps playing after the help screen, a part switch, RIGHT
2 or the quit); the help line ("NO DSP n"); how long the sounds took to load; whether the reverb and the chorus
were back after quitting. **If anything goes wrong, switch the instrument off and on**: the firmware resets and
reloads the DSP at every power-on, and nothing of this outlives that (no IC23, no user memory, no card writes
but `AWPERFn.TXT`).

The `n` of "NO DSP n" (`src/dsp.inc`, `DF_*`): 1 the routines not found, 2 the DSP was already marked dead, 3 its
kernel never downloaded, 4 SYSCON or channel 8 not as the firmware leaves them, 5 a slot unreadable or not the
kernel's form, 6 the mixer read back different, 7 a hooked slot read back different, 8 a sound file missing or
damaged, 9 the mixer stopped taking the bank, 10 the DSP marked dead while the bank was sent, 11 the firmware
stopped calling the game (the slots were put back), 12 the DSP marked dead while playing.

### The tone generator mode (iteration 1, 2026-10-20)

The first iteration: sound effects and music, played by the KN7000's own tone generator, unchanged but for the
mode switch. **On the instrument (2026-10-21):** Felipe ran this build (`KN7APP.BIN` `97fbd9e6...`, from the menu's `AW\`)
on his KN7000 (program 893) and reported that the sound plays properly; no further detail was recorded.
The game never outputs a sample. It becomes a MIDI source inside the instrument (`src/audio.s`), and
the firmware plays its notes by its normal path, the one an external sequencer on MIDI IN uses.

- **The way in: the MIDI IN 1 receive ring.** The firmware's MIDI 1 receive ISR (941 `0x484B1E86`)
  takes each byte from the serial port and enqueues it into a byte ring in work RAM (lib `0x4C0249C5`,
  the enqueue `0x4C024CBC`: the byte at `wr`, `wr` + 1 wrapping at `last`, `free` - 1, nothing when
  `free` is 0); a firmware task dequeues and parses the bytes. The game's `MidiMsg` writes each whole
  message the same way, with interrupts masked (PSW IE off), so that neither the ISR nor a task switch
  can come in the middle; it never touches the read pointer. The ring is the one `fwfind.s` already
  finds for MIDI IN input (step 5; 893 `0x5001F020`, 941 `0x5001F050`). A full ring drops the message.
- **Which parts.** The KN7000's MIDI receive routing as initialised (owner's manual p.190): channels
  1-3 are RIGHT 1, RIGHT 2 and LEFT, the panel's voices; channels 4-16 are PART 4-16, the parts "for SMF
  playback or MIDI receive". The game sends only on channels 4-7 (the sound effects, one per AW mixer
  channel), 10 (the drums of both) and 11-14 (the music, one per module channel): **it never touches
  the panel's parts.** On those channels it sends reset all controllers and volume 100 at the start,
  then GM2 bank select (121/0, drums 120/0) and a program change whenever a channel needs another
  sound, and notes.
- **The sound effects** (opcode 0x18 PLAY_SOUND). Each sound resource has a GM program and the note it
  sounds at 8363 Hz, or a GM drum key: `tools/aw_sound_map.py`, a hand-made table from each sample's
  analysis (length, noise or tone, pitch), loaded at the start from the card file `AWSND.AW`. The
  frequency index moves the note by semitones, the volume is the velocity, the note lasts as long as the
  sample would at that rate (held while a looping sample plays); volume 0 stops the channel.
- **The music** (opcode 0x1A PLAY_MUSIC): rawgl's module player, on the kernel's millisecond counter.
  Each row, each of the four channels may start a note (an Amiga period, played as the nearest
  semitone, on the instrument's program), stop, change the volume, or set the **sync mark var 0xF4**.
  The marks are written as the original does, whether the sound is on or off: the intro reads them to
  time its scenes, and with them it follows the music (it reached the lake by itself in MAME, below).
  The module is loaded with its part's files (`AWR07.AW` with the intro, `AWR8A.AW` with the final
  part) into `MUSIC_BUF`.
- **When.** `AudioPoll` runs at every switch of VM thread and between 4 ms slices of every yield
  (`DLY_TSK`): the rows that are due, the notes whose time is up, the sound button. A part switch and
  LOAD 0 stop everything (as rawgl's `restartAt` and `stopAll`); the help screen sends all notes off
  and freezes the music; **quitting sends all notes off, all sound off and reset all controllers on
  every channel the game used**, before the game task ends.
- **PART SELECT RIGHT 2 takes the sound on to OFF** (all notes off, all sound off, nothing more is sent),
  and from OFF to the DSP; coming into this mode (from the DSP, or from OFF when the DSP cannot be used) sets
  the channels up again. The music player keeps running in every mode, so the intro's timing does not depend
  on the button.
- **MIDI IN as input now means channels 1-3.** The game's own notes go into the same ring as MIDI IN,
  so its note trackers count only channels 1-3 there (`MIDI_IN_CHANNELS`); the keybed is unaffected.

What was asked of the instrument for this mode: whether the intro's music and the effects sound at all;
which effects sound wrong or too loud (the resource ids are in `aw_sound_map.py`); whether any note keeps
sounding after the help screen, a part switch, the sound button or quitting; whether RIGHT 1, RIGHT 2 and LEFT
still have your voices afterwards.

## Speed

**Why it was slow on the instrument.** Every VM tick the old `KN7APP.BIN` (`b952c2aa...`) blitted the
front page to the LCD twice (the bytecode's own blit, then once more at the end of every frame) and
repainted the whole black border with each blit: 128,000 16-bit and 89,600 32-bit stores into the LCD
frame per tick, whatever had changed (counted in MAME: `probes/cnv/awcnv_perf.lua`). The LCD frame at
`0x9CE00000` sits on a 16-bit bus behind four wait states (the firmware leaves MEMCTR3 at `0x0424`):
on the owner's unit a 16-bit store there takes 439 ns, a 32-bit one 888 ns, a 16-bit load 694 ns,
where work RAM answers in one 15.6 ns cycle of the 64 MHz core from its cache (the ROM dumper's pass 9,
technics-roms-disasm `cnv_romdump`, 2026-10-20). So those stores alone took about 136 ms per tick, a
ceiling of 7 frames per second where the gameplay asks for 25 or 50. MAME gives the LCD no wait
states, so it showed none of it.

**What changed (2026-10-20).** One `KN7APP.BIN` that is faster and measures itself:

- **The blit writes only what changed** (`src/display.s` `BlitPage`). `SHADOW`, a copy in RAM of the
  colour indices the LCD's window shows, is compared with the page eight pixels at a time; a group
  of four pixels that differs is written as two 32-bit stores of two pixels each, from a table of the
  RGB565 of every pair of indices that is rebuilt only when the palette changes. The LCD is never read
  back for this. A blit of the page the LCD already shows, when nothing has drawn on that page since
  (the end-of-frame blit, mostly), is skipped. A new palette rewrites the whole window.
- **The border is painted once**, and everything again only when something may have drawn over it:
  the first blit, the load bar at a part switch and 5 and 30 frames after the load, the overlay going
  off, a switch of the blit mode, the stop screen, every 500 frames, and whenever one of 47 sentinel
  pixels of the LCD (the bands, the strips, a grid in the window), read after each yield to the
  firmware, no longer holds what the game drew there: about 33 us of LCD loads per frame. The firmware
  repaints its own text screen over the whole LCD now and then: in MAME, twice while the intro hands
  over to the lake, and once after DISPLAY HOLD. Before, every blit painted over it.
- **Spans, page fills and page copies** store 32 bits at a time (`src/vm.s`, `src/interp.s`): the same
  bytes, a quarter of the stores into work RAM.
- **A frame that has overrun its time yields 2 ms** to the firmware, no longer 8: the firmware's tasks
  get the CPU when they are ready whatever the yield asks; a longer yield only spins.
- **The measurement** (`src/perf.s`), below, and the **old blit as a switch**: PAGE DOWN changes
  between the new blit and the old one (every pixel 16 bits at a time, the whole border on every blit,
  twice a frame, and the 8 ms yield), so that one run on the instrument measures both.

In MAME (`KN7APP.BIN` `26aabecb...`, the intro, ticks 1-300, mean per tick): the stores into the LCD
frame fell from 217,600 (about 136 ms at the unit's times) to 2,036 32-bit ones and 47 sentinel loads
(1.84 ms; most ticks a few hundred stores, the two full repaints after the intro's load 76,800 each);
the game's loads from the pages, from 141,694 to 45,931. In MAME's own time (no wait states, but the
instructions counted) the intro ran at 25.0 frames per second with the new blit and 8.7 with the old
one (`probes/cnv/README.md`, "Speed"). The picture is the same: the intro's 2,612 frames are identical
to the reference VM's; the whole LCD frame, checked at every one of 3,601 ticks of the intro and the
lake against what the old blit made of the same VM state (`probes/cnv/awcnv_lcd.lua`), was that picture
but at one tick, when the firmware was repainting its text screen and the next tick put it right; and
its snapshots every 100 ticks are byte-identical to the old build's.

**What else was looked at.** The code, the VM pages and `SHADOW` lie in work RAM's cached view
(`0x50...`; pass 9 read `CHCTR` `0x008F` on the unit: instruction and data caches on); only the LCD frame
is reached uncached (`0x9CE00000`), as it must be. The old pacing yielded at least 8 ms even after a
frame that had overrun; the yield (the firmware's, found at run time) rotates the ready queue until
the millisecond counter has advanced that far, so any ready firmware task runs whatever it asks and
a longer yield only spins: now 2 ms. In MAME the yield took what it asked (31.1 ms for 31.5 asked,
7.5 for 8.0 with the old blit): the firmware's tasks took little there; YIELD against ASKED on the
overlay says what they take on the unit. The rasterizer still keeps its per-scanline state in
variables in (cached) RAM and calls a span routine per scanline; in MAME's time polygons took about
1 ms per frame of the intro, the blit 8 (the comparison: 128 KB of loads a frame), so the unit's
figures should decide what comes next.

**Where the time goes, on the instrument.** The game times itself with the clock pass 8 of the ROM
dumper proved on the owner's unit: the kernel's millisecond counter and timer 4's down-counter
(`TM4BC`, 2001 counts per ms). Every frame is split into phases, summed over one-second windows, per
part and over the whole game, separately for the new and the old blit:

| phase    | what                                                                             |
|----------|----------------------------------------------------------------------------------|
| VM       | the interpreter, input, everything not below                                     |
| polygons | the polygon and string ops (`0x80`, `0x40`, DRAW_STRING)                         |
| page ops | page fill, page copy, a bitmap drawn                                             |
| blit     | the page to the LCD                                                              |
| border   | the border fill                                                                  |
| yield    | the end-of-frame yield to the firmware: the pacing, and the firmware's own tasks |
| (load)   | waiting for a part's files: not part of a frame                                  |
| (pause)  | the help screens, the stop screen, drawing the overlay: not part of a frame      |

Before the game starts, a benchmark of a few milliseconds measures, on that instrument, the ns per
access of a register add, 16- and 32-bit stores and 16-bit loads to the LCD frame (in the top border
rows, which the game paints black anyway), 8- and 32-bit stores and loads to work RAM through the cache
and 32-bit loads through its uncached view; and the game reads the bus controller's registers
(MEMCTR0-7, `0x32000040`, `0x32000042`), the cache control (`CHCTR`), timer 4's mode and base.

The figures show in three places:

- **The overlay** (PAGE UP turns it on and off): in the left border, refreshed every second: the blit
  in use (NEW BLIT or OLD BLIT), frames per second, ms per frame, the longest frame, and ms per frame
  for each phase, the yield the pacing asked for, the load time in the window, LCD pixels written per
  frame, full repaints.
- **The help screen's fourth page** (HELP, then PAGE DOWN three times; "SPEED 4/4"): the last
  second, the whole game with the new blit and the whole game with the old one side by side; the
  benchmark in ns per access; the registers in hex. The game is paused while it shows.
- **`AWPERFn.TXT`** on the SD card: at each quit, the game writes the same page, the figures per
  part and per blit, the counters, the benchmark and the registers in full to a new file in the
  card's root, `AWPERF0.TXT`, then `AWPERF1.TXT` ... `AWPERF9.TXT` (it never writes over a file; with
  all ten there it writes nothing). It uses the loader's routines as the ROM dumper does for its
  files on the owner's unit: drive switch, open, one write, close.

**On the instrument: what to do, photograph and send.** With the card files of this build
(`make sdcard`; the floppy as it is):

1. Start the game as usual. Just after "LOADING ANOTHER WORLD" the top rows of the screen go black for
   a moment: the benchmark (well under a second).
2. When the splash shows, press **PAGE UP**: the overlay appears in the left border, "NEW BLIT
   PGDN:OLD" on top. Let the splash and the intro play with no input (they are the same every time).
   After 20 s or so photograph the overlay; once more 10 s later.
3. Press **PAGE DOWN**: "OLD BLIT". Let the intro go on 20 s, photograph the overlay twice as before.
   (In the old mode the border is repainted on every blit, so the overlay is drawn again after each
   one; it may flicker.)
4. Press **PAGE DOWN** again ("NEW BLIT"). Skip to the lake with C4, play a little (walk, swim), and
   photograph the overlay. If you like, the same in the old blit (PAGE DOWN, photograph, PAGE DOWN).
5. Press **HELP**, then **PAGE DOWN** three times: "SPEED 4/4". Photograph that page: it holds the
   last second, both blits over the whole game, the benchmark and the bus registers. **EXIT**.
6. Quit as usual (hold EXIT, EXIT, **NO**). On the way out the game writes `AWPERF0.TXT` (or the next
   free number) to the card's root. Send the photographs and that file; it can be deleted from the
   card afterwards.

How to read the figures (all in ms per VM frame unless said otherwise; "last 1 s" is the window the
overlay shows):

| figure                 | meaning                                                                                             |
|------------------------|-----------------------------------------------------------------------------------------------------|
| FPS, frames/s          | VM frames per second, loads and pauses left out                                                     |
| FRAME, frame           | the time of a frame: the sum of the six lines below it                                              |
| LONGEST, longest       | the longest frame                                                                                   |
| VM ... YIELD           | the phases (table above)                                                                            |
| ASKED, yield asked     | the yield the pacing asked for: var[0xFF] x 20 ms less the frame's work, at least 2 ms (old blit 8) |
| LOAD/S                 | ms of the last second spent waiting for a part's files                                              |
| PIXELS, LCD pixels     | LCD pixels the blits wrote per frame (the old blit: 128,000)                                        |
| REPAINT, repaints      | full repaints of border and window so far                                                           |
| ns per access          | the benchmark: ALU (one add), LCD w16 / w32 / r16, RAM w8 / w32 / r8 / r32, uncached r32            |
| bus 20-2E, 40 42 CHCTR | MEMCTR0-7, `0x32000040`, `0x32000042`, the cache control and TM4MD, as the firmware left them       |

A frame should take what the bytecode asks (var[0xFF] x 20 ms, set scene by scene; in MAME the intro
ran at 25 frames per second, 40 ms a frame). When FRAME is longer, the phases say why; when YIELD is
much longer than ASKED, the firmware's own tasks took the CPU in the yield.

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
| `0x502BA000`-`0x502C7FFF` | KN7APP.BIN: header, code and tables (31,756 bytes, to 0x502C1C0C)                     |
| `0x502C8000`-`0x502D79FF` | HELP_BUF: help pages, stop screen, bitmap unpacking                                   |
| `0x502D8000`-`0x502D82FF` | AW_FONT: the 8x8 font, from AWFONT.AW                                                 |
| `0x502D8300`-`0x502D8AFF` | AW_STRIDX: string index, from AWSTRIDX.AW                                             |
| `0x502D8B00`-`0x502D9AFF` | AW_STRDAT: strings, from AWSTRDAT.AW                                                  |
| `0x502DA000`-`0x502DA1FF` | AUDIO_VARS: audio.s: MIDI producer, music player, note slots                          |
| `0x502DA200`-`0x502DA5FF` | SND_TAB: each sound's program, note, length, from AWSND.AW                            |
| `0x502DA600`-`0x502DA9FF` | DSP_HOST: dsp.s: the effects DSP's routines, state, commands, readback                |
| `0x502DB000`-`0x502DEFFF` | MUSIC_BUF: the current part's music module                                            |
| `0x502DF000`-`0x502DF3FF` | CNV_VARS: the entry's and the part loader's variables                                 |
| `0x502DF400`-`0x502DF4FF` | FW_VARS: what fwfind.s found, and its scratch                                         |
| `0x502DF800`-`0x502DF83F` | AW_PATHS: the game's folder, from the menu's launch block                             |
| `0x502E0000`-`0x502E01FF` | VM_POLY_BASE: rasterizer scratch                                                      |
| `0x502E1000`-`0x502E20FF` | VM_INTERP_BASE: VM variables, threads, call stack                                     |
| `0x502E3000`-`0x502E43FF` | VM_MISC_BASE: input, help, guard, note trackers                                       |
| `0x502E5000`-`0x502E5247` | RES_TAB: where each resource is now                                                   |
| `0x502E6000`-`0x502E6FFF` | VM_PERF_BASE: speed figures, the blit's palette and pixel pairs                       |
| `0x502E7000`-`0x502E7EFF` | DSP_BANKTAB: the DSP's sample bank: where each sound goes, from AWBANK.AW             |
| `0x502E7F00`-`0x502E7FFF` | LB_ADDR: the program menu's launch block (kn7cnv.inc): read, never ours               |
| `0x502E8000`-`0x502EE3FF` | VIDEO2_AT: the shared polygons (0x11)                                                 |
| `0x502EE400`-`0x5031AFFF` | PART_AREA: the current part's files                                                   |
| `0x5031B000`-`0x5031BFFF` | the firmware's mailbox page (0x5031BC00..): never written by the game but the request |
| `0x50320000`-`0x5032F9FF` | PAGE_BITMAP_0: VM page 0                                                              |
| `0x50330000`-`0x5033F9FF` | PAGE_BITMAP_1: VM page 1                                                              |
| `0x50340000`-`0x5034F9FF` | PAGE_BITMAP_2: VM page 2                                                              |
| `0x50350000`-`0x5035F9FF` | PAGE_BITMAP_3: VM page 3                                                              |
| `0x50360000`-`0x5036F9FF` | SHADOW: the page as the LCD shows it (the blit)                                       |
| `0x50370000`-`0x50371FFF` | REPORT_BUF: the text of AWPERF.TXT                                                    |

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
   from its service table (11 of them: the table check of steps 1 and 2, with the write routine and
   the program build). `make app` stops unless it
   says "clean"; `probes/cnv/guard_loader_selftest.s` proves the guard finds a store, an address taken,
   a byte load, the loader's variables or code, an address as data and an IC23 address.
   `tools/cnv_layout.py` checks the map above: every region inside `0x502BA000`-`0x50379FFF`, off the
   mailbox page and the loader's area, no overlaps, every `vm.inc` field inside its block, the image
   starting at `APP_BASE` with its header and ending below `IMAGE_END_MAX` (`0x502C0000`), `AW_LO` equal to the loader's
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

Outside its RAM the game writes only the mailbox's request, the LCD frame, at each quit one new file in
the SD card's root (`AWPERF0.TXT` .. `AWPERF9.TXT`, the first name that does not exist: "Speed"), through
the loader's file routines, and, through the firmware's own host-port routines, the effects DSP's memory
("Sound"): its mixer at PM `0x8200`-`0x82A1`, its variables, voices, command records, staging buffer and
marker at DM `0x9D00`-`0x9EFF` (never written by the firmware: the ROM dumper's pass 7), the sample bank
at SDRAM `0x70000`-`0x99E37` (above the kernel's delay rings), MSGR4-MSGR7, and the CALL slots of units 0
and 9, which it puts back as it found them. All of that is the DSP's, which the firmware resets and
reloads at every power-on.

## How it was checked

All in the overlay emulator (`kn7000-emulator`, binary md5 `2a8e2fce...`), which models IC23 as 256 KB
of NVRAM repeating through CS1 and runs the firmware's power-down from its POWER OFF input. `-bios v13`
is the owner's program 893 / table 80, from the owner's own dumps; `-bios v16` is program 941. Every
run boots with the owner's loader floppy image (`b7a67de6...`) and a copy of the real KN7000's SD card
with `build/sdcard/` added to its root. The commands, the scripts and what each check reads are in
`probes/cnv/README.md`; every number below comes from `probes/cnv/run_cnv_tests.sh`, run on the speed
build (`KN7APP.BIN` `26aabecb...`; the build before, `b952c2aa...`, passed the same with 16 session
checks).

| check        | question                                                                      | 893, blank IC23           | 893, the owner's IC23     | 941, blank IC23           |
|--------------|-------------------------------------------------------------------------------|---------------------------|---------------------------|---------------------------|
| (a) guard    | does the game name any address in CS1, the pools or the loader? map in range? | clean; map ok             | (same build)              | (same build)              |
| (b) session  | a whole session (18 checks, below)                                            | 18 of 18                  | 18 of 18                  | 18 of 18                  |
| (b) report   | `AWPERF0.TXT` at the first quit, `AWPERF1.TXT` at the second, nothing more?   | both, as built            | both, as built            | both, as built            |
| (c) ic23w    | any write into CS1 from the converter area, or past IC23's 256 KB?            | none, none                | none, none                | none, none                |
| (d) same     | IC23 after the game and POWER OFF = IC23 after a control run and POWER OFF?   | identical, checksum valid | identical, checksum valid | identical, checksum valid |
| (d) accepted | does the next boot find it valid, PANEL MEMORY store as it was?               | valid, store kept         | valid, store kept         | valid, store kept         |
| (e) pools    | `0x50180000`-`0x50297FFF` identical at POWER OFF, and no write there?         | identical, none           | identical, none           | identical, none           |
| (f) area     | any foreign write into the game's RAM while it runs?                          | none                      | none                      | none                      |
| (g) loader   | any write into the loader's area but the loader's own?                        | none                      | none                      | none                      |

The session's 18 checks: the loader ran the game, having found all seven of its services (`0x7F`),
and the game's firmware search found everything (on 893: from the loader's table SD open
`0x48564A88`, read `0x48564D70`, close `0x48564B4F`, the drive switch the loader's no-op `0x502B85BE`;
`cre_tsk` `0x4C03D0B5`, `sta_tsk` `0x4C03D898`, the yield `0x4C03DD5C`, `exd_tsk` `0x4C03D58E`, ms
counter `0x500C53F8`, panel `0x5006BE4C`, MIDI rings `0x5001F020` / `0x5001F834`: the `aw_find_fw.py`
column); the splash, the intro, a key skipping it to the lake; the panel's five game buttons and the
keybed's action; HELP (the VM pauses, PAGE DOWN turns the page, EXIT returns); the speed figures (the
fourth help page, the overlay on and off, the old blit and back); the level codes HTDC
(the prison) and CLLD (the city, the largest part); quitting, "Continue Next?" YES (the loader reads
`KN7APP.BIN` again: a new game), quitting again and NO; no guard refusal and no load error; and each
part's resources, every time one became resident (8 times, 46 resources), byte for byte the
reference unpack; and the two speed reports on the card, the second the text the game built. No
panel press was lost and no file read failed in any of the three. The saved IC23s are byte for byte
those of the build before and of the control runs.

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

**The sound (2026-10-20, `KN7APP.BIN` `15f5c57e...` and `97fbd9e6...`; `probes/cnv/README.md`,
"Sound").** Only short runs, as asked: no acceptance suite was rerun for the sound build.

- `awcnv_sound.lua` (893, `15f5c57e...`, the build before the last change, which only keeps the
  sound quiet until the game has set it up): the whole intro with no input, recorded. The game put
  1,704 messages into the ring, dropped none, and the firmware read every one (its read pointer equal
  to the write pointer at every one-second sample). The module player played 951 rows; all 24 of the
  intro module's sync marks reached var 0xF4 in order (1, 4, 8, 12, 1, 16, 20, 33 .. 49), the intro
  stopped the music at mark 49, as its bytecode does, and went on to the lake by itself (at VM tick
  about 2,660; 2,612 before, without marks). 211 PLAY_SOUNDs sounded. The recording is silent before
  the game and between -27 and -49 dBFS through the intro, its pitches the module's (the bass's E2 at
  82 Hz, the melody's E4, G4, D4). PART SELECT RIGHT 2 stopped the game's output for the six seconds
  it was off. At the quit the ring's last bytes were all notes off, all sound off and reset all
  controllers on channels 10 to 14 (and before them 4 to 7), all read by the firmware.
- `awcnv_noteoff.lua` (893, `97fbd9e6...`, the game's own sound muted): the same notes put into the
  ring by the script, as `MidiMsg` does, and sent through the MIDI IN port from an SMF behave alike: a
  square lead (GM 80) falls by about 40 dB within a second of its note-off either way; a piano (GM 0)
  rings on after its note-off either way, which is the overlay's tone generator, not the path.

### The DSP sound (2026-10-21)

Light, as asked: one MAME session through the program menu, as Felipe runs it (`probes/cnv/run_dsp.sh`,
`awcnv_dsp.lua`, `dsp_report.py`; program 893, the owner's loader floppy, a copy of the real card with the menu as
the root `KN7APP.BIN` and the game in `AW\`), and the build's guards (`leafcheck` 0 unsafe calls, `ic23_guard`
clean with the DSP host port now forbidden too, `cnv_layout` ok, every word of the mixer checked against MAME's
SHARC disassembler). On `KN7APP.BIN` `a2fbbaa6...`, 11 of 11 checks (`probes/cnv/README.md`, "Sound on the
effects DSP"; the run's files: `probes/cnv/dsp-results-2026-10-21/`): the firmware's dead flag 0 throughout; the
whole bank sent in 25.9 s; both slots hooked and both units' counts at 44,100 a second through the intro; all
eight voices sounding, the music's alone audible in the recording (-52 to -43 dBFS); no MIDI sent in the DSP
mode; RIGHT 2 to the tone generator put both slots back, and back to the DSP hooked them again; after each quit
both slots as found, MSGR4-MSGR7 0, the reverb running again; a second game from the menu found the bank by its
marker and did not send it again. Not run: the acceptance suite (`run_cnv_tests.sh`, `run_menu_route.sh`),
program 941, the help screen's mode line, the watchdog.

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
- **The speed.** MAME gives the LCD frame no wait states, so its frame times say nothing of the
  instrument's; it counts the accesses (before and after: "Speed") and checks the picture. On the unit
  the overlay, the speed page and `AWPERFn.TXT` say where the time goes, with both blits.
- **The firmware's painting on the instrument.** In MAME the firmware repainted its text screen
  around the intro's last load and once after DISPLAY HOLD; on the unit it may do so at other times
  too. The sentinels, read after each yield, and the repaints after each load put it right within a
  frame or two where MAME saw it; a painting that misses all 47 sentinels and comes long after a load
  stays until the game draws there again or the 500-frame repaint. PAGE DOWN (the old blit) always
  paints everything.
- **`AWPERFn.TXT`.** Writing a file through the loader's routines has run on the owner's unit many
  times (the ROM dumper's `DUMPLIST.TXT` and dump files); the game does it the same way, in the root,
  once per quit, and never opens an existing file for writing (it tries each name for reading first,
  which fails for a missing one as a missing game file's read does).
- **The sound on the instrument.** In MAME the notes the game sends are consumed and sound, and its
  note-offs are honoured as MIDI IN's are; but the overlay's tone generator keeps some voices sounding
  after their note-off (and after all notes off), so MAME cannot show that nothing hangs: listen after
  the help screen, the sound button, a part switch and the quit. The GM programs and drum keys are
  chosen without hearing the KN7000 play them. And the routing is the instrument's initial one: if
  PART 4-14 have been given other channels, NOTE ONLY or no program change in the MIDI menus, or MIDI IN
  is set to BASS PEDAL, the game may sound differently or not at all.
- **The DSP sound on the instrument.** What iteration 1 (DSPTONE) settled on the unit: the firmware's
  host-port routines, the upload and readback of a program, a unit slot hooked and put back, SDRAM from
  `0x70000` written and played, the heartbeat at 44,087 frames a second, unit 0's return heard with REVERB
  on. What is new here and has run only in MAME: SDRAM up to `0x99E37` (the bank's 171,576 words; DSPTONE's
  PCM reached `0x7AC44`), the multiply and the shifts by a register on the chip, unit 9's slot and its
  return (MAME mixes it only while the CHORUS is on; whether the instrument mixes it whatever REVERB and
  CHORUS are is the open question), host traffic from a task of ours rather than the firmware's main task,
  how long the bank takes, and the level. MAME runs the DSP at exactly 44,100 frames a second and moves
  the host's words straight into DSP memory; the chip moves them through the external port's FIFO and
  DMA, as the firmware's own uploads, which is why every upload is read back before the hook.
- **IC23, the pools and the loader are only measured in MAME.** The game names no address there and
  refuses any computed one outside its RAM, but the first run should still check the instrument's
  memory: "Before the first run on the instrument".

## Limits

- **Sound: the DSP's is a second iteration** ("Sound"). No interpolation between samples, and the level
  against the instrument's own sound is not set (one voice at full volume peaks at -18 dBFS at the DSP).
  While it plays, the instrument's REVERB and CHORUS are off (the keybed sounds dry). The bank takes a
  while to load after each power-on. The tone generator mode is the first iteration's: GM sounds for the
  effects, the music's notes on GM instruments. The SP7001 build stays silent.
- **Load pauses** at each part switch, up to 130 KB of files (the city).
- **One card per build.** `KN7APP.BIN`'s part tables name the files of the build that wrote them:
  copy the whole of `build/sdcard/` each time, never `KN7APP.BIN` alone.
- **YES restarts from scratch.** The loader reloads `KN7APP.BIN` for "Continue Next?" YES, so a new
  game repeats the firmware search and the global files before the splash, and its speed figures
  start afresh (the new blit, the overlay off).
- **Room in `KN7APP.BIN`.** The variables moved up on 2026-10-21 (they were right after the image, at
  `0x502C0000`); the image may now reach `0x502C8000` (`IMAGE_END_MAX`): 25,588 bytes are left.
- **Ten speed reports at most.** With `AWPERF0.TXT` .. `AWPERF9.TXT` all on the card, a quit writes no
  more; delete them after copying them off.

## History: the AW.CNV floppy (retired)

Until 2026-10-20 the game was its own style converter, `AW.CNV`, on a floppy of its own with the 43
game files beside it, loaded at `0x502B8000` by STYLE CONVERT directly, with the floppy's file
routines found by its own search (`OpenHere`, `fmmread`, `fmmclose`). It passed the same acceptance
tests in MAME (`probes/cnv/README.md`), but it never went to the instrument: all custom code on the
owner's unit is started by `KN7LOAD.CNV` from the one write-protected floppy, and no other `.CNV` goes
on a floppy for it. It is retired, not kept as a MAME-only target: the loader route runs in MAME just
as well, and a second route would need its own guards and tests. Its last state is commit `dbc7a2c`
(`make floppy`, `src/cnv_main.s` linked at `0x502B8000`, `tools/make_cnv_floppy.py`).
