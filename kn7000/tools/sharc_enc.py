#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# sharc_enc.py -- a minimal ADSP-2106x / ADSP-21065L ("SHARC") instruction encoder: only the instruction forms the
# effects-DSP sample mixer (tools/dsp_mixer.py) uses.
#
# COPIED from technics-roms-disasm kn7000/tools/dsptone/sharc_enc.py (DSPTONE, iteration 1 of our own program on
# the KN7000's effects DSP; as last changed by its commit 07d1d519f), so that this repository builds on
# its own. Added here: the multiplier's "Rn = Rx * Ry (SSI)" (mul_ssi), the shifter's shifts by a register
# (shift_reg) and the ALU's XOR; on 2026-10-21 (the bank decoder) Program.call, a CALL to a label. Keep the two
# copies' common part in step by hand.
#
# There is no SHARC assembler in either project, so each form is encoded from the bit layout MAME's SHARC
# disassembler decodes (src/devices/cpu/sharc/sharc_dasm.cpp: the opcode table at the end, and each dasm_*
# routine), and every instruction is checked against that disassembler (unidasm -arch sharc) by dsp_mixer.py
# --check: an instruction whose text differs from what was meant stops the build.
#
# A 48-bit instruction word is returned as an int. Registers are named as the disassembler names them
# ("R0".."R15", "I0".."I15", "M0".."M15", "L0".., "B0"..); conditions as its condition_codes_if table.

UREG = {}
for _k, _p in enumerate("RIMLB"):
    for _n in range(16):
        UREG[f"{_p}{_n}"] = _k * 16 + _n

COND = {c: n for n, c in enumerate(
    ["EQ", "LT", "LE", "AC", "AV", "MV", "MS", "SV", "SZ", "FLAG0_IN", "FLAG1_IN", "FLAG2_IN", "FLAG3_IN",
     "TF", "BM", "NOT LCE", "NE", "GE", "GT", "NOT AC", "NOT AV", "NOT MV", "NOT MS", "NOT SV", "NOT SZ",
     "NOT FLAG0_IN", "NOT FLAG1_IN", "NOT FLAG2_IN", "NOT FLAG3_IN", "NOT TF", "NBM", "TRUE"])}

# single-function ALU operations, fixed point (compute field, CU = 00): opcode, operands used
ALU = {"ADD": 0x01, "SUB": 0x02, "COMP": 0x0A, "PASS": 0x21, "INC": 0x29, "DEC": 0x2A, "AND": 0x40,
       "OR": 0x41, "XOR": 0x42, "MIN": 0x61, "MAX": 0x62, "CLIP": 0x63}
SHIFT_IMM = {"LSHIFT": 0x00, "ASHIFT": 0x01}
SHIFT_REG = {"LSHIFT": 0x00, "ASHIFT": 0x04}   # shifter (compute field CU = 10): Rn = LSHIFT/ASHIFT Rx BY Ry


def _r(name):
    assert name[0] == "R" and 0 <= int(name[1:]) < 16, name
    return int(name[1:])


def _u(name):
    return UREG[name]


def _dag1(name):
    n = int(name[1:])
    assert name[0] in "IM" and 0 <= n < 8, f"{name}: a DAG1 register (I0-I7 / M0-M7)"
    return n


# ---- compute fields (23 bits) --------------------------------------------------------------------
def alu(op, rn, rx, ry="R0"):
    """single-function fixed-point ALU: Rn = Rx op Ry"""
    return (ALU[op] << 12) | (_r(rn) << 8) | (_r(rx) << 4) | _r(ry)


def mul_ssi(rn, rx, ry):
    """single-function multiplier (CU = 01), opcode 0x70: Rn = Rx * Ry (SSI): signed integers, the low 32 bits"""
    return (1 << 20) | (0x70 << 12) | (_r(rn) << 8) | (_r(rx) << 4) | _r(ry)


def shift_reg(op, rn, rx, ry):
    """single-function shifter (CU = 10): Rn = LSHIFT/ASHIFT Rx BY Ry (Ry's low byte, signed: < 0 shifts right)"""
    return (2 << 20) | (SHIFT_REG[op] << 12) | (_r(rn) << 8) | (_r(rx) << 4) | _r(ry)


# ---- instructions --------------------------------------------------------------------------------
def nop():
    return 0


def compute(comp, cond="TRUE"):
    """type 2: IF cond compute"""
    return (0x01 << 40) | (COND[cond] << 33) | comp


def shift_imm(op, rn, rx, amount, cond="TRUE"):
    """type 6 without a data move: Rn = LSHIFT/ASHIFT Rx BY amount (signed 8 bits)"""
    assert -128 <= amount < 128
    d = amount & 0xFF
    return (0x02 << 40) | (COND[cond] << 33) | (SHIFT_IMM[op] << 16) | (d << 8) | (_r(rn) << 4) | _r(rx)


def ureg_move(dst, src, cond="TRUE"):
    """type 5: dst = src (any two universal registers)"""
    return (0x7 << 44) | (_u(src) << 36) | (COND[cond] << 31) | (_u(dst) << 23)


def ureg_imm(dst, value):
    """type 17: ureg = 32-bit immediate"""
    return (0x0F << 40) | (_u(dst) << 32) | (value & 0xFFFFFFFF)


def dm_read_abs(dst, addr):
    """type 14: ureg = DM(addr32)"""
    return (0x10 << 40) | (_u(dst) << 32) | (addr & 0xFFFFFFFF)


def dm_write_abs(addr, src):
    """type 14: DM(addr32) = ureg"""
    return (0x11 << 40) | (_u(src) << 32) | (addr & 0xFFFFFFFF)


def dm_read_off(dst, offset, ireg):
    """type 15: ureg = DM(data32, Ia) -- address Ia + data32, Ia not updated (no circular wrap)"""
    return (0b101 << 45) | (_dag1(ireg) << 41) | (_u(dst) << 32) | (offset & 0xFFFFFFFF)


def dm_write_off(offset, ireg, src):
    """type 15: DM(data32, Ia) = ureg"""
    return (0b101 << 45) | (_dag1(ireg) << 41) | (1 << 40) | (_u(src) << 32) | (offset & 0xFFFFFFFF)


def dm_post(ureg, ireg, mreg, write):
    """type 3 without a compute: ureg = DM(Ia, Mb) / DM(Ia, Mb) = ureg, post-modify (Ia += Mb)"""
    return ((0b010 << 45) | (1 << 44) | (_dag1(ireg) << 41) | (_dag1(mreg) << 38) | (COND["TRUE"] << 33)
            | ((1 if write else 0) << 31) | (_u(ureg) << 23))


def jump_abs(addr, cond="TRUE", call=False, db=False):
    """type 8: [IF cond] JUMP/CALL (addr24) [(DB)]"""
    return ((0x06 << 40) | ((1 if call else 0) << 39) | (COND[cond] << 33) | ((1 if db else 0) << 26)
            | (addr & 0xFFFFFF))


def jump_rel(offset, cond="TRUE"):
    """type 8, PC-relative: [IF cond] JUMP (PC + offset)"""
    return (0x07 << 40) | (COND[cond] << 33) | (offset & 0xFFFFFF)


def rts(db=True):
    """type 11: RTS [(DB)]"""
    return (0x0A << 40) | (COND["TRUE"] << 33) | ((1 if db else 0) << 26)


def modify_imm(ireg, value):
    """type 19: MODIFY (Ia, data32)"""
    n = int(ireg[1:])
    return (0x16 << 40) | ((1 if n >= 8 else 0) << 38) | ((n & 7) << 32) | (value & 0xFFFFFFFF)


class Program:
    """a list of (instruction word, the text the disassembler must print) with labels for PC-relative jumps"""

    def __init__(self, base):
        self.base = base
        self.items = []          # [word or (callable, label), expected text]
        self.labels = {}

    @property
    def pc(self):
        return self.base + len(self.items)

    def label(self, name):
        assert name not in self.labels, name
        self.labels[name] = self.pc

    def emit(self, word, text):
        self.items.append([word, text])

    def jump(self, label, cond="TRUE"):
        """IF cond JUMP label (PC-relative, not delayed)"""
        self.items.append([("jump", label, cond), None])

    def call(self, label):
        """CALL label (absolute, not delayed)"""
        self.items.append([("call", label, "TRUE"), None])

    def assemble(self):
        out = []
        for k, (w, text) in enumerate(self.items):
            pc = self.base + k
            if isinstance(w, tuple):
                kind, label, cond = w
                target = self.labels[label]
                if kind == "call":
                    w = jump_abs(target, call=True)
                    text = f"CALL (0x{target:08X})"
                else:
                    w = jump_rel(target - pc, cond)
                    text = ("" if cond == "TRUE" else f"IF {cond}, ") + f"JUMP (0x{target:08X})"
            out.append((pc, w, text))
        return out
