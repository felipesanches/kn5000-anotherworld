# Another World on a stock KN7000, from a floppy (no SP7001)

The same Another World VM as the SP7001 build ([README.md](README.md)), started a different way: as
a **style converter**. The KN7000's DISK MENU > STYLE CONVERT loads a `.CNV` program from the floppy
into RAM and runs it on its own CPU; that is how Technics shipped converters for other brands'
styles (the Style Convert Disk, `scd7000`). `AW.CNV` is such a program. It needs **program 941**,
the KN7000's normal firmware, and nothing else: no SP7001 plug-in, no SD card.

> **Status (2026-10-18): runs in MAME on program 941.** It loads the whole game from the floppy and
> unpacks the original data on the instrument, byte-identical to what the SD build loads. The
> intro plays pixel-identically to the reference VM, and the keyboard, panel, quitting and
> playing again all work.
>
> **Do not run it on a real KN7000 yet.** It keeps its 1.7 MB of game data in the `0x44000000`
> window. MAME maps 16 MB of RAM there, but a real KN7000 has only its 256 KB battery-backed
> backup SRAM there, which holds the panel memories. See Limits.

## Playing it

1. Build the floppy: `make floppy` writes `build/another_floppy.img` (see Building). Write it to a
   1.44 MB disk, or give it to MAME (`make cnvrun`).
2. On the KN7000: **DISK MENU**, then **STYLE CONVERT** (left button 3). The list shows `AW.CNV`.
   Press **OK** (right button 4).
3. The game loads: the white bar along the bottom fills as the 13 data files are read and
   unpacked (about 75 seconds in MAME). Then the intro starts. The keyboard, MIDI IN 1 and the
   panel play it exactly as in the SP7001 build; **HELP** shows the controls and the level codes.
4. **Hold EXIT for 1.5 seconds** to quit. The firmware shows a message box; press EXIT, and it
   asks **Continue Next?** **YES** (right button 3) plays again at once. **NO** (right button 4)
   returns to the main screen. A short EXIT press still closes the help screen.
5. Run AW.CNV again later and it starts at once: the game data is still in RAM, unless something
   else has used that RAM since.

## How it works

Traced in the firmware (`kn7000_disassembly` notes/style-converter.md) and measured in MAME
(`probes/cnv/`):

- **Loading.** STYLE CONVERT zeroes `0x30000` bytes at `0x502B8000`, reads the chosen `.CNV` there
  whole, and calls its first byte (`calls (a0)`) on the firmware's **main task**.
- **The mailbox.** When the converter returns, the firmware reads a request from the mailbox at
  `0x5031BC00`, serves it, writes `0xFF` and calls again. The real converters use it to ask for
  file listing, file reads and screens.
- **AW.CNV's first call.** It reads the game from the floppy with the firmware's own file routines,
  in the same context the firmware just used them in, and unpacks it. Then it starts a task of
  its own (`cre_tsk` / `sta_tsk`, ids 10 then 9, priority 3) that runs the VM. Finally it answers
  **request 5**, "show this text" (`HOLD EXIT TO QUIT`).
- **Parking the UI.** The firmware then keeps calling the converter, about 20 times a second, and
  AW.CNV answers 5 every time. That parks the user interface on the converter: the firmware
  doesn't repaint the screen under the game, and ignores EXIT. The main task keeps running,
  which matters because it decodes the panel buttons and passes the keybed's notes to MIDI OUT,
  the two inputs the game reads (probe 2 in `probes/cnv/README.md`). A converter that never
  returned would freeze both (probe 1).
- **Quitting.** The entry watches EXIT. Once it has been held for 1.5 s, the game task ends itself
  at its next yield (`exd_tsk`), and the next call answers **0xFE**, which ends the conversion.
  The firmware shows its message box, then "Continue Next?". YES calls AW.CNV again without
  reloading it, and the entry starts a new game task. NO goes back to the main screen.

Program-941 facts the build uses (`src/platform941.inc`):

| what                                           | 941                                                       | 942 (SP7001 build)                                        |
|------------------------------------------------|-----------------------------------------------------------|-----------------------------------------------------------|
| `cre_tsk` / `sta_tsk` / `dly_tsk` / `exd_tsk`  | `0x4C03D0C8` / `0x4C03D8AB` / `0x4C03DD6F` / `0x4C03D5A1` | `0x4C03D46B` / `0x4C03DCD3` / `0x4C03E295` / `0x4C03D944` |
| open a file in the current folder; read; close | `0x48531AC5`, `0x48532463`, `0x485323BC`                  | (`fopen_api` etc.)                                        |
| kernel millisecond counter                     | `0x500D3C58`                                              | `0x500D3C68`                                              |
| panel switch bitmaps (CPR, CPL/CPC)            | `0x5006BE50`, `0x5006BE80`                                | `0x5006BE60`, `0x5006BE90`                                |
| MIDI IN 1 / MIDI OUT 1 ring headers            | `0x5001F050`, `0x5001F864`                                | `0x5001F060`, `0x5001F874`                                |

The firmware writes only `0x44000000`–`0x4403FFFF` of the `0x44000000` window (probes/cnv/README.md),
so the game keeps the SD build's RAM layout above it; a bank file is staged at `0x44600000`.

## The floppy

| file                                      | what                                                             |
|-------------------------------------------|------------------------------------------------------------------|
| `AW.CNV`                                  | the game: platform layer, VM, ByteKiller unpacker (13,840 bytes) |
| `BANK01` … `BANK0D`                       | the original MS-DOS release's data files, unchanged              |
| `AWFONT.AW`, `AWSTRIDX.AW`, `AWSTRDAT.AW` | the 8x8 font and the string tables (as the SD build)             |

It is built on a blank disk the KN7000 itself formatted, labelled `ANOTHERWRLD`, and uses 2,299
of the disk's 2,847 clusters. The resource tables inside AW.CNV are generated from your copy's
`MEMLIST.BIN` at build time (`tools/aw_extract.py --banks`), so the floppy must carry the same
BANK files the build read.

## Building

As for the SD build (README.md), plus the floppy tools of the `kn7000_mame` repository beside
this one (`FLOPPY_TOOLS`):

    make cnv        # build/AW.CNV (runs tools/leafcheck.py first)
    make floppy     # build/another_floppy.img
    make cnvrun     # boot the published overlay build (program 941) with it

`tools/leafcheck.py` stops the build when a routine entered with `call X, 0, 0` calls another
before making a frame of its own. On the MN10300 that nested call overwrites the return address.

## How it was checked

- **The game data.** After loading, the 1,730,376 bytes of resources in RAM are identical to the
  SD build's packs, and the font and string tables are identical (`probes/cnv/README.md`). No
  resource failed its ByteKiller checksum.
- **The intro, frame by frame.** `probes/cnv/awcnv_cksum.lua` drives STYLE CONVERT and captures the
  displayed page at each VM tick. Compared with rustyworld as for the SP7001 build
  (`probes/CHECKSUM-COMPARISON.md`), all 2612 frames are identical.
- **A whole session.** `probes/cnv/awcnv_session.lua` passes 9 of 9 checks: start, skipping the
  intro with a key, the panel and keybed controls, quitting, "Continue Next?" YES and NO, and
  running AW.CNV again.
- **The platform.** Three probe converters measured what a converter may do on 941. One that never
  returns freezes the panel and the keybed. A task of its own plus request 5 keeps both working.
  `exd_tsk` plus 0xFE ends the game cleanly. Details and commands: `probes/cnv/README.md`.

## Limits

- **Load time.** About 75 s in MAME, reading and unpacking 1.15 MB; real-drive timing is unknown.
- **No sound,** as in the SP7001 build.
- **Real hardware: the `0x44000000` window.** The game keeps its pages at `0x44100000`, its
  resources at `0x44200000` and a bank file at `0x44600000`, as the SD build does. MAME maps
  16 MB of RAM at `0x44000000` as a placeholder ("TODO: identify these" in the driver). The
  kn7000_disassembly notes, though, identify the window as the **256 KB battery-backed backup
  SRAM** (IC23, mirrored at `0x84000000`). It holds the panel settings and the PANEL MEMORY
  records, and `BackupSramTest` fixes its size exactly. The firmware writes exactly its first
  256 KB (`probes/cnv/README.md`). On a real KN7000 the game's RAM is therefore not there, and
  with partial address decoding its writes would overwrite the stored settings.
- **What a real-hardware build needs.** Build 941 leaves about 928 KB of work RAM to a converter:
  `0x50298000`–`0x502B8000`, unused by 941, plus `INSTALL_SCRATCH` up to `0x50380000`, where
  AW.CNV itself sits. That is not enough for all 1.7 MB unpacked at once. The game would have to
  load each part's resources from the floppy when the part starts, as the original does, and keep
  its pages in work RAM.
- **No real-instrument test yet.**
