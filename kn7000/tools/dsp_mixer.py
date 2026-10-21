#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# dsp_mixer.py -- the effects-DSP side of Another World's sound on the KN7000 (README-CNV.md, "Sound"): a
# four-voice sample mixer for the KN7000's effects DSP (IC306, an ADSP-21065L "SHARC"), the data the main CPU
# uploads with it, and the include files src/dsp.s carries them in.
#
#   python3 -I tools/dsp_mixer.py OUT_DIR [--check UNIDASM] [--listing OUT.lst]
# writes OUT_DIR/dsp_equ.inc (addresses and sizes, for src/dsp.s) and OUT_DIR/dsp_data.inc (the program and the
# initial variables, included after the code). --check runs MAME's SHARC disassembler over every word and compares
# each line with the text it was meant to be: any difference stops the build (as DSPTONE's dsp_prog.py does).
#
# Where it comes from. Iteration 1, DSPTONE (technics-roms-disasm kn7000/tools/dsptone, README.md), put a program of
# our own into the running DSP through the firmware's host-port routines, as one *effect unit* of the firmware's
# resident kernel (rec04), and it played on Felipe's KN7000 (program 893) on 2026-10-21. This is the same kind of
# unit, with the same rules (they are why it is written the way it is):
#   * the kernel keeps running everything: the SPORT rings, the 44.1 kHz frame loop, BUSLK, the per-frame strobe
#     the main CPU's handshake waits for. Our code is CALLed from the kernel's unit slots and returns as every
#     effect does: RTS (DB); R4 = DM(I1, M5), R7 = PM(I12, M8); MODIFY (I8, 0x50) (M5 = 0x4D, M8 = +1 in every
#     program build's kernel);
#   * no M0-M7: the kernels of 893/935 set M0 = +1, M2 = +3, those of 941/942 M2 = +1 (DSPTONE kernel_mregs.py).
#     Memory is addressed with immediate offsets (DM(k, Ia)) and absolute addresses only;
#   * I5 and I7 are the only index registers used, saved and put back; I1, I2, I3, I4, I6, I8, I12 belong to the
#     kernel's walk (kn7000/dsp/kernel-architecture.md 4-7) and are left as the unit ABI leaves them (I4 + 2);
#   * MODE1.ALUSAT is set by the kernel: adds saturate, so nothing relies on a wrap.
#
# Two entry points, hooked into two of the kernel's ten CALL slots (src/dsp.s points each slot at its entry with the
# firmware's own single-word PM poke, and puts the firmware's word back on every way out):
#   E0, unit 0 (slot PM 0x8080, normally the panel REVERB at 0x8400). Runs first in the frame, inside BUSLK, so the
#       SDRAM reads and writes are made while the host is held off the bus (as DSPTONE's PCM). Every frame:
#       1. heartbeat: MSGR7 + 1;
#       2. commands: when MSGR6 is not 0, for each voice v (0-3 the sound effects' channels, 4-7 the music's, as
#          rawgl's mixer and module player keep them apart): bit 16+v stops it (END = 0), bit v starts it from the
#          host's command record CMD[v] (BASE, INC, END, LOOP, VOL; POS = FRAC = 0), bit 8+v updates its INC and
#          VOL from CMD[v] without a restart (the music's volume effects); then MSGR6 = 0 (the host waits for 0);
#       3. the mix: for each voice with POS < END, the 8-bit sample at POS (four packed in an SDRAM word, the first
#          in the low byte), sign-extended, times VOL (0..63), summed; then POS.FRAC += INC (16.16 fixed point);
#          past END, POS -= LOOP when the sample loops, else the voice stays silent. MIX = sum * GAIN;
#       4. the bank (tools/dsp_bank.py): MSGR4 = 1 decodes the block the host has put into staging buffer MSGR5
#          (0 or 1, STAGE_HALF words each: the first output word's offset from BANK, the words, the Rice-coded bit
#          stream) into SDRAM, DEC_BITS bits of it a frame (about five samples), and writes MSGR4 = 0 when the
#          block is done; MSGR4 = 2 computes the checksum (dsp_bank.checksum) of MSGR5 words of SDRAM from BANK,
#          SUM_STEP words a frame, and writes it to MSGR5, then MSGR4 = 0. A block whose words would leave
#          BANK..BANK+BANK_MAX is not decoded at all (the checksum then tells the host);
#       5. unit 0's return = its input + MIX (ROUTE bit 0; else its input alone), clipped to 24 bits.
#       The firmware's reverb program at 0x8400 is not run while the slot is ours (as in DSPTONE).
#   E9, unit 9 (slot PM 0x80A0, normally the CHORUS at 0x8D00). Runs last in the frame: unit 9's return = MIX.
#       The chorus has no return register in the tone generator (kn7000_mame notes/effect-return-routing.md: the
#       CHORUS button moves only its send), so its return is the one the tone generator mixes whatever REVERB is;
#       unit 0's return is heard only while REVERB is on (the crossfade 0x803A). README-CNV.md, "Sound", says what
#       is known and what the unit must still tell.
#
# Host <-> DSP: the message registers MSGR4-MSGR7 (IOP 0x0C-0x0F; the kernel zeroes them at boot and nothing of the
# firmware uses them: DSPTONE README) and a few words of internal DM. Memory: PM 0x8200-0x82FF (the firmware never
# writes PM 0x8102-0x82FF: pass 7), DM 0x9D00-0x9EFF (never written by the firmware: pass 7), SDRAM from 0x70000
# (above the kernel's three delay rings, which end at 0x69D3F; DSPTONE's PCM at 0x70000 played on the unit).
import os
import re
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sharc_enc import (Program, alu, compute, shift_imm, shift_reg, mul_ssi, ureg_move, ureg_imm,  # noqa: E402
                       dm_read_abs, dm_write_abs, dm_read_off, dm_write_off, rts, modify_imm)

PM_CODE = 0x8140          # our code: PM 0x8102-0x82FF is never written by the firmware (pass 7)
PM_END = 0x8300
PM_SLOT0 = 0x8080         # the kernel's unit-0 CALL slot (REVERB): CALL (0x8400) (DB) on the owner's unit
PM_SLOT9 = 0x80A0         # the kernel's unit-9 CALL slot (CHORUS): CALL (0x8D00) (DB)
DEF_TARGET0 = 0x8400      # the firmware's program areas of those units (0x8400 + unit x 0x100)
DEF_TARGET9 = 0x8D00
CALL_DB = 0x06BE04000000  # "CALL (addr) (DB)", unconditional, absolute: the slot word less its target
MSGR4, MSGR5, MSGR6, MSGR7 = 0x0C, 0x0D, 0x0E, 0x0F
CLIP24 = 0x7FFFFF

# internal DM, 0x9D00-0x9EFF
MARK = 0x9D00             # 2 words: "AWSB" and the bank's id, written by the host once the whole bank is in SDRAM
VARS = 0x9D10             # the variables, uploaded with the program (DspVars below)
V_SAVEI5, V_SAVEI7, V_CPY, V_MIX, V_GAIN, V_ROUTE, V_HB9 = range(VARS, VARS + 7)
VOICES = 0x9D20           # 8 x 8 words: POS, FRAC, BASE, INC, END, LOOP, VOL, -
VP_POS, VP_FRAC, VP_BASE, VP_INC, VP_END, VP_LOOP, VP_VOL = range(7)
VOICE_LEN = 8
CMDS = 0x9D60             # 8 x 5 words, written by the host: BASE, INC, END, LOOP, VOL
CMD_LEN = 5
NVOICES = 8
DEC = CMDS + NVOICES * CMD_LEN            # the bank decoder's state (unit 0, step 4)
(V_RUN, V_BUF, V_NB, V_PTR, V_PREV, V_K, V_GLEFT, V_OUTW, V_SI, V_DST, V_NW, V_SUM) = range(DEC, DEC + 12)
VARS_END = DEC + 12       # DspVars covers VARS..VARS_END-1 (the voices, commands and decoder state zeroed)
STAGE = 0x9E00            # two staging buffers of STAGE_HALF words for the bank's blocks (tools/dsp_bank.py)
STAGE_HALF = 128
STAGE_WORDS = 2 * STAGE_HALF
COPY_STEP = 8             # each sound starts a whole number of COPY_STEP words past BANK (tools/aw_extract.py)
DEC_BITS = 20             # bank decoding: bits of the stream a frame (then the sample being decoded is finished)
SUM_STEP = 16             # bank checksum: SDRAM words a frame
QMAX, GROUP, KBITS = 12, 64, 3            # the code (tools/dsp_bank.py)
BANK = 0x70000            # SDRAM: the sample bank, four 8-bit samples a word (tools/aw_extract.py places them)
BANK_MAX = 0x30000        # words: to 0x9FFFF
GAIN = 128                # MIX = sum(sample x volume) x GAIN: one voice at full volume and full scale = -18 dBFS
ROUTE = 1                 # bit 0: unit 0's return carries MIX
EPILOGUE = 0x234903800000 # "R4 = DM(I1, M5),  R7 = PM(I12, M8)" (rec05 0x8404, as DSPTONE)


def program():
    p = Program(PM_CODE)
    e = p.emit
    # ---- E0: unit 0 -------------------------------------------------------------------------------
    p.label("E0")
    e(dm_write_abs(V_SAVEI7, "I7"), f"DM(0x{V_SAVEI7:08X}) = I7")
    e(dm_write_abs(V_SAVEI5, "I5"), f"DM(0x{V_SAVEI5:08X}) = I5")
    e(dm_read_off("R0", 0x20, "I4"), "R0 = DM(0x00000020, I4)")          # unit 0's input, left
    e(dm_read_off("R1", 0x21, "I4"), "R1 = DM(0x00000021, I4)")          # and right
    e(dm_read_abs("R2", MSGR7), "R2 = DM(0x0000000F)")                   # heartbeat
    e(compute(alu("INC", "R2", "R2")), "R2 = R2 + 1")
    e(dm_write_abs(MSGR7, "R2"), "DM(0x0000000F) = R2")
    # commands
    e(dm_read_abs("R2", MSGR6), "R2 = DM(0x0000000E)")
    e(compute(alu("PASS", "R2", "R2")), "R2 = PASS R2")
    p.jump("mix", "EQ")
    e(ureg_imm("R13", VOICES), f"R13 = 0x{VOICES:08X}")
    e(ureg_imm("R14", CMDS), f"R14 = 0x{CMDS:08X}")
    e(ureg_imm("R3", 1), "R3 = 0x00000001")                              # this voice's start bit
    e(ureg_imm("R11", NVOICES), f"R11 = 0x{NVOICES:08X}")
    p.label("cl")
    e(ureg_move("I7", "R13"), "I7 = R13")                                # the voice
    e(ureg_move("I5", "R14"), "I5 = R14")                                # its command record
    e(shift_imm("LSHIFT", "R10", "R3", 16), "R10 = LSHIFT R3 BY 16")     # (I5, I7 written: a cycle before use)
    e(compute(alu("AND", "R10", "R2", "R10")), "R10 = R2 AND R10")       # stop?
    p.jump("cstart", "EQ")
    e(ureg_imm("R10", 0), "R10 = 0x00000000")
    e(dm_write_off(VP_END, "I7", "R10"), f"DM(0x{VP_END:08X}, I7) = R10")
    p.label("cstart")
    e(compute(alu("AND", "R10", "R2", "R3")), "R10 = R2 AND R3")         # start?
    p.jump("cupd", "EQ")
    for k, f in enumerate((VP_BASE, VP_INC, VP_END, VP_LOOP, VP_VOL)):
        e(dm_read_off("R10", k, "I5"), f"R10 = DM(0x{k:08X}, I5)")
        e(dm_write_off(f, "I7", "R10"), f"DM(0x{f:08X}, I7) = R10")
    e(ureg_imm("R10", 0), "R10 = 0x00000000")
    e(dm_write_off(VP_POS, "I7", "R10"), f"DM(0x{VP_POS:08X}, I7) = R10")
    e(dm_write_off(VP_FRAC, "I7", "R10"), f"DM(0x{VP_FRAC:08X}, I7) = R10")
    p.label("cupd")
    e(shift_imm("LSHIFT", "R10", "R3", 8), "R10 = LSHIFT R3 BY 8")
    e(compute(alu("AND", "R10", "R2", "R10")), "R10 = R2 AND R10")       # update rate and volume?
    p.jump("cnext", "EQ")
    for k, f in ((1, VP_INC), (4, VP_VOL)):
        e(dm_read_off("R10", k, "I5"), f"R10 = DM(0x{k:08X}, I5)")
        e(dm_write_off(f, "I7", "R10"), f"DM(0x{f:08X}, I7) = R10")
    p.label("cnext")
    e(ureg_imm("R10", VOICE_LEN), f"R10 = 0x{VOICE_LEN:08X}")
    e(compute(alu("ADD", "R13", "R13", "R10")), "R13 = R13 + R10")
    e(ureg_imm("R10", CMD_LEN), f"R10 = 0x{CMD_LEN:08X}")
    e(compute(alu("ADD", "R14", "R14", "R10")), "R14 = R14 + R10")
    e(shift_imm("LSHIFT", "R3", "R3", 1), "R3 = LSHIFT R3 BY 1")
    e(compute(alu("DEC", "R11", "R11")), "R11 = R11 - 1")
    p.jump("cl", "NE")
    e(ureg_imm("R10", 0), "R10 = 0x00000000")
    e(dm_write_abs(MSGR6, "R10"), "DM(0x0000000E) = R10")                # done: tell the host
    # the mix
    p.label("mix")
    e(ureg_imm("R12", 0), "R12 = 0x00000000")                            # the sum
    e(ureg_imm("R13", VOICES), f"R13 = 0x{VOICES:08X}")
    e(ureg_imm("R11", NVOICES), f"R11 = 0x{NVOICES:08X}")
    p.label("vl")
    e(ureg_move("I7", "R13"), "I7 = R13")
    e(0, "NOP")                                                          # I7 written: a cycle before use
    e(dm_read_off("R5", VP_POS, "I7"), f"R5 = DM(0x{VP_POS:08X}, I7)")
    e(dm_read_off("R6", VP_END, "I7"), f"R6 = DM(0x{VP_END:08X}, I7)")
    e(compute(alu("COMP", "R0", "R5", "R6")), "COMP(R5, R6)")
    p.jump("vnext", "GE")                                                # silent: POS >= END
    e(shift_imm("LSHIFT", "R8", "R5", -2), "R8 = LSHIFT R5 BY -2")       # the word: BASE + POS / 4
    e(dm_read_off("R9", VP_BASE, "I7"), f"R9 = DM(0x{VP_BASE:08X}, I7)")
    e(compute(alu("ADD", "R8", "R8", "R9")), "R8 = R8 + R9")
    e(ureg_move("I5", "R8"), "I5 = R8")
    e(ureg_imm("R9", 3), "R9 = 0x00000003")
    e(compute(alu("XOR", "R10", "R5", "R9")), "R10 = R5 XOR R9")
    e(dm_read_off("R8", 0, "I5"), "R8 = DM(0x00000000, I5)")             # SDRAM (inside BUSLK)
    e(compute(alu("AND", "R10", "R10", "R9")), "R10 = R10 AND R9")       # 3 - POS mod 4
    e(shift_imm("LSHIFT", "R10", "R10", 3), "R10 = LSHIFT R10 BY 3")
    e(compute(shift_reg("LSHIFT", "R8", "R8", "R10")), "R8 = LSHIFT R8 BY R10")  # the sample's byte to the top
    e(shift_imm("ASHIFT", "R8", "R8", -24), "R8 = ASHIFT R8 BY -24")     # down again, sign-extended
    e(dm_read_off("R9", VP_VOL, "I7"), f"R9 = DM(0x{VP_VOL:08X}, I7)")
    e(compute(mul_ssi("R8", "R8", "R9")), "R8 = R8 * R9")
    e(compute(alu("ADD", "R12", "R12", "R8")), "R12 = R12 + R8")
    e(dm_read_off("R9", VP_FRAC, "I7"), f"R9 = DM(0x{VP_FRAC:08X}, I7)")  # POS.FRAC += INC
    e(dm_read_off("R10", VP_INC, "I7"), f"R10 = DM(0x{VP_INC:08X}, I7)")
    e(compute(alu("ADD", "R9", "R9", "R10")), "R9 = R9 + R10")
    e(shift_imm("LSHIFT", "R10", "R9", -16), "R10 = LSHIFT R9 BY -16")
    e(compute(alu("ADD", "R5", "R5", "R10")), "R5 = R5 + R10")
    e(ureg_imm("R10", 0xFFFF), "R10 = 0x0000FFFF")
    e(compute(alu("AND", "R9", "R9", "R10")), "R9 = R9 AND R10")
    e(dm_write_off(VP_FRAC, "I7", "R9"), f"DM(0x{VP_FRAC:08X}, I7) = R9")
    e(compute(alu("COMP", "R0", "R5", "R6")), "COMP(R5, R6)")
    p.jump("vstore", "LT")
    e(dm_read_off("R9", VP_LOOP, "I7"), f"R9 = DM(0x{VP_LOOP:08X}, I7)")  # past the end: loop back, or stay silent
    e(compute(alu("PASS", "R9", "R9")), "R9 = PASS R9")
    p.jump("vstore", "EQ")
    e(compute(alu("SUB", "R5", "R5", "R9")), "R5 = R5 - R9")
    p.label("vstore")
    e(dm_write_off(VP_POS, "I7", "R5"), f"DM(0x{VP_POS:08X}, I7) = R5")
    p.label("vnext")
    e(ureg_imm("R10", VOICE_LEN), f"R10 = 0x{VOICE_LEN:08X}")
    e(compute(alu("ADD", "R13", "R13", "R10")), "R13 = R13 + R10")
    e(compute(alu("DEC", "R11", "R11")), "R11 = R11 - 1")
    p.jump("vl", "NE")
    e(dm_read_abs("R9", V_GAIN), f"R9 = DM(0x{V_GAIN:08X})")
    e(compute(mul_ssi("R12", "R12", "R9")), "R12 = R12 * R9")
    e(dm_write_abs(V_MIX, "R12"), f"DM(0x{V_MIX:08X}) = R12")            # for unit 9 (E9)
    # the bank (tools/dsp_bank.py): MSGR4 1 decode a block, 2 checksum; R0, R1 (the input) and R12 (MIX) are kept
    e(dm_read_abs("R7", MSGR4), "R7 = DM(0x0000000C)")
    e(compute(alu("PASS", "R7", "R7")), "R7 = PASS R7")
    p.jump("out", "LE")
    e(dm_read_abs("R8", V_RUN), f"R8 = DM(0x{V_RUN:08X})")
    e(compute(alu("PASS", "R8", "R8")), "R8 = PASS R8")
    p.jump("running", "NE")
    e(ureg_imm("R10", 1), "R10 = 0x00000001")                            # a new command
    e(compute(alu("COMP", "R0", "R7", "R10")), "COMP(R7, R10)")
    p.jump("dstart", "EQ")
    e(ureg_imm("R10", 2), "R10 = 0x00000002")
    e(compute(alu("COMP", "R0", "R7", "R10")), "COMP(R7, R10)")
    p.jump("sumstart", "EQ")
    p.jump("cmddone")                                                    # unknown: done
    # -- decode: the block in staging buffer MSGR5 & 1
    p.label("dstart")
    e(dm_read_abs("R9", MSGR5), "R9 = DM(0x0000000D)")
    e(ureg_imm("R10", 1), "R10 = 0x00000001")
    e(compute(alu("AND", "R9", "R9", "R10")), "R9 = R9 AND R10")
    e(shift_imm("LSHIFT", "R9", "R9", 7), "R9 = LSHIFT R9 BY 7")         # x STAGE_HALF
    e(ureg_imm("R10", STAGE), f"R10 = 0x{STAGE:08X}")
    e(compute(alu("ADD", "R9", "R9", "R10")), "R9 = R9 + R10")
    e(ureg_move("I7", "R9"), "I7 = R9")
    e(0, "NOP")                                                          # I7 written: a cycle before use
    e(dm_read_off("R10", 0, "I7"), "R10 = DM(0x00000000, I7)")           # the first word's offset from BANK
    e(dm_read_off("R11", 1, "I7"), "R11 = DM(0x00000001, I7)")           # the words
    e(compute(alu("PASS", "R10", "R10")), "R10 = PASS R10")
    p.jump("cmddone", "LT")
    e(compute(alu("PASS", "R11", "R11")), "R11 = PASS R11")
    p.jump("cmddone", "LE")
    e(compute(alu("ADD", "R13", "R10", "R11")), "R13 = R10 + R11")
    e(ureg_imm("R14", BANK_MAX), f"R14 = 0x{BANK_MAX:08X}")
    e(compute(alu("COMP", "R0", "R13", "R14")), "COMP(R13, R14)")
    p.jump("cmddone", "GT")                                              # outside the bank: not decoded
    e(ureg_imm("R13", BANK), f"R13 = 0x{BANK:08X}")
    e(compute(alu("ADD", "R10", "R10", "R13")), "R10 = R10 + R13")
    e(dm_write_abs(V_DST, "R10"), f"DM(0x{V_DST:08X}) = R10")
    e(dm_write_abs(V_NW, "R11"), f"DM(0x{V_NW:08X}) = R11")
    e(ureg_imm("R10", 2), "R10 = 0x00000002")
    e(compute(alu("ADD", "R4", "R9", "R10")), "R4 = R9 + R10")           # the stream
    e(ureg_imm("R3", 0), "R3 = 0x00000000")                              # no bits in hand
    e(ureg_imm("R5", 0), "R5 = 0x00000000")                              # the predictor
    e(ureg_imm("R7", 0), "R7 = 0x00000000")                              # a k first
    e(ureg_imm("R8", 0), "R8 = 0x00000000")
    e(ureg_imm("R9", 0), "R9 = 0x00000000")
    e(ureg_imm("R10", 1), "R10 = 0x00000001")
    e(dm_write_abs(V_RUN, "R10"), f"DM(0x{V_RUN:08X}) = R10")
    p.jump("dgo")
    p.label("running")
    e(ureg_imm("R10", 1), "R10 = 0x00000001")
    e(compute(alu("COMP", "R0", "R8", "R10")), "COMP(R8, R10)")
    p.jump("csum", "NE")
    e(dm_read_abs("R2", V_BUF), f"R2 = DM(0x{V_BUF:08X})")              # the decoder's state
    e(dm_read_abs("R3", V_NB), f"R3 = DM(0x{V_NB:08X})")
    e(dm_read_abs("R4", V_PTR), f"R4 = DM(0x{V_PTR:08X})")
    e(dm_read_abs("R5", V_PREV), f"R5 = DM(0x{V_PREV:08X})")
    e(dm_read_abs("R6", V_K), f"R6 = DM(0x{V_K:08X})")
    e(dm_read_abs("R7", V_GLEFT), f"R7 = DM(0x{V_GLEFT:08X})")
    e(dm_read_abs("R8", V_OUTW), f"R8 = DM(0x{V_OUTW:08X})")
    e(dm_read_abs("R9", V_SI), f"R9 = DM(0x{V_SI:08X})")
    p.label("dgo")
    e(ureg_imm("R13", 0), "R13 = 0x00000000")                            # bits this frame
    p.label("sd")                                                        # a sample
    e(compute(alu("PASS", "R7", "R7")), "R7 = PASS R7")
    p.jump("havek", "NE")
    e(ureg_imm("R6", 0), "R6 = 0x00000000")                              # a new group: its k, 3 bits
    e(ureg_imm("R11", KBITS), f"R11 = 0x{KBITS:08X}")
    p.label("kl")
    p.call("getbit")
    e(shift_imm("LSHIFT", "R6", "R6", 1), "R6 = LSHIFT R6 BY 1")
    e(compute(alu("OR", "R6", "R6", "R10")), "R6 = R6 OR R10")
    e(compute(alu("DEC", "R11", "R11")), "R11 = R11 - 1")
    p.jump("kl", "NE")
    e(ureg_imm("R7", GROUP), f"R7 = 0x{GROUP:08X}")
    p.label("havek")
    e(compute(alu("DEC", "R7", "R7")), "R7 = R7 - 1")
    e(ureg_imm("R11", 0), "R11 = 0x00000000")                            # q
    p.label("ul")
    p.call("getbit")
    e(compute(alu("PASS", "R10", "R10")), "R10 = PASS R10")
    p.jump("uend", "NE")
    e(compute(alu("INC", "R11", "R11")), "R11 = R11 + 1")
    e(ureg_imm("R10", QMAX), f"R10 = 0x{QMAX:08X}")
    e(compute(alu("COMP", "R0", "R11", "R10")), "COMP(R11, R10)")
    p.jump("ul", "LT")
    e(ureg_imm("R14", 0), "R14 = 0x00000000")                            # the escape: z in 8 bits
    e(ureg_imm("R11", 8), "R11 = 0x00000008")
    p.jump("zl")
    p.label("uend")
    e(compute(alu("PASS", "R14", "R11")), "R14 = PASS R11")              # z = q, then k bits shifted in
    e(compute(alu("PASS", "R11", "R6")), "R11 = PASS R6")
    p.jump("zdone", "EQ")
    p.label("zl")
    p.call("getbit")
    e(shift_imm("LSHIFT", "R14", "R14", 1), "R14 = LSHIFT R14 BY 1")
    e(compute(alu("OR", "R14", "R14", "R10")), "R14 = R14 OR R10")
    e(compute(alu("DEC", "R11", "R11")), "R11 = R11 - 1")
    p.jump("zl", "NE")
    p.label("zdone")                                                     # d = (z >> 1) xor -(z & 1)
    e(ureg_imm("R10", 1), "R10 = 0x00000001")
    e(compute(alu("AND", "R10", "R14", "R10")), "R10 = R14 AND R10")
    e(ureg_imm("R11", 0), "R11 = 0x00000000")
    e(compute(alu("SUB", "R10", "R11", "R10")), "R10 = R11 - R10")
    e(shift_imm("LSHIFT", "R14", "R14", -1), "R14 = LSHIFT R14 BY -1")
    e(compute(alu("XOR", "R14", "R14", "R10")), "R14 = R14 XOR R10")
    e(compute(alu("ADD", "R5", "R5", "R14")), "R5 = R5 + R14")           # the sample: predictor + d, 8 bits
    e(ureg_imm("R10", 0xFF), "R10 = 0x000000FF")
    e(compute(alu("AND", "R5", "R5", "R10")), "R5 = R5 AND R10")
    e(shift_imm("LSHIFT", "R8", "R8", -8), "R8 = LSHIFT R8 BY -8")       # into the word from the top: the first
    e(shift_imm("LSHIFT", "R10", "R5", 24), "R10 = LSHIFT R5 BY 24")     #   sample ends in the low byte
    e(compute(alu("OR", "R8", "R8", "R10")), "R8 = R8 OR R10")
    e(compute(alu("INC", "R9", "R9")), "R9 = R9 + 1")
    e(ureg_imm("R10", 4), "R10 = 0x00000004")
    e(compute(alu("COMP", "R0", "R9", "R10")), "COMP(R9, R10)")
    p.jump("nexts", "LT")
    e(ureg_imm("R9", 0), "R9 = 0x00000000")                              # a whole word: into SDRAM
    e(dm_read_abs("R14", V_DST), f"R14 = DM(0x{V_DST:08X})")
    e(ureg_move("I5", "R14"), "I5 = R14")
    e(0, "NOP")
    e(dm_write_off(0, "I5", "R8"), "DM(0x00000000, I5) = R8")            # SDRAM (inside BUSLK)
    e(compute(alu("INC", "R14", "R14")), "R14 = R14 + 1")
    e(dm_write_abs(V_DST, "R14"), f"DM(0x{V_DST:08X}) = R14")
    e(dm_read_abs("R14", V_NW), f"R14 = DM(0x{V_NW:08X})")
    e(compute(alu("DEC", "R14", "R14")), "R14 = R14 - 1")
    e(dm_write_abs(V_NW, "R14"), f"DM(0x{V_NW:08X}) = R14")
    p.jump("cmddone", "EQ")                                              # the block is done
    p.label("nexts")
    e(ureg_imm("R10", DEC_BITS), f"R10 = 0x{DEC_BITS:08X}")
    e(compute(alu("COMP", "R0", "R13", "R10")), "COMP(R13, R10)")
    p.jump("sd", "LT")
    e(dm_write_abs(V_BUF, "R2"), f"DM(0x{V_BUF:08X}) = R2")             # this frame's share: the state kept
    e(dm_write_abs(V_NB, "R3"), f"DM(0x{V_NB:08X}) = R3")
    e(dm_write_abs(V_PTR, "R4"), f"DM(0x{V_PTR:08X}) = R4")
    e(dm_write_abs(V_PREV, "R5"), f"DM(0x{V_PREV:08X}) = R5")
    e(dm_write_abs(V_K, "R6"), f"DM(0x{V_K:08X}) = R6")
    e(dm_write_abs(V_GLEFT, "R7"), f"DM(0x{V_GLEFT:08X}) = R7")
    e(dm_write_abs(V_OUTW, "R8"), f"DM(0x{V_OUTW:08X}) = R8")
    e(dm_write_abs(V_SI, "R9"), f"DM(0x{V_SI:08X}) = R9")
    p.jump("out")
    # -- checksum: MSGR5 words of SDRAM from BANK
    p.label("sumstart")
    e(dm_read_abs("R11", MSGR5), "R11 = DM(0x0000000D)")
    e(compute(alu("PASS", "R11", "R11")), "R11 = PASS R11")
    p.jump("cmddone", "LT")
    e(ureg_imm("R14", BANK_MAX), f"R14 = 0x{BANK_MAX:08X}")
    e(compute(alu("COMP", "R0", "R11", "R14")), "COMP(R11, R14)")
    p.jump("cmddone", "GT")
    e(dm_write_abs(V_NW, "R11"), f"DM(0x{V_NW:08X}) = R11")
    e(ureg_imm("R10", BANK), f"R10 = 0x{BANK:08X}")
    e(dm_write_abs(V_DST, "R10"), f"DM(0x{V_DST:08X}) = R10")
    e(ureg_imm("R10", 0), "R10 = 0x00000000")
    e(dm_write_abs(V_SUM, "R10"), f"DM(0x{V_SUM:08X}) = R10")
    e(ureg_imm("R10", 2), "R10 = 0x00000002")
    e(dm_write_abs(V_RUN, "R10"), f"DM(0x{V_RUN:08X}) = R10")
    p.label("csum")
    e(dm_read_abs("R2", V_SUM), f"R2 = DM(0x{V_SUM:08X})")
    e(dm_read_abs("R4", V_DST), f"R4 = DM(0x{V_DST:08X})")
    e(dm_read_abs("R11", V_NW), f"R11 = DM(0x{V_NW:08X})")
    e(ureg_imm("R3", SUM_STEP), f"R3 = 0x{SUM_STEP:08X}")
    p.label("csl")
    e(compute(alu("PASS", "R11", "R11")), "R11 = PASS R11")
    p.jump("csdone", "EQ")
    e(ureg_move("I5", "R4"), "I5 = R4")
    e(0, "NOP")
    e(dm_read_off("R8", 0, "I5"), "R8 = DM(0x00000000, I5)")             # SDRAM (inside BUSLK)
    e(shift_imm("LSHIFT", "R9", "R2", 1), "R9 = LSHIFT R2 BY 1")         # c = rotl(c, 1) xor w
    e(shift_imm("LSHIFT", "R2", "R2", -31), "R2 = LSHIFT R2 BY -31")
    e(compute(alu("OR", "R2", "R2", "R9")), "R2 = R2 OR R9")
    e(compute(alu("XOR", "R2", "R2", "R8")), "R2 = R2 XOR R8")
    e(compute(alu("INC", "R4", "R4")), "R4 = R4 + 1")
    e(compute(alu("DEC", "R11", "R11")), "R11 = R11 - 1")
    e(compute(alu("DEC", "R3", "R3")), "R3 = R3 - 1")
    p.jump("csl", "NE")
    e(dm_write_abs(V_SUM, "R2"), f"DM(0x{V_SUM:08X}) = R2")
    e(dm_write_abs(V_DST, "R4"), f"DM(0x{V_DST:08X}) = R4")
    e(dm_write_abs(V_NW, "R11"), f"DM(0x{V_NW:08X}) = R11")
    p.jump("out")
    p.label("csdone")
    e(dm_write_abs(V_SUM, "R2"), f"DM(0x{V_SUM:08X}) = R2")
    e(dm_write_abs(MSGR5, "R2"), "DM(0x0000000D) = R2")                  # the answer
    p.label("cmddone")                                                   # done: the host waits for MSGR4 = 0
    e(ureg_imm("R10", 0), "R10 = 0x00000000")
    e(dm_write_abs(V_RUN, "R10"), f"DM(0x{V_RUN:08X}) = R10")
    e(dm_write_abs(MSGR4, "R10"), "DM(0x0000000C) = R10")
    # out: unit 0's input (+ MIX), clipped to the 24 bits the SPORT sends
    p.label("out")
    e(dm_read_abs("R9", V_ROUTE), f"R9 = DM(0x{V_ROUTE:08X})")
    e(ureg_imm("R10", 1), "R10 = 0x00000001")
    e(compute(alu("AND", "R9", "R9", "R10")), "R9 = R9 AND R10")
    p.jump("clip", "EQ")
    e(compute(alu("ADD", "R0", "R0", "R12")), "R0 = R0 + R12")
    e(compute(alu("ADD", "R1", "R1", "R12")), "R1 = R1 + R12")
    p.label("clip")
    e(ureg_imm("R14", CLIP24), f"R14 = 0x{CLIP24:08X}")
    e(compute(alu("CLIP", "R0", "R0", "R14")), "R0 = CLIP R0 BY R14")
    e(compute(alu("CLIP", "R1", "R1", "R14")), "R1 = CLIP R1 BY R14")
    e(dm_write_off(0, "I4", "R0"), "DM(0x00000000, I4) = R0")           # unit 0's return pair; I4 on by two, as
    e(dm_write_off(1, "I4", "R1"), "DM(0x00000001, I4) = R1")           #   an effect's two DM(I4, Mx) writes leave it
    e(modify_imm("I4", 2), "MODIFY (I4, 0x00000002)")
    e(dm_read_abs("I5", V_SAVEI5), f"I5 = DM(0x{V_SAVEI5:08X})")
    e(dm_read_abs("I7", V_SAVEI7), f"I7 = DM(0x{V_SAVEI7:08X})")
    e(rts(db=True), "RTS (DB)")                                          # the kernel's effect epilogue
    e(EPILOGUE, "R4 = DM(I1, M5),  R7 = PM(I12, M8)")
    e(modify_imm("I8", 0x50), "MODIFY (I8, 0x00000050)")
    # ---- E9: unit 9 -------------------------------------------------------------------------------
    p.label("E9")
    e(dm_read_abs("R0", V_HB9), f"R0 = DM(0x{V_HB9:08X})")               # its own heartbeat
    e(compute(alu("INC", "R0", "R0")), "R0 = R0 + 1")
    e(dm_write_abs(V_HB9, "R0"), f"DM(0x{V_HB9:08X}) = R0")
    e(dm_read_abs("R0", V_MIX), f"R0 = DM(0x{V_MIX:08X})")
    e(ureg_imm("R14", CLIP24), f"R14 = 0x{CLIP24:08X}")
    e(compute(alu("CLIP", "R0", "R0", "R14")), "R0 = CLIP R0 BY R14")
    e(dm_write_off(0, "I4", "R0"), "DM(0x00000000, I4) = R0")           # unit 9's return pair: MIX alone (a
    e(dm_write_off(1, "I4", "R0"), "DM(0x00000001, I4) = R0")           #   chorus return is wet only)
    e(modify_imm("I4", 2), "MODIFY (I4, 0x00000002)")
    e(rts(db=True), "RTS (DB)")
    e(EPILOGUE, "R4 = DM(I1, M5),  R7 = PM(I12, M8)")
    e(modify_imm("I8", 0x50), "MODIFY (I8, 0x00000050)")
    # ---- getbit: R10 = the stream's next bit (R2 the bits in hand from the top, R3 how many, R4 the next word);
    #      R13 + 1 (the frame's bits). Called from E0's decoder only.
    p.label("getbit")
    e(compute(alu("PASS", "R3", "R3")), "R3 = PASS R3")
    p.jump("gbh", "NE")
    e(ureg_move("I7", "R4"), "I7 = R4")
    e(0, "NOP")
    e(dm_read_off("R2", 0, "I7"), "R2 = DM(0x00000000, I7)")
    e(compute(alu("INC", "R4", "R4")), "R4 = R4 + 1")
    e(ureg_imm("R3", 32), "R3 = 0x00000020")
    p.label("gbh")
    e(shift_imm("LSHIFT", "R10", "R2", -31), "R10 = LSHIFT R2 BY -31")
    e(shift_imm("LSHIFT", "R2", "R2", 1), "R2 = LSHIFT R2 BY 1")
    e(compute(alu("DEC", "R3", "R3")), "R3 = R3 - 1")
    e(compute(alu("INC", "R13", "R13")), "R13 = R13 + 1")
    e(rts(db=False), "RTS")
    return p.assemble(), p.labels


def dsp_vars():
    v = [0] * (VARS_END - VARS)
    v[V_GAIN - VARS] = GAIN
    v[V_ROUTE - VARS] = ROUTE
    return v


def check(words, unidasm):
    """unidasm -arch sharc over the words: each line must be the text it was meant to be"""
    with tempfile.NamedTemporaryFile(suffix=".bin") as t:
        t.write(b"".join(struct.pack("<Q", w) for _, w, _ in words))
        t.flush()
        out = subprocess.run([unidasm, t.name, "-arch", "sharc", "-basepc", hex(PM_CODE)],
                             capture_output=True, text=True, check=True).stdout
    lines = [ln for ln in out.splitlines() if re.match(r"\s*[0-9a-f]+: [0-9a-f]{16}", ln)]
    bad = 0
    for (pc, w, text), ln in zip(words, lines):
        got = re.sub(r"\s+", " ", ln.split(None, 2)[2].strip())
        if got != re.sub(r"\s+", " ", text):
            print(f"dsp_mixer: PM 0x{pc:04X} {w:012X}: unidasm says '{got}', meant '{text}'")
            bad += 1
    if len(lines) != len(words):
        print(f"dsp_mixer: unidasm gave {len(lines)} lines for {len(words)} words")
        bad += 1
    return bad


def write_inc(out, words, labels):
    eq = [("DSP_CODE_ADDR", PM_CODE), ("DSP_CODE_WORDS", len(words)), ("DSP_ENTRY0", labels["E0"]),
          ("DSP_ENTRY9", labels["E9"]), ("DSP_OURS_LO", 0x8100), ("DSP_OURS_HI", PM_END),
          ("DSP_SLOT0", PM_SLOT0), ("DSP_SLOT9", PM_SLOT9), ("DSP_DEF0", DEF_TARGET0), ("DSP_DEF9", DEF_TARGET9),
          ("DSP_CALLDB_HI", CALL_DB >> 32), ("DSP_MARK", MARK), ("DSP_VARS", VARS), ("DSP_NVARS", VARS_END - VARS),
          ("DSP_V_HB9", V_HB9), ("DSP_V_MIX", V_MIX), ("DSP_VOICES", VOICES), ("DSP_VOICE_LEN", VOICE_LEN),
          ("DSP_CMDS", CMDS), ("DSP_CMD_LEN", CMD_LEN), ("DSP_NVOICES", NVOICES), ("DSP_STAGE", STAGE),
          ("DSP_STAGE_WORDS", STAGE_WORDS), ("DSP_STAGE_HALF", STAGE_HALF), ("DSP_COPY_STEP", COPY_STEP),
          ("DSP_BANK", BANK), ("DSP_V_RUN", V_RUN), ("DSP_V_SUM", V_SUM),
          ("DSP_BANK_MAX", BANK_MAX), ("DSP_MSGR4", MSGR4), ("DSP_MSGR5", MSGR5), ("DSP_MSGR6", MSGR6),
          ("DSP_MSGR7", MSGR7)]
    with open(os.path.join(out, "dsp_equ.inc"), "w") as f:
        f.write("# GENERATED by tools/dsp_mixer.py -- the effects-DSP mixer's addresses (do not edit)\n")
        for name, val in eq:
            f.write(f".equ {name + ',':<17} 0x{val:X}\n")
    with open(os.path.join(out, "dsp_data.inc"), "w") as f:
        f.write("# GENERATED by tools/dsp_mixer.py -- the effects-DSP mixer (do not edit; see tools/dsp_mixer.py)\n")
        f.write("\n# the program: PM words as the host streams them, three 16-bit halves each, least significant "
                "first\n    .align  4\nDspCode:\n")
        for pc, w, text in words:
            f.write(f"    .word   0x{w & 0xFFFF:04X}, 0x{(w >> 16) & 0xFFFF:04X}, 0x{w >> 32:04X}"
                    f"    # {pc:04X}: {text}\n")
        f.write(f"\n# DM 0x{VARS:04X}-0x{VARS_END - 1:04X}: SAVEI5, SAVEI7, CPY, MIX, GAIN, ROUTE, HB9, -, the voices "
                f"and the command records (zero)\n    .align  4\nDspVars:\n")
        v = dsp_vars()
        for k in range(0, len(v), 8):
            f.write("    .long   " + ", ".join(f"0x{x:08X}" for x in v[k:k + 8]) + "\n")


def main():
    out = sys.argv[1]
    args = sys.argv[2:]
    words, labels = program()
    assert PM_CODE + len(words) <= PM_END, f"the code ({len(words)} words) must stay in PM 0x{PM_CODE:04X}-0x{PM_END - 1:04X}"
    assert VARS_END <= STAGE and STAGE + STAGE_WORDS <= 0x9F00
    import dsp_bank
    assert (dsp_bank.STAGE_HALF, dsp_bank.QMAX, dsp_bank.GROUP, dsp_bank.KBITS) == (STAGE_HALF, QMAX, GROUP, KBITS)
    if "--check" in args:
        u = args[args.index("--check") + 1]
        if not os.path.exists(u):
            sys.exit(f"dsp_mixer: no unidasm at {u} (make UNIDASM=...); every word must be checked against it")
        bad = check(words, u)
        if bad:
            sys.exit(f"dsp_mixer: {bad} instruction(s) do not disassemble as meant")
        print(f"dsp_mixer: {len(words)} instructions, each disassembles as meant (unidasm -arch sharc)")
    if "--listing" in args:
        with open(args[args.index("--listing") + 1], "w") as f:
            for pc, w, text in words:
                f.write(f"{pc:04x}: {w:012x}  {text}\n")
    write_inc(out, words, labels)
    print(f"dsp_mixer: {out}/dsp_equ.inc, dsp_data.inc: {len(words)} PM words at 0x{PM_CODE:04X} "
          f"(E0 0x{labels['E0']:04X}, E9 0x{labels['E9']:04X})")


if __name__ == "__main__":
    main()
