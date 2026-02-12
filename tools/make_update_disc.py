#!/usr/bin/env python3
"""
Create a KN5000 system update floppy disc image.

Produces a raw 1.44MB floppy image with the KN5000 update disc format:
  - 38-byte signature identifying the update type
  - SLIDE4K (LZSS) compressed ROM data with header
  - Padded to 1,474,560 bytes (2880 sectors x 512 bytes)

Usage:
    python tools/make_update_disc.py <rom_file> <output_image> [--type TYPE]

Types:
    7  - Compressed Program ROM (default)
    8  - Compressed Table Data ROM
    6  - Uncompressed HDAE5000 extension ROM

The KN5000 firmware detects the update type from the first 38 bytes
of the disc and programs the appropriate flash chip.
"""

import sys
import os

# Add parent's scripts dir to path for compress_lzss
COMPRESS_SCRIPT = os.path.join(
    os.path.dirname(__file__),
    '..', '..', '..', 'kn5000-roms-disasm', 'scripts', 'compress_lzss.py'
)

# Import compression from the existing tool
sys.path.insert(0, os.path.dirname(os.path.abspath(COMPRESS_SCRIPT)))
from compress_lzss import compress_slide4k

# Floppy disc parameters
FLOPPY_SIZE = 1474560  # 2880 sectors x 512 bytes = 1.44MB
SECTOR_SIZE = 512

# Update disc signatures (38 bytes each, as stored in table_data ROM at 0x9FA000)
SIGNATURES = {
    7: b"Technics KN5000 Program  DATA FILE PCK",
    8: b"Technics KN5000 Table    DATA FILE PCK",
    6: b"Technics KN5000 HD-AEPRG DATA FILE    ",
}


def make_slide4k_header(decompressed_size):
    """Build the 11-byte SLIDE4K header: magic + 24-bit big-endian size."""
    header = bytearray(b"SLIDE4K\x00")
    # 24-bit big-endian decompressed size
    header.append((decompressed_size >> 16) & 0xFF)
    header.append((decompressed_size >> 8) & 0xFF)
    header.append(decompressed_size & 0xFF)
    return bytes(header)


def make_update_disc(rom_data, disc_type=7):
    """Create a complete floppy disc image for a KN5000 update."""
    if disc_type not in SIGNATURES:
        raise ValueError(f"Unknown disc type {disc_type}. Supported: {list(SIGNATURES.keys())}")

    signature = SIGNATURES[disc_type]
    assert len(signature) == 38, f"Signature must be 38 bytes, got {len(signature)}"

    if disc_type in (7, 8):
        # Compressed format: signature + SLIDE4K header + compressed data
        print(f"Compressing {len(rom_data):,} bytes with SLIDE4K...")
        compressed = compress_slide4k(rom_data)
        print(f"Compressed: {len(compressed):,} bytes ({100 * len(compressed) / len(rom_data):.1f}%)")

        slide4k_header = make_slide4k_header(len(rom_data))
        payload = slide4k_header + compressed

        total_data = len(signature) + len(payload)
        if total_data > FLOPPY_SIZE:
            raise RuntimeError(
                f"Compressed data ({total_data:,} bytes) exceeds floppy capacity "
                f"({FLOPPY_SIZE:,} bytes). Cannot create update disc."
            )
    elif disc_type == 6:
        # Uncompressed format: signature + raw ROM data
        payload = rom_data
        total_data = len(signature) + len(payload)
        if total_data > FLOPPY_SIZE:
            raise RuntimeError(
                f"ROM data ({total_data:,} bytes) exceeds floppy capacity "
                f"({FLOPPY_SIZE:,} bytes). Cannot create update disc."
            )
    else:
        raise ValueError(f"Disc type {disc_type} not yet supported")

    # Build disc image: signature + payload + padding
    image = bytearray(FLOPPY_SIZE)
    # Fill with 0xFF (erased flash state) for unused sectors
    for i in range(FLOPPY_SIZE):
        image[i] = 0xFF
    # Write signature
    image[0:38] = signature
    # Write payload
    image[38:38 + len(payload)] = payload

    return bytes(image)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <rom_file> <output_image> [--type TYPE]")
        print()
        print("Create a KN5000 system update floppy disc image.")
        print()
        print("Options:")
        print("  --type TYPE  Update type: 7=Program ROM (default), 8=Table Data, 6=HDAE5000")
        sys.exit(1)

    rom_file = sys.argv[1]
    output_file = sys.argv[2]

    # Parse disc type
    disc_type = 7
    if '--type' in sys.argv:
        idx = sys.argv.index('--type')
        if idx + 1 < len(sys.argv):
            disc_type = int(sys.argv[idx + 1])

    # Read ROM
    with open(rom_file, 'rb') as f:
        rom_data = f.read()
    print(f"Input ROM: {rom_file} ({len(rom_data):,} bytes)")

    # Create disc image
    image = make_update_disc(rom_data, disc_type)

    # Write output
    with open(output_file, 'wb') as f:
        f.write(image)
    print(f"Output disc image: {output_file} ({len(image):,} bytes)")
    print(f"Update type: {disc_type} ({SIGNATURES[disc_type].decode('ascii').strip()})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
