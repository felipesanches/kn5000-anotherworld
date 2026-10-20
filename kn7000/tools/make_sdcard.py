#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# make_sdcard.py -- everything the SD card needs for Another World, in one folder.
#
# Question it answers: which files, exactly, go on the card (README-CNV.md, "The SD card")? The
# folder OUT gets KN7APP.BIN (the game, an application of the loader KN7LOAD.CNV) and every game file
# it reads (tools/aw_extract.py --parts: FILES_DIR/sdfiles.lst, FILES_DIR/sdfiles/<name>), and nothing
# else, so that "copy everything in OUT to the card's root folder" is the whole instruction. The list,
# with sizes and SHA-1, is printed and written to OUT.txt beside the folder (not into it). Every name
# must be an 8.3 name, as the firmware's FAT library opens them (the loader opens C:\KN7APP.BIN the
# same way). The folder is emptied first: only build products live there.
#
# usage: python3 -I tools/make_sdcard.py OUT KN7APP.BIN FILES_DIR
import hashlib
import os
import re
import shutil
import sys

out, app, fdir = sys.argv[1:4]
files = [("KN7APP.BIN", app)]
files += [(n, os.path.join(fdir, "sdfiles", n)) for n in open(os.path.join(fdir, "sdfiles.lst")).read().split()]
for name, _ in files:
    if not re.fullmatch(r"[A-Z0-9_]{1,8}(\.[A-Z0-9_]{1,3})?", name):
        sys.exit(f"make_sdcard: {name} is not an 8.3 name")
if len({n for n, _ in files}) != len(files):
    sys.exit("make_sdcard: a name appears twice")
outabs = os.path.abspath(out)
if os.path.basename(os.path.dirname(outabs)) != "build":
    sys.exit(f"make_sdcard: {out} must be a folder inside build/")
for old in os.listdir(out) if os.path.isdir(out) else []:
    path = os.path.join(outabs, old)
    assert os.path.dirname(path) == outabs and old not in ("", ".", "..")
    os.remove(path)
os.makedirs(out, exist_ok=True)
rows = []
for name, src in files:
    shutil.copyfile(src, os.path.join(out, name))
    data = open(src, "rb").read()
    rows.append((name, len(data), hashlib.sha1(data).hexdigest()))
total = sum(r[1] for r in rows)
lines = [f"{sha}  {name}  {size}" for name, size, sha in rows]
open(outabs + ".txt", "w").write("\n".join(lines) + "\n")
print(f"make_sdcard: {out}: {len(rows)} files, {total:,} bytes; KN7APP.BIN SHA-1 {rows[0][2]}")
