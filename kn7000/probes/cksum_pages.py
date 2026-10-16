#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# Turn the raw per-frame page dump from probes/awcksum.lua into a checksum log
# that is directly comparable to the reference VM's (rustyworld refcksum).
# awcksum.lua appends each VM frame's 64000-byte front page (palette indices) to
# a .bin, in the tick order listed in the .idx ("tick frontaddr"). Here we CRC-32
# each block (IEEE/zlib, the same polynomial rustyworld's refcksum uses) and emit
# "<tick> <crc32hex>" per line -- the exact format of ref_checksums.log.
#
# Question it answers: what is our port's per-frame framebuffer checksum stream?
#
#   python3 -I cksum_pages.py <pages.bin> <pages.idx> <out.log>
import sys, zlib

PAGE = 320 * 200  # 64000 bytes, one palette index per pixel

def main():
    binpath, idxpath, outpath = sys.argv[1], sys.argv[2], sys.argv[3]
    ticks = [int(line.split()[0]) for line in open(idxpath) if line.strip()]
    data = open(binpath, "rb").read()
    assert len(data) == len(ticks) * PAGE, \
        f"{len(data)} bytes != {len(ticks)} ticks * {PAGE}"
    with open(outpath, "w") as out:
        for i, tick in enumerate(ticks):
            block = data[i * PAGE:(i + 1) * PAGE]
            crc = zlib.crc32(block) & 0xFFFFFFFF
            out.write(f"{tick} {crc:08x}\n")
    print(f"cksum_pages: wrote {outpath} ({len(ticks)} frames)")

if __name__ == "__main__":
    main()
