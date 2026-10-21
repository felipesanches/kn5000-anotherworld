# The DSP sound build in MAME, 2026-10-21

What `run_dsp.sh` wrote for `KN7APP.BIN` `a2fbbaa6c660020757b543878fc2a6cdc46ba3f2` (the commit that adds this
folder), kept because README-CNV.md and `../README.md` quote it. `versions.txt` names the emulator, the menu, the
floppy and the card image. Regenerate with `probes/cnv/run_dsp.sh OUT` from `kn7000/`.

| file           | what                                                                           |
|----------------|--------------------------------------------------------------------------------|
| `report.txt`   | `dsp_report.py`'s verdict: 11 of 11 checks                                     |
| `events.txt`   | what the session pressed and saw, with emulated times (`awcnv_dsp.lua`)        |
| `tap.txt`      | the game's and the DSP's state every 0.25 s (its first line names the columns) |
| `versions.txt` | emulator md5, `KN7APP.BIN` and menu SHA-1, floppy and card image SHA-1         |

Not kept: the recording (`run.wav`, the game's own music) and the snapshots.
