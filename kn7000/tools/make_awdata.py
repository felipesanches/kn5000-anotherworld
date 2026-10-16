#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Pack the four Another-World "intro" resources into a single AWDATA.AW blob
# with a small header that the MN10300 loader reads.  ALL header fields are
# little-endian, to match the KN7000's little-endian CPU.
#
#   make_awdata.py [<resource-dir>] <out-file>
#
# Layout:
#   offset 0:  ASCII magic "AW01"
#   offset 4:  four records, each two LE uint32 (offset, length), in order:
#                1. bytecode  = resource-0x18.bin
#                2. video1    = resource-0x19.bin
#                3. video2    = resource-0x11.bin
#                4. palettes  = resource-0x17.bin
#   header (4 + 4*8 = 36 bytes) is zero-padded to 64 bytes.
#   each resource's data starts at offset 64, 4-byte aligned.
import os, struct, sys

DEFAULT_DIR = os.path.expanduser(
    "~/compartilhado/custom-kn5000-roms/anotherworld/game_data/MSDOS")
MAGIC = b"AW01"
HEADER_SIZE = 64
# (label, filename) in the fixed header order.
RESOURCES = [
    ("bytecode", "resource-0x18.bin"),
    ("video1",   "resource-0x19.bin"),
    ("video2",   "resource-0x11.bin"),
    ("palettes", "resource-0x17.bin"),
]

def main():
    args = sys.argv[1:]
    if len(args) == 1:
        res_dir, out_path = DEFAULT_DIR, args[0]
    elif len(args) == 2:
        res_dir, out_path = args[0], args[1]
    else:
        sys.exit("usage: make_awdata.py [<resource-dir>] <out-file>")

    blobs = []
    for label, fname in RESOURCES:
        with open(os.path.join(res_dir, fname), "rb") as f:
            blobs.append(f.read())

    # Lay the data section out first so we know each resource's offset.
    data = bytearray()
    records = []  # (offset, length)
    for blob in blobs:
        if len(data) % 4:                       # 4-byte align each resource
            data.extend(b"\x00" * (4 - len(data) % 4))
        offset = HEADER_SIZE + len(data)
        records.append((offset, len(blob)))
        data.extend(blob)

    header = bytearray(MAGIC)
    for offset, length in records:
        header += struct.pack("<II", offset, length)
    header += b"\x00" * (HEADER_SIZE - len(header))
    assert len(header) == HEADER_SIZE

    out = bytes(header) + bytes(data)
    with open(out_path, "wb") as f:
        f.write(out)

    print(f"AWDATA layout (magic {MAGIC.decode()}, header {HEADER_SIZE} bytes):")
    for (label, fname), (offset, length) in zip(RESOURCES, records):
        print(f"  {label:9s} {fname:16s} offset=0x{offset:06X} ({offset:>6})  "
              f"length=0x{length:05X} ({length:>6})")
    print(f"total size: 0x{len(out):X} ({len(out)} bytes) -> {out_path}")

if __name__ == "__main__":
    main()
