#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_cnv_tests.sh OUT CASE... -- the KN7APP.BIN build's acceptance tests in MAME (probes/cnv/README.md):
# the game the way the owner's KN7000 runs it, through the loader. Every MAME run boots with the owner's
# loader floppy (KN7LOAD.CNV as released on 2026-10-19, unchanged) and a copy of the real KN7000's SD card
# with the files of build/sdcard/ (KN7APP.BIN and the game's files) added to its root.
# OUT is a scratch directory (never /tmp: ~/compartilhado/tmp/...). Run `make sdcard` first. CASEs:
#
#   guard              (a) the build-time checks: ic23_guard.py --loader calls KN7APP.BIN clean, finds exactly
#                      the 7 planted references of guard_loader_selftest.s and the SP7001 build's references;
#                      cnv_layout.py accepts the memory map
#   blank-v13 | blank-v16
#                      a blank IC23 stamped by one POWER OFF (-bios v13 = program 893, v16 = 941): the
#                      baseline for the cases below
#   ic23 BIOS BASE NAME
#                      (b)-(g) from the IC23 image BASE (a file: OUT/blank-v13/ic23, or the owner's, see
#                      below), results in OUT/BIOS-NAME: a control run (the same floppy and card, with the
#                      no-op application noop_app.s as KN7APP.BIN) and a game run (the whole session,
#                      awcnv_test.lua), both ending with POWER OFF, then a boot of each saved IC23 (the
#                      firmware's verdict) ending with POWER OFF. Prints:
#                        session   every awcnv_test.lua check of the game run passed      (b)
#                        ic23w     no write into CS1 from the converter area (the loader and the game),
#                                  none past 256 KB                                       (c)
#                        same      the saved IC23s of the control and game runs are byte-identical,
#                                  checksum valid                                        (d)
#                        accepted  the next boot finds them valid, and leaves the PANEL MEMORY store
#                                  as it was (no factory reset)                           (d)
#                        pools     0x50180000-0x50297FFF identical at POWER OFF, and no write there
#                                  from the converter area                                (e)
#                        area      no foreign write into the game's RAM while it ran       (f)
#                        loader    no write into the loader's resident area 0x502B8000-0x502B9FFF but
#                                  the loader's own (and the firmware's load of it)        (g)
#
# The owner's IC23 (private: technics_roms roms/kn7000/real_dump_v1.3_b893/pass5-run1/R8400000.BIN, its first
# 256 KB) is used only from a copy in OUT, deleted afterwards:
#   head -c 262144 .../R8400000.BIN > OUT/owner-ic23.bin; run_cnv_tests.sh OUT ic23 v13 OUT/owner-ic23.bin owner
# Env: EMU (the overlay emulator dir, default ~/compartilhado/kn7000-emulator; it must hold kn7000, roms/,
# plugins/ and sdcard_from_real_kn7000.img), CARDFILES (default build/sdcard), FLOPPY (default the loader's
# released floppy image), DISPLAY.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KN="$(cd "$HERE/../.." && pwd)"
EMU="${EMU:-$HOME/compartilhado/kn7000-emulator}"
DISASM_REPO="${DISASM_REPO:-$KN/../../technics-roms-disasm/kn7000}"
LOADER_DIR="$DISASM_REPO/tools/cnv_romdump"
FLOPPY="${FLOPPY:-$LOADER_DIR/releases/2026-10-19/floppy/kn7load_floppy.img}"
CARDFILES="${CARDFILES:-$KN/build/sdcard}"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
nvdir() { case "$1" in v13) echo kn7000_4 ;; v16) echo kn7000 ;; *) echo "unknown bios $1" >&2; exit 2 ;; esac; }
valid() { case "$1" in v13) echo 0x5006CC7C ;; v16) echo 0x5006CC80 ;; esac; }  # BackupSramChecksumVerify's byte
panel() { case "$1" in v13) echo 0x5006BE4C ;; v16) echo 0x5006BE50 ;; esac; }  # PANEL_CPR (tools/aw_find_fw.py)
say() { echo "run_cnv_tests: $*" | tee -a "$OUT/summary.txt"; }
say "floppy $(sha1sum < "$FLOPPY" | cut -c1-16) ($FLOPPY); KN7APP.BIN $(sha1sum < "$CARDFILES/KN7APP.BIN" | cut -c1-16); emulator md5 $(md5sum < "$EMU/kn7000" | cut -c1-8)"

# mame RUNDIR BIOS MODE KN7APP [POWER]: one boot, fresh cfg, the loader floppy, a writable copy of the real
# KN7000's SD card with CARDFILES added to its root and KN7APP as its KN7APP.BIN, IC23 from RUNDIR/nv (prepared
# by the caller); awcnv_test.lua writes its reports to RUNDIR. The card copy is deleted afterwards.
mame() {
  local R="$1" B="$2" M="$3" A="$4" P="${5:-1}" args=() f
  mkdir -p "$R/snap"
  cp "$EMU/sdcard_from_real_kn7000.img" "$R/sd.img"; chmod u+w "$R/sd.img"
  for f in "$CARDFILES"/*; do
    [ "$(basename "$f")" = KN7APP.BIN ] && continue
    args+=("$(basename "$f")" "$f")
  done
  python3 -I "$DISASM_REPO/tools/sd_addfile.py" "$R/sd.img" KN7APP.BIN "$A" "${args[@]}" > "$R/card.log"
  cp "$FLOPPY" "$R/floppy.img"; chmod u+w "$R/floppy.img"
  ( cd "$EMU" && AWT_MODE="$M" AWT_OUT="$R" AWT_RES="$KN/build/res" AWT_VALID="$(valid "$B")" AWT_PANEL="$(panel "$B")" AWT_POWER="$([ "$P" = 1 ] && echo 1)" \
    DISPLAY="${DISPLAY:-:0}" timeout 3600 ./kn7000 kn7000 -bios "$B" -rompath ./roms -pluginspath ./plugins \
    -skip_gameinfo -window -nothrottle -harddisk "$R/sd.img" -flop "$R/floppy.img" -nvram_directory "$R/nv" \
    -cfg_directory "$R/cfg" -snapshot_directory "$R/snap" -autoboot_script "$HERE/awcnv_test.lua" ) > "$R/run.log" 2>&1
  rm -f -- "$R/sd.img" "$R/floppy.img"
}

while [ $# -gt 0 ]; do
  CASE="$1"; shift
  case "$CASE" in
  guard)
    G="$OUT/guard"; mkdir -p "$G"
    [ -f "$KN/build/res/awres.inc" ] || make -s -C "$KN" build/res/awres.inc > /dev/null   # the SP7001 build's tables
    ( cd "$KN" && python3 -I tools/ic23_guard.py "$DISASM_REPO/tools" src/cnv_main.s -I src -I build/res -I "$LOADER_DIR" --loader "$LOADER_DIR/kn7cnv.inc" ) > "$G/app.txt"; a=$?
    ( cd "$KN" && python3 -I tools/ic23_guard.py "$DISASM_REPO/tools" probes/cnv/guard_loader_selftest.s -I "$LOADER_DIR" --loader "$LOADER_DIR/kn7cnv.inc" ) > "$G/selftest.txt"; s=$?
    ( cd "$KN" && python3 -I tools/ic23_guard.py "$DISASM_REPO/tools" src/main.s -I src -I build/res ) > "$G/sp7001.txt"; b=$?
    ( cd "$KN" && python3 -I tools/cnv_layout.py "$LOADER_DIR/kn7cnv.inc" src/platformcnv.inc src/vm.inc build/kn7app.map build/kn7app.bin "$LOADER_DIR/releases/2026-10-19/floppy/KN7LOAD.CNV" ) > "$G/layout.txt"; c=$?
    st=$(tail -1 "$G/selftest.txt"); case "$st" in *": 7 reference(s)"*) s7=1 ;; *) s7=0 ;; esac
    case "$(tail -1 "$G/sp7001.txt")" in *": "[1-9]*" reference(s)"*) b1=1 ;; *) b1=0 ;; esac   # found, not crashed
    say "guard     $([ $a = 0 ] && [ $s = 1 ] && [ $s7 = 1 ] && [ $b = 1 ] && [ $b1 = 1 ] && [ $c = 0 ] && echo PASS || echo FAIL)  $(tail -1 "$G/app.txt"); $(tail -2 "$G/app.txt" | head -1 | cut -c13-); $st; $(tail -1 "$G/sp7001.txt"); $(tail -1 "$G/layout.txt")"
    ;;
  blank-v13|blank-v16)
    B="${CASE#blank-}"; R="$OUT/$CASE"; rm -rf -- "${R:?}"; mkdir -p "$R"
    mame "$R" "$B" verify "$CARDFILES/KN7APP.BIN"
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
      A="$CARDFILES/KN7APP.BIN"; [ "$M" = control ] && A="$W/KN7APP.BIN"
      mame "$R" "$B" "$M" "$A" &
    done
    wait
    for M in control game; do cp "$C/$M/nv/$(nvdir "$B")/ic23" "$C/ic23-$M.bin"; done
    for M in control game; do                         # the next boot: does the firmware accept it?
      R="$C/next-$M"; rm -rf -- "${R:?}"; mkdir -p "$R/nv/$(nvdir "$B")"
      cp "$C/ic23-$M.bin" "$R/nv/$(nvdir "$B")/ic23"
      mame "$R" "$B" verify "$CARDFILES/KN7APP.BIN" &
    done
    wait
    G="$C/game"; K="$C/control"
    grep '^awcnv_test:' "$G/run.log" > "$C/session.txt"
    nf=$(grep -c ' FAIL ' "$C/session.txt"); np=$(grep -c ' PASS ' "$C/session.txt")
    say "$B/$N session   $([ "$nf" = 0 ] && [ "$np" -ge 16 ] && echo PASS || echo FAIL)  $np checks passed, $nf failed ($C/session.txt)"
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
