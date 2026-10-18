#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# make_cnv_floppy.py -- the Another World floppy for a stock KN7000 (program 941, no SP7001):
# AW.CNV (the game as a style converter), the game's own BANK01..BANK0D and the font/string
# tables, on a blank disk the KN7000 itself formatted (kn7000_mame tools/floppy-images: the
# instrument's FORMAT output, the base every KN7000 floppy image of the project starts from).
#
# usage: python3 -I make_cnv_floppy.py OUT.img AW.CNV MSDOS_DIR FONT_DIR FLOPPY_TOOLS
#   MSDOS_DIR     the original MS-DOS release (BANK01..BANK0D; MEMLIST.BIN is not needed on disk)
#   FONT_DIR      anotherworld_chargen.rom, str_index.rom, str_data.rom (as the SD build)
#   FLOPPY_TOOLS  kn7000_mame/tools/floppy-images (technics_floppy.py + base/)
import gzip
import os
import subprocess
import sys
import tempfile
import zipfile

out, cnv, msdos, fonts, tools = sys.argv[1:6]
files = [("AW.CNV", cnv)]
files += [(f"BANK{i:02X}", os.path.join(msdos, f"BANK{i:02X}")) for i in range(1, 14)]
files += [("AWFONT.AW", os.path.join(fonts, "anotherworld_chargen.rom")),
          ("AWSTRIDX.AW", os.path.join(fonts, "str_index.rom")),
          ("AWSTRDAT.AW", os.path.join(fonts, "str_data.rom"))]
with tempfile.TemporaryDirectory() as tmp:
    zpath = os.path.join(tmp, "aw.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for name, src in files:
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 18, 0, 0, 0))
            info.external_attr = 0x20                  # DOS: archive
            z.writestr(info, open(src, "rb").read())
    base = os.path.join(tmp, "kn7000_formatted.img")
    with gzip.open(os.path.join(tools, "base", "kn7000_formatted.img.gz")) as g:
        open(base, "wb").write(g.read())
    subprocess.run([sys.executable, "-I", os.path.join(tools, "technics_floppy.py"), base, zpath, out,
                    "--label", "ANOTHERWRLD"], check=True)
