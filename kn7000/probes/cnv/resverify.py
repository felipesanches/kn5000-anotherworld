#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# resverify.py -- are the resources AW.CNV unpacked on the instrument the bytes the SD build
# loads? Compares awcnv_resdump.lua's dumps with build/res/AWPxx.bin laid end to end (the RAM
# image from RES_BASE, as tools/aw_extract.py lays it out; those packs are what the SD build
# copies to RAM, checked against rustyworld) and with the font and string tables.
#   python3 -I resverify.py DUMP_DIR RES_DIR FONT_DIR      (exit 0 = all identical)
import glob
import hashlib
import os
import sys

dump, res, fonts = sys.argv[1:4]
want = b"".join(open(f, "rb").read() for f in sorted(glob.glob(os.path.join(res, "AWP*.bin"))))
got = open(os.path.join(dump, "ram_res.bin"), "rb").read()[:len(want)]
ok = got == want
print(f"resources {len(want)} bytes: {'IDENTICAL' if ok else 'DIFFER'}  sha1 {hashlib.sha1(got).hexdigest()}")
for name, f in (("font", "anotherworld_chargen.rom"), ("stridx", "str_index.rom"), ("strdat", "str_data.rom")):
    same = open(os.path.join(fonts, f), "rb").read() == open(os.path.join(dump, f"ram_{name}.bin"), "rb").read()
    ok &= same
    print(f"{name}: {'IDENTICAL' if same else 'DIFFER'}")
sys.exit(0 if ok else 1)
