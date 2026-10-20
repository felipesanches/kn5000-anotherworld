# Another World on a stock KN7000, from a floppy (no SP7001)

The same Another World VM as the SP7001 build ([README.md](README.md)), started a different way: as
a **style converter**. The KN7000's DISK MENU > STYLE CONVERT loads a `.CNV` program from the floppy
into RAM and runs it on its own CPU; that is how Technics shipped converters for other brands'
styles (the Style Convert Disk, `scd7000`). `AW.CNV` is such a program. It needs a stock KN7000 and
nothing else: no SP7001 plug-in, no SD card. It finds what it needs in the firmware by itself, so
the same floppy serves every program build we know: **893** (v1.3, the owner's), 935, **941** (v1.6)
and 942. (The SP7001 build is for MAME only: it lives in the window that is IC23 on an instrument.)

> **Status (2026-10-20): runs in MAME on program 893 (`-bios v13`) and program 941 (`-bios v16`),
> and leaves the instrument's stored data alone.** The game lives only in the work RAM STYLE CONVERT
> leaves to a converter, loads each part's files from the floppy when the part starts, and refuses
> any write outside its own RAM. In the overlay emulator, which models IC23 (the battery-backed
> panel memories), a whole session ending with POWER OFF leaves IC23 and the user-memory pools
> byte-identical to a session that never ran the game, and the next boot accepts them. Results and
> evidence: "How it was checked". **It has not run on a real KN7000 yet**: what that first run should
> watch is under "Before the first run on the instrument".

## Playing it

1. Build the floppy: `make floppy` writes `build/another_floppy.img` (see Building). Write it to a
   1.44 MB disk, or give it to MAME (`make cnvrun`, `BIOS=v13` for program 893).
2. On the KN7000: **DISK MENU**, then **STYLE CONVERT** (left button 3). The list shows `AW.CNV`.
   Press **OK** (right button 4).
3. "LOADING ANOTHER WORLD" shows while a white bar along the bottom fills: six steps of the
   firmware search, then the font, the strings and the shared polygons. Then the splash starts.
   Whenever the game moves to another part, the picture stops for a few seconds while the bar
   fills again: the part's files are being read from the floppy. The keyboard, MIDI IN 1 and the
   panel play it exactly as in the SP7001 build; **HELP** shows the controls and the level codes.
   **Prefer the keybed to the panel's UP, DOWN and FIRE.** Those are R1/R2 OCTAVE + / - and
   SUSTAIN, and the firmware keeps doing their own job while the game runs: OCTAVE + / - shift the
   R1/R2 octave, and SUSTAIN switches sustain on and off. Those are ordinary setting changes, kept
   at power-off like any other (measured in MAME: `probes/cnv/awcnv_panelsettings.lua`); press them
   back afterwards if they matter. PART SELECT LEFT and RIGHT 1, HELP, OTHER PART & FR, PAGE DOWN
   and EXIT changed no setting in the tests.
4. **Hold EXIT for 1.5 seconds** to quit. The firmware shows a message box; press EXIT, and it
   asks **Continue Next?** **YES** (right button 3) plays again at once. **NO** (right button 4)
   returns to the main screen. A short EXIT press still closes the help screen.
5. If the firmware is one AW.CNV does not recognise, or a game file is missing or damaged, the
   screen says so ("AW: UNKNOWN FIRMWARE, STEP n", "AW: A GAME FILE IS MISSING OR BAD") and EXIT
   ends it; nothing has been written outside the converter's RAM.

## How it works

Traced in the firmware (technics-roms-disasm `kn7000/notes/style-converter.md`) and measured in
MAME (`probes/cnv/`):

- **Loading.** STYLE CONVERT zeroes `0x30000` bytes at `0x502B8000`, reads the chosen `.CNV` there
  whole, and calls its first byte (`calls (a0)`) on the firmware's **main task** (941 `0x48479929`,
  893 `0x48479766`).
- **The mailbox.** When the converter returns, the firmware reads a request from the mailbox at
  `0x5031BC00`, serves it, writes `0xFF` and calls again. 893 uses the same address, area and
  requests (its STYLE CONVERT code reads `0x5031BC00`; the ROM dumper ran there with them).
- **One step per call.** Every call does one step and answers **request 5**, "show this text"
  (`LOADING ANOTHER WORLD`, then `HOLD EXIT TO QUIT`). The firmware keeps calling, about 20 times a
  second, which parks the user interface on the converter: the firmware doesn't repaint the screen
  under the game and ignores EXIT, while the main task goes on decoding the panel and passing the
  keybed's notes to MIDI OUT, the two inputs the game reads (probe 2 in `probes/cnv/README.md`).
- **Finding the firmware** (`src/fwfind.s`, the first six calls). AW.CNV carries no firmware
  address. It searches the program flash and the kernel library in RAM by code signatures, the way
  the ROM dumper's loader does (technics-roms-disasm `kn7000/tools/cnv_romdump`, which ran on the
  owner's 893), and accepts a find only when it is unambiguous and cross-checked:

  | what                                          | found by                                                                   |
  |-----------------------------------------------|----------------------------------------------------------------------------|
  | the panel switch bitmaps                      | the panel decoder's two sites, which must agree (CPL = CPR + 0x30)         |
  | the firmware's yield, the millisecond counter | the yield routine in the library and the tick handler, which must agree    |
  | open in the current folder, read, close       | the dumper's fmm signatures; OpenHere must call the fmmopen found          |
  | `cre_tsk`, `sta_tsk`                          | the firmware's own "cre_tsk then sta_tsk(N, 0)" call sites: all must agree |
  | `exd_tsk`                                     | the firmware's tasks that end themselves: all must agree, a kernel stub    |
  | the MIDI IN 1 and MIDI OUT 1 rings            | the library's per-port ring wrappers                                       |

  `tools/aw_find_fw.py` runs the same searches over every program image we have:

  | what         | 893 (v1.3)   | 935 (v1.5)   | 941 (v1.6)   | 942 (SP7001) |
  |--------------|--------------|--------------|--------------|--------------|
  | open         | `0x485313F0` | `0x48531A83` | `0x48531AC5` | `0x48531AB4` |
  | fmmread      | `0x48531D8E` | `0x48532421` | `0x48532463` | `0x48532452` |
  | fmmclose     | `0x48531CE7` | `0x4853237A` | `0x485323BC` | `0x485323AB` |
  | cre_tsk      | `0x4C03D0B5` | `0x4C03D0C8` | `0x4C03D0C8` | `0x4C03D46B` |
  | sta_tsk      | `0x4C03D898` | `0x4C03D8AB` | `0x4C03D8AB` | `0x4C03DCD3` |
  | dly_tsk      | `0x4C03DD5C` | `0x4C03DD6F` | `0x4C03DD6F` | `0x4C03E295` |
  | exd_tsk      | `0x4C03D58E` | `0x4C03D5A1` | `0x4C03D5A1` | `0x4C03D944` |
  | kernel_ms    | `0x500C53F8` | `0x500C541C` | `0x500D3C58` | `0x500D3C68` |
  | panel_cpr    | `0x5006BE4C` | `0x5006BE50` | `0x5006BE50` | `0x5006BE60` |
  | panel_cpl    | `0x5006BE7C` | `0x5006BE80` | `0x5006BE80` | `0x5006BE90` |
  | midiin1_rxq  | `0x5001F020` | `0x5001F024` | `0x5001F050` | `0x5001F060` |
  | midiout1_txq | `0x5001F834` | `0x5001F838` | `0x5001F864` | `0x5001F874` |

  The 941 and 942 columns equal the addresses measured in MAME before; in MAME, AW.CNV's own search
  gives the 893 and 941 columns exactly (the session test prints them).
- **The global files** (the next four calls): the font, the string tables and the shared polygons
  (resource 0x11), one file per call. Then AW.CNV starts a task of its own (`cre_tsk` / `sta_tsk`,
  ids 10 then 9, priority 3) that runs the VM.
- **Parts on demand.** Like the original engine, the game holds one part at a time. At a part
  switch the game task asks for the new part (`EnsurePart`) and yields until it is there. Each
  converter call then reads one of the part's files into the part area, in the floppy's current
  folder, and unpacks it in place, as the original engine does (`tools/aw_extract.py` checks at
  build time that every such resource unpacks right in place). The bitmaps a part's bytecode LOADs
  stay packed until LOAD draws one; they are unpacked into a buffer of their own (`BitmapData`).
  A part's loads start only once no panel button is down (or after about 5 s), so that a button's
  release never arrives while the main task is busy in a file read; a file that fails to load is
  tried again on the next call, up to three times, before the game stops and says so.
- **Quitting.** The entry watches EXIT. Once it has been held for 1.5 s, the game task ends itself
  at its next yield (`exd_tsk`), and the next call answers **0xFE**, which ends the conversion.
  The firmware shows its message box, then "Continue Next?". YES calls AW.CNV again without
  reloading it, and the entry starts a new game task. NO goes back to the main screen.

## Memory

Everything the game writes is in **`0x502B8000`-`0x50379FFF`**, the work RAM STYLE CONVERT leaves to
a converter, less the mailbox page. That range was measured untouched by the firmware on program 893
in MAME through boot, idle, DISK MENU and a converter run (research-scratch
`aw-memory-plan/taps893_ranges.out`), and the acceptance tests below measure it again while the game
runs. `src/platformcnv.inc` holds the map; `tools/cnv_layout.py` prints and checks it at every build:

| range                     | what                                                              |
|---------------------------|-------------------------------------------------------------------|
| `0x502B8000`-`0x502BDFFF` | AW.CNV: code and tables (15,812 bytes)                            |
| `0x502BE000`-`0x502BFAFF` | the 8x8 font, the string index, the strings                       |
| `0x502C0000`-`0x502C04FF` | the converter's and loader's variables; what the search found     |
| `0x502C1000`-`0x502C53FF` | VM state: rasterizer, interpreter, input, help, guard, note rings |
| `0x502C6000`-`0x502C6247` | `RES_TAB`: where each resource is resident now (0 = not)          |
| `0x502C8000`-`0x502D79FF` | help pages, the stop screen, bitmap unpacking                     |
| `0x502E8000`-`0x502EE3FF` | the shared polygons (resource 0x11), loaded once                  |
| `0x502EE400`-`0x5031AFFF` | the current part's files (183,296 bytes; the city needs 164,408)  |
| `0x5031B000`-`0x5031BFFF` | the firmware's mailbox page: only the request bytes are ours      |
| `0x50320000`-`0x5035F9FF` | the four VM pages, `0x10000` apart                                |

What the game must never touch, and how that is checked:

- **IC23**, the 256 KB battery-backed SRAM with the panel settings and the 104 PANEL MEMORY records,
  is chip select CS1: `0x44000000`-`0x47FFFFFF`, and its uncached view `0x84000000`-`0x87FFFFFF`. It
  repeats every 256 KB through the whole chip select (A1-A17 only; confirmed on the owner's unit on
  2026-10-20), so any address there is the panel memories. The firmware writes it at any time and
  stamps a checksum over its header only at power-off: damage done during a session would be
  stamped valid (kn7000_mame `notes/ic23-nvram-2026-10-20`). Earlier builds of AW.CNV kept all their
  data there; this one names no address in CS1.
- **The user-memory pools**, `0x50180000`-`0x50297FFF` (and `0x90180000`-...): COMPOSER styles, pads
  and the other user data the firmware never clears and keeps across power-off.
- **Boot data** from `0x5037A000`, and 941's zlib arena `0x503B1000`-`0x503FFFFF`.

Three checks keep the game inside its range:

1. **At build time**, `tools/ic23_guard.py` assembles AW.CNV with the toolchain's own assembler and
   records every value any expression produces (operands, data, constants, labels): none may lie in
   CS1 or the pools. `make cnv` stops unless it says "clean". (The earlier AW.CNV had 717 such
   references.) `tools/cnv_layout.py` checks the map above: every region inside
   `0x502B8000`-`0x50379FFF`, off the mailbox page, no overlaps, every `vm.inc` field inside its block,
   the image below the font.
2. **At run time**, every load destination is checked before the file is read (`GuardRange`: inside
   `0x502B8000`-`0x50379FFF`, clear of the mailbox page), every page the VM draws or copies on must
   be one of the four pages (`GuardPage`), and the VM's call stack must stay in its 512 bytes. A
   refused write is skipped, and the game stops at once with "ANOTHER WORLD STOPPED", the reason and
   the address on the LCD; EXIT then ends it as usual. The rasterizer already clips every span and
   point to the page; variables and threads are indexed with masks.
3. **In MAME**, write taps over CS1, the pools and the game's own RAM, through whole sessions on 893
   and 941 (below).

The task's stack is the kernel's: `cre_tsk` allocates it and `exd_tsk` frees it.

## The floppy

| file                                      | what                                                                    |
|-------------------------------------------|-------------------------------------------------------------------------|
| `AW.CNV`                                  | the game: platform layer, firmware search, VM, unpacker (15,812 bytes)  |
| `AWR11.AW` ... `AWR91.AW` (40 files)      | each resource the game draws or runs, as MEMLIST.BIN finds it in BANKxx |
| `AWFONT.AW`, `AWSTRIDX.AW`, `AWSTRDAT.AW` | the 8x8 font and the string tables (as the SD build)                    |

Each `AWRxx.AW` holds the exact bytes the original MS-DOS release's `MEMLIST.BIN` points at in its
`BANKxx` file, ByteKiller-packed or stored, for every palette, bytecode, polygon set and bitmap (the
sounds and music modules are left out: the port has no audio). The disk is built on a blank disk
the KN7000 itself formatted, labelled `ANOTHERWRLD`: 44 files, 570,440 bytes of game data, 1,166
of the disk's 2,847 clusters. The part tables inside AW.CNV are generated from your copy's
`MEMLIST.BIN` at build time (`tools/aw_extract.py --parts`), so the floppy must carry the files the
same build wrote.

## Building

As for the SD build (README.md), plus the floppy tools of the `kn7000_mame` repository beside
this one (`FLOPPY_TOOLS`):

    make cnv        # build/AW.CNV: leafcheck, ic23_guard ("clean"), assemble, cnv_layout
    make floppy     # build/another_floppy.img (also `make`)
    make cnvrun     # boot the overlay emulator with it (BIOS=v13: program 893; default v16: 941)
    make fwfind     # tools/aw_find_fw.py: the firmware search over every program build

`tools/leafcheck.py` stops the build when a routine entered with `call X, 0, 0` calls another
before making a frame of its own. On the MN10300 that nested call overwrites the return address.

## How it was checked

All in the overlay emulator (`kn7000-emulator`, binary md5 `ed41d01b...`), which models IC23 as 256 KB
of NVRAM repeating through CS1 and runs the firmware's power-down from its POWER OFF input. `-bios v13`
is the owner's program 893 / table 80, from the owner's own dumps; `-bios v16` is program 941. The
commands, the scripts and what each check reads are in `probes/cnv/README.md`; every number below
comes from `probes/cnv/run_cnv_tests.sh` (AW.CNV `7aab745c...`, floppy `b7214529...`).

| check        | question                                                                    | 893, blank IC23           | 893, the owner's IC23     | 941, blank IC23           |
|--------------|-----------------------------------------------------------------------------|---------------------------|---------------------------|---------------------------|
| (a) guard    | does AW.CNV name any address in CS1 or the pools? is the map in range?      | clean; map ok             | (same build)              | (same build)              |
| (b) session  | a whole session (16 checks, below)                                          | 16 of 16                  | 16 of 16                  | 16 of 16                  |
| (c) ic23w    | any write into CS1 from the game's code, or past IC23's 256 KB?             | none, none                | none, none                | none, none                |
| (d) same     | IC23 after the game and POWER OFF = IC23 after a control run and POWER OFF? | identical, checksum valid | identical, checksum valid | identical, checksum valid |
| (d) accepted | does the next boot find it valid, PANEL MEMORY store as it was?             | valid, store kept         | valid, store kept         | valid, store kept         |
| (e) pools    | `0x50180000`-`0x50297FFF` identical at POWER OFF, and no game write there?  | identical, none           | identical, none           | identical, none           |
| (f) area     | any firmware write into the game's RAM while it runs?                       | none                      | none                      | none                      |

The session's 16 checks: the firmware search found everything (on 893: OpenHere `0x485313F0`, fmmread
`0x48531D8E`, fmmclose `0x48531CE7`, `cre_tsk` `0x4C03D0B5`, `sta_tsk` `0x4C03D898`, the yield
`0x4C03DD5C`, `exd_tsk` `0x4C03D58E`, ms counter `0x500C53F8`, panel `0x5006BE4C`, MIDI rings
`0x5001F020` / `0x5001F834`: the `aw_find_fw.py` column); the splash, the intro, a key skipping it to
the lake; the panel's five game buttons and the keybed's action; HELP (the VM pauses, PAGE DOWN turns
the page, EXIT returns); the level codes HTDC (the prison) and CLLD (the city, the largest part);
quitting, "Continue Next?" YES (a new game), quitting again and NO; no guard refusal and no load
error; and each part's resources, every time one became resident (8 times, 46 resources), byte for
byte the reference unpack.

How long the loads take in MAME (893, emulated time; one file per converter call, about 20 calls a
second; a real drive's speed is not known):

| what                                     | files | bytes read | time      |
|------------------------------------------|-------|------------|-----------|
| the firmware search (six steps)          | -     | -          | ~10 s     |
| font, string tables, shared polygons     | 4     | 25,776     | 5.2 s     |
| the splash part (0x3E80, with 4 bitmaps) | 7     | 30,060     | 6.3-6.5 s |
| the intro (0x3E81)                       | 3     | 64,176     | 5.6 s     |
| the lake (0x3E82)                        | 3     | 60,108     | 4.7 s     |
| the prison (0x3E83, with 2 bitmaps)      | 5     | 93,464     | 9.8 s     |
| the city (0x3E84, with 4 bitmaps)        | 7     | 129,892    | 13.2 s    |

- **The writes.** In the game runs, the firmware's own writes into IC23 are the boot's and a few from
  its library (`0x4C01F310`-`0x4C01F39C`: the settings OCTAVE and SUSTAIN change); none from the
  converter area. The game's RAM saw only the firmware loading AW.CNV and the floppy reads AW.CNV
  asked for. The stack pointer seen while the game's code runs (the game task's, and the main
  task's during converter calls) stays in `0x5038DD5C`-`0x503AD844`, the kernel's, outside the
  game's range. Nothing touched the pools after boot. No panel press was lost and no file read failed in
  the final runs.
- **The intro, frame by frame**, on 893 with the final floppy: `probes/cnv/awcnv_cksum.lua` captures
  the displayed page at every VM tick; compared with rustyworld as for the SP7001 build
  (`probes/CHECKSUM-COMPARISON.md`), 2612 of 2612 frames are identical.
- **The firmware search on the instrument's own data.** `tools/aw_find_fw.py` finds the same 893
  addresses in the owner's program dump, and, with `--real-lib893`, in the library RAM the ROM
  dumper read from the instrument (equal to the boot's copy of the flash over its whole length).
- **What these tests found and the commits fixed** (none of it a write outside the game's RAM; the
  guard turned each into a clean stop or a retry):
  - the load guard measured a packed bitmap by its unpacked size and refused the city's last one
    ("ANOTHER WORLD STOPPED", resource `0x46`);
  - a failed part list was retried on every call afterwards, so YES could not start a new game;
  - right after OTHER PART & FR started a part load, the button's release was lost while the main
    task was busy in a file read: the firmware's switch bitmap kept OTHER PARTS set and the emulated
    panel delivered nothing more (EXIT, YES, OK: 36 lost presses). A part's loads now start only once
    no panel button is down (or after about 5 s);
  - once, the intro's polygons (`0x19`, the biggest file) failed to load, and loaded on a rerun. A
    failed file is now tried again on the next call, up to 3 times.
- **The panel buttons.** `probes/cnv/awcnv_panelsettings.lua`: while the game runs, the firmware
  still acts on R1/R2 OCTAVE + / - (the octave setting) and SUSTAIN (sustain on/off), the game's UP,
  DOWN and FIRE; PART SELECT LEFT, RIGHT 1, RIGHT 2 and DISPLAY HOLD change nothing. The session
  therefore presses those in pairs that cancel, and checks that the settings end as they began.

## Before the first run on the instrument

What MAME cannot settle, and how a first run can watch for it:

- **Everything rests on the emulation of program 893.** The `-bios v13` program and table images are
  the owner's own dumps (cnv_romdump passes 1 and 2, checked byte for byte), and the kernel library
  the search reads in RAM is the boot's copy of that flash, so the firmware search's results should
  carry over unchanged; `tools/aw_find_fw.py` gives the same answers from the dump files alone.
- **Never yet on the real unit:** answering request 5 (the ROM dumper parks with request 1), starting
  and ending a task of our own (`cre_tsk`, `sta_tsk`, `exd_tsk`), and the firmware's yield routine.
  MAME runs the same firmware code for all of them, but not the real chip's timing.
- **The floppy drive.** Each part switch reads one file per converter call, up to 55,476 bytes
  (the intro's polygons), with the firmware's own `fmmread`, the routine STYLE CONVERT loads a
  converter with; the main task is busy meanwhile, as when the firmware loads a 100 KB converter.
  How long a real drive takes per part is unknown (MAME: see "How it was checked"), and whether a
  panel event that comes in meanwhile is kept: in MAME one release was lost that way (above),
  which is why loads now wait for the panel to be let go.
- **The panel while parked.** Request 5 keeps the firmware on the converter's text screen, and the
  panel's switch bitmaps keep being updated. In MAME the firmware also acts on R1/R2 OCTAVE + / -
  and SUSTAIN there (above); other buttons may do the same on the instrument, which a changed
  setting after a session would show.
- **IC23 and the pools are only measured in MAME.** The game names no address there and refuses any
  computed one outside its RAM, but a first run should still check the instrument's memory:
  1. before the run, save the panel memories the usual way (and, for a byte-exact record, dump IC23
     with the ROM dumper's SURVEY2 pass, technics-roms-disasm `kn7000/tools/cnv_romdump`);
  2. run AW.CNV: the six search steps and four global files fill the bar in about 15 s in MAME; an
     error names its step ("AW: UNKNOWN FIRMWARE, STEP n") and ends cleanly with EXIT;
  3. play into a part switch, open HELP, quit with EXIT held, answer NO, switch the instrument off
     and on;
  4. compare the panel memories (and a second SURVEY2 dump, with `probes/cnv/ic23_diff.py`: the
     PANEL MEMORY store `0x824`-`0x30173` must be identical).

## Limits

- **No sound,** as in the SP7001 build.
- **Load pauses.** Each part switch reads up to 130 KB from the floppy (the city); in MAME that takes
  up to 13 s (the table above). A real drive's timing is unknown.
- **One floppy per build.** AW.CNV's tables point at the files of the build that wrote them.
