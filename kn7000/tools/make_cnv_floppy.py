#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# make_cnv_floppy.py -- the Another World floppy for a stock KN7000 (any program build, no SP7001):
# AW.CNV (the game as a style converter) and the game files it loads part by part, on a blank disk
# the KN7000 itself formatted (kn7000_mame tools/floppy-images: the instrument's FORMAT output, the
# base every KN7000 floppy image of the project starts from).
#
# usage: python3 -I make_cnv_floppy.py OUT.img AW.CNV FILES_DIR FLOPPY_TOOLS
#   FILES_DIR     tools/aw_extract.py --parts output: floppy.lst (one name per line) and floppy/<name>:
#                 AWRxx.AW (resource xx, the bytes MEMLIST.BIN points at in BANKxx, packed or not),
#                 AWFONT.AW, AWSTRIDX.AW, AWSTRDAT.AW
#   FLOPPY_TOOLS  kn7000_mame/tools/floppy-images (technics_floppy.py + base/)
import gzip
import os
import subprocess
import sys
import tempfile
import zipfile

out, cnv, fdir, tools = sys.argv[1:5]
files = [("AW.CNV", cnv)]
files += [(n, os.path.join(fdir, "floppy", n)) for n in open(os.path.join(fdir, "floppy.lst")).read().split()]
with tempfile.TemporaryDirectory() as tmp:
    zpath = os.path.join(tmp, "aw.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for name, src in files:
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 20, 0, 0, 0))
            info.external_attr = 0x20                  # DOS: archive
            z.writestr(info, open(src, "rb").read())
    base = os.path.join(tmp, "kn7000_formatted.img")
    with gzip.open(os.path.join(tools, "base", "kn7000_formatted.img.gz")) as g:
        open(base, "wb").write(g.read())
    subprocess.run([sys.executable, "-I", os.path.join(tools, "technics_floppy.py"), base, zpath, out,
                    "--label", "ANOTHERWRLD"], check=True)
print(f"make_cnv_floppy: {out}: {len(files)} files")
