#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# dsp_bank.py -- the effects DSP's sample bank as it goes onto the SD card and through the host port: losslessly
# compressed, decoded by the DSP itself (tools/dsp_mixer.py, the decoder in unit 0), and checked by a checksum the
# DSP computes over the SDRAM it wrote (README-CNV.md, "Sound"; src/dsp.s BankStep).
#
# Why. The host port moves one 16-bit half per DSP frame (the firmware's handshake: 44,100 a second, 22.68 us), and
# the card is read by the firmware's own FAT code at the CPU's pace. Before 2026-10-21 the game read the 93 sounds as
# their ByteKiller-packed resource files (574,084 bytes), unpacked each, and sent the 686,304 bytes of the bank raw:
# 25.9 s in MAME (probes/cnv/README.md, "Round 3": 10.2 s reading the card, 1.7 s unpacking, 12.3 s of host-port
# traffic, 1.7 s between converter calls). The same bank, Rice-coded, is about 61 % of that, read from a few files
# and sent as it is read, never unpacked by the main CPU.
#
# The code (lossless; every block decodes on its own):
#   * the bank is the SDRAM image tools/aw_extract.py lays out: each sound from a word that is a whole number of
#     COPY_STEP words past BANK, four 8-bit samples a 32-bit word, the first in the low byte, and the words between
#     two sounds zero;
#   * it is cut into blocks of whole words, each at most STAGE_HALF DM words once coded (two header words: the first
#     output word's offset from BANK, the output words; then the bit stream, 32 bits a word, most significant first);
#   * in a block, each sample is predicted by the one before it (the first by 0): d = (v - previous) mod 256, read
#     as -128..127, folded to z = 2d (d >= 0) or -2d - 1 (d < 0);
#   * every GROUP samples (from the block's start) a 3-bit k; then each z as Rice(k): q = z >> k zero bits, a one,
#     and z's low k bits, most significant first; when q >= QMAX: QMAX zero bits and z in 8 bits (no one).
# decode() below is the DSP's decoder step for step (tools/dsp_mixer.py); the build decodes every block with it
# and stops unless the result is the bank, word for word.
#
# The checksum: c = 0; for each word w of the bank, c = rotl(c, 1) xor w (32 bits). The DSP computes it over SDRAM
# once the last block is decoded (and at a later start that finds the bank there), and the host compares it with the
# one in AWBANK.AW: the bank is used only when they agree.
#
# The card files AWSB0.AW, AWSB1.AW ...: blocks, each as u32 n (its DM words, header included) and the n words,
# little-endian (the host uploads them as they are: two 16-bit halves a word, the low one first); a file holds
# whole blocks, at most FILE_MAX bytes.
import struct

STAGE_HALF = 128          # DM words per staging buffer (two: the DSP decodes one while the host fills the other)
HEADER = 2
GROUP = 64                # samples per k
QMAX = 12                 # the unary part's escape
KBITS = 3
FILE_MAX = 32768          # bytes per card file (one is read per converter call)


def _sx(b):
    return b - 256 if b >= 128 else b


class _Bits:
    def __init__(self):
        self.words, self.acc, self.n = [], 0, 0

    def put(self, value, bits):
        for i in range(bits - 1, -1, -1):
            self.acc = (self.acc << 1) | ((value >> i) & 1)
            self.n += 1
            if self.n == 32:
                self.words.append(self.acc)
                self.acc, self.n = 0, 0

    def flush(self):
        if self.n:
            self.words.append(self.acc << (32 - self.n))
            self.acc, self.n = 0, 0
        return self.words


def _zs(samples):
    prev, out = 0, []
    for v in samples:
        d = _sx((v - prev) & 0xFF)
        out.append(2 * d if d >= 0 else -2 * d - 1)
        prev = v
    return out


def _zcost(z, k):
    q = z >> k
    return QMAX + 8 if q >= QMAX else q + 1 + k


def _group_bits(zs):
    return KBITS + min(sum(_zcost(z, k) for z in zs) for k in range(8))


def _encode_block(off, samples):
    zs = _zs(samples)
    b = _Bits()
    for g in range(0, len(zs), GROUP):
        grp = zs[g:g + GROUP]
        k = min(range(8), key=lambda k: (sum(_zcost(z, k) for z in grp), k))
        b.put(k, KBITS)
        for z in grp:
            q = z >> k
            if q >= QMAX:
                b.put(0, QMAX)
                b.put(z, 8)
            else:
                b.put(0, q)
                b.put(1, 1)
                b.put(z & ((1 << k) - 1), k)
    return [off, len(samples) // 4] + b.flush()


def encode(bank):
    """bank: the SDRAM image (bytes, a multiple of 4) -> list of blocks (lists of DM words, header included). Each
    block takes as many words as fit STAGE_HALF once coded (groups align with words: GROUP is 16 words)."""
    assert len(bank) % 4 == 0 and GROUP % 4 == 0
    words = len(bank) // 4
    limit = (STAGE_HALF - HEADER) * 32
    blocks, w = [], 0
    while w < words:
        n, prev, done, ksum = 0, 0, 0, [0] * 8   # words taken; the predictor; bits of whole groups; this group's
        while w + n < words:
            s = bank[4 * (w + n):4 * (w + n + 1)]
            add, p = [0] * 8, prev
            for v in s:
                d = _sx((v - p) & 0xFF)
                z = 2 * d if d >= 0 else -2 * d - 1
                for k in range(8):
                    add[k] += _zcost(z, k)
                p = v
            trial = [ksum[k] + add[k] for k in range(8)]
            if done + KBITS + min(trial) > limit:
                break
            n, prev, ksum = n + 1, p, trial
            if (4 * n) % GROUP == 0:
                done, ksum = done + KBITS + min(ksum), [0] * 8
        assert n > 0
        blk = _encode_block(w, list(bank[4 * w:4 * (w + n)]))
        assert len(blk) <= STAGE_HALF, len(blk)
        blocks.append(blk)
        w += n
    return blocks


def decode(blocks, words):
    """the DSP's decoder (tools/dsp_mixer.py, unit 0's decode step), on the blocks -> the bank's words"""
    out = [None] * words
    for blk in blocks:
        off, nw = blk[0], blk[1]
        assert 0 <= off and off + nw <= words
        stream, pos = blk[HEADER:], 0
        buf, nb = 0, 0

        def bit():
            nonlocal buf, nb, pos
            if nb == 0:
                buf, nb = stream[pos], 32
                pos += 1
            r = buf >> 31
            buf, nb = (buf << 1) & 0xFFFFFFFF, nb - 1
            return r
        prev, k, gleft = 0, 0, 0
        for i in range(nw):
            word = 0
            for _ in range(4):
                if gleft == 0:
                    k = 0
                    for _ in range(KBITS):
                        k = (k << 1) | bit()
                    gleft = GROUP
                gleft -= 1
                q = 0
                while True:
                    if bit():
                        z = q
                        for _ in range(k):
                            z = (z << 1) | bit()
                        break
                    q += 1
                    if q >= QMAX:
                        z = 0
                        for _ in range(8):
                            z = (z << 1) | bit()
                        break
                d = (z >> 1) ^ -(z & 1)
                prev = (prev + d) & 0xFF
                word = (word >> 8) | (prev << 24)
            out[off + i] = word
    return out


def checksum(words):
    c = 0
    for w in words:
        c = (((c << 1) | (c >> 31)) & 0xFFFFFFFF) ^ w
    return c


def card_files(blocks, prefix="AWSB"):
    """-> {name: bytes}: the blocks, FILE_MAX bytes a file at most, in order"""
    files, cur = [], b""
    for blk in blocks:
        rec = struct.pack(f"<I{len(blk)}I", len(blk), *blk)
        if cur and len(cur) + len(rec) > FILE_MAX:
            files.append(cur)
            cur = b""
        cur += rec
    if cur:
        files.append(cur)
    return {f"{prefix}{i:X}.AW": b for i, b in enumerate(files)}


def build(bank):
    """-> (files, checksum, blocks): encoded and checked by decoding every block"""
    blocks = encode(bank)
    words = len(bank) // 4
    ref = list(struct.unpack(f"<{words}I", bank))
    got = decode(blocks, words)
    if got != ref:
        bad = next(i for i in range(words) if got[i] != ref[i])
        raise SystemExit(f"dsp_bank: the decoder gives word {bad} wrong ({got[bad]} for {ref[bad]:08X})")
    files = card_files(blocks)
    if len(files) > 16:
        raise SystemExit(f"dsp_bank: {len(files)} card files; AWSB0-F.AW are the names src/dsp.s makes")
    return files, checksum(ref), blocks
