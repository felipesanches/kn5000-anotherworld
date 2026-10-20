# The KN7APP.BIN build: probes and acceptance tests

Measurements behind [README-CNV.md](../../README-CNV.md), the Another World build that a stock KN7000
runs through its SD loader: STYLE CONVERT runs `KN7LOAD.CNV` from the owner's floppy, and the loader
loads and calls `KN7APP.BIN` from the SD card. They run in the published overlay MAME build
(`kn7000-emulator`, which models IC23 as 256 KB of NVRAM repeating through CS1 and has a POWER OFF
input), with the owner's loader floppy and a copy of the real KN7000's SD card. The acceptance tests
(2026-10-20) come first; the probes that established the platform (2026-10-18, program 941, with
`AW.CNV`, the floppy-only predecessor that kept its data in the `0x44000000` window) follow.

## Acceptance tests (2026-10-20): through the loader, program 893 and 941

`run_cnv_tests.sh OUT CASE...` runs them, after `make sdcard`; `OUT` is a scratch directory. Each
prints `run_cnv_tests: <case> PASS|FAIL detail` and appends it to `OUT/summary.txt`. Every MAME run
boots with the loader floppy exactly as released (technics-roms-disasm
`kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img`, SHA-1 `b7a67de6...`, holding
`KN7LOAD.CNV` `6b81f382...`) and a fresh copy of the real KN7000's SD card (`sdcard_from_real_kn7000.img`)
with the 44 files of `build/sdcard/` added to its root by `sd_addfile.py`; the copy is deleted when
the run ends.

| file                      | what it is                                                                                   |
|---------------------------|----------------------------------------------------------------------------------------------|
| `run_cnv_tests.sh`        | the runner: the cases below, each MAME run in its own directory with fresh cfg and NVRAM     |
| `awcnv_test.lua`          | the MAME side: the whole game session (or the control, or a plain boot) and every tap        |
| `noop_app.s`              | the control application: a `KN7APP.BIN` that ends the conversion on its first call           |
| `guard_loader_selftest.s` | what `ic23_guard.py --loader` must find: 7 planted references, and the 2 loads it must allow |
| `ic23_file.py`            | a saved IC23's stored and computed header checksum (copied from kn7000_mame)                 |
| `ic23_diff.py`            | which regions of two IC23 images differ (copied from kn7000_mame)                            |
| `awcnv_cksum.lua`         | the intro frame by frame, for the pixel comparison with the reference VM                     |

The questions, and how each is answered:

| case / check          | question                                                                                        | how                                                                                                                                                                                                                                                                 |
|-----------------------|-------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `guard`               | (a) does KN7APP.BIN name any address in CS1, the user pools or the loader? is the map in range? | `tools/ic23_guard.py --loader` must say "clean" for `src/cnv_main.s`, find exactly the 7 planted hits of `guard_loader_selftest.s` and the SP7001 build's references; `tools/cnv_layout.py` must accept the memory map                                              |
| `blank-v13`, `-v16`   | a realistic empty baseline                                                                      | boot with no IC23 file, POWER OFF at 40 s: the firmware initialises IC23 and stamps it                                                                                                                                                                              |
| `ic23` ... `session`  | (b) does a whole session work?                                                                  | `awcnv_test.lua` drives DISK MENU > STYLE CONVERT > OK (the loader), the splash, the intro, a key to skip it, the panel and keybed controls, HELP, two level codes, quitting, YES (the loader reloads the game), quitting, NO; 16 checks                            |
| `ic23` ... `ic23w`    | (c) does anything of the converter area write into CS1?                                         | a write tap over all of CS1 (both views), per PC: none from `0x502B8000`-`0x502E7FFF` (the loader's code or the game's), none past IC23's first 256 KB                                                                                                              |
| `ic23` ... `same`     | (d) is IC23 exactly as it would have been without the game?                                     | the same baseline, a control run (the same floppy, card and menus, `noop_app.s` as `KN7APP.BIN`, NO) and the game run, both ending with POWER OFF: the saved IC23s must be byte-identical, checksum valid                                                           |
| `ic23` ... `accepted` | (d) does the next boot accept it?                                                               | each saved IC23 booted once more: the firmware's own verdict byte (893 `0x5006CC7C`, 941 `0x5006CC80`) must be 0, and the PANEL MEMORY store must come out as it went in (no factory reset)                                                                         |
| `ic23` ... `pools`    | (e) are the user-memory pools untouched?                                                        | `0x50180000`-`0x50297FFF` dumped just before POWER OFF in both runs: identical; and a write tap: none from the converter area                                                                                                                                       |
| `ic23` ... `area`     | (f) does anything else write into the game's RAM while it runs?                                 | a write tap over `0x502BA000`-`0x50379FFF` (and its `0x90` view) but the mailbox page: every write not from the game's code, classified: the firmware's and the loader's loads, the SD reads the game asked for (into the current file's destination), or "foreign" |
| `ic23` ... `loader`   | (g) is the loader left alone?                                                                   | a write tap over the loader's resident area `0x502B8000`-`0x502B9FFF` (and its `0x90` view), in both runs: no write from the game's code, and none but the loader's own once it has filled in its service table                                                     |

The session's `resources` check compares, each time a part has become resident, every resource in
`RES_TAB` with the reference unpack (`build/res/resource-0xNN.bin`, or the card file
`build/res/sdfiles/AWRxx.AW` for a bitmap kept packed).

Commands, from `kn7000/` after `make sdcard` (`T` is a scratch directory; the owner's IC23 is private
and used only from a copy, deleted afterwards):

    T=~/compartilhado/tmp/aw-kn7load-tests    # EMU=... to run another copy of the overlay emulator
    probes/cnv/run_cnv_tests.sh $T guard blank-v13 blank-v16
    probes/cnv/run_cnv_tests.sh $T ic23 v13 $T/blank-v13/ic23 blank
    probes/cnv/run_cnv_tests.sh $T ic23 v16 $T/blank-v16/ic23 blank
    head -c 262144 ~/compartilhado/technics_roms/roms/kn7000/real_dump_v1.3_b893/pass5-run1/R8400000.BIN > $T/owner-ic23.bin
    probes/cnv/run_cnv_tests.sh $T ic23 v13 $T/owner-ic23.bin owner
    rm -f -- $T/owner-ic23.bin

**Results (2026-10-20, through the loader: `KN7APP.BIN` `b952c2aa...`, the loader floppy `b7a67de6...`,
overlay binary md5 `2a8e2fce...`):**

| case                 | session  | ic23w | same                      | accepted          | pools               | area  | loader |
|----------------------|----------|-------|---------------------------|-------------------|---------------------|-------|--------|
| `ic23 v13 ... blank` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... owner` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v16 ... blank` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |

`guard`: "ic23_guard: src/cnv_main.s: clean" with "9 load(s) from the loader's service table
0x502B9E00-0x502B9E6B allowed, nothing else in 0x502B8000-0x502B9FFF"; the self-test "7 reference(s)";
"src/main.s: 670 reference(s)"; "cnv_layout: ok -- everything in 0x502BA000-0x50379FFF, off the
mailbox page and the loader's 0x502B8000-0x502B9FFF, no overlaps".

In all three sessions: the loader found all seven of its services (`0x7F`); the game's search printed
the `aw_find_fw.py` column of its build, and took from the loader's table the SD backends (893: open
`0x48564A88`, read `0x48564D70`, close `0x48564B4F`; 941: `0x4856580E`, `0x48565AF6`, `0x485658D5`) and
its no-op drive switch `0x502B85BE`; no panel press lost, no failed file read, 8 parts made resident with
46 resources compared to the reference unpack, 0 differing. The saved game IC23s' SHA-1 (prefix) equal
the controls', and the ones `AW.CNV` gave: `eb26c67b...` (893 blank), `14f82423...` (893 owner),
`bc2305dd...` (941 blank). The tap reports, per writer: the game's RAM saw the boot, the firmware
zeroing the converter area when it loaded the loader (893 pc `0x48478E7D`, 941 `0x48479040`), the
loader zeroing the application area (`0x502B8187`, twice: at the start and after YES) and the SD reads
(893 `0x4854BA0D`, `0x4C003031`; 941 `0x4854C0E0`, `0x4C003046`), of `KN7APP.BIN` and, into each record's
destination, of the game's files: "loads 313144, SD reads 474104" writes, no foreign one. The loader's
area saw the firmware load `KN7LOAD.CNV` (14,256 writes) and then only the loader's code, in the
control runs too. The firmware's own IC23 writes during the game are the OCTAVE and SUSTAIN settings'
(893 `0x4C01F310`-`0x4C01F39C`, 941 `0x4C01F325`-`0x4C01F3B1`). The pools saw no write after boot in the
game runs; in the control runs, after NO, the firmware itself (893 `0x48455812` and a copy at
`0x4C003031`, 941 `0x484558DB`, `0x4C003046`) rewrote part of `0x501A5000`-`0x501A6FFF`, ending with the
same bytes (the pools are identical at POWER OFF), which it did not with `AW.CNV` as the control. The
stack pointer seen while the game's code runs stays in `0x5038DD2C`-`0x503AD844`, the kernel's.
Load times per part are in README-CNV.md, "How it was checked"; the loader route needed no fix.

What each run printed is in `OUT/summary.txt` and `OUT/<bios>-<name>/session.txt`; the tap reports
are `ic23.txt`, `pools.txt`, `awarea.txt` and `loader.txt` in each run's directory.

### Before the loader: AW.CNV from its own floppy (2026-10-20, retired)

The same tests ran first on `AW.CNV`, the game as a style converter of its own on a floppy with its
files (README-CNV.md, "History"; harness and build at commit `dbc7a2c`). They passed on the overlay
binary of that day (md5 `ed41d01b...`, AW.CNV `7aab745c...`, floppy `b7214529...`), and again,
unchanged, as the baseline for this work on the binary the loader route was tested on (md5
`2a8e2fce...`, which takes the 1 kHz tick from timer 4, gives the DSP handshake once per DSP frame
and lets the DSP read MSGR back):

| case                 | binary        | session  | ic23w | same                      | accepted          | pools               | area  |
|----------------------|---------------|----------|-------|---------------------------|-------------------|---------------------|-------|
| `ic23 v13 ... blank` | `ed41d01b...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v13 ... owner` | `ed41d01b...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v16 ... blank` | `ed41d01b...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v13 ... blank` | `2a8e2fce...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v13 ... owner` | `2a8e2fce...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |
| `ic23 v16 ... blank` | `2a8e2fce...` | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean |

In all six, the saved game IC23 equals the control's, and their SHA-1s (prefix) are the same on both
binaries: `eb26c67b...` (893 blank), `14f82423...` (893 owner), `bc2305dd...` (941 blank). The
baseline's `guard` and blank boots also matched (the same stamped checksum `6e1e9dd0` for both blank
IC23s); its full output: research-scratch `aw-kn7load-2026-10-20/baseline-summary.txt`.

In those sessions the floppy's loads took (emulated): the splash 6.5 s, the intro 5.6 s, the lake
4.7 s, the prison 9.8 s, the city 13.3 s (`session.txt` of each run), against well under 2 s each
from the SD card through the loader (above).

**How the runs went wrong before they went right** (AW.CNV, each fixed in its own commit, 2026-10-20;
the fixes are all in `KN7APP.BIN` too):

- the load guard refused the city's last bitmap: it measured a packed bitmap by its unpacked size;
- a failed part list was retried on every call, and YES could not start a new game;
- the firmware still acts on OCTAVE and SUSTAIN while the game runs (`awcnv_panelsettings.lua`): the
  session now presses them in pairs that cancel and checks the settings end as they began;
- with the session driven by `emu.register_periodic`, OK on STYLE TYPE SELECT was lost in every run
  with the owner's IC23 and with a stamped one on 941; driven by the emulated frame and confirming
  each press in the firmware's bitmap, no press was lost in those runs;
- with the owner's IC23, OTHER PART & FR's release was lost while the main task was in a part's first
  file read, the bitmap kept the button down and the emulated panel delivered nothing more (36
  presses lost; the bitmap dump on each lost press showed CPC_SEG5 `0x01` stuck while the converter
  kept being called). AW.CNV now starts a part's loads only once the panel is let go;
- once, the intro's polygons failed to load and loaded on a rerun; a failed file is now retried.

**The panel buttons while AW.CNV runs** (`awcnv_panelsettings.lua`, -bios v13, AW.CNV `61fb4601`,
presses each button once while the game runs and lists the IC23 header bytes each press changed):

| button (game control)             | header bytes changed                              |
|-----------------------------------|---------------------------------------------------|
| PART SELECT RIGHT 1 (RIGHT)       | none                                              |
| PART SELECT LEFT (LEFT)           | none                                              |
| R1/R2 OCTAVE + (UP)               | `0x6EA`: `0x40` -> `0x4C`                         |
| R1/R2 OCTAVE - (DOWN)             | `0x6EA`: `0x4C` -> `0x40`                         |
| SUSTAIN (FIRE)                    | `0xCE`: `0x25` -> `0x2D`                          |
| SUSTAIN again                     | written with the next panel event, back to `0x25` |
| PART SELECT RIGHT 2, DISPLAY HOLD | none                                              |

(In the session, where SUSTAIN comes before any PART SELECT, it changes `0x03A` instead: the sustain
of whichever part is selected.)

Commands for these two, through the loader as the acceptance tests run (`$T` a scratch directory; the
card copy is 121 MB and `pages.bin` 167 MB: delete both afterwards):

    K=$PWD; E=../../kn7000-emulator; R=$T/panelset; mkdir -p $R/nv/kn7000_4 && cp $T/blank-v13/ic23 $R/nv/kn7000_4/
    F=../../technics-roms-disasm/kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img
    cp $F $R/floppy.img; cp $E/sdcard_from_real_kn7000.img $R/sd.img; chmod u+w $R/sd.img $R/floppy.img
    python3 -I ../../technics-roms-disasm/kn7000/tools/sd_addfile.py $R/sd.img \
      $(cd build/sdcard && for f in *; do printf '%s build/sdcard/%s ' $f $f; done)
    (cd $E && ./kn7000 kn7000 -bios v13 -rompath ./roms -skip_gameinfo -window -nothrottle \
      -harddisk $R/sd.img -flop $R/floppy.img -nvram_directory $R/nv \
      -autoboot_script $K/probes/cnv/awcnv_panelsettings.lua)
    # the intro frame by frame
    (cd $E && AWCK_BIN=$T/pages.bin AWCK_IDX=$T/pages.idx ./kn7000 kn7000 -bios v13 \
      -rompath ./roms -skip_gameinfo -window -nothrottle -harddisk $R/sd.img \
      -flop $R/floppy.img -nvram_directory $R/nv2 -autoboot_script $K/probes/cnv/awcnv_cksum.lua)
    python3 -I probes/cksum_pages.py $T/pages.bin $T/pages.idx $T/cnv_checksums.log
    python3 -I probes/compare_frames.py $T/cnv_checksums.log \
      ~/compartilhado/research-scratch/kn7000-aw-reference/ref_checksums.log

The intro on 893 through the loader (`KN7APP.BIN` `b952c2aa...`): "first frame at t=63.2 s; global
files loaded in 831 ms, load errors 0, task 10", "captured 2613 frames (last tick 2612); part loads 3,
load errors 0, guard 0", and `compare_frames.py`: 2612 of 2612 frames identical to the reference
(the checksum log: research-scratch `aw-kn7load-2026-10-20/intro_checksums_kn7app.log`). With `AW.CNV` and its floppy (`b7214529...`) the same check
gave "captured 2613 frames (last tick 2612); part loads 3, load errors 0, guard 0", and 2612 of 2612
frames identical.

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

**The `0x44000000` window on a real instrument** is chip select CS1, which is IC23 alone: the
KN7000's **256 KB battery-backed SRAM** (also at `0x84000000`, uncached), holding the panel settings
and the 104 PANEL MEMORY records. It has address pins A1-A17 only, so it **repeats every 256 KB through
the whole window**; the owner's unit confirmed it on 2026-10-20 (SURVEY2 dump: 7 of 7 copies equal).
`ram44.cmd` above measured MAME's 16 MB placeholder RAM, so "nothing above `0x4403FFFF`" says what
the firmware addresses, not that the rest is free: on an instrument every address there is the panel
memories. The 2026-10-18 AW.CNV kept its data at `0x44050000`-`0x4480CFFF`; the current one names
no address in CS1 at all (README-CNV.md, "Memory"), which `tools/ic23_guard.py` checks at every
build and the acceptance tests above measure.

## Firmware addresses for 941 (2026-10-18)

AW.CNV no longer carries these: it finds them, and every other build's, by search
(`src/fwfind.s`, `tools/aw_find_fw.py`; table in README-CNV.md). The values found for 941 equal the
ones below.

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

## Does the game run right? (2026-10-18, the earlier AW.CNV, program 941)

These ran the earlier AW.CNV, which loaded the whole game into the `0x44000000` window at start.
`awcnv_resdump.lua`, `resverify.py` and `awcnv_session.lua` read that layout; they are superseded by
`awcnv_test.lua` and are in git history (`97a9cd9`). `awcnv_cksum.lua` follows the current layout.

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
