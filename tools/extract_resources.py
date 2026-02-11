#!/usr/bin/env python3
"""Extract Another World resources from original DOS game data files.

Usage:
    python3 tools/extract_resources.py <game_data_dir> [output_dir]

The game_data_dir should contain either:
    - Pre-extracted resource-0x*.bin files (preferred), OR
    - MEMLIST.BIN + BANK01..BANK0D (packed resource data banks)

Resources are extracted to output_dir (default: src/resources/).
Pre-existing files with non-zero content are never overwritten with
zero-filled data of the same size — the best version is always kept.

Reference: https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter
"""

import os
import struct
import sys


# Resource types from the reference implementation
RT_SOUND = 0
RT_MUSIC = 1
RT_POLY_ANIM = 2
RT_PALETTE = 3
RT_BYTECODE = 4
RT_POLY_CINEMATIC = 5

MEMENTRY_STATE_END = 0xFF

# Game parts and their resource indices (from parts.cpp)
# Each part: [palette, bytecode, video1, video2]
GAME_PARTS = [
    # Part 0: Protection screens
    {"name": "protection",  "palette": 0x14, "code": 0x15, "video1": 0x16, "video2": None},
    # Part 1: Introduction cinematic
    {"name": "intro",       "palette": 0x17, "code": 0x18, "video1": 0x19, "video2": None},
    # Part 2: Water / lake
    {"name": "water",       "palette": 0x1A, "code": 0x1B, "video1": 0x1C, "video2": 0x11},
    # Part 3: Jail / prison
    {"name": "jail",        "palette": 0x1D, "code": 0x1E, "video1": 0x1F, "video2": 0x11},
    # Part 4: Citadel
    {"name": "citadel",     "palette": 0x20, "code": 0x21, "video1": 0x22, "video2": 0x11},
    # Part 5: Battlechar cinematic
    {"name": "battlechar",  "palette": 0x23, "code": 0x24, "video1": 0x25, "video2": None},
    # Part 6: Arena
    {"name": "arena",       "palette": 0x26, "code": 0x27, "video1": 0x28, "video2": 0x11},
    # Part 7: Final / ending
    {"name": "final",       "palette": 0x29, "code": 0x2A, "video1": 0x2B, "video2": 0x11},
    # Part 8-9: Password screen
    {"name": "password",    "palette": 0x7D, "code": 0x7E, "video1": 0x7F, "video2": None},
]

# Screen bitmap resources (special, loaded via opcode 0x19)
SCREEN_RESOURCES = [0x49, 0x53]


def read_memlist(path):
    """Parse memlist.bin into a list of resource entries."""
    entries = []
    with open(path, 'rb') as f:
        idx = 0
        while True:
            data = f.read(20)
            if len(data) < 20:
                break
            state = data[0]
            if state == MEMENTRY_STATE_END:
                break
            res_type = data[1]
            buf_ptr = struct.unpack('>H', data[2:4])[0]
            unk4 = struct.unpack('>H', data[4:6])[0]
            rank_num = data[6]
            bank_id = data[7]
            bank_offset = struct.unpack('>I', data[8:12])[0]
            unkC = struct.unpack('>H', data[12:14])[0]
            packed_size = struct.unpack('>H', data[14:16])[0]
            unk10 = struct.unpack('>H', data[16:18])[0]
            size = struct.unpack('>H', data[18:20])[0]
            entries.append({
                'index': idx,
                'state': state,
                'type': res_type,
                'rank': rank_num,
                'bank_id': bank_id,
                'bank_offset': bank_offset,
                'packed_size': packed_size,
                'size': size,
            })
            idx += 1
    return entries


def unpack(src, dst_size):
    """Decompress Another World packed data.

    The compression format uses a backward-writing scheme with
    bit-level control for literal bytes and back-references.
    """
    if len(src) < 12:
        return src[:dst_size]

    # Read trailer (last 12 bytes)
    end = len(src)
    data_size = struct.unpack('>I', src[end-4:end])[0]
    crc = struct.unpack('>I', src[end-8:end-4])[0]
    chk = struct.unpack('>I', src[end-12:end-8])[0]

    dst = bytearray(dst_size)
    src_pos = end - 12
    dst_pos = dst_size - 1
    bits = chk

    def next_bit():
        nonlocal bits, crc, src_pos
        carry = bits & 1
        bits >>= 1
        if bits == 0:
            src_pos -= 4
            if src_pos >= 0:
                bits = struct.unpack('>I', src[src_pos:src_pos+4])[0]
            else:
                bits = 0
            crc ^= bits
            carry = bits & 1
            bits = (bits >> 1) | 0x80000000
        return carry

    def get_bits(n):
        val = 0
        for _ in range(n):
            val = (val << 1) | next_bit()
        return val

    def copy_from_dst(offset, count):
        nonlocal dst_pos
        for _ in range(count):
            if dst_pos >= 0 and dst_pos + offset < dst_size:
                dst[dst_pos] = dst[dst_pos + offset]
            dst_pos -= 1

    while dst_pos >= 0:
        if next_bit():  # Bit = 1: back-reference
            if next_bit():  # 11: long copy
                length = get_bits(2)
                if length == 0:
                    # 1100: copy 1 byte from distance
                    length = 1
                    offset = get_bits(8)
                elif length == 1:
                    # 1101
                    length = 2
                    offset = get_bits(8)
                elif length == 2:
                    # 1110
                    length = get_bits(8) + 1
                    offset = get_bits(12)
                else:
                    # 1111
                    length = get_bits(8) + 9
                    offset = get_bits(12)
                copy_from_dst(offset + 1, length)
            else:  # 10: short copy
                offset = get_bits(8)
                length = 2
                copy_from_dst(offset + 1, length)
        else:  # Bit = 0: literal byte
            if dst_pos >= 0:
                dst[dst_pos] = get_bits(8)
                dst_pos -= 1

    return bytes(dst)


def find_bank_file(game_dir, bank_id):
    """Find a bank file, trying different case conventions."""
    names = [
        f'bank{bank_id:02x}',
        f'BANK{bank_id:02X}',
        f'Bank{bank_id:02x}',
        f'bank{bank_id:02X}',
    ]
    for name in names:
        path = os.path.join(game_dir, name)
        if os.path.exists(path):
            return path
    return None


def find_memlist(game_dir):
    """Find memlist.bin trying different case conventions."""
    for name in ['memlist.bin', 'MEMLIST.BIN', 'Memlist.bin']:
        path = os.path.join(game_dir, name)
        if os.path.exists(path):
            return path
    return None


def has_nonzero_content(data):
    """Check if data contains any non-zero bytes."""
    return any(b != 0 for b in data)


def find_preextracted(game_dir, idx):
    """Look for a pre-extracted resource-0x*.bin file in the game data directory."""
    path = os.path.join(game_dir, f'resource-0x{idx:02x}.bin')
    if os.path.exists(path):
        with open(path, 'rb') as f:
            return f.read()
    return None


def extract_resource(game_dir, entry):
    """Extract a single resource from its bank file."""
    bank_path = find_bank_file(game_dir, entry['bank_id'])
    if not bank_path:
        return None

    with open(bank_path, 'rb') as f:
        f.seek(entry['bank_offset'])
        packed_data = f.read(entry['packed_size'])

    if entry['packed_size'] == entry['size']:
        # Not compressed
        return packed_data
    else:
        # Compressed
        return unpack(packed_data, entry['size'])


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    game_dir = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else 'src/resources'

    memlist_path = find_memlist(game_dir)
    if not memlist_path:
        print(f"Warning: memlist.bin not found in {game_dir}, using pre-extracted files only",
              file=sys.stderr)
        entries = []
    else:
        print(f"Reading {memlist_path}...")
        entries = read_memlist(memlist_path)
        print(f"Found {len(entries)} resource entries")

    os.makedirs(output_dir, exist_ok=True)

    # Determine which resources we need
    needed = set()
    for part in GAME_PARTS:
        for key in ('palette', 'code', 'video1', 'video2'):
            if part[key] is not None:
                needed.add(part[key])
    for res_id in SCREEN_RESOURCES:
        needed.add(res_id)

    type_names = {
        RT_SOUND: 'sound', RT_MUSIC: 'music', RT_POLY_ANIM: 'poly_anim',
        RT_PALETTE: 'palette', RT_BYTECODE: 'bytecode', RT_POLY_CINEMATIC: 'poly_cine',
    }

    # Build index of entries by resource ID
    entry_by_id = {}
    for entry in entries:
        entry_by_id[entry['index']] = entry

    extracted = 0
    kept = 0
    failed = 0

    for idx in sorted(needed):
        entry = entry_by_id.get(idx)
        type_name = type_names.get(entry['type'], f"type{entry['type']}") if entry else 'unknown'
        out_path = os.path.join(output_dir, f'resource-0x{idx:02x}.bin')

        # Gather candidate data from multiple sources
        # Source 1: Bank extraction
        bank_data = None
        if entry:
            bank_data = extract_resource(game_dir, entry)

        # Source 2: Pre-extracted file in game_data directory
        preextracted = find_preextracted(game_dir, idx)

        # Source 3: Existing file in output directory
        existing = None
        if os.path.exists(out_path):
            with open(out_path, 'rb') as f:
                existing = f.read()

        # Pick the best version:
        # 1. Prefer data with non-zero content
        # 2. Among non-zero candidates, prefer the one with correct size from memlist
        # 3. Among zero-filled candidates, prefer the one with correct size
        expected_size = entry['size'] if entry else None

        candidates = []
        for label, data in [('bank', bank_data), ('pre-extracted', preextracted), ('existing', existing)]:
            if data is not None:
                nz = has_nonzero_content(data)
                size_match = (expected_size is None) or (len(data) == expected_size)
                candidates.append((label, data, nz, size_match))

        if not candidates:
            print(f"  [FAIL] 0x{idx:02X} ({type_name}): no data source available")
            failed += 1
            continue

        # Sort: non-zero first, then size-matching, then by source preference
        best_label, best_data, best_nz, _ = max(
            candidates,
            key=lambda c: (c[2], c[3], len(c[1]))  # nz > size_match > larger
        )

        # Don't overwrite a good existing file with zero-filled data
        if existing is not None and has_nonzero_content(existing) and not best_nz:
            print(f"  [KEEP] 0x{idx:02X} ({type_name}): keeping existing {len(existing)} bytes (new data is zero-filled)")
            kept += 1
            continue

        # Don't overwrite if identical
        if existing is not None and existing == best_data:
            print(f"  [SAME] 0x{idx:02X} ({type_name}): {len(best_data)} bytes (unchanged)")
            kept += 1
            continue

        with open(out_path, 'wb') as f:
            f.write(best_data)

        status = "OK" if best_nz else "ZERO"
        print(f"  [{status:4s}] 0x{idx:02X} ({type_name}): {len(best_data)} bytes from {best_label} -> {out_path}")
        extracted += 1

    print(f"\nExtracted {extracted} resources, {kept} kept, {failed} failed")

    # Summary of what each part needs
    print("\nPart resource mapping:")
    for i, part in enumerate(GAME_PARTS):
        ids = [f"0x{part[k]:02X}" if part[k] is not None else "----" for k in ('palette', 'code', 'video1', 'video2')]
        print(f"  Part {i} ({part['name']:12s}): pal={ids[0]} code={ids[1]} vid1={ids[2]} vid2={ids[3]}")


if __name__ == '__main__':
    main()
