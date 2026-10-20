#!/bin/bash
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# build_probe.sh PROBE.s OUT.img -- assemble a probe converter as AW.CNV (linked at 0x502B8000, the
# STYLE CONVERT load address) and put it alone on a blank disk the KN7000 formatted.
#   probes/cnv/build_probe.sh probes/cnv/probe2_task.s ~/compartilhado/tmp/cnvprobe/probe2.img
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DISASM_REPO="${DISASM_REPO:-$HERE/../../../../technics-roms-disasm/kn7000}"
FLOPPY_TOOLS="${FLOPPY_TOOLS:-$HERE/../../../../kn7000_mame/tools/floppy-images}"
OUT="$2"; W="$(mktemp -d)"; trap 'rm -rf -- "${W:?}"' EXIT
python3 "$DISASM_REPO/tools/xapasm.py" "$1" -o "$W/AW.CNV" -m "$W/AW.map"
python3 -I - "$W" <<'PY'
import sys, zipfile
w = sys.argv[1]
with zipfile.ZipFile(w + "/aw.zip", "w") as z:
    i = zipfile.ZipInfo("AW.CNV", date_time=(2026, 10, 18, 0, 0, 0)); i.external_attr = 0x20
    z.writestr(i, open(w + "/AW.CNV", "rb").read())
PY
gzip -dc "$FLOPPY_TOOLS/base/kn7000_formatted.img.gz" > "$W/base.img"
python3 -I "$FLOPPY_TOOLS/technics_floppy.py" "$W/base.img" "$W/aw.zip" "$OUT"
sha1sum "$W/AW.CNV" | sed 's|  .*| AW.CNV|'
