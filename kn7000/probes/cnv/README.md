# The KN7APP.BIN build: probes and acceptance tests

Measurements behind [README-CNV.md](../../README-CNV.md), the Another World build that a stock KN7000
runs through its SD loader: STYLE CONVERT runs `KN7LOAD.CNV` from the owner's floppy, and the loader
loads and calls `KN7APP.BIN` from the SD card. They run in the published overlay MAME build
(`kn7000-emulator`, which models IC23 as 256 KB of NVRAM repeating through CS1 and has a POWER OFF
input), with the owner's loader floppy and a copy of the real KN7000's SD card. The acceptance tests
(2026-10-20) come first; the probes that established the platform (2026-10-18, program 941, with
`AW.CNV`, the floppy-only predecessor that kept its data in the `0x44000000` window) follow.

**Addresses.** On 2026-10-21 (the DSP sound build, commit `f87fc55`) the game's variables moved up as one
block, from `0x502C0000`-`0x502C7FFF` to `0x502DF000`-`0x502E6FFF` (`src/platformcnv.inc`), and the image may
now reach `0x502C8000`. The Lua probes here name the new addresses, so they run against that build and later;
the results below for earlier builds were measured with the old ones (the git history has those scripts).

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

**Results for the speed build (2026-10-20, `KN7APP.BIN` `26aabecb...`, the loader floppy `b7a67de6...`,
overlay binary md5 `2a8e2fce...`; a copy of the emulator, `EMU`):**

| case                 | session  | report                        | ic23w | same                      | accepted          | pools               | area  | loader |
|----------------------|----------|-------------------------------|-------|---------------------------|-------------------|---------------------|-------|--------|
| `ic23 v13 ... blank` | 18 of 18 | AWPERF0, AWPERF1 (2335, 1801) | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... owner` | 18 of 18 | AWPERF0, AWPERF1 (2335, 1801) | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v16 ... blank` | 18 of 18 | AWPERF0, AWPERF1 (2335, 1801) | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |

`guard`: clean with "11 load(s) from the loader's service table" (the write routine and the program
build added); "src/main.s: 798 reference(s)"; `cnv_layout: ok`. The saved game IC23s are the same as
before, SHA-1 prefixes `eb26c67b...` (893 blank), `14f82423...` (893 owner), `bc2305dd...` (941 blank),
equal to the control runs'; so writing `AWPERF0.TXT` and `AWPERF1.TXT` to the card changed nothing that
is kept in IC23 or the pools. The `speed` check in all three: the speed page shown, the overlay on and
off, the old blit and back with the VM running on, IC23's live settings unchanged by PAGE UP and PAGE
DOWN. The game's RAM saw "loads 326936, SD reads 474104" foreign-but-expected writes (the loader zeroing
and loading a larger `KN7APP.BIN`), none foreign. The summaries: research-scratch
`sessions/2026-10-20_aw-perf/acceptance_summary_26aabecb.txt` and `session_*.txt`.

**Results for the build before (2026-10-20, through the loader: `KN7APP.BIN` `b952c2aa...`, the loader
floppy `b7a67de6...`, overlay binary md5 `2a8e2fce...`):**

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

### Through the program menu (2026-10-20, branch `launcher-folders`)

The same tests with the game in `AW\` of the program menu's card (technics-roms-disasm
`kn7000/tools/kn7menu`, `make card` there: the menu as the root's `KN7APP.BIN`, this game in `AW\`,
the ROM dumper's passes 5 to 9 in their folders). `run_menu_route.sh` is `run_cnv_tests.sh` with that
card (copied into the image by kn7menu's `fatimg.py`) and `awmenu_test.lua` is `awcnv_test.lua` with
the menu in front: the session picks "Another World" in the menu's list and presses RUN, and after
"Continue Next?" YES (which now brings the menu back) does so again. The control run is the same card
with `noop_app.s` as the root's `KN7APP.BIN`. The taps count the menu's and the trampoline's code as
the converter's, and allow a firmware write into the converter RAM while the menu runs only as a sector
read the menu asked for, into its destination.

| file                | what it is                                                                                         |
|---------------------|----------------------------------------------------------------------------------------------------|
| `run_menu_route.sh` | the runner: `blank-v13`, `ic23 BIOS BASE NAME` as in `run_cnv_tests.sh`, through the menu          |
| `awmenu_test.lua`   | the session through the menu: `menu`, `launch`, the 16 checks, `menu-again`, `menu-again-run`, ... |

    T=~/compartilhado/tmp/aw-menu-tests     # EMU=a copy of kn7000-emulator; CARDTREE=kn7menu's build/card
    make -C ../../technics-roms-disasm/kn7000/tools/kn7menu card
    probes/cnv/run_menu_route.sh $T blank-v13
    probes/cnv/run_menu_route.sh $T ic23 v13 $T/blank-v13/ic23 blank
    head -c 262144 ~/compartilhado/technics_roms/roms/kn7000/real_dump_v1.3_b893/pass5-run1/R8400000.BIN > $T/owner-ic23.bin
    probes/cnv/run_menu_route.sh $T ic23 v13 $T/owner-ic23.bin owner
    rm -f -- $T/owner-ic23.bin

**Results (2026-10-20, branch `launcher-folders`: the game `KN7APP.BIN` `b80b0205...` in `AW\`, the menu
`0566fba3...`, the loader floppy `b7a67de6...`, overlay binary md5 `5dfebca3...`, `-bios v13`):**

| case                       | session  | ic23w | same                      | accepted          | pools               | area  | loader |
|----------------------------|----------|-------|---------------------------|-------------------|---------------------|-------|--------|
| `ic23 v13 ... blank`, menu | 20 of 20 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... owner`, menu | 20 of 20 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |
| `ic23 v13 ... blank`, root | 16 of 16 | clean | identical, checksum valid | valid, store kept | identical, no write | clean | clean  |

The last row is `run_cnv_tests.sh` as it is, on this branch's build in the card's root, without the menu:
the game still runs as before when the loader starts it directly. Through the menu the session's 20
checks are the 16, plus the menu listing the six programs of its card, the launch (the launch block's
folder `AW`, prefix `AW\`, the game's `AW_PREFIX` `AW\`), and the same two after "Continue Next?" YES
brought the menu back. The saved IC23s equal the controls' and the ones every earlier route gave
(SHA-1 prefixes `eb26c67b...` blank, `14f82423...` owner); the pools `dde3dd9c...`. Every file the game
read came from `AW\` (474,104 bytes of SD reads into the record's destination, as from the root);
the area tap also counts the menu's sector reads (541,696 bytes, each inside the destination it asked
for) and the trampoline's writes (94,338), and no foreign write. The owner's IC23 copy and every image
derived from it were deleted after the run.

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

## Sound on the effects DSP (2026-10-21): the game's own samples

The DSP build (README-CNV.md, "Sound": `src/dsp.s`, `tools/dsp_mixer.py`) in one MAME session through the program
menu, as Felipe runs it. Light, as asked for this iteration: one session, no sweeps.

| file            | what it is                                                                                                 |
|-----------------|------------------------------------------------------------------------------------------------------------|
| `run_dsp.sh`    | the runner: builds the card (the menu as the root `KN7APP.BIN`, `build/sdcard/` as `AW\`), runs MAME       |
| `awcnv_dsp.lua` | the session (below) and a tap of the game's and the DSP's state every 0.25 s (`OUT/tap.txt`, `events.txt`) |
| `dsp_report.py` | the verdict: one line per check (its docstring says what each reads), "dsp_report: N of M checks"          |

    probes/cnv/run_dsp.sh ~/compartilhado/tmp/aw-dsp/run    # from kn7000/; DISPLAY=:0; about 10 minutes

The session (program 893, `-bios v13`; the owner's loader floppy as released; a fresh copy of the real card): DISK
MENU, STYLE CONVERT, OK; the menu; "Another World", RUN; the firmware search, the global files, the DSP set up and
the whole bank sent; the splash skipped (`NO_SPLASH`, as `awcnv_cksum.lua`); the intro with no input; PART SELECT
RIGHT 2 at intro + 25 s (tone generator), + 35 s (off), + 45 s (DSP again); EXIT held 2 s at intro + 60 s; EXIT;
"Continue Next?" YES; the menu, RUN again (the bank must not be sent again); 15 s of the game; EXIT held; EXIT; NO;
a C4 on the keybed. The recording (`OUT/run.wav`) is the game's own music: never commit it.

What it showed, for `KN7APP.BIN` `a2fbbaa6...` (the run's files: `dsp-results-2026-10-21/`; the published overlay,
md5 `3077b137...`; the menu `0566fba3...`), `dsp_report: 11 of 11 checks`:

| check      | result                                                                                                                                                  |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| `dead`     | the firmware's dead flag 0 at all 771 samples after the boot (20-212.5 s)                                                                               |
| `setup`    | the 8-step firmware search 6.8 s from RUN (DSP routines found: `1F`); the mixer loaded, read back, hooked; the whole bank, 171,576 words, in 25.9 s     |
| `hooked`   | through the intro in DSP mode PM `0x8080` = `06BE04008200`, PM `0x80A0` = `06BE04008296`; MSGR7 and unit 9's count both 44,100 a second                 |
| `voices`   | all eight voices sounded (the music's in 63, the effects' in 46 of 93 quarter-seconds); unit 0's and unit 9's returns carried the mix, peak 1,224,576   |
| `midi`     | MIDI messages sent: 0 in the DSP mode, 76 in the tone generator's, 0 when off, 0 in the DSP mode again                                                  |
| `modes`    | TG: both slots back as at boot, nothing hooked (35 samples); DSP again: both hooked (54 samples)                                                        |
| `restored` | after each quit both slots as at boot, MSGR4-MSGR7 0; DM `0xC003` (the reverb's store of I6) 1 value while hooked, 16 in the 4 s after: the reverb runs |
| `again`    | YES, the menu, RUN: the bank found in SDRAM by its marker, not sent again (the DSP setup 0.1 s)                                                         |
| `sound`    | the recording: -240 dBFS before the game; the intro on the DSP -61.9 to -38.4 dBFS a second, every second more than 20 dB above that                    |
| `music`    | the 47 quarter-seconds in which only the music's voices sounded: -52.1 to -43.4 dBFS, all of them audible                                               |

The tone generator's notes in MAME ring on after their note-off (the overlay's tone generator, as in "Sound" below),
so after the TG interval the recording and unit 0's input stay loud (-29 to -28 dBFS) through OFF and later: that
is not the DSP. MAME mixes unit 9's return only while the CHORUS is on (its bridge), so the recording heard the mix
through unit 0's return (REVERB on, the default); the tap shows unit 9's return carrying the same mix. In MAME the
DSP's sound is about 10 dB below the tone generator's for the same intro: MAME's return level is not calibrated.
Not checked here: the help screen's mode line, a part switch, the watchdog (the firmware stopping the calls), a
program build other than 893.

## Sound (2026-10-20): the game as a MIDI source on the firmware's receive ring

`src/audio.s` (README-CNV.md, "Sound") writes MIDI into the MIDI IN 1 receive ring as the RX ISR does.
These answer whether the firmware takes it, and whether the intro still runs with the music's sync
marks. All on program 893 (`-bios v13`) through the owner's loader floppy, each one MAME run with
`-wavwrite` (the commands below; `$F` a scratch directory holding a card copy with `build/sdcard/`
added, the loader floppy image and, for the last, the SMF; never `/tmp`).

| file                  | question                                                                                                                         |
|-----------------------|----------------------------------------------------------------------------------------------------------------------------------|
| `awcnv_midiprog.lua`  | before audio.s: are bytes written into the ring consumed and played? do program change and bank select work on PART 4 and 10?    |
| `midiprog_spectra.py` | its reading: flatness, peaks, level and C4's harmonics per segment                                                               |
| `awcnv_sound.lua`     | the sound build's intro with no input: messages sent / dropped, ring rd vs wr, rows, PLAY_SOUNDs, var 0xF4, the toggle, the quit |
| `wavrms.py`           | level (dBFS) and dominant frequency per window of a recording                                                                    |
| `awcnv_noteoff.lua`   | are the game's note-offs honoured as MIDI IN's are? the same notes through the ring and through the port                         |
| `gen_noteoff_mid.py`  | the SMF for awcnv_noteoff.lua's MIDI IN half (`-midiin1`)                                                                        |
| `noteoff_levels.py`   | its reading: each note's level from note-on to 2.5 s after its note-off                                                          |

What they showed:

| probe                | KN7APP.BIN    | result                                                                                                                                                                                                                                                                                                                                                                                                                             |
|----------------------|---------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `awcnv_midiprog.lua` | `e3ee3a40...` | every byte consumed; program 80 alone and with bank 121/0 make PART 4 a square wave (C4's even harmonics 49-58 dB down), program 48 sawtooth-like strings, program 0 piano; channel 10 is a drum part as it is and after bank 120/0 (a 57 Hz thump on key 36, 216 Hz on 38)                                                                                                                                                        |
| `awcnv_sound.lua`    | `15f5c57e...` | 1,704 messages, 0 dropped, rd = wr at every sample; 951 rows; the 24 marks of module 0x07 in order into var 0xF4; the intro stops the music at mark 49 and reaches the lake by itself (tick about 2,660); 211 PLAY_SOUNDs; silent before the game, -27 to -49 dBFS in the intro; nothing sent while RIGHT 2 had the sound off; the quit's all notes off / all sound off / reset all controllers on channels 4-7 and 10-14 consumed |
| `awcnv_noteoff.lua`  | `97fbd9e6...` | ring and MIDI IN port alike: GM 80 falls about 40 dB within 1 s of its note-off (C4 132 -> 89 dB, G4 128 -> 91), GM 0 rings on either way (E4 92 -> 90, A4 110 -> 108): the overlay's tone generator, not the path                                                                                                                                                                                                                 |

In MAME notes of some voice classes ring on after their note-off whatever sends them (kn7000_mame
`notes/tg-envelope-implementation-plan.md`: the overlay releases them only on a keybed key-up), so the
recordings cannot show that every note ends; the unit can.

    K=$PWD; E=../../kn7000-emulator; F=~/compartilhado/tmp/aw-sound/feas      # from kn7000/
    cp $E/sdcard_from_real_kn7000.img $F/sd.img; chmod u+w $F/sd.img
    python3 -I ../../technics-roms-disasm/kn7000/tools/sd_addfile.py $F/sd.img \
      $(cd build/sdcard && for f in *; do printf '%s build/sdcard/%s ' "$f" "$f"; done)
    cp ../../technics-roms-disasm/kn7000/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img $F/floppy.img
    cd $E && AWS_OUT=$F/sound.log DISPLAY=:0 ./kn7000 kn7000 -bios v13 -rompath ./roms -pluginspath ./plugins \
      -skip_gameinfo -window -nothrottle -harddisk $F/sd.img -flop $F/floppy.img -nvram_directory $F/nv \
      -cfg_directory $F/cfg -wavwrite $F/sound.wav -autoboot_script $K/probes/cnv/awcnv_sound.lua
    python3 $K/probes/cnv/wavrms.py $F/sound.wav 60 246 1.0
    # awcnv_noteoff.lua: the same, with AWN_OUT, a fresh card copy, the SMF and its reading:
    python3 $K/probes/cnv/gen_noteoff_mid.py $F/noteoff.mid      # then add -midiin1 $F/noteoff.mid
    python3 $K/probes/cnv/noteoff_levels.py $F/noteoff.wav

The recordings are of the game's own music: regenerate them, never commit them. The card copy is
121 MB: delete it afterwards.

## Speed (2026-10-20): where a frame's time goes

On the owner's KN7000 the game ran, but its frame rate was very low. MAME gives every memory access the
same cost, with no wait states, so it cannot show why; what it can do is count the accesses the game
makes per VM tick in each region, and check that a faster blit leaves the LCD as it was. The probes
run through the loader exactly as the acceptance tests do (`run_perf.sh`: the owner's floppy, a copy
of the real card with `CARDFILES` added, fresh NVRAM, program 893; the game's `AWPERFn.TXT` files are
copied off the card before it is deleted):

| file              | question                                                                                                                                                                           |
|-------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `run_perf.sh`     | the runner: one MAME run with a given autoboot script and card files; the card copy is deleted after                                                                               |
| `awcnv_perf.lua`  | per VM tick: the game's stores into the LCD frame (by size), its loads from it, its accesses to the pages and to the rest of its RAM; the firmware's LCD stores; the emulated time |
| `awcnv_fwlcd.lua` | while the game runs, when and where does the firmware draw on the LCD? 10 s with no input, then each panel button and a key, 4 s each; or (`AWL_INTRO=1`) through the intro        |
| `lcd_cost.py`     | what the counted LCD accesses cost at the unit's measured times (pass 9), or at others given                                                                                       |
| `awcnv_lcd.lua`   | at every VM tick of the intro and the lake: is the whole LCD frame what the old blit made of the same VM state? snapshots for a byte comparison between builds                     |
| `awcnv_speed.lua` | the owner's run on the instrument, in MAME: the overlay, the old blit and back, the speed page, quitting; what the game measures in MAME's time; `AWPERF0.TXT`                     |

**Why it was slow.** Before (`KN7APP.BIN` `b952c2aa...`, the intro, ticks 1-300, mean per tick):

| region              | accesses per tick                                |
|---------------------|--------------------------------------------------|
| LCD frame, 16-bit   | 128,000 stores: the window, 64,000 pixels, twice |
| LCD frame, 32-bit   | 89,600 stores: the black border, 44,800, twice   |
| VM pages            | 141,694 loads, 21,231 stores                     |
| the rest of its RAM | 6,470 loads, 2,188 stores                        |
| the firmware's LCD  | 0 stores                                         |

Every tick blitted the front page twice (the bytecode's own blit, then `NextThread`'s at the end of
every frame) and repainted the whole border with each blit: 217,600 stores, about 614 KB, into the LCD
frame per tick, whatever changed. The ROM dumper's pass 9 measured the costs on the owner's unit
(technics-roms-disasm `cnv_romdump`, 2026-10-20, run by the main session): the core runs at 64 MHz, a
cached work-RAM access takes one 15.6 ns cycle (a new 16-byte line 389 ns to load), and the LCD frame
is on a 16-bit bus with four wait states (MEMCTR3 `0x0424`, which also covers the DSP's ports): a
16-bit store 439 ns, a 32-bit store 888 ns (two accesses), a 16-bit load 694 ns. At those times
`lcd_cost.py` puts the old build's LCD stores at **136 ms per tick**, a ceiling of 7 frames per second
before any other work, where the gameplay asks for 25 or 50. (Before pass 9 a model from the bus
set-up, 4 or 7 waits on a 16-bit bus at a guessed 16 MHz, gave 115 or 173 ms: `lcd_cost.py --model`.)

**The firmware's own drawing.** The firmware drew on the LCD before the first VM frame (its text
screen, 458,880 stores from `0x48414F92`), and with the game running it drew nothing in 10 s with no
input or after R1/R2 OCTAVE + / -, SUSTAIN (twice), PART SELECT RIGHT 1 / LEFT, PAGE UP (twice), PAGE DOWN,
HELP, EXIT, OTHER PART & FR or a keybed key. But through the intro (`AWL_INTRO=1`) it repainted its whole
text screen twice (305,920 stores, `0x48414F92`) between ticks 2600 and 2800, when the intro hands over
to the lake and the lake's files load; in a traced run of the new build (`AWL_TRACE`) that painting was
split around one of the game's frames (301,406 stores before the frame's check, 4,514 after it), so it is
not confined to one yield of the game and may land at any moment. The old blit painted over it at every
blit. **DISPLAY HOLD**: in the first run, pressed in the intro, the firmware repainted the
whole screen (152,960 stores) and stopped calling the converter for the rest of the run (so EXIT could
no longer end the game); in the second, pressed on the level-code screen, it did nothing. Do not press
DISPLAY HOLD while the game runs.

**After** (`KN7APP.BIN` `26aabecb...`, the same ticks): **2,036 32-bit stores into the LCD frame per tick**
(most ticks a few hundred; 76,800 for each of the two full repaints that follow the intro's load) and
the 47 sentinel loads, **1.84 ms per tick** at the unit's times (from 135.84); the pages' loads 45,931,
their stores 16,718; the rest of the RAM 8,358 loads and 2,271 stores (the measuring). In MAME's own
time a tick of the intro took 45.9 ms on average, from 122.7 (the bytecode asks for 40).

| check                                  | before (`b952c2aa`) | after (`26aabecb`)                                                |
|----------------------------------------|---------------------|-------------------------------------------------------------------|
| LCD stores per tick (16 / 32-bit)      | 128,000 / 89,600    | 0 / 2,036                                                         |
| LCD time per tick at pass 9's costs    | 135.84 ms           | 1.84 ms                                                           |
| the intro's pages against rustyworld   | 2612 of 2612        | 2612 of 2612                                                      |
| LCD = the old blit's picture, per tick | 3601 of 3601        | 3600 of 3601: tick 2612, the firmware painting, put right at 2613 |
| LCD snapshots every 100 ticks          | -                   | 37 of 37 byte-identical to the old build's                        |

The intro's page checksums of the new build: research-scratch
`sessions/2026-10-20_aw-perf/intro_checksums_kn7app_26aabecb.log` (`awcnv_cksum.lua` through
`run_perf.sh`, then `cksum_pages.py` and `compare_frames.py` as above). The one tick: while the firmware
was repainting its text screen (above), 5,347 pixels showed its
painting at the check; one sentinel pixel caught it after the next yield and the next blit repainted
everything. An earlier version with 16 sentinels and no repaints after a load (`c1fd72bc`) missed the
same painting in the border for 500 ticks, until the periodic repaint; hence the 47 sentinels read
after each yield and the repaints 5 and 30 frames after each load.

**The game's own figures in MAME** (`awcnv_speed.lua`, `26aabecb`, MAME's time, no wait states; the
intro): new blit 25.1 frames per second, 39.8 ms a frame (blit 7.9 ms, yield 31.1); old blit (PAGE
DOWN) 8.7 frames per second, 114.1 ms a frame (blit 97.1, border 9.1); over the run 25.0 and 8.7
frames per second. The speed page and the overlay in their snapshots fit their places; `AWPERF0.TXT`,
1,979 bytes, holds the same page, the figures per part and blit, the benchmark and the registers.
(MAME reads 0 from the bus controller's registers and gives every access the same 43 ns; the unit's
figures will say what matters.)

    T=~/compartilhado/tmp/aw-perf    # EMU=a copy of kn7000-emulator; CARDFILES=the build's card files
    probes/cnv/run_perf.sh $T/base-perf probes/cnv/awcnv_perf.lua           # AWP_MAX=300
    probes/cnv/run_perf.sh $T/base-fwlcd2 probes/cnv/awcnv_fwlcd.lua         # DISPLAY HOLD last
    AWL_HOLD_EARLY=1 probes/cnv/run_perf.sh $T/base-fwlcd probes/cnv/awcnv_fwlcd.lua   # ... as the first run
    AWL_INTRO=1 probes/cnv/run_perf.sh $T/base-fwintro probes/cnv/awcnv_fwlcd.lua
    python3 -I probes/cnv/lcd_cost.py $T/base-perf/perf.tsv $T/fin-perf/perf.tsv [--model]
    AWL_PAL=0x$(grep ' palette$' build/kn7app.map | cut -c3-10) AWL_TRACE=2605-2650 \
      probes/cnv/run_perf.sh $T/fin-lcd probes/cnv/awcnv_lcd.lua           # the same for the old build
    for f in $T/fin-lcd/lcd_*.bin; do cmp $f $T/base-lcd/$(basename $f); done
    probes/cnv/run_perf.sh $T/fin-speed probes/cnv/awcnv_speed.lua
    AWCK_BIN=$T/fin-ck/pages.bin AWCK_IDX=$T/fin-ck/pages.idx probes/cnv/run_perf.sh $T/fin-ck probes/cnv/awcnv_cksum.lua

The acceptance tests (above) gained two checks for this build: `speed` (the speed page, the overlay on
and off, the old blit and back with the VM running, IC23's header unchanged) and `report` (the first
quit leaves `AWPERF0.TXT`, the second `AWPERF1.TXT` beside it, the text the game built).

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
