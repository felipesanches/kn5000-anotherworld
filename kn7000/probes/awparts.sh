#!/bin/bash
# awparts.sh -- does every Another World part open identically in the KN7000 port and the reference?
#
# For each part 0x3E80, 0x3E82..0x3E89 (0x3E81, the intro, is the CHECKSUM-COMPARISON.md run):
# the reference (rustyworld refcksum, START_PART, AW_NO_VIDEO2_BG=1 = the original engine's part
# setup) and the port (probes/awcksum.lua, AW_START_PART) both enter the part at the end of tick 0
# and run TICKS ticks with no input; the per-tick CRC-32s of the displayed page are compared.
# 2026-10-17: every part 600/600 identical (FULL-GAME-PLAN.md section 4).
#
#   probes/awparts.sh <out dir> [ticks=600]        (from kn7000/, after `make card`)
# Needs the reference clone with replay-mods/rustyworld-kn7000-all.diff applied and
# `cargo build --release --no-default-features --bin refcksum` done (RUSTY_RUN below).
# Runs two emulators at a time. -str 299: mame-pr/kn7000 has no -skip_gameinfo patch for the
# warning screen, and MAME skips that screen only for 0 < -str < 300 -- with -str 900 an instance
# now and then sat on it (autoboot script never started); 600 ticks need ~85 s emulated.
set -u
OUT=${1:?usage: probes/awparts.sh <out dir> [ticks]}
TICKS=${2:-600}
RUSTY_RUN=${RUSTY_RUN:-$HOME/compartilhado/tmp/kn7000-aw-reference/run}
MAME=${MAME:-../../mame-pr/kn7000}
mkdir -p "$OUT"
PARTS="3E80 3E82 3E83 3E84 3E85 3E86 3E87 3E88 3E89"
for P in $PARTS; do
    (cd "$RUSTY_RUN" && START_PART=0x$P AW_PARTS=1 AW_NO_VIDEO2_BG=1 \
        ../rustyworld/target/release/refcksum "$OUT/ref_$P.log" "$TICKS" > /dev/null 2> "$OUT/ref_$P.err")
done
kn() {
    local P=$1
    AW_START_PART=0x$P AWCK_BIN="$OUT/kn_$P.bin" AWCK_IDX="$OUT/kn_$P.idx" AWCK_MAX=$((TICKS - 1)) \
        timeout -k 5 600 "$MAME" -rompath ../../technics_romsets -skip_gameinfo -window kn7000 -bios sp7001 \
        -harddisk build/another_sd.img -nothrottle -autoboot_script probes/awcksum.lua -str 299 \
        > "$OUT/kn_$P.out" 2>&1
    python3 -I probes/cksum_pages.py "$OUT/kn_$P.bin" "$OUT/kn_$P.idx" "$OUT/kn_$P.log" > /dev/null
    rm -f -- "${OUT:?}/kn_${P:?}.bin"
}
set -- $PARTS
while [ $# -gt 0 ]; do
    kn "$1" &
    if [ $# -gt 1 ]; then kn "$2" & fi
    wait
    shift; [ $# -gt 0 ] && shift
done
for P in $PARTS; do
    printf '%s  ' "$P"
    python3 -I probes/compare_frames.py "$OUT/kn_$P.log" "$OUT/ref_$P.log" | grep -E 'match:' | tr -s ' '
done
