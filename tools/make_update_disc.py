#!/usr/bin/env python3
"""
Create a KN5000 system update floppy disc image.

Produces a FAT12-formatted 1.44MB floppy image matching the format of
original Technics KN5000 system update discs (as archived at Internet Archive).

Disc layout (FAT12, 2880 sectors x 512 bytes):
  - Boot sector with OEM ID "Technics" and standard 1.44MB BPB
  - Two FAT12 tables (9 sectors each)
  - Root directory (224 entries, 14 sectors)
  - Data area with files:
      TECHNICS.PRP  - 56-byte signature file (type 7) or TECHNICS.AE (type 6)
      DUMMY.1       - 64-byte placeholder
      DUMMY.2       - 64-byte placeholder
      HKMSPRG.SLD   - SLIDE4K compressed ROM (type 7) or HKEXTROM.XAP (type 6)

Usage:
    python tools/make_update_disc.py <rom_file> <output_image> [--type TYPE]

Types:
    7  - Compressed Program ROM (default)
    6  - Uncompressed HDAE5000 extension ROM
"""

import sys
import os
import struct

# Add parent's scripts dir to path for compress_lzss
COMPRESS_SCRIPT = os.path.join(
    os.path.dirname(__file__),
    '..', '..', '..', 'kn5000-roms-disasm', 'scripts', 'compress_lzss.py'
)

# Import compression from the existing tool
sys.path.insert(0, os.path.dirname(os.path.abspath(COMPRESS_SCRIPT)))
from compress_lzss import compress_slide4k

# ============================================================================
# Floppy disc parameters (standard 1.44MB 3.5" HD)
# ============================================================================
FLOPPY_SIZE = 1474560       # 2880 sectors x 512 bytes
SECTOR_SIZE = 512
SECTORS_PER_CLUSTER = 1
RESERVED_SECTORS = 1
NUM_FATS = 2
ROOT_ENTRIES = 224
TOTAL_SECTORS = 2880
SECTORS_PER_FAT = 9
SECTORS_PER_TRACK = 18
NUM_HEADS = 2
MEDIA_DESCRIPTOR = 0xF0     # 3.5" HD floppy

# Derived layout
FAT1_START = RESERVED_SECTORS * SECTOR_SIZE                         # 0x0200
FAT2_START = (RESERVED_SECTORS + SECTORS_PER_FAT) * SECTOR_SIZE     # 0x1400
ROOT_DIR_START = (RESERVED_SECTORS + NUM_FATS * SECTORS_PER_FAT) * SECTOR_SIZE  # 0x2600
ROOT_DIR_SECTORS = (ROOT_ENTRIES * 32 + SECTOR_SIZE - 1) // SECTOR_SIZE  # 14
DATA_START = ROOT_DIR_START + ROOT_DIR_SECTORS * SECTOR_SIZE        # 0x4200
FIRST_DATA_CLUSTER = 2      # FAT convention: cluster 2 = first data cluster

# Data area capacity (for file size validation)
DATA_CAPACITY = FLOPPY_SIZE - DATA_START

# Fill byte for unused data sectors (matches original Technics discs)
FILL_BYTE = 0xE5

# ============================================================================
# Disc type definitions
# ============================================================================
# Each type defines the signature file, data file name, and processing
DISC_TYPES = {
    7: {
        'sig_name': 'TECHNICS.PRP',
        'sig_content': (
            b"Technics KN5000 Program  DATA FILE PCK"
            b"  by T.Nishino\r\n\r\n"
        ),
        'data_name': 'HKMSPRG.SLD',
        'compressed': True,
    },
    6: {
        'sig_name': 'TECHNICS.AE',
        'sig_content': (
            b"Technics KN5000 HD-AEPRG DATA FILE    "
            b"  by Nishino Teruhiko !!!\r\n\x0a"
        ),
        'data_name': 'HKEXTROM.XAP',
        'compressed': False,
    },
}

# DUMMY files (same content on all disc types)
DUMMY_CONTENT = (
    b"Technics KN5000 Table    DATA FILE 1/2"
    b" by Nishino Teruhiko !!!\r\n"
)


def make_slide4k_header(decompressed_size):
    """Build the 11-byte SLIDE4K header: magic + 24-bit big-endian size."""
    header = bytearray(b"SLIDE4K\x00")
    header.append((decompressed_size >> 16) & 0xFF)
    header.append((decompressed_size >> 8) & 0xFF)
    header.append(decompressed_size & 0xFF)
    return bytes(header)


def make_boot_sector():
    """Build the 512-byte FAT12 boot sector matching Technics OEM format."""
    boot = bytearray(SECTOR_SIZE)

    # Jump instruction + NOP
    boot[0] = 0xEB          # JMP short
    boot[1] = 0x1C          # offset to boot code (0x1E)
    boot[2] = 0x90          # NOP

    # OEM ID (8 bytes)
    boot[3:11] = b"Technics"

    # BIOS Parameter Block
    struct.pack_into('<H', boot, 11, SECTOR_SIZE)           # Bytes per sector
    boot[13] = SECTORS_PER_CLUSTER                          # Sectors per cluster
    struct.pack_into('<H', boot, 14, RESERVED_SECTORS)      # Reserved sectors
    boot[16] = NUM_FATS                                     # Number of FATs
    struct.pack_into('<H', boot, 17, ROOT_ENTRIES)          # Root dir entries
    struct.pack_into('<H', boot, 19, TOTAL_SECTORS)         # Total sectors (16-bit)
    boot[21] = MEDIA_DESCRIPTOR                             # Media descriptor
    struct.pack_into('<H', boot, 22, SECTORS_PER_FAT)       # Sectors per FAT
    struct.pack_into('<H', boot, 24, SECTORS_PER_TRACK)     # Sectors per track
    struct.pack_into('<H', boot, 26, NUM_HEADS)             # Number of heads
    # Hidden sectors (bytes 28-31): 0
    # Extended BPB byte 37: "current head" / reserved (0x01 on v10 disc)
    boot[37] = 0x01
    # Boot code at offset 0x1E: infinite loop (JMP -2)
    boot[0x1E] = 0xEB
    boot[0x1F] = 0xFE

    return bytes(boot)


def make_fat12_entry(fat, cluster, value):
    """Write a 12-bit value into a FAT12 table at the given cluster index."""
    byte_offset = (cluster * 3) // 2
    if cluster % 2 == 0:
        # Low 8 bits in byte[n], low 4 bits of byte[n+1]
        fat[byte_offset] = value & 0xFF
        fat[byte_offset + 1] = (fat[byte_offset + 1] & 0xF0) | ((value >> 8) & 0x0F)
    else:
        # High 4 bits in byte[n], high 8 bits in byte[n+1]
        fat[byte_offset] = (fat[byte_offset] & 0x0F) | ((value & 0x0F) << 4)
        fat[byte_offset + 1] = (value >> 4) & 0xFF


def make_fat_table(file_sizes):
    """Build a FAT12 table for the given list of file sizes.

    Returns a bytearray of SECTORS_PER_FAT * SECTOR_SIZE bytes.
    Files are allocated contiguously starting at cluster 2.
    """
    fat = bytearray(SECTORS_PER_FAT * SECTOR_SIZE)

    # Cluster 0: media descriptor
    make_fat12_entry(fat, 0, 0xFF0 | MEDIA_DESCRIPTOR)
    # Cluster 1: end-of-chain marker
    make_fat12_entry(fat, 1, 0xFFF)

    cluster = FIRST_DATA_CLUSTER
    for size in file_sizes:
        num_clusters = max(1, (size + SECTOR_SIZE - 1) // SECTOR_SIZE)
        for i in range(num_clusters):
            if i == num_clusters - 1:
                make_fat12_entry(fat, cluster, 0xFFF)  # EOF
            else:
                make_fat12_entry(fat, cluster, cluster + 1)  # Next cluster
            cluster += 1

    return fat


def make_dir_entry(filename, ext, size, first_cluster, attr=0x20):
    """Build a 32-byte FAT12 directory entry."""
    entry = bytearray(32)
    # Filename (8 bytes, space-padded)
    name_bytes = filename.encode('ascii')[:8].ljust(8, b' ')
    entry[0:8] = name_bytes
    # Extension (3 bytes, space-padded)
    ext_bytes = ext.encode('ascii')[:3].ljust(3, b' ')
    entry[8:11] = ext_bytes
    # Attributes
    entry[11] = attr
    # First cluster
    struct.pack_into('<H', entry, 26, first_cluster)
    # File size
    struct.pack_into('<I', entry, 28, size)
    return bytes(entry)


def make_update_disc(rom_data, disc_type=7):
    """Create a FAT12-formatted floppy disc image for a KN5000 update."""
    if disc_type not in DISC_TYPES:
        raise ValueError(f"Unknown disc type {disc_type}. Supported: {list(DISC_TYPES.keys())}")

    dtype = DISC_TYPES[disc_type]

    # Prepare file contents
    sig_content = dtype['sig_content']
    sig_name_parts = dtype['sig_name'].split('.')
    sig_name = sig_name_parts[0]
    sig_ext = sig_name_parts[1] if len(sig_name_parts) > 1 else ''

    data_name_parts = dtype['data_name'].split('.')
    data_name = data_name_parts[0]
    data_ext = data_name_parts[1] if len(data_name_parts) > 1 else ''

    if dtype['compressed']:
        print(f"Compressing {len(rom_data):,} bytes with SLIDE4K...")
        compressed = compress_slide4k(rom_data)
        print(f"Compressed: {len(compressed):,} bytes ({100 * len(compressed) / len(rom_data):.1f}%)")
        data_content = make_slide4k_header(len(rom_data)) + compressed
    else:
        data_content = rom_data

    # File list: (name, ext, content)
    files = [
        (sig_name, sig_ext, sig_content),
        ('DUMMY', '1', DUMMY_CONTENT),
        ('DUMMY', '2', DUMMY_CONTENT),
        (data_name, data_ext, data_content),
    ]

    # Validate total data fits
    total_data = sum(len(f[2]) for f in files)
    if total_data > DATA_CAPACITY:
        raise RuntimeError(
            f"File data ({total_data:,} bytes) exceeds floppy data area capacity "
            f"({DATA_CAPACITY:,} bytes). Cannot create update disc."
        )

    # Build disc image
    image = bytearray(FLOPPY_SIZE)
    # Fill unused data area with 0xE5 (matches original Technics discs)
    for i in range(DATA_START, FLOPPY_SIZE):
        image[i] = FILL_BYTE

    # 1. Boot sector
    image[0:SECTOR_SIZE] = make_boot_sector()

    # 2. FAT tables
    file_sizes = [len(f[2]) for f in files]
    fat = make_fat_table(file_sizes)
    image[FAT1_START:FAT1_START + len(fat)] = fat
    image[FAT2_START:FAT2_START + len(fat)] = fat  # FAT2 is a copy

    # 3. Root directory entries
    cluster = FIRST_DATA_CLUSTER
    dir_offset = ROOT_DIR_START
    for name, ext, content in files:
        entry = make_dir_entry(name, ext, len(content), cluster)
        image[dir_offset:dir_offset + 32] = entry
        dir_offset += 32
        num_clusters = max(1, (len(content) + SECTOR_SIZE - 1) // SECTOR_SIZE)
        cluster += num_clusters

    # 4. File data in data area
    data_offset = DATA_START
    for name, ext, content in files:
        image[data_offset:data_offset + len(content)] = content
        # Advance to next cluster boundary
        num_clusters = max(1, (len(content) + SECTOR_SIZE - 1) // SECTOR_SIZE)
        data_offset += num_clusters * SECTOR_SIZE

    return bytes(image)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <rom_file> <output_image> [--type TYPE]")
        print()
        print("Create a KN5000 system update floppy disc image (FAT12 formatted).")
        print()
        print("Options:")
        print("  --type TYPE  Update type: 7=Program ROM (default), 6=HDAE5000")
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
    sig_38 = DISC_TYPES[disc_type]['sig_content'][:38].decode('ascii').strip()
    print(f"Update type: {disc_type} ({sig_38})")
    print(f"Files: {', '.join(DISC_TYPES[disc_type][k] for k in ['sig_name', 'data_name'])}, DUMMY.1, DUMMY.2")

    return 0


if __name__ == "__main__":
    sys.exit(main())
