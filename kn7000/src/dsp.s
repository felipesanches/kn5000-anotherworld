# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# dsp.s -- Another World's own samples, played by the KN7000's effects DSP (IC306, an ADSP-21065L), the main
# CPU's side (KN7APP.BIN build only). README-CNV.md, "Sound", says what it does on the instrument and why; the DSP's
# side is tools/dsp_mixer.py (a four-voice mixer in two of the firmware kernel's unit slots).
#
# It is iteration 2 of our own program on the DSP. Iteration 1, DSPTONE (technics-roms-disasm
# kn7000/tools/dsptone/dsptone.s), ran on Felipe's KN7000 (program 893) on 2026-10-21; the routines below that talk
# to the DSP are DSPTONE's, ported to this program's names and frames, and keep its rules:
#   * it never drives the host port itself: every access goes through the firmware's own routines (found by their
#     code: DspFind, the same search as DSPTONE's and the ROM dumper's DspFind), which keep the firmware's lock, its
#     per-frame handshake wait (INTC group 0x17) and its "DSP dead" guard;
#   * it checks the DSP is as the firmware leaves it before it touches anything (dead flag, kernel downloaded,
#     SYSCON, external-port channel 8), reads back everything it uploads, and puts back what it changed: the two
#     CALL slots (each read back), MSGR4-MSGR7, channel 8's registers.
#
# What the converter does with it (cnv_main.s, state 5, after the global files and before the game task starts):
#   DspPrepare  the checks; the slots of unit 0 (REVERB, PM 0x8080) and unit 9 (CHORUS, PM 0x80A0) read back and
#               kept; the mixer, its variables and the message registers loaded and read back; both slots hooked
#               and read back; the bank's marker read (DM 0x9D00: "AWSB" and the bank's id): when it is this
#               build's, the bank is still in SDRAM from an earlier run since the last power-on, and is not sent;
#   BankStep    the sample bank, BANK_MS of work per converter call: each sound's file (AWRxx.AW) read from the
#               card into PART_AREA and unpacked there, then sent to the DSP's staging buffer a chunk at a time,
#               which the mixer copies into SDRAM (the table AWBANK.AW, tools/aw_extract.py, says where each sound
#               goes); then the marker. Progress on the load bar.
# Any failure on the way puts the slots back (DspUnhook) and leaves the game on the tone generator (audio.s), with
# the reason on the help screen (DV_FAIL, "NO DSP n").
#
# What the game task does with it (audio.s): DspVoiceStart / DspVoiceVol / DspVoiceStop / DspStopAll fill the
# command records and a mask in RAM; DspFlush (from AudioPoll) sends them: it waits until MSGR6 reads 0 (the mixer
# has taken the last ones), uploads the records that changed into DM, and writes the mask to MSGR6. DspUnhook and
# DspHook (the sound mode, PART SELECT RIGHT 2) put the firmware's effects back and take them again. The firmware's
# routines are called from the game task as from the main task: a task of priority 3 is not preempted by another of
# the same priority, so no sequence of ours is interleaved with one of the firmware's.
#
# Calling convention as the rest of the port. Every routine here that calls a firmware routine makes a frame of
# 0x20 bytes first (movm + add -0x20, sp): the firmware's routines store into 4..0x10(sp) of their caller's frame,
# and the register write takes its third argument at (0x10, sp).

# The equates (DV_*, DS_*, DF_*, MODE_*, the host-port constants) are in dsp.inc, which cnv_main.s includes
# first: audio.s and cnv_main.s use them too.

# ==============================================================================================================
# The search (the converter's search steps 6 and 7, fwfind.s FwStep): one signature per call.
# DspFindStep(d0 = 0: the handshake wait, 1: the register routines, then the cross-checks) -> d0 = 0 always (the
# game runs without the DSP when something is not found).
DspFindStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    cmp     0, d0
    bne     dfs_regs
    mov     sig_dspwait, a0
    call    CountFlash, 0, 0
    mov     d0, (DV_SIGN0)
    mov     (FS_LASTHIT), d0
    mov     d0, (DV_SIGA0)
    bra     dfs_ret
dfs_regs:
    mov     sig_dspregs, a0
    call    CountFlash, 0, 0
    mov     d0, (DV_SIGN1)
    mov     (FS_LASTHIT), d0
    mov     d0, (DV_SIGA1)
    call    DspFind, 0, 0
dfs_ret:
    clr     d0
    ret     [d2,d3,a2,a3], 0x30

# DspFind: the firmware's DSP host-port routines (941 / 893 addresses), as DSPTONE's DspFind:
#   sig_dspwait  the handshake wait (0x48404D25 / 0x4840AE77): its operands are the "kernel downloaded" flag
#                (+0x0F) and the "DSP dead" flag (+0x36);
#   sig_dspregs  the 2x16 register write and read (0x484052DD / 0x4840B3F5; the read at +0x3E);
#   the read's calls: the index write (body + 6) and the guarded data read (body + 0xE);
#   the guarded data write: the register write's second call (body + 0x14, the DM-word writer) makes it at its
#   own body + 0x11; it must start "movhu d1, (0x1c, sp); movhu d0, (0x18, sp); movbu (dead), d0".
# Every call target must be preceded by the "add -frame, sp" its call allocates. Only when all of it holds is
# DV_FOUND = DFB_ALL; otherwise the DSP is not touched at all. (technics-roms-disasm dsptone/find_dspw.py runs the
# same search over every program build: found and consistent in 893, 935, 941 and 942.)
DspFind:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    clr     d2
    mov     (DV_SIGN0), d0
    cmp     1, d0
    bne     dfd_regs
    or      DFB_WAIT, d2
    mov     (DV_SIGA0), a2
    mov     a2, (DV_DWAIT)
    mov     a2, a0
    add     0x0F, a0
    call    Read32U, 0, 0           # movbu (downloaded), d0
    mov     d0, (DV_DDOWN)
    mov     a2, a0
    add     0x36, a0
    call    Read32U, 0, 0           # movbu d0, (dead)
    mov     d0, (DV_DDEAD)
dfd_regs:
    mov     (DV_SIGN1), d0
    cmp     1, d0
    bne     dfd_end
    or      DFB_REGS, d2
    mov     (DV_SIGA1), a2
    mov     a2, (DV_DREGWR)
    mov     a2, a0
    add     0x3E, a0
    mov     a0, (DV_DREGRD)
    add     9, a0                   # the read's body + 6: call DspAddrWrite
    call    CallTarget, 0, 0
    cmp     0, d0
    beq     dfd_data
    call    CheckEntry, 0, 0
    cmp     0, d0
    beq     dfd_data
    mov     d0, (DV_DIDXWR)
    or      DFB_IDX, d2
dfd_data:
    mov     (DV_DREGRD), a0
    add     0x11, a0                # the read's body + 0xE: call the guarded data read
    call    CallTarget, 0, 0
    cmp     0, d0
    beq     dfd_write
    mov     d0, a3                  # its body: movbu (dead), d0 = fc a8 <dead>
    call    CheckEntry, 0, 0
    cmp     0, d0
    beq     dfd_write
    mov     d0, (DV_DDATARD)
    movbu   (a3), d0
    cmp     0xFC, d0
    bne     dfd_write
    movbu   (1, a3), d0
    cmp     0xA8, d0
    bne     dfd_write
    mov     a3, a0
    add     2, a0
    call    Read32U, 0, 0
    mov     (DV_DDEAD), d1
    cmp     d1, d0
    bne     dfd_write
    or      DFB_DATA, d2
dfd_write:
    mov     (DV_DREGWR), a0
    add     0x17, a0                # the write's body + 0x14: call the DM-word writer
    call    CallTarget, 0, 0
    cmp     0, d0
    beq     dfd_end
    mov     d0, a3
    call    CheckEntry, 0, 0
    cmp     0, d0
    beq     dfd_end
    mov     a3, a0
    add     0x11, a0                # its body + 0x11: call the guarded data write
    call    CallTarget, 0, 0
    cmp     0, d0
    beq     dfd_end
    mov     d0, a3
    call    CheckEntry, 0, 0
    cmp     0, d0
    beq     dfd_end
    mov     d0, (0x14, sp)
    mov     WriteHead, a0           # movhu d1, (0x1c, sp); movhu d0, (0x18, sp); movbu (abs32), d0
    clr     d3
dfd_head:
    mov     a3, a1
    add     d3, a1
    movbu   (a1), d0
    mov     a0, a1
    add     d3, a1
    movbu   (a1), d1
    cmp     d1, d0
    bne     dfd_end
    inc     d3
    cmp     8, d3
    bcs     dfd_head
    mov     a3, a0
    add     8, a0
    call    Read32U, 0, 0
    mov     (DV_DDEAD), d1
    cmp     d1, d0
    bne     dfd_end
    mov     (0x14, sp), d0
    mov     d0, (DV_DDATAWR)
    or      DFB_WRITE, d2
dfd_end:
    mov     d2, (DV_FOUND)
    ret     [d2,d3,a2,a3], 0x30

# CallTarget (leaf): a0 = address of a "call d16, regs, imm8" (cd lo hi regs imm) -> d0 = its target, d1 = its
# imm8 (the frame it allocates); d0 = 0 when a0 holds no such instruction.
CallTarget:
    movbu   (a0), d0
    cmp     0xCD, d0
    bne     ct_none
    movbu   (2, a0), d0
    asl     8, d0
    movbu   (1, a0), d1
    or      d1, d0
    exth    d0
    mov     a0, d1
    add     d1, d0
    movbu   (4, a0), d1
    rets
ct_none:
    clr     d0
    rets

# CheckEntry (leaf): d0 = a function body, d1 = the frame its callers allocate -> d0 = the entry `calls` needs,
# body - 3, which must be "add -frame, sp" (f8 fe -frame); or 0.
CheckEntry:
    mov     d0, a0
    add     -3, a0
    movbu   (a0), d0
    cmp     0xF8, d0
    bne     ce_no
    movbu   (1, a0), d0
    cmp     0xFE, d0
    bne     ce_no
    movbu   (2, a0), d0
    add     d1, d0
    and     0xFF, d0
    bne     ce_no
    mov     a0, d0
    rets
ce_no:
    clr     d0
    rets

# ==============================================================================================================
# The firmware's routines, and what is built on them (DSPTONE's).

# DspRead(d0 = IOP register) -> d0 = its 32 bits. The firmware's read returns (high << 16) + the low half
# sign-extended; when the low half's bit 15 is set that is 0x10000 short, which is added back here.
DspRead:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (DV_DREGRD), a0
    calls   (a0)
    btst    0x8000, d0
    beq     drd_ret
    mov     0x10000, d1
    add     d1, d0
drd_ret:
    ret     [d2,d3,a2,a3], 0x30

# DspWrite(d0 = IOP register, d1 = 32-bit value): the firmware's 2x16 register write, low half first.
DspWrite:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d1, d2
    and     0xFFFF, d2
    mov     d2, (0x10, sp)          # its third argument: the low half
    lsr     16, d1                  # d1: the high half
    mov     (DV_DREGWR), a0
    calls   (a0)
    ret     [d2,d3,a2,a3], 0x30

DspIndex:                           # d0 = the index to latch at 0x98000000 (the firmware's guarded write)
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (DV_DIDXWR), a0
    calls   (a0)
    ret     [d2,d3,a2,a3], 0x30

DspData:                            # -> d0 = one 16-bit read of 0x9C000000 (0xFFFF once the DSP is "dead")
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (DV_DDATARD), a0
    calls   (a0)
    exthu   d0
    ret     [d2,d3,a2,a3], 0x30

DspDataW:                           # d0 = 16 bits to write to 0x9C000000 (the firmware's guarded write: nothing
    movm    [d2,d3,a2,a3], (sp)     #   once the DSP is "dead")
    add     -0x20, sp
    mov     d0, d1
    exthu   d1
    mov     DATA_PORT, d0
    mov     (DV_DDATAWR), a0
    calls   (a0)
    ret     [d2,d3,a2,a3], 0x30

DeadFlag:                           # leaf -> d0 = the firmware's dead flag byte (0 when not found)
    mov     (DV_DDEAD), a0
    clr     d0
    cmp     0, a0
    beq     dfl_ret
    movbu   (a0), d0
dfl_ret:
    rets

DownFlag:                           # leaf -> d0 = the "kernel downloaded" flag byte (0 when not found)
    mov     (DV_DDOWN), a0
    clr     d0
    cmp     0, a0
    beq     dwn_ret
    movbu   (a0), d0
dwn_ret:
    rets

# DspUpload(d0 = DSP address, d1 = words, a0 = their 16-bit halves, least significant first, a1 = DMAC_UP_PM or
# DMAC_UP_DM): the firmware's own upload of a block (941 0x48407AAB, 0x48407A86/0x48407A99, 0x48407ADF):
# IIEP0 = address, IMEP0 = 1, CEP0 = words, DMAC0 = 0xA1 (PM, three halves a word) or 0x41 (DM, two); the index
# latched to EPB0 once; the halves; DMAC0 = 0xA0.
DspUpload:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2
    mov     a1, d3
    mov     d1, (0x14, sp)
    mov     d0, d1
    mov     IOP_IIEP0, d0
    call    DspWrite, 0, 0
    mov     IOP_IMEP0, d0
    mov     1, d1
    call    DspWrite, 0, 0
    mov     IOP_CEP0, d0
    mov     (0x14, sp), d1
    call    DspWrite, 0, 0
    mov     IOP_DMAC0, d0
    mov     d3, d1
    call    DspWrite, 0, 0
    mov     IOP_EPB0, d0
    call    DspIndex, 0, 0
    mov     (0x14, sp), d2          # halves: two a word, three for PM
    add     d2, d2
    cmp     DMAC_UP_PM, d3
    bne     dup_half
    mov     (0x14, sp), d0
    add     d0, d2
dup_half:
    cmp     0, d2
    beq     dup_close
    movhu   (a2), d0
    add     2, a2
    call    DspDataW, 0, 0
    add     -1, d2
    bra     dup_half
dup_close:
    mov     IOP_DMAC0, d0
    mov     DMAC_CLOSE, d1
    call    DspWrite, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# DspReadback(d0 = first address, d1 = words, a0 = out, a1 = DMAC_RB_PM or DMAC_RB_DM) -> d0 = words read. The
# pass-7 readback: channel 8, slave mode, transmit: flush; IIEP0 = address, IMEP0 = 1, CEP0 = words; DMAC0 = mode.
# Per word: read DMAC0 until FS says EPB0 holds data (FS_POLLS at most: a read of an empty EPB0 would hold the
# bus), latch EPB0, read 3 (PM) or 2 (DM) halves, least significant first. Then flush, and DMAC0's control bits as
# found. DV_RBFAIL = 1 when it stopped early.
DspReadback:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a3
    mov     d0, (0x14, sp)
    mov     d1, (0x18, sp)
    mov     a1, (0x1C, sp)
    mov     1, d0
    mov     d0, (DV_RBFAIL)
    clr     d2                      # words read
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     drb_skip
    mov     IOP_DMAC0, d0
    mov     DMAC_FLSH, d1
    call    DspWrite, 0, 0
    mov     IOP_IIEP0, d0
    mov     (0x14, sp), d1
    call    DspWrite, 0, 0
    mov     IOP_IMEP0, d0
    mov     1, d1
    call    DspWrite, 0, 0
    mov     IOP_CEP0, d0
    mov     (0x18, sp), d1
    call    DspWrite, 0, 0
    mov     IOP_DMAC0, d0
    mov     (0x1C, sp), d1
    call    DspWrite, 0, 0
drb_word:
    mov     (0x18, sp), d0
    cmp     d0, d2
    bcc     drb_done
    clr     d3                      # polls
drb_poll:
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     drb_end
    mov     IOP_DMAC0, d0
    call    DspRead, 0, 0
    mov     0xC000, d1              # FS: 00 empty, 10 partly full, 11 full
    and     d1, d0
    bne     drb_data
    inc     d3
    cmp     FS_POLLS, d3
    bcs     drb_poll
    bra     drb_end
drb_data:
    mov     IOP_EPB0, d0
    call    DspIndex, 0, 0
    call    DspData, 0, 0
    movhu   d0, (a3)
    add     2, a3
    call    DspData, 0, 0
    movhu   d0, (a3)
    add     2, a3
    mov     (0x1C, sp), d0
    btst    0x20, d0
    beq     drb_next
    call    DspData, 0, 0
    movhu   d0, (a3)
    add     2, a3
drb_next:
    inc     d2
    bra     drb_word
drb_done:
    clr     d0
    mov     d0, (DV_RBFAIL)
drb_end:
    mov     IOP_DMAC0, d0
    mov     DMAC_FLSH, d1
    call    DspWrite, 0, 0
    mov     IOP_DMAC0, d0
    mov     (DV_DMAC0), d1
    mov     DMAC_KEEP, d3
    and     d3, d1
    call    DspWrite, 0, 0
drb_skip:
    mov     d2, d0
    ret     [d2,d3,a2,a3], 0x30

# Verify(d0 = DSP address, d1 = words, a1 = DMAC_RB_PM or DMAC_RB_DM, a2 = what was uploaded) -> d0 = 0 when the
# readback equals it, else 1. RB_WORDS words at a time (DV_RBBUF).
Verify:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x14, sp)          # the next address
    mov     d1, (0x18, sp)          # words left
    mov     a1, (0x1C, sp)
vf_chunk:
    mov     (0x18, sp), d3
    cmp     0, d3
    beq     vf_good
    cmp     RB_WORDS, d3
    bls     vf_n
    mov     RB_WORDS, d3
vf_n:
    mov     (0x14, sp), d0
    mov     d3, d1
    mov     DV_RBBUF, a0
    mov     (0x1C, sp), a1
    call    DspReadback, 0, 0
    cmp     d3, d0
    bne     vf_bad
    mov     d3, d2                  # halves to compare: two a word, three for PM
    add     d2, d2
    mov     (0x1C, sp), d0
    cmp     DMAC_RB_PM, d0
    bne     vf_cmp0
    add     d3, d2
vf_cmp0:
    mov     DV_RBBUF, a0
vf_cmp:
    cmp     0, d2
    beq     vf_more
    movhu   (a0), d0
    movhu   (a2), d1
    cmp     d1, d0
    bne     vf_bad
    add     2, a0
    add     2, a2
    add     -1, d2
    bra     vf_cmp
vf_more:
    mov     (0x14, sp), d0
    add     d3, d0
    mov     d0, (0x14, sp)
    mov     (0x18, sp), d0
    sub     d3, d0
    mov     d0, (0x18, sp)
    bra     vf_chunk
vf_good:
    clr     d0
    bra     vf_ret
vf_bad:
    mov     1, d0
vf_ret:
    ret     [d2,d3,a2,a3], 0x30

# ReadSlot(d0 = the slot's PM address) -> d0 = 0, d1 = its low 32 bits, a1 = its high 16; or d0 = 1 (the
# readback failed).
ReadSlot:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     1, d1
    mov     DV_RBBUF, a0
    mov     DMAC_RB_PM, a1
    call    DspReadback, 0, 0
    cmp     1, d0
    bne     rs_bad
    mov     DV_RBBUF, a0
    movhu   (4, a0), d0
    mov     d0, a1
    movhu   (2, a0), d1
    asl     16, d1
    movhu   (a0), d0
    or      d0, d1
    clr     d0
    bra     rs_ret
rs_bad:
    mov     1, d0
rs_ret:
    ret     [d2,d3,a2,a3], 0x30

# PokeSlot(a0 = the slot's PM address, d0 = bits 47-32, d1 = bits 31-0): one PM word, as the firmware pokes a slot.
PokeSlot:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, d2
    mov     sp, a0                  # the three halves at (0x14, sp), least significant first
    add     0x14, a0
    movhu   d1, (a0)
    lsr     16, d1
    movhu   d1, (2, a0)
    movhu   d0, (4, a0)
    mov     d2, d0
    mov     1, d1
    mov     DMAC_UP_PM, a1
    call    DspUpload, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# SetSlot(a0 = the slot's PM address, d0 = the target) -> d0 = 0 when it now reads back "CALL (target) (DB)", else 1.
SetSlot:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2
    mov     0x04000000, d2
    or      d0, d2                  # the low 32 bits
    mov     DSP_CALLDB_HI, d0
    mov     d2, d1
    call    PokeSlot, 0, 0
    mov     a2, d0
    call    ReadSlot, 0, 0
    cmp     0, d0
    bne     sst_bad
    cmp     DSP_CALLDB_HI, a1
    bne     sst_bad
    cmp     d2, d1
    bne     sst_bad
    clr     d0
    bra     sst_ret
sst_bad:
    mov     1, d0
sst_ret:
    ret     [d2,d3,a2,a3], 0x30

# FoundSlot(d0 = the slot's PM address, d1 = the firmware's own target for it) -> d0 = 0 and the slot as the
# firmware keeps it in d1 (low 32) / a1 (high 16), or d0 = 1 (not readable, or not the kernel's form). A slot that
# points into our PM area already (an earlier program of ours that never put it back: DSPTONE's or this one's)
# is put back to the firmware's own target first, so that nothing runs our area while the mixer is uploaded.
FoundSlot:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, a2                  # a2 = the slot
    mov     d1, d3                  # d3 = the firmware's target for it
    call    ReadSlot, 0, 0
    cmp     0, d0
    bne     fsl_bad
    cmp     DSP_CALLDB_HI, a1
    bne     fsl_bad
    mov     d1, d2                  # bits 31-16 must be 0x0400 (DB, no condition), the target in 0x8000-0x8FFF
    lsr     16, d2
    cmp     0x0400, d2
    bne     fsl_bad
    mov     d1, d2
    exthu   d2
    cmp     0x8000, d2
    bcs     fsl_bad
    cmp     0x8FFF, d2
    bhi     fsl_bad
    cmp     DSP_OURS_LO, d2
    bcs     fsl_ok
    cmp     DSP_OURS_HI, d2
    bcc     fsl_ok
    mov     a2, a0                  # ours: the firmware's target back first
    mov     d3, d0
    call    SetSlot, 0, 0
    cmp     0, d0
    bne     fsl_bad
    mov     0x04000000, d1
    or      d3, d1
    mov     DSP_CALLDB_HI, a1
fsl_ok:
    clr     d0
    bra     fsl_ret
fsl_bad:
    mov     1, d0
fsl_ret:
    ret     [d2,d3,a2,a3], 0x30

# Now -> d0 = the kernel's milliseconds. Leaf.
DspNow:
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    rets

# ==============================================================================================================
# The converter's side.

# DspPrepare -> d0 = 0: the mixer is loaded and hooked (DS_BANK, or DS_READY when the bank is there already);
# else 1, DV_FAIL says why, nothing of the firmware's is left changed (DS_OFF).
DspPrepare:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     DF_NOTFOUND, d2
    mov     (DV_FOUND), d0
    cmp     DFB_ALL, d0
    bne     dpr_fail
    mov     DF_DEAD, d2
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     dpr_fail
    mov     DF_NOTDOWN, d2
    call    DownFlag, 0, 0
    cmp     0, d0
    beq     dpr_fail
    mov     IOP_SYSCON, d0          # the DSP as the firmware leaves it (DSPTONE's checks)
    call    DspRead, 0, 0
    mov     d0, (DV_SYSCON)
    mov     IOP_DMAC0, d0
    call    DspRead, 0, 0
    mov     d0, (DV_DMAC0)
    mov     IOP_IIEP0, d0
    call    DspRead, 0, 0
    mov     d0, (DV_IIEP0)
    mov     IOP_IMEP0, d0
    call    DspRead, 0, 0
    mov     d0, (DV_IMEP0)
    mov     IOP_CEP0, d0
    call    DspRead, 0, 0
    mov     d0, (DV_CEP0)
    mov     IOP_DMASTAT, d0
    call    DspRead, 0, 0
    mov     d0, (DV_DMASTAT)
    mov     DF_STATE, d2
    mov     (DV_SYSCON), d0         # SYSCON: HBW = 01 (16-bit host bus), HMSWF = 0 (low half first)
    and     0x70, d0
    cmp     0x10, d0
    bne     dpr_fail
    mov     (DV_DMAC0), d0          # DMAC0: DEN, CHEN clear
    and     3, d0
    bne     dpr_fail
    mov     (DV_DMASTAT), d0        # DMASTAT: channel 8 neither active (bit 6) nor chaining (bit 16)
    mov     0x10040, d1
    and     d1, d0
    bne     dpr_fail
    mov     DF_SLOT, d2             # the slots as the firmware keeps them
    mov     DSP_SLOT0, d0
    mov     DSP_DEF0, d1
    call    FoundSlot, 0, 0
    cmp     0, d0
    bne     dpr_fail
    mov     a1, (DV_SLOT0_HI)
    mov     d1, (DV_SLOT0_LO)
    clr     d0                      # unit 9: hooked too only when it is the kernel's form
    mov     d0, (DV_U9)
    mov     DSP_SLOT9, d0
    mov     DSP_DEF9, d1
    call    FoundSlot, 0, 0
    cmp     0, d0
    bne     dpr_load
    mov     a1, (DV_SLOT9_HI)
    mov     d1, (DV_SLOT9_LO)
    mov     1, d0
    mov     d0, (DV_U9)
dpr_load:
    mov     DSP_CODE_ADDR, d0       # the mixer, its variables, the message registers
    mov     DSP_CODE_WORDS, d1
    mov     DspCode, a0
    mov     DMAC_UP_PM, a1
    call    DspUpload, 0, 0
    mov     DSP_VARS, d0
    mov     DSP_NVARS, d1
    mov     DspVars, a0
    mov     DMAC_UP_DM, a1
    call    DspUpload, 0, 0
    call    ZeroMsgr, 0, 0
    mov     DF_DEAD, d2
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     dpr_fail
    mov     DF_VERIFY, d2           # read back and compared
    mov     DSP_CODE_ADDR, d0
    mov     DSP_CODE_WORDS, d1
    mov     DMAC_RB_PM, a1
    mov     DspCode, a2
    call    Verify, 0, 0
    cmp     0, d0
    bne     dpr_fail
    mov     DSP_VARS, d0
    mov     DSP_NVARS, d1
    mov     DMAC_RB_DM, a1
    mov     DspVars, a2
    call    Verify, 0, 0
    cmp     0, d0
    bne     dpr_fail
    mov     DSP_MSGR7, d0           # the heartbeat before the hook
    call    DspRead, 0, 0
    mov     d0, (DV_HB0)
    call    DspHook, 0, 0           # both slots: from here on every way out puts them back
    mov     DF_HOOK, d2
    cmp     0, d0
    bne     dpr_fail
    mov     DSP_MARK, d0            # the bank already in SDRAM? ("AWSB" and this bank's id)
    mov     2, d1
    mov     DV_RBBUF, a0
    mov     DMAC_RB_DM, a1
    call    DspReadback, 0, 0
    mov     DF_VERIFY, d2
    cmp     2, d0
    bne     dpr_fail
    mov     DV_RBBUF, a0
    mov     (a0), d0
    mov     MARK_MAGIC, d1
    cmp     d1, d0
    bne     dpr_send
    mov     (4, a0), d0
    mov     (DSP_BANKTAB + BT_ID), d1
    cmp     d1, d0
    bne     dpr_send
    mov     2, d0                   # there: nothing to send
    mov     d0, (DV_BK_SENT)
    mov     DS_READY, d0
    mov     d0, (DV_STATE)
    mov     1, d0
    mov     d0, (DV_READY)
    clr     d0
    bra     dpr_ret
dpr_send:
    mov     DV_RBBUF, a0            # the marker cleared until the whole bank is there again
    clr     d0
    mov     d0, (a0)
    mov     d0, (4, a0)
    mov     DSP_MARK, d0
    mov     2, d1
    mov     DMAC_UP_DM, a1
    call    DspUpload, 0, 0
    clr     d0
    mov     d0, (DV_BK_RES)
    mov     d0, (DV_BK_DONE)
    mov     d0, (DV_STALLS)
    mov     -1, d0
    mov     d0, (DV_BK_OFS)
    mov     DS_BANK, d0
    mov     d0, (DV_STATE)
    clr     d0
    bra     dpr_ret
dpr_fail:
    mov     d2, d0
    call    DspGiveUp, 0, 0
    mov     1, d0
dpr_ret:
    ret     [d2,d3,a2,a3], 0x30

# ZeroMsgr: MSGR4-MSGR7 = 0, as the kernel leaves them at boot.
ZeroMsgr:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     DSP_MSGR4, d2
zm_one:
    mov     d2, d0
    clr     d1
    call    DspWrite, 0, 0
    inc     d2
    cmp     DSP_MSGR7, d2
    bls     zm_one
    ret     [d2,d3,a2,a3], 0x30

# DspGiveUp(d0 = DF_* reason): the slots back if they are ours, the message registers and channel 8 as found;
# the DSP is not used again in this run.
DspGiveUp:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (DV_FAIL), d1           # the first reason is the one kept
    cmp     0, d1
    bne     dg_keep
    mov     d0, (DV_FAIL)
dg_keep:
    call    DspUnhook, 0, 0
    clr     d0
    mov     d0, (DV_READY)
    mov     DS_OFF, d0
    mov     d0, (DV_STATE)
    ret     [d2,d3,a2,a3], 0x30

# DspHook -> d0 = 0 when unit 0's slot (and unit 9's, DV_U9) now call the mixer, read back; else 1, and whatever
# was hooked is put back.
DspHook:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     dh_bad
    mov     (DV_HOOKED), d0         # from here on every way out puts the slots back
    or      1, d0
    mov     d0, (DV_HOOKED)
    mov     DSP_SLOT0, a0
    mov     DSP_ENTRY0, d0
    call    SetSlot, 0, 0
    cmp     0, d0
    bne     dh_bad
    mov     (DV_U9), d0
    cmp     0, d0
    beq     dh_ok
    mov     (DV_HOOKED), d0
    or      2, d0
    mov     d0, (DV_HOOKED)
    mov     DSP_SLOT9, a0
    mov     DSP_ENTRY9, d0
    call    SetSlot, 0, 0
    cmp     0, d0
    bne     dh_bad
dh_ok:
    clr     d0
    bra     dh_ret
dh_bad:
    call    DspUnhook, 0, 0
    mov     1, d0
dh_ret:
    ret     [d2,d3,a2,a3], 0x30

# DspUnhook: the voices silent, the slots as found (each read back), MSGR4-MSGR7 = 0, channel 8's registers as
# found. Does nothing when no slot is ours. -> d0 = 0 when everything read back right.
DspUnhook:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    clr     d3                      # problems
    mov     (DV_HOOKED), d0
    cmp     0, d0
    beq     du_ret0
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     du_dead
    mov     (DV_HOOKED), d0
    btst    2, d0
    beq     du_u0
    mov     DSP_SLOT9, a0           # unit 9 first: it reads the mix unit 0 makes
    mov     (DV_SLOT9_LO), d0
    exthu   d0
    call    SetSlot, 0, 0
    or      d0, d3
    cmp     0, d0
    bne     du_u0
    mov     (DV_HOOKED), d0
    and     0xFFFFFFFD, d0
    mov     d0, (DV_HOOKED)
du_u0:
    mov     (DV_HOOKED), d0
    btst    1, d0
    beq     du_regs
    mov     DSP_SLOT0, a0
    mov     (DV_SLOT0_LO), d0
    exthu   d0
    call    SetSlot, 0, 0
    or      d0, d3
    cmp     0, d0
    bne     du_regs
    mov     (DV_HOOKED), d0
    and     0xFFFFFFFE, d0
    mov     d0, (DV_HOOKED)
du_regs:
    call    ZeroMsgr, 0, 0
    mov     IOP_IIEP0, d0           # channel 8's registers as found
    mov     (DV_IIEP0), d1
    call    DspWrite, 0, 0
    mov     IOP_IMEP0, d0
    mov     (DV_IMEP0), d1
    call    DspWrite, 0, 0
    mov     IOP_CEP0, d0
    mov     (DV_CEP0), d1
    call    DspWrite, 0, 0
    mov     IOP_DMAC0, d0
    mov     (DV_DMAC0), d1
    mov     DMAC_KEEP, d2
    and     d2, d1
    call    DspWrite, 0, 0
    clr     d0
    mov     d0, (DV_PEND)
    mov     d3, d0
    bra     du_ret
du_dead:                            # nothing reaches the DSP any more: the firmware reloads it at power-on
    clr     d0
    mov     d0, (DV_HOOKED)
    mov     1, d0
    bra     du_ret
du_ret0:
    clr     d0
du_ret:
    ret     [d2,d3,a2,a3], 0x30

# CopyIdle -> d0 = 1 when MSGR4 reads 0 (the mixer has finished the last copy) within COPY_POLLS reads, else 0.
CopyIdle:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    clr     d2
ci_poll:
    mov     DSP_MSGR4, d0
    call    DspRead, 0, 0
    cmp     0, d0
    beq     ci_yes
    inc     d2
    cmp     COPY_POLLS, d2
    bcs     ci_poll
    clr     d0
    bra     ci_ret
ci_yes:
    mov     1, d0
ci_ret:
    ret     [d2,d3,a2,a3], 0x30

# BankEntry(d0 = resource id) -> a0 = its AWBANK.AW entry. Leaf.
BankEntry:
    mov     BE_LEN, d1
    mulu    d1, d0
    mov     DSP_BANKTAB + BT_ENT, a0
    add     d0, a0
    rets

# BankStep -> d0 = 0 more to come, 1 the bank is in SDRAM (DS_READY), 2 it failed (DspGiveUp has run). BANK_MS
# of work: read and unpack the next sound's file, send its samples a chunk at a time.
BankStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    call    DspNow, 0, 0
    mov     d0, (DV_BK_T0)
bs_loop:
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     bs_dead
    mov     (DV_BK_OFS), d0
    cmp     0, d0
    bge     bs_chunk
bs_find:                            # the next sound in the bank
    mov     (DV_BK_RES), d2
    cmp     RES_COUNT, d2
    bcc     bs_end
    mov     d2, d0
    call    BankEntry, 0, 0
    mov     (BE_ADDR, a0), d0
    cmp     0, d0
    bne     bs_read
    inc     d2
    mov     d2, (DV_BK_RES)
    bra     bs_find
bs_read:
    mov     d2, d0
    call    BankRead, 0, 0          # its file, unpacked at PART_AREA
    cmp     0, d0
    bne     bs_file
    mov     (DV_BK_RES), d0
    call    BankEntry, 0, 0
    mov     (BE_END, a0), d0        # bytes to send: whole copy steps (DSP_COPY_STEP words)
    add     DSP_COPY_STEP*4 - 1, d0
    and     0xFFFFFFE0, d0          # (DSP_COPY_STEP 8: 32 bytes)
    mov     d0, (DV_BK_LEN)
    clr     d0
    mov     d0, (DV_BK_OFS)
    bra     bs_time
bs_chunk:
    call    CopyIdle, 0, 0          # the mixer has copied the last chunk out of STAGE?
    cmp     0, d0
    beq     bs_waiting
    clr     d0
    mov     d0, (DV_STALLS)
    mov     (DV_BK_LEN), d3
    mov     (DV_BK_OFS), d2
    sub     d2, d3                  # bytes left -> words, at most a STAGE's
    lsr     2, d3
    cmp     DSP_STAGE_WORDS, d3
    bls     bs_n
    mov     DSP_STAGE_WORDS, d3
bs_n:
    mov     PART_AREA + 8, a0       # the samples: after the resource's 8-byte header
    add     d2, a0
    mov     DSP_STAGE, d0
    mov     d3, d1
    mov     DMAC_UP_DM, a1
    call    DspUpload, 0, 0
    mov     (DV_BK_RES), d0         # where: its first word, less the bank's, plus what is sent
    call    BankEntry, 0, 0
    mov     (BE_ADDR, a0), d1
    mov     DSP_BANK, d0
    sub     d0, d1
    mov     d2, d0
    lsr     2, d0
    add     d0, d1
    mov     DSP_MSGR5, d0
    call    DspWrite, 0, 0
    mov     DSP_MSGR4, d0
    mov     d3, d1
    call    DspWrite, 0, 0
    mov     (DV_BK_DONE), d0
    add     d3, d0
    mov     d0, (DV_BK_DONE)
    asl     2, d3
    add     d3, d2
    mov     d2, (DV_BK_OFS)
    mov     (DV_BK_LEN), d0
    cmp     d0, d2
    bcs     bs_progress
    mov     -1, d0                  # this sound is sent: the next one
    mov     d0, (DV_BK_OFS)
    mov     (DV_BK_RES), d0
    inc     d0
    mov     d0, (DV_BK_RES)
bs_progress:
    mov     (DV_BK_DONE), d0
    mov     (DSP_BANKTAB + BT_WORDS), d1
    call    Progress, 0, 0
bs_time:
    call    DspNow, 0, 0
    mov     (DV_BK_T0), d1
    sub     d1, d0
    cmp     BANK_MS, d0
    bcs     bs_loop
    clr     d0
    bra     bs_ret
bs_waiting:
    mov     (DV_STALLS), d0         # no copy finished in COPY_POLLS reads: try again at the next call
    inc     d0
    mov     d0, (DV_STALLS)
    cmp     STALL_CALLS, d0
    bcs     bs_wait_ret
    mov     DF_STALL, d0
    bra     bs_fail
bs_wait_ret:
    clr     d0
    bra     bs_ret
bs_end:                             # every sound sent: the last copy, then the marker
    call    CopyIdle, 0, 0
    cmp     0, d0
    beq     bs_waiting
    mov     DV_RBBUF, a0
    mov     MARK_MAGIC, d0
    mov     d0, (a0)
    mov     (DSP_BANKTAB + BT_ID), d0
    mov     d0, (4, a0)
    mov     DSP_MARK, d0
    mov     2, d1
    mov     DMAC_UP_DM, a1
    call    DspUpload, 0, 0
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     bs_dead
    mov     1, d0
    mov     d0, (DV_BK_SENT)
    mov     d0, (DV_READY)
    mov     DS_READY, d0
    mov     d0, (DV_STATE)
    mov     1, d0
    bra     bs_ret
bs_file:
    mov     DF_FILE, d0
    bra     bs_fail
bs_dead:
    mov     DF_RUNDEAD, d0
bs_fail:
    call    DspGiveUp, 0, 0
    mov     2, d0
bs_ret:
    ret     [d2,d3,a2,a3], 0x30

# BankRead(d0 = resource id) -> d0 = 0 when its file AWRxx.AW (in the game's folder) is read and unpacked at
# PART_AREA, as LoadStep reads a part's files (the drive switch to the SD card and back around it, FILE_PIECE
# bytes at a time), and a music instrument's first four samples zeroed (rawgl SfxPlayer::prepareInstruments);
# else 1. A packed file is read to BANK_PACKED first.
BankRead:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2
    mov     DV_NAME, a0             # "AWRxx.AW"
    mov     aw_sound_name, a1
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     d2, d0
    lsr     4, d0
    call    HexDigit, 0, 0
    movbu   d0, (DV_NAME + 3)
    mov     d2, d0
    call    HexDigit, 0, 0
    movbu   d0, (DV_NAME + 4)
    mov     d2, d0
    call    BankEntry, 0, 0
    mov     a0, (0x1C, sp)          # (0x1C, sp) = the entry (the firmware's routines keep 0x14-0x1C of our frame)
    mov     (BE_SIZE, a0), d1
    mov     0x7FFFFFFF, d3
    and     d3, d1                  # d1 = bytes unpacked
    mov     (BE_FILE, a0), d0       # d0 = bytes in the file
    mov     0x10000, d3             # the build makes sure of both (aw_extract.py): never past the staging space
    cmp     d3, d0
    bcc     br_bad
    cmp     d3, d1
    bcc     br_bad
    mov     BANK_PACKED, d3         # where the file goes: packed, or straight to PART_AREA
    cmp     d0, d1
    bne     br_dest
    mov     PART_AREA, d3
br_dest:
    mov     d3, (0x18, sp)          # (0x18, sp) = where the next piece goes
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    mov     DV_NAME, a0
    call    AppPath, 0, 0           # a0 = AW_PREFIX + the name, in the game's folder
    mov     mode_rb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    blt     br_back
    mov     (0x1C, sp), a0
    mov     (BE_FILE, a0), d2       # d2: bytes still to read
    clr     d3                      # d3: bytes read
br_piece:
    cmp     0, d2
    beq     br_close
    mov     d2, d0
    mov     FILE_PIECE, d1
    cmp     d1, d0
    bls     br_ask
    mov     d1, d0
br_ask:
    mov     d0, (0x14, sp)          # asked for
    mov     (0x18, sp), a0
    mov     (FW_READ), a3
    calls   (a3)                    # d0 = bytes read
    mov     (0x14, sp), d1
    cmp     d1, d0
    bne     br_close                # short, or an error: the count below tells
    add     d0, d3
    mov     (0x18, sp), d1
    add     d0, d1
    mov     d1, (0x18, sp)
    sub     d0, d2
    bra     br_piece
br_close:
    mov     (FW_CLOSE), a3
    calls   (a3)
    mov     (FW_RESETEXT), a3       # the file layer back, as the firmware expects between calls
    calls   (a3)
    mov     (0x1C, sp), a3          # a3 = the entry
    mov     (BE_FILE, a3), d0
    cmp     d0, d3
    bne     br_bad
    mov     (BE_SIZE, a3), d1
    mov     0x7FFFFFFF, d2
    and     d2, d1
    cmp     d0, d1
    beq     br_inst                 # stored as is
    mov     BANK_PACKED, a0         # BkUnpack(a0 = packed, d0 = packed size, a1 = dst, d1 = size)
    mov     PART_AREA, a1
    call    BkUnpack, 0, 0
    cmp     0, d0
    bne     br_bad
br_inst:
    mov     (BE_SIZE, a3), d0
    cmp     0, d0
    bge     br_ok                   # bit 31 clear: not a music instrument
    clr     d0
    mov     d0, (PART_AREA + 8)
br_ok:
    clr     d0
    bra     br_ret
br_back:
    mov     (FW_RESETEXT), a3
    calls   (a3)
br_bad:
    mov     1, d0
br_ret:
    ret     [d2,d3,a2,a3], 0x30

# HexDigit(d0) -> d0 = the ASCII hex digit of its low 4 bits, upper case. Leaf.
HexDigit:
    and     15, d0
    cmp     10, d0
    bcs     hd_num
    add     0x41 - 10, d0
    rets
hd_num:
    add     0x30, d0
    rets

# DspInitMode: the sound mode the game task starts with (audio.s): the DSP when its slots are ours, else the
# tone generator. Leaf.
DspInitMode:
    mov     MODE_TG, d1
    mov     (DV_HOOKED), d0
    btst    1, d0
    beq     dim_set
    mov     MODE_DSP, d1
dim_set:
    mov     d1, (DV_MODE)
    rets

# DspModeText: DV_MODETXT = the help screen's line for the sound mode: "NOW: DSP SAMPLES", "NOW: TONE
# GENERATOR", "NOW: OFF", and " NO DSP n" when the DSP was given up (DV_FAIL, the DF_* codes above).
DspModeText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     DV_MODETXT, a0
    mov     hs_now, a1
    call    StrPut, 0, 0
    mov     (DV_MODE), d0
    mov     hs_now_dsp, a1
    cmp     MODE_DSP, d0
    beq     dmt_put
    mov     hs_now_off, a1
    cmp     MODE_OFF, d0
    beq     dmt_put
    mov     hs_now_tg, a1
dmt_put:
    call    StrPut, 0, 0
    mov     (DV_FAIL), d2
    cmp     0, d2
    beq     dmt_end
    mov     hs_nodsp, a1
    call    StrPut, 0, 0
    cmp     10, d2
    bcs     dmt_one
    mov     0x31, d0
    movbu   d0, (a0)
    inc     a0
    add     -10, d2
dmt_one:
    mov     d2, d0
    add     0x30, d0
    movbu   d0, (a0)
    inc     a0
dmt_end:
    clr     d0
    movbu   d0, (a0)
    ret     [d2,d3,a2,a3], 0x20

# DspQuit: the game is leaving (cnv_main.s, before 0xFE): the slots back, read back. Also after a failure.
DspQuit:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (DV_STATE), d0
    cmp     DS_NONE, d0
    beq     dq2_ret
    cmp     DS_OFF, d0
    beq     dq2_ret
    call    DspUnhook, 0, 0
    mov     DS_OFF, d0
    mov     d0, (DV_STATE)
dq2_ret:
    ret     [d2,d3,a2,a3], 0x30

# ==============================================================================================================
# The game task's side (audio.s): the voices.

# DspVoiceStart(d0 = voice 0..7, d1 = resource id, a0 = rate as a 16.16 step per 44.1 kHz frame, a1 = volume
# 0..63): from the start of the sound's samples at that rate and volume (nothing when it is not in the bank).
# Voices 0-3 are PLAY_SOUND's channels, 4-7 the music's (audio.s).
DspVoiceStart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    and     7, d0
    mov     d0, d2                  # d2 = voice
    mov     a0, d3                  # d3 = rate
    mov     a1, (0x14, sp)
    cmp     RES_COUNT, d1
    bcc     dvs_ret
    mov     d1, d0
    call    BankEntry, 0, 0
    mov     a0, a2                  # a2 = the bank entry
    mov     (BE_ADDR, a2), d0
    cmp     0, d0
    beq     dvs_ret
    mov     d2, d0                  # a3 = the voice's command record: voice x 20
    asl     2, d0
    add     d2, d0
    asl     2, d0
    mov     DV_CMDS, a3
    add     d0, a3
    mov     (BE_ADDR, a2), d0
    mov     d0, (a3)                # BASE
    mov     d3, (4, a3)             # INC
    mov     (BE_END, a2), d0
    mov     d0, (8, a3)             # END
    mov     (BE_LOOP, a2), d0
    mov     d0, (12, a3)            # LOOP
    mov     (0x14, sp), d0
    mov     d0, (16, a3)            # VOL
    mov     0x10101, d0             # this voice: start, and no update or stop
    asl     d2, d0
    not     d0
    mov     (DV_PEND), d1
    and     d0, d1
    mov     1, d0
    asl     d2, d0
    or      d0, d1
    mov     d1, (DV_PEND)
dvs_ret:
    ret     [d2,d3,a2,a3], 0x30

# DspVoiceVol(d0 = voice, d1 = volume): the voice goes on at that volume (rawgl setChannelVolume). Leaf.
DspVoiceVol:
    and     7, d0
    mov     d1, a0                  # a0 = volume
    mov     d0, d1                  # d1 = voice
    asl     2, d0
    add     d1, d0
    asl     2, d0                   # voice x 20: its command record
    mov     DV_CMDS + 16, a1
    add     d0, a1
    mov     a0, (a1)                # VOL
    mov     0x100, d0               # this voice: update
    asl     d1, d0
    mov     (DV_PEND), d1
    or      d0, d1
    mov     d1, (DV_PEND)
    rets

# DspVoiceStop(d0 = voice): silent from the next frame on. Leaf.
DspVoiceStop:
    and     7, d0
    mov     d0, a0                  # a0 = voice
    mov     0x101, d1               # no start, no update
    asl     d0, d1
    not     d1
    mov     (DV_PEND), d0
    and     d1, d0
    mov     d0, a1                  # a1 = the mask so far
    mov     a0, d0
    mov     0x10000, d1             # stop
    asl     d0, d1
    mov     a1, d0
    or      d1, d0
    mov     d0, (DV_PEND)
    rets

# DspMusicStop: the music's voices (4-7) silent. Leaf.
DspMusicStop:
    mov     (DV_PEND), d0
    and     0x0F0F0F, d0            # the sound effects' voices as they are
    mov     0xF00000, d1            # voices 4-7: stop, no start, no update
    or      d1, d0
    mov     d0, (DV_PEND)
    rets

# DspStopAll: every voice silent from the next frame on. Leaf.
DspStopAll:
    mov     0xFF0000, d0
    mov     d0, (DV_PEND)
    rets

# DspFlush: send what DspVoice* asked for, when anything is pending and the slots are ours: wait until the mixer
# has taken the last commands (MSGR6 reads 0, CMD_POLLS reads at most; otherwise later), upload the command records
# of the voices started or updated (one block, from the first to the last), then the mask into MSGR6.
DspFlush:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (DV_PEND), d2
    cmp     0, d2
    beq     dfl2_ret
    mov     (DV_HOOKED), d0
    btst    1, d0
    beq     dfl2_drop
    call    DeadFlag, 0, 0
    cmp     0, d0
    bne     dfl2_dead
    clr     d3
dfl2_poll:
    mov     DSP_MSGR6, d0
    call    DspRead, 0, 0
    cmp     0, d0
    beq     dfl2_idle
    inc     d3
    cmp     CMD_POLLS, d3
    bcs     dfl2_poll
    mov     (DV_BUSY), d0           # the mixer has not taken the last ones yet: try at the next poll
    inc     d0
    mov     d0, (DV_BUSY)
    bra     dfl2_ret
dfl2_idle:
    mov     d2, d0                  # voices whose record goes: started or updated
    lsr     8, d0
    or      d2, d0
    and     0xFF, d0
    beq     dfl2_mask
    clr     d3                      # d3 = the first such voice
dfl2_lo:
    btst    1, d0
    bne     dfl2_hi
    lsr     1, d0
    inc     d3
    bra     dfl2_lo
dfl2_hi:
    mov     d3, a2                  # a2 = the last one + 1
dfl2_hi2:
    cmp     0, d0
    beq     dfl2_send
    lsr     1, d0
    inc     a2
    bra     dfl2_hi2
dfl2_send:
    mov     a2, d1                  # words: (last + 1 - first) x 5
    sub     d3, d1
    mov     d1, d0
    asl     2, d0
    add     d1, d0
    mov     d0, (0x14, sp)
    mov     d3, d0                  # to: CMDS + first x 5
    asl     2, d0
    add     d3, d0
    mov     d0, d1
    add     DSP_CMDS, d0
    mov     d0, (0x18, sp)
    asl     2, d1                   # from: DV_CMDS + first x 20
    mov     DV_CMDS, a0
    add     d1, a0
    mov     (0x18, sp), d0
    mov     (0x14, sp), d1
    mov     DMAC_UP_DM, a1
    call    DspUpload, 0, 0
dfl2_mask:
    mov     DSP_MSGR6, d0
    mov     d2, d1
    call    DspWrite, 0, 0
    mov     (DV_FLUSHES), d0
    inc     d0
    mov     d0, (DV_FLUSHES)
dfl2_drop:
    clr     d0
    mov     d0, (DV_PEND)
dfl2_ret:
    ret     [d2,d3,a2,a3], 0x30
dfl2_dead:                          # the firmware has marked the DSP dead: back to the tone generator
    clr     d0
    mov     d0, (DV_PEND)
    mov     d0, (DV_HOOKED)
    mov     d0, (DV_READY)
    mov     DF_RUNTIME, d0
    mov     d0, (DV_FAIL)
    mov     DS_OFF, d0
    mov     d0, (DV_STATE)
    bra     dfl2_ret

# DspWatch -> d0 = 1 when the firmware has stopped calling the converter for WATCH_MS while the slots are ours
# (it left STYLE CONVERT some other way than our 0xFE): then the voices are stopped and the slots put back here,
# from the game task, and the sound is off. Else 0. (AudioPoll.)
DspWatch:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    call    DspNow, 0, 0
    mov     d0, d2
    mov     (CV_CALLS), d0
    mov     (DV_LASTCALLS), d1
    cmp     d1, d0
    beq     dw_same
    mov     d0, (DV_LASTCALLS)
    mov     d2, (DV_LASTMS)
    bra     dw_no
dw_same:
    mov     (DV_HOOKED), d0
    cmp     0, d0
    beq     dw_no
    mov     d2, d0
    mov     (DV_LASTMS), d1
    sub     d1, d0
    cmp     WATCH_MS, d0
    bcs     dw_no
    call    DspStopAll, 0, 0
    call    DspFlush, 0, 0
    call    DspUnhook, 0, 0
    mov     DF_WATCH, d0
    mov     d0, (DV_FAIL)
    clr     d0
    mov     d0, (DV_READY)
    mov     DS_OFF, d0
    mov     d0, (DV_STATE)
    mov     1, d0
    bra     dw_ret
dw_no:
    clr     d0
dw_ret:
    ret     [d2,d3,a2,a3], 0x30

# ---- data --------------------------------------------------------------------------------------------------
aw_sound_name:
    .asciz  "AWR00.AW"
hs_now:
    .asciz  "NOW: "
hs_now_dsp:
    .asciz  "DSP SAMPLES"
hs_now_tg:
    .asciz  "TONE GENERATOR"
hs_now_off:
    .asciz  "OFF"
hs_nodsp:
    .asciz  " NO DSP "
WriteHead:  # the guarded data write's first 8 bytes, less the dead flag's address (941 0x48404EF8)
    .byte   0xf8, 0x97, 0x1c, 0xf8, 0x93, 0x18, 0xfc, 0xa8
    .align  2
sig_dspwait:    # the handshake wait (941 0x48404D25); masked: the downloaded and dead flag operands (DSPTONE)
    .word   0xcf, 0x80, 0xf8, 0xfe, 0xfc, 0xfc, 0xcc, 0xff, 0xff, 0x03, 0x00, 0x42, 0x00, 0xfc
    .word   0xa8, 0x100, 0x100, 0x100, 0x100, 0xa0, 0x00, 0xc9, 0x04, 0xca, 0x32, 0x80, 0x01, 0xfc
    .word   0x83, 0x5c, 0x01, 0x00, 0x34, 0xca, 0x1b, 0x58, 0x00, 0x8a, 0x01, 0x81, 0xf1, 0x09
    .word   0x46, 0x00, 0xa0, 0x00, 0xc8, 0x04, 0xca, 0x0c, 0x80, 0xff, 0xfc, 0x82, 0x100, 0x100
    .word   0x100, 0x100, 0xca, 0x0f, 0xfc, 0xac, 0x5c, 0x01, 0x00, 0x34, 0xf8, 0xec, 0x10, 0xc9
    .word   0x04, 0xca, 0xdc, 0xdf, 0x80, 0x08, 0xFFFF
sig_dspregs:    # 2x16 register write, its twin, 2x16 read, its twin (941 0x484052DD); masked: call displacements
    .word   0xf8, 0xfe, 0xf0, 0xf8, 0x97, 0x1c, 0x42, 0x18, 0xf8, 0xbc, 0x18, 0x1c, 0xcd, 0x100
    .word   0x100, 0x00, 0x10, 0xf8, 0xbc, 0x1c, 0xf8, 0xbd, 0x20, 0xcd, 0x100, 0x100, 0x00, 0x10
    .word   0xdf, 0x00, 0x10, 0xf8, 0xfe, 0xf0, 0xf8, 0x97, 0x1c, 0x42, 0x18, 0xf8, 0xbc, 0x18
    .word   0x1c, 0xcd, 0x100, 0x100, 0x00, 0x10, 0xf8, 0xbc, 0x1c, 0xf8, 0xbd, 0x20, 0xcd, 0x100
    .word   0x100, 0x00, 0x10, 0xdf, 0x00, 0x10, 0xf8, 0xfe, 0xe8, 0x42, 0x20, 0xf8, 0xbc, 0x20
    .word   0x1c, 0xcd, 0x100, 0x100, 0x00, 0x10, 0x2c, 0xc4, 0x09, 0xcd, 0x100, 0x100, 0x00, 0x0c
    .word   0x18, 0x42, 0x0c, 0x2c, 0xc4, 0x09, 0xcd, 0x100, 0x100, 0x00, 0x0c, 0x18, 0x42, 0x10
    .word   0x58, 0x10, 0xf8, 0xc0, 0x10, 0x59, 0x0c, 0xe4, 0x42, 0x14, 0xdf, 0x00, 0x18, 0xf8
    .word   0xfe, 0xe8, 0x42, 0x20, 0xf8, 0xbc, 0x20, 0x1c, 0xcd, 0x100, 0x100, 0x00, 0x10, 0x2c
    .word   0xc4, 0x09, 0xcd, 0x100, 0x100, 0x00, 0x14, 0x18, 0x42, 0x0c, 0x2c, 0xc4, 0x09, 0xcd
    .word   0x100, 0x100, 0x00, 0x14, 0x18, 0x42, 0x10, 0x58, 0x10, 0xf8, 0xc0, 0x10, 0x59, 0x0c
    .word   0xe4, 0x42, 0x14, 0xdf, 0x00, 0x18, 0xFFFF
.include "dsp_data.inc"             # generated: DspCode (the mixer's PM words), DspVars
    .align  4
