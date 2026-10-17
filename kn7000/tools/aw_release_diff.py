#!/usr/bin/env python3
# How different are two Another World MS-DOS data sets? Unpacks every MEMLIST resource of each
# (tools/aw_extract.py) and lists the ids whose bytes differ. Both directories hold MEMLIST.BIN +
# BANK01..0D (upper-case names; symlink a lower-case set into a scratch directory first).
#   python3 -I tools/aw_release_diff.py ~/compartilhado/MSDOS <other set>
# 2026-10-17: the upper-case set (what rustyworld and the port use) vs the lower-case 2013 set in
# custom-kn5000-roms/anotherworld/game_data/MSDOS: 128 of 146 resources differ.
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("ax", os.path.join(os.path.dirname(__file__), "aw_extract.py"))
ax = importlib.util.module_from_spec(spec); spec.loader.exec_module(ax)
def load(d):
    out = {}
    for e in ax.memlist(os.path.join(d, "MEMLIST.BIN")):
        if not e["size"]:
            out[e["id"]] = b""; continue
        with open(os.path.join(d, f"BANK{e['bank']:02X}"), "rb") as f:
            f.seek(e["offset"]); raw = f.read(e["packed"])
        try:
            out[e["id"]] = raw if e["packed"] == e["size"] else ax.unpack(raw, e["size"])
        except ValueError as err:
            out[e["id"]] = f"unreadable: {err}".encode()
    return out
a, b = load(sys.argv[1]), load(sys.argv[2])
diff = [i for i in sorted(set(a) | set(b)) if a.get(i) != b.get(i)]
print(f"{len(diff)} of {len(set(a) | set(b))} resources differ: " + " ".join(f"{i:02X}" for i in diff))
