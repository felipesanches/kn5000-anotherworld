#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_menu_route.sh OUT CASE... -- run_cnv_tests.sh's acceptance tests through the program menu (technics-roms-disasm
# kn7000/tools/kn7menu): the card's root KN7APP.BIN is the menu, the game is in AW\ with its files, and the session
# (awmenu_test.lua) starts it from the menu, and again from the menu after "Continue Next?" YES. The same floppy (the
# owner's loader, as released), the same copy of the real KN7000's SD card, the same checks (b)-(g); the card tree
# is the menu's card (CARDTREE, default kn7menu's build/card from `make card` there, which builds this game from this
# tree), copied into the image with kn7menu's fatimg.py. The control run uses the same tree with the no-op
# application (noop_app.s) as the root KN7APP.BIN. CASEs:
#   blank-v13 | blank-v16      a blank IC23 stamped by one POWER OFF (as run_cnv_tests.sh)
#   ic23 BIOS BASE NAME        (b)-(g) through the menu, from the IC23 image BASE (as run_cnv_tests.sh)
# The owner's IC23 is used only from a copy in OUT, deleted afterwards (run_cnv_tests.sh says how).
# Env: EMU, CARDTREE, FLOPPY, DISPLAY, DISASM_REPO.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
LOADER_DIR="$DISASM_REPO/tools/cnv_romdump"
FLOPPY="${FLOPPY:-$LOADER_DIR/releases/2026-10-19/floppy/kn7load_floppy.img}"
CARDTREE="${CARDTREE:-$DISASM_REPO/tools/kn7menu/build/card}"
MENUTOOLS="$DISASM_REPO/tools/kn7menu"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
nvdir() { case "$1" in v13) echo kn7000_4 ;; v16) echo kn7000 ;; *) echo "unknown bios $1" >&2; exit 2 ;; esac; }
valid() { case "$1" in v13) echo 0x5006CC7C ;; v16) echo 0x5006CC80 ;; esac; }  # BackupSramChecksumVerify's byte
panel() { case "$1" in v13) echo 0x5006BE4C ;; v16) echo 0x5006BE50 ;; esac; }  # PANEL_CPR (tools/aw_find_fw.py)
say() { echo "run_menu_route: $*" | tee -a "$OUT/summary.txt"; }
say "floppy $(sha1sum < "$FLOPPY" | cut -c1-16) ($FLOPPY); the menu $(sha1sum < "$CARDTREE/KN7APP.BIN" | cut -c1-16); AW\\KN7APP.BIN $(sha1sum < "$CARDTREE/AW/KN7APP.BIN" | cut -c1-16); emulator md5 $(md5sum < "$EMU/kn7000" | cut -c1-8)"

# mame RUNDIR BIOS MODE ROOTAPP [POWER]: one boot, fresh cfg, the loader floppy, a writable copy of the real
# KN7000's SD card with CARDTREE copied into it and ROOTAPP as the root's KN7APP.BIN, IC23 from RUNDIR/nv (prepared
# by the caller); awmenu_test.lua writes its reports to RUNDIR. The card copy is deleted afterwards.
mame() {
  local R="$1" B="$2" M="$3" A="$4" P="${5:-1}"
  mkdir -p "$R/snap"
  cp "$EMU/sdcard_from_real_kn7000.img" "$R/sd.img"; chmod u+w "$R/sd.img"
  rm -rf -- "${R:?}/tree"; cp -r "$CARDTREE" "$R/tree"; cp "$A" "$R/tree/KN7APP.BIN"
  python3 -I "$MENUTOOLS/fatimg.py" "$R/sd.img" put "$R/tree" > "$R/card.log"
  rm -rf -- "${R:?}/tree"
  cp "$FLOPPY" "$R/floppy.img"; chmod u+w "$R/floppy.img"
  ( cd "$EMU" && AWT_MODE="$M" AWT_OUT="$R" AWT_RES="$KN/build/res" AWT_VALID="$(valid "$B")" AWT_PANEL="$(panel "$B")" AWT_POWER="$([ "$P" = 1 ] && echo 1)" \
    DISPLAY="${DISPLAY:-:0}" timeout 5400 ./kn7000 kn7000 -bios "$B" -rompath ./roms -pluginspath ./plugins \
    -skip_gameinfo -window -nothrottle -harddisk "$R/sd.img" -flop "$R/floppy.img" -nvram_directory "$R/nv" \
    -cfg_directory "$R/cfg" -snapshot_directory "$R/snap" -autoboot_script "$HERE/awmenu_test.lua" ) > "$R/run.log" 2>&1
  rm -f -- "$R/sd.img" "$R/floppy.img"
}

while [ $# -gt 0 ]; do
  CASE="$1"; shift
  case "$CASE" in
  blank-v13|blank-v16)
    B="${CASE#blank-}"; R="$OUT/$CASE"; rm -rf -- "${R:?}"; mkdir -p "$R"
    mame "$R" "$B" verify "$CARDTREE/KN7APP.BIN"
    cp "$R/nv/$(nvdir "$B")/ic23" "$R/ic23"
    say "$CASE  $(python3 -I "$HERE/ic23_file.py" "$R/ic23")"
    ;;
  ic23)
    B="$1"; BASE="$(readlink -f "$2")"; N="$3"; shift 3
    C="$OUT/$B-$N"; mkdir -p "$C"
    # the control application: the no-op, as KN7APP.BIN beside the same game files
    W="$C/noop"; mkdir -p "$W"
    python3 "$DISASM_REPO/tools/xapasm.py" "$HERE/noop_app.s" -I "$LOADER_DIR" -o "$W/noop.bin" -m "$W/noop.map" > /dev/null
    python3 -I "$LOADER_DIR/mkapp.py" "$W/noop.bin" "$W/KN7APP.BIN" > /dev/null
    for M in control game; do
      R="$C/$M"; rm -rf -- "${R:?}"; mkdir -p "$R/nv/$(nvdir "$B")"
      cp "$BASE" "$R/nv/$(nvdir "$B")/ic23"
      A="$CARDTREE/KN7APP.BIN"; [ "$M" = control ] && A="$W/KN7APP.BIN"   # the menu, or the no-op
      mame "$R" "$B" "$M" "$A" &
    done
    wait
    for M in control game; do cp "$C/$M/nv/$(nvdir "$B")/ic23" "$C/ic23-$M.bin"; done
    for M in control game; do                         # the next boot: does the firmware accept it?
      R="$C/next-$M"; rm -rf -- "${R:?}"; mkdir -p "$R/nv/$(nvdir "$B")"
      cp "$C/ic23-$M.bin" "$R/nv/$(nvdir "$B")/ic23"
      mame "$R" "$B" verify "$CARDTREE/KN7APP.BIN" &
    done
    wait
    G="$C/game"; K="$C/control"
    grep '^awmenu_test:' "$G/run.log" > "$C/session.txt"
    nf=$(grep -c ' FAIL ' "$C/session.txt"); np=$(grep -c ' PASS ' "$C/session.txt")
    say "$B/$N session   $([ "$nf" = 0 ] && [ "$np" -ge 20 ] && echo PASS || echo FAIL)  $np checks passed, $nf failed ($C/session.txt)"
    say "$B/$N ic23w     $(grep -q 'IC23 verdict: CLEAN' "$G/ic23.txt" && grep -q 'IC23 verdict: CLEAN' "$K/ic23.txt" && echo PASS || echo FAIL)  game: $(head -1 "$G/ic23.txt" | cut -c3-)"
    if cmp -s "$C/ic23-control.bin" "$C/ic23-game.bin"; then same=identical; else same="DIFFER: $(cmp -l "$C/ic23-control.bin" "$C/ic23-game.bin" | wc -l) bytes"; fi
    ck="$(python3 -I "$HERE/ic23_file.py" "$C/ic23-game.bin")"
    say "$B/$N same      $([ "$same" = identical ] && echo "$ck" | grep -q 'match=True' && echo PASS || echo FAIL)  control vs game: $same; game: $ck; sha1 $(sha1sum < "$C/ic23-game.bin" | cut -c1-16)"
    [ "$same" = identical ] || python3 -I "$HERE/ic23_diff.py" "$C/ic23-control.bin" "$C/ic23-game.bin" | tee -a "$OUT/summary.txt"
    acc=PASS; detail=""
    for M in control game; do
      v="$(grep -o "verdict byte [0-9A-F]*" "$C/next-$M/run.log" | head -1)"
      cmp -s <(tail -c +$((0x825)) "$C/ic23-$M.bin" | head -c $((0x30174 - 0x824))) \
             <(tail -c +$((0x825)) "$C/next-$M/nv/$(nvdir "$B")/ic23" | head -c $((0x30174 - 0x824))) && st=kept || st=CHANGED
      [ "$v" = "verdict byte 00" ] && [ "$st" = kept ] || acc=FAIL
      detail="$detail $M: $v, PANEL MEMORY store $st;"
    done
    say "$B/$N accepted  $acc $detail"
    if cmp -s "$K/pools.bin" "$G/pools.bin"; then pl=identical; else pl="DIFFER: $(cmp -l "$K/pools.bin" "$G/pools.bin" | wc -l) bytes"; fi
    say "$B/$N pools     $([ "$pl" = identical ] && grep -q 'POOLS verdict: CLEAN' "$G/pools.txt" && echo PASS || echo FAIL)  control vs game at POWER OFF: $pl (sha1 $(sha1sum < "$G/pools.bin" | cut -c1-16)); $(head -1 "$G/pools.txt" | cut -c3-)"
    say "$B/$N area      $(grep -q 'AWAREA verdict: CLEAN' "$G/awarea.txt" && echo PASS || echo FAIL)  $(head -1 "$G/awarea.txt" | cut -c3-)"
    say "$B/$N loader    $(grep -q 'LOADER verdict: CLEAN' "$G/loader.txt" && grep -q 'LOADER verdict: CLEAN' "$K/loader.txt" && echo PASS || echo FAIL)  $(head -1 "$G/loader.txt" | cut -c3-)"
    ;;
  *) echo "unknown case $CASE" >&2; exit 2 ;;
  esac
done
