#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_perf.sh OUT LUA [MAME ARGS...] -- one MAME run of the KN7APP.BIN build through the loader, for the
# speed probes (probes/cnv/README.md, "Speed"): the owner's loader floppy as released, a copy of the real
# KN7000's SD card with the files of CARDFILES added to its root, a fresh NVRAM and cfg in OUT, and the
# autoboot script LUA (awcnv_perf.lua, awcnv_fwlcd.lua, awcnv_lcd.lua, awcnv_speed.lua, awcnv_cksum.lua).
# The speed reports the game wrote to the card (AWPERF0.TXT ...) are copied to OUT; then the card and floppy
# copies are deleted. MAME's output goes to OUT/run.log. Every environment variable is passed on to the script (AWP_*, AWL_*).
# Env: EMU (the overlay emulator dir, default ~/compartilhado/kn7000-emulator: kn7000, roms/, plugins/,
# sdcard_from_real_kn7000.img), CARDFILES (default build/sdcard), BIOS (default v13 = program 893),
# FLOPPY (default the loader's released floppy image), DISPLAY.
#   probes/cnv/run_perf.sh ~/compartilhado/tmp/aw-perf/base-perf probes/cnv/awcnv_perf.lua
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
FLOPPY="${FLOPPY:-$DISASM_REPO/tools/cnv_romdump/releases/2026-10-19/floppy/kn7load_floppy.img}"
CARDFILES="$(cd "${CARDFILES:-$KN/build/sdcard}" && pwd)"
BIOS="${BIOS:-v13}"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
LUA="$(readlink -f "$2")"; shift 2
mkdir -p "$OUT/snap"
cp "$EMU/sdcard_from_real_kn7000.img" "$OUT/sd.img"; chmod u+w "$OUT/sd.img"
args=()
for f in "$CARDFILES"/*; do args+=("$(basename "$f")" "$f"); done
python3 -I "$DISASM_REPO/tools/sd_addfile.py" "$OUT/sd.img" "${args[@]}" > "$OUT/card.log"
cp "$FLOPPY" "$OUT/floppy.img"; chmod u+w "$OUT/floppy.img"
echo "run_perf: KN7APP.BIN $(sha1sum < "$CARDFILES/KN7APP.BIN" | cut -c1-16), bios $BIOS, emulator md5 $(md5sum < "$EMU/kn7000" | cut -c1-8), $(basename "$LUA")" | tee "$OUT/run.log"
( cd "$EMU" && AWP_OUT="$OUT" AWL_OUT="$OUT" DISPLAY="${DISPLAY:-:0}" timeout 7200 ./kn7000 kn7000 -bios "$BIOS" \
  -rompath ./roms -pluginspath ./plugins -skip_gameinfo -window -nothrottle -harddisk "$OUT/sd.img" \
  -flop "$OUT/floppy.img" -nvram_directory "$OUT/nv" -cfg_directory "$OUT/cfg" -snapshot_directory "$OUT/snap" \
  -autoboot_script "$LUA" "$@" ) >> "$OUT/run.log" 2>&1
for f in AWPERF0.TXT AWPERF1.TXT AWPERF2.TXT; do
  python3 -I "$DISASM_REPO/tools/cnv_romdump/fatls.py" "$OUT/sd.img" "C:\\$f" "$OUT/$f" > /dev/null 2>&1 || rm -f -- "$OUT/$f"
done
rm -f -- "$OUT/sd.img" "$OUT/floppy.img"
grep -E '^aw(perf|lcd|speed|cnv):' "$OUT/run.log"
