#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_dsp.sh OUT -- the DSP sound build in one MAME session, through the program menu, as Felipe runs it
# (awcnv_dsp.lua says what it plays; dsp_report.py what it checks). The light check of iteration 2 of our own
# program on the effects DSP (README-CNV.md, "Sound"):
#   * a card tree: the program menu (technics-roms-disasm kn7000/tools/kn7menu, built into OUT/menu) as the root
#     KN7APP.BIN, and this build's build/sdcard/ as AW\ with a MANIFEST.TXT, copied into a fresh copy of the real
#     KN7000's SD card (kn7menu's fatimg.py put);
#   * the published overlay emulator (EMU, default ~/compartilhado/kn7000-emulator), -bios v13 (program 893, the
#     owner's), the owner's loader floppy as released, -wavwrite OUT/run.wav, awcnv_dsp.lua as the autoboot script;
#   * dsp_report.py OUT: OUT/report.txt, its last line "dsp_report: N of M checks".
# OUT is scratch (~/compartilhado/tmp/..., never /tmp); the card and floppy copies are deleted afterwards. The
# recording is the game's own music: never commit it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
MENU="$DISASM_REPO/tools/kn7menu"
FLOPPY="$DISASM_REPO/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img"
O="$(mkdir -p "$1" && cd "$1" && pwd)"
make -s -C "$KN" sdcard > "$O/build.log" 2>&1 || { cat "$O/build.log"; exit 1; }
make -s -C "$MENU" OUT="$O/menu" > "$O/menu.log" 2>&1 || { cat "$O/menu.log"; exit 1; }
rm -rf -- "${O:?}/tree" "${O:?}/snap"; mkdir -p "$O/tree/AW" "$O/snap" "$O/cfg" "$O/nv"
cp "$O/menu/KN7APP.BIN" "$O/tree/KN7APP.BIN"
cp "$KN"/build/sdcard/* "$O/tree/AW/"
printf '# AW: the KN7000 program menu shows this name (kn7menu/README.md)\r\nNAME=Another World\r\n' > "$O/tree/AW/MANIFEST.TXT"
cp "$EMU/sdcard_from_real_kn7000.img" "$O/sd.img"; chmod u+w "$O/sd.img"
python3 -I "$MENU/fatimg.py" "$O/sd.img" put "$O/tree" > "$O/fatimg.txt"
cp "$FLOPPY" "$O/floppy.img"; chmod u+w "$O/floppy.img"
rm -f -- "$O/run.wav"
{
  echo "emulator md5 $(md5sum < "$EMU/kn7000" | cut -c1-32), bios v13"
  echo "AW KN7APP.BIN $(sha1sum < "$KN/build/KN7APP.BIN" | cut -c1-40), menu $(sha1sum < "$O/menu/KN7APP.BIN" | cut -c1-40)"
  echo "floppy $(sha1sum < "$FLOPPY" | cut -c1-40), card image $(sha1sum < "$EMU/sdcard_from_real_kn7000.img" | cut -c1-40)"
} > "$O/versions.txt"
( cd "$EMU" && env AWD_OUT="$O" AWD_DEAD=0x500066D8 AWD_PANEL=0x5006BE4C DISPLAY="${DISPLAY:-:0}" timeout 5400 \
    ./kn7000 kn7000 -bios v13 -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nothrottle \
    -harddisk "$O/sd.img" -flop "$O/floppy.img" -wavwrite "$O/run.wav" \
    -nvram_directory "$O/nv" -cfg_directory "$O/cfg" -snapshot_directory "$O/snap" \
    -autoboot_script "$HERE/awcnv_dsp.lua" ) > "$O/run.log" 2>&1
rm -f -- "$O/sd.img" "$O/floppy.img"
rm -rf -- "${O:?}/tree"
python3 -I "$HERE/dsp_report.py" "$O" | tee "$O/report.txt"
