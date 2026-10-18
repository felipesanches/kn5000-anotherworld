# The STYLE CONVERT build: probes

Measurements behind [README-CNV.md](../../README-CNV.md), the Another World build that a stock
KN7000 runs as a style converter (`AW.CNV`). All of them run on **program 941** in the published
overlay MAME build (`kn7000-emulator/run.sh kn7000`), with a copy of the real KN7000's SD card
and a floppy in the drive. They were run on 2026-10-18; the results below are from the committed
files.

## What the platform does with a converter

Three small converters, each alone on a floppy, ask what a converter may do on 941. They answer
the questions the port's design rests on. `build_probe.sh` assembles one into `AW.CNV` on a blank
disk the KN7000 formatted; `run_probe.sh` boots with it and runs a command file for
`tools/rigs/remote.lua` (kn7000_mame). The command files walk DISK MENU > STYLE CONVERT > OK and
then print the probe's variables. Rebuilt from these sources, the three converters are
byte-identical to the ones measured.

| probe (`.s` + `.cmd`)                         | question                                                                                              | result                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
|-----------------------------------------------|-------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `probe1_noreturn`                             | Does a converter that never returns (it yields with `dly_tsk`) keep the instrument usable?            | **No.** Its loop runs, 62.5 passes per second (`hb` 304 → 429 in 2 s). But a PART SELECT press never reaches the switch bitmap (no `52:01` in `seen`), and a keybed note never reaches the MIDI OUT 1 ring (`mout` stays `0x5001F064`). Both are the main task's work, and the converter is holding the main task.                                                                                                                                                                                      |
| `probe2_task`                                 | If the converter starts a task of its own and answers request 5 on every call, does input still work? | **Yes.** `cre_tsk(10)` and `sta_tsk(10, 0)` return 0, and the task runs at 62.5 passes per second. The firmware calls the converter 20 times a second (`entries` 77 → 117 in 2 s), with the main task's title on `0x4A` (`_TT_STYLCNVTXT`). PART SELECT sets `0x5006BE52` bit `0x01`. One keybed note (on + off) moves the MIDI OUT 1 write pointer by 6 bytes (`0x5001F064` → `0x5001F06A`). EXIT shows up at `0x5006BE8B` bit `0x80`, and the firmware keeps calling: EXIT does not leave the screen. |
| `probe3_quit`                                 | Can the converter end itself and the conversion?                                                      | **Yes.** On EXIT the task records `quit` and calls `exd_tsk`, and its heartbeat stops (243 → 243 over 3 s). The next call answers `0xFE`, and the firmware stops calling (`entries` 79 → 79). Each call finds `0xFF` in mailbox byte 0 (`mb` = `4F4E41FF`: `0xFF`, then the "ANO" left there by the text request).                                                                                                                                                                                      |
| `ram44.cmd` (with probe3's disk)              | Which part of the `0x44000000` window does the firmware write?                                        | Only `0x44000000`–`0x4403FFFF`: 64 KB blocks `00`–`03`, with 243,011, 242,062, 242,060 and 225,037 writes, through boot (40 s) and the same counts after STYLE CONVERT ran the probe. That is the 256 KB battery-backed SRAM (see below).                                                                                                                                                                                                                                                               |
| `taskprobe.cmd` (with the Style Convert Disk) | Which task calls a converter, and which decodes the panel? Where are 941's MIDI rings?                | Both are the **main task**. Breakpoint `0x48479929` (`calls (a0)`) hit 3 times, with the current TCB (`*0x5038002C`) = `0x50381470` = the main task's TCB. `PanelFrameDecode` `0x484AD116`: 395 of 395 hits on `0x50381470`. Ring headers: MIDI IN 1 at `0x5001F050` (buffer `0x5001EC50`–`0x5001F04F`); MIDI OUT 1 at `0x5001F864` (buffer `0x5001F064`–`0x5001F863`, write pointer `0x5001F06A` after one note). That is 942's addresses minus `0x10`.                                                |

How to read the `PROBE` lines (`probe1`/`probe2`):

- `hb` is the probe's heartbeat at `0x502E0000`, one per pass. A pass ends in `dly_tsk(16)`.
- `entries` is how many times the firmware has called the converter (`0x502E0020`).
- `mout` and `min` are the MIDI OUT 1 and MIDI IN 1 ring write pointers (`0x5001F870`,
  `0x5001F05C`).
- `ms` is the kernel millisecond counter (`0x500D3C58`).
- `title` is the title table's two words (`0x5000099C`, `0x500009A0`): `0xF0000 + title`.
- `seen` is every bit seen set since the start in the switch bitmaps `0x5006BE40`–`0x5006BEBF`,
  as `offset:bits` (`52:01` is `0x5006BE52` bit `0x01`).

taskprobe needs MAME's debugger for its breakpoints (`DEBUG=1`). It also needs the rebuilt floppy
set: with the older `scd7000` image, the STYLE CONVERT screen shows an empty box and no
converter is called. The MIDI-OUT watchpoint and
enqueue breakpoint in its second half never fired. The ring header dump answered the question
instead.

    probes/cnv/build_probe.sh probes/cnv/probe2_task.s $T/probe2.img
    probes/cnv/run_probe.sh probes/cnv/probe2_task.cmd $T/probe2.img $T/run2
    probes/cnv/run_probe.sh probes/cnv/ram44.cmd $T/probe3.img $T/runram
    R=~/compartilhado/technics_romsets/floppy-rebuild-2026-10-18
    DEBUG=1 probes/cnv/run_probe.sh probes/cnv/taskprobe.cmd scd7000 $T/runtask \
      -rompath "$R/roms;./roms" -hashpath "$R/hash;hash"

`T` is any scratch directory. The converters' SHA-1s are probe1 `94df8164…`, probe2 `4c88cbcb…`
and probe3 `d471e36e…`.

**The `0x44000000` window on a real instrument.** The kn7000_disassembly notes identify it as
the KN7000's **256 KB battery-backed backup SRAM** (IC23, mirrored at `0x84000000`). It holds the
panel settings and the 104 PANEL MEMORY records, and `BackupSramTest` fixes its size exactly. The
MAME driver maps 16 MB of plain RAM there as a placeholder. The game keeps its data at
`0x44100000`–`0x44600000` and above, which works in MAME. On a real KN7000 that RAM is not there,
and if the decoding is partial, writes would land on the stored settings. See README-CNV.md,
Limits.

## Firmware addresses for 941

- **RAM.** The ring headers, switch bitmaps and millisecond counter come from the probes above.
- **Task services.** The 941 entry stubs are paired with 942's exports by the kernel routine each
  one enters (kn7000_disassembly `tools/itron_stubs.py`):
  - `cre_tsk` `0x4C03D0C8`
  - `sta_tsk` `0x4C03D8AB`
  - `exd_tsk` `0x4C03D5A1`

  The disassembly's ported symbol file had `0x4C03D8AB` as `ext_tsk` until 2026-10-18. probe2
  measured what it does: it returns 0 and starts the dormant task.
- **`dly_tsk`.** `addrmap.py` matches 942's `dly_tsk` `0x4C03E295` against the 941 image, with
  absolute operands masked, and finds one 941 candidate, `0x4C03DD6F`. It does not settle the
  other stubs: their first bytes are alike, so a short match is ambiguous and a long one fails.
- **File routines.** `open` in the current folder `0x48531AC5`, `fmmread` `0x48532463` and
  `fmmclose` `0x485323BC` are in kn7000_disassembly's symbol files.

## Does the game run right?

| probe                                                            | question                                                                           | result                                                                                                                                                                                                                                 |
|------------------------------------------------------------------|------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `awcnv_resdump.lua` + `resverify.py`                             | Are the resources AW.CNV unpacked on the instrument the bytes the SD build loads?  | **Yes.** All 1,730,376 bytes from `0x44200000` are identical to `build/res/AWP*.bin` laid end to end (SHA-1 `7a707a66…`), and so are the font and both string tables. The loader reported 0 errors and a 76,445 ms load (emulated).    |
| `awcnv_cksum.lua` + `../cksum_pages.py` + `../compare_frames.py` | Does the intro play pixel-identically to the reference VM (rustyworld)?            | **Yes.** 2612 of 2612 frames (floppy SHA-1 `b0d07c4e…`) are identical to rustyworld's `ref_checksums.log` (research-scratch `kn7000-aw-reference/`), as for the SP7001 build ([../CHECKSUM-COMPARISON.md](../CHECKSUM-COMPARISON.md)). |
| `awcnv_session.lua`                                              | Does a whole session work: start, input, quit, play again, leave, run again?       | **9 of 9 PASS**, listed below.                                                                                                                                                                                                         |
| `../../tools/leafcheck.py` (run by `make cnv`)                   | Does any routine entered with `call X, 0, 0` call something before making a frame? | **No.** 51 call targets checked, none unsafe. The first unpacker did this (`GetBits` called `ReadBE`): the nested call overwrote its return address, and the load hung.                                                                |

The session results (`awcnv_session.lua`, floppy SHA-1 `b0d07c4e…`):

    start    PASS  frame 51 at t=123 s; load 76846 ms, errors 0, task 10
    skip     PASS  part 0x3E82 at frame 52
    panel    PASS  var[0xFC] reached 1
    keybed   PASS  var[0xFA] reached 1
    quit     PASS  TASK_DONE=1 QUIT_REQ=1
    menus    PASS  frame stayed 117 after quitting; snapshot: Continue Next? YES/NO
    again    PASS  YES restarted the game (frame 11, task 10)
    leave    PASS  second quit, NO; snapshot shows the main screen
    rerun    PASS  reloaded AW.CNV runs at once: load 0 ms (data still in RAM)

Its snapshots show:

1. the intro;
2. the lake after the skip;
3. the firmware's message box after quitting;
4. "Continue Next?" with YES/NO;
5. the game again after YES;
6. the main screen after NO;
7. the game once more after running AW.CNV again.

How to run them, from `kn7000/` after `make floppy`:

    E=../../kn7000-emulator; cp $E/sdcard_from_real_kn7000.img $T/sd.img; chmod u+w $T/sd.img
    # resources, font and strings
    AWDUMP_DIR=$T $E/run.sh kn7000 -window -nothrottle -harddisk $T/sd.img \
      -flop $PWD/build/another_floppy.img -autoboot_script $PWD/probes/cnv/awcnv_resdump.lua
    python3 -I probes/cnv/resverify.py $T build/res ../../custom-kn5000-roms/anotherworld/src/hardcoded_data
    # the intro, frame by frame
    AWCK_BIN=$T/pages.bin AWCK_IDX=$T/pages.idx $E/run.sh kn7000 -window -nothrottle \
      -harddisk $T/sd.img -flop $PWD/build/another_floppy.img \
      -autoboot_script $PWD/probes/cnv/awcnv_cksum.lua
    python3 -I probes/cksum_pages.py $T/pages.bin $T/pages.idx $T/cnv_checksums.log
    python3 -I probes/compare_frames.py $T/cnv_checksums.log \
      ~/compartilhado/research-scratch/kn7000-aw-reference/ref_checksums.log
    # a whole session
    $E/run.sh kn7000 -window -nothrottle -harddisk $T/sd.img \
      -flop $PWD/build/another_floppy.img -snapshot_directory $T/snap \
      -autoboot_script $PWD/probes/cnv/awcnv_session.lua

`pages.bin` is 167 MB; it is regenerated, not kept.
