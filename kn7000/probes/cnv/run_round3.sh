#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_round3.sh OUT [bank|full] -- Felipe's third round (probes/cnv/README.md, "Round 3") in one MAME session
# through the program menu, as run_dsp.sh: the menu as the card's root KN7APP.BIN, the game in AW\, the published
# overlay emulator (EMU, default ~/compartilhado/kn7000-emulator), -bios v13 (program 893, the owner's), the owner's
# loader floppy as released, awcnv_round3.lua as the autoboot script (AWR_MODE = the second argument, default full).
# SDDIR: the game's card files to use (default: this build's build/sdcard/, made first); to time an older build,
# point it at a copy of that build's sdcard/ directory.
# OUT is scratch (~/compartilhado/tmp/..., never /tmp); the card and floppy copies are deleted afterwards.
# Snapshots (OUT/snap) show the game's graphics and OUT/run.wav holds its sound: never commit them.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
MENU="$DISASM_REPO/tools/kn7menu"
FLOPPY="$DISASM_REPO/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img"
O="$(mkdir -p "$1" && cd "$1" && pwd)"
MODE="${2:-full}"
if [ -z "${SDDIR:-}" ]; then
  make -s -C "$KN" sdcard > "$O/build.log" 2>&1 || { cat "$O/build.log"; exit 1; }
  SDDIR="$KN/build/sdcard"
fi
make -s -C "$MENU" OUT="$O/menu" > "$O/menu.log" 2>&1 || { cat "$O/menu.log"; exit 1; }
rm -rf -- "${O:?}/tree" "${O:?}/snap"; mkdir -p "$O/tree/AW" "$O/snap" "$O/cfg" "$O/nv"
cp "$O/menu/KN7APP.BIN" "$O/tree/KN7APP.BIN"
cp "$SDDIR"/* "$O/tree/AW/"
printf '# AW: the KN7000 program menu shows this name (kn7menu/README.md)\r\nNAME=Another World\r\n' > "$O/tree/AW/MANIFEST.TXT"
cp "$EMU/sdcard_from_real_kn7000.img" "$O/sd.img"; chmod u+w "$O/sd.img"
python3 -I "$MENU/fatimg.py" "$O/sd.img" put "$O/tree" > "$O/fatimg.txt"
cp "$FLOPPY" "$O/floppy.img"; chmod u+w "$O/floppy.img"
rm -f -- "$O/run.wav"
{
  echo "emulator md5 $(md5sum < "$EMU/kn7000" | cut -c1-32), bios v13, mode $MODE"
  echo "AW KN7APP.BIN $(sha1sum < "$SDDIR/KN7APP.BIN" | cut -c1-40), menu $(sha1sum < "$O/menu/KN7APP.BIN" | cut -c1-40)"
  echo "floppy $(sha1sum < "$FLOPPY" | cut -c1-40), card image $(sha1sum < "$EMU/sdcard_from_real_kn7000.img" | cut -c1-40)"
} > "$O/versions.txt"
( cd "$EMU" && env AWR_OUT="$O" AWR_MODE="$MODE" AWR_DEAD=0x500066D8 AWR_PANEL=0x5006BE4C DISPLAY="${DISPLAY:-:0}" timeout 5400 \
    ./kn7000 kn7000 -bios v13 -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nothrottle \
    -harddisk "$O/sd.img" -flop "$O/floppy.img" -wavwrite "$O/run.wav" \
    -nvram_directory "$O/nv" -cfg_directory "$O/cfg" -snapshot_directory "$O/snap" \
    -autoboot_script "$HERE/awcnv_round3.lua" ) > "$O/run.log" 2>&1
rm -f -- "$O/sd.img" "$O/floppy.img"
rm -rf -- "${O:?}/tree"
cat "$O/events.txt"
