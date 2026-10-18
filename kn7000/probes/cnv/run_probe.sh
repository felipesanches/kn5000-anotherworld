#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# run_probe.sh CMDFILE FLOPPY OUTDIR [MAME ARGS...] -- boot the KN7000 (program 941, the published overlay build)
# with FLOPPY in the drive and a copy of the real KN7000 SD card, run the remote.lua command file
# CMDFILE (kn7000_mame tools/rigs/remote.lua), then quit. The probe's result lines (PROBE, W44,
# CNVCALL, PANELDEC, HDR, MOUTWR) are printed from OUTDIR/rig.log; snapshots go to OUTDIR/snap.
# FLOPPY may also be a softlist name (scd7000). DEBUG=1 enables MAME's debugger (no window), which
# taskprobe.cmd needs for its breakpoints. Further arguments go to MAME as they are.
#   probes/cnv/run_probe.sh probes/cnv/probe2_task.cmd ~/compartilhado/tmp/cnvprobe/probe2.img \
#     ~/compartilhado/tmp/cnvprobe/run2
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MAME_REPO="${MAME_REPO:-$HERE/../../../../kn7000_mame}"
SD="${SD941:-$HERE/../../../../kn7000-emulator/sdcard_from_real_kn7000.img}"
D="$(mkdir -p "$3" && cd "$3" && pwd)"; mkdir -p "$D/snap"
cp "$SD" "$D/sd.img"; chmod u+w "$D/sd.img"
DBG=(); [ "${DEBUG:-0}" = 1 ] && DBG=(-debug -debugger none)
FLOP="$2"; if [ -f "$FLOP" ]; then cp "$FLOP" "$D/disk.img"; FLOP="$D/disk.img"; fi
{ cat "$1"; echo "exit"; } > "$D/cmd.txt"; rm -f -- "$D/cmd.txt.log"
cd "$MAME_REPO"
REMOTE_CMD="$D/cmd.txt" DISPLAY="${DISPLAY:-:0}" ./tools/rig.sh remote kn7000 -s 3000 -l "$D/rig.log" -- \
  -snapshot_directory "$D/snap" -harddisk "$D/sd.img" -flop "$FLOP" "${DBG[@]}" "${@:4}" > "$D/launch.out" 2>&1 || true
grep -E '^(PROBE|W44|CNVCALL|HDR|MOUTWR|ENQ)' "$D/rig.log" || true
echo "PANELDEC lines: $(grep -c '^PANELDEC' "$D/rig.log" || true), distinct: $(grep '^PANELDEC' "$D/rig.log" | sort -u | tr '\n' ' ')"
