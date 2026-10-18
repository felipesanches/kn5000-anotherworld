# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World on the Technics SX-KN7000, program 941, with no SP7001: the game is a style
# converter. DISK MENU > STYLE CONVERT lists AW.CNV, and choosing it loads this file to 0x502B8000
# and calls its first byte (platform941.inc says how the firmware drives a converter).
#
# First call (on the firmware's main task, where the file layer is in use anyway):
#   * read the font, the strings and the game's own BANK01..BANK0D from the floppy, unpacking every
#     resource (ByteKiller) to the RAM address the SD build loads it to (awbank_tab.s);
#   * start the game task (display.s: GameTask runs the VM, as in the SP7001 build);
#   * answer request 5, a short text, which parks the firmware on the converter.
# Every later call answers 5 again, until EXIT has been held for QUIT_HOLD_MS: then the game task
# ends itself at its next yield (DLY_TSK below) and the following call answers 0xFE, which hands
# the instrument back: the firmware shows a message (EXIT), then "Continue Next?". YES calls the
# converter again, which starts a new game at once; NO leaves STYLE CONVERT.

.include "platform941.inc"
.include "vm.inc"
.include "awres.inc"                # generated: RES_COUNT, RES_BASE, RES_END
.include "awbank.inc"               # generated: BANK_FILES, BANK_RECS, BANK_MAX
.mnbase 0x502B8000                  # CNV_BASE: the firmware loads AW.CNV here

# ---- our variables (CNV_VARS, zeroed by the firmware with the whole area on each load) ----
.equ CV_STATE,     CNV_VARS + 0x00  # 0 first call, 1 started
.equ CV_QUIT_REQ,  CNV_VARS + 0x04  # set by the entry when EXIT has been held long enough
.equ CV_TASK_DONE, CNV_VARS + 0x08  # set when no game task runs (ended, or never started)
.equ CV_EXIT_T0,   CNV_VARS + 0x0C  # KERNEL_MS when EXIT went down (0 = up)
.equ CV_CALLS,     CNV_VARS + 0x10  # entry calls so far
.equ CV_LOAD_ERR,  CNV_VARS + 0x14  # files that failed to open/read + resources that failed to unpack
.equ CV_LOAD_MS,   CNV_VARS + 0x18  # how long the load took
.equ CV_TASK_ID,   CNV_VARS + 0x1C  # the game task's id (0 = none)
.equ CV_BANK,      CNV_VARS + 0x20  # loader: bank file index
.equ CV_REC,       CNV_VARS + 0x24  # loader: next BankRec
.equ CV_FILE_LEFT, CNV_VARS + 0x28  # ReadFile: bytes still to read
.equ CV_FILE_DST,  CNV_VARS + 0x2C  # ReadFile: where the next chunk goes
.equ CV_ENDED,     CNV_VARS + 0x30  # we answered 0xFE: the next call is "Continue Next?" -> YES
.equ BK_CRC,       CNV_VARS + 0x40  # unpacker state
.equ BK_LEFT,      CNV_VARS + 0x44
.equ BK_N,         CNV_VARS + 0x48
.equ BK_ACC,       CNV_VARS + 0x4C
.equ BK_D1,        CNV_VARS + 0x50
.equ BK_D2,        CNV_VARS + 0x54
.equ CV_ERRLOG,    CNV_VARS + 0x100 # u32 per failed step: (kind << 24) | detail

# =================================================================================
# The entry: called by the firmware with `calls (a0)`, a0 = CNV_BASE, on its main task.
CnvEntry:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (CV_CALLS), d0
    inc     d0
    mov     d0, (CV_CALLS)
    mov     (CV_STATE), d0
    cmp     0, d0
    bne     ce_running
    mov     1, d0
    mov     d0, (CV_STATE)
    mov     (KERNEL_MS), d0
    mov     d0, (CV_LOAD_MS)
    call    CnvLoad, 0, 0
    mov     (KERNEL_MS), d0
    mov     (CV_LOAD_MS), d1
    sub     d1, d0
    mov     d0, (CV_LOAD_MS)
    mov     (CV_LOAD_ERR), d0
    cmp     0, d0
    bne     ce_no_task              # the game data is incomplete: show why, start nothing
    call    StartTask, 0, 0
    bra     ce_running
ce_no_task:
    mov     1, d0
    mov     d0, (CV_TASK_DONE)
ce_running:
    # A call after we answered 0xFE is the firmware's "Continue Next?" answered YES: play again
    # (the data is still in RAM). NO leaves STYLE CONVERT without calling us.
    mov     (CV_ENDED), d0
    cmp     0, d0
    beq     ce_poll_exit
    clr     d0
    mov     d0, (CV_ENDED)
    mov     d0, (CV_QUIT_REQ)
    mov     d0, (CV_TASK_DONE)
    mov     d0, (CV_EXIT_T0)
    mov     (CV_LOAD_ERR), d0
    cmp     0, d0
    bne     ce_no_task
    call    StartTask, 0, 0
ce_poll_exit:
    # EXIT held for QUIT_HOLD_MS -> quit request (the firmware ignores EXIT while we answer 5)
    movbu   (EXIT_BYTE), d0
    btst    EXIT_BIT, d0
    beq     ce_exit_up
    mov     (CV_EXIT_T0), d1
    cmp     0, d1
    bne     ce_exit_held
    mov     (KERNEL_MS), d1
    or      1, d1
    mov     d1, (CV_EXIT_T0)
    bra     ce_answer
ce_exit_held:
    mov     (KERNEL_MS), d0
    sub     d1, d0
    cmp     QUIT_HOLD_MS, d0
    blt     ce_answer
    mov     1, d0
    mov     d0, (CV_QUIT_REQ)
    bra     ce_answer
ce_exit_up:
    clr     d0
    mov     d0, (CV_EXIT_T0)
ce_answer:
    mov     MAILBOX, a0
    mov     (CV_QUIT_REQ), d0
    cmp     0, d0
    beq     ce_park
    mov     (CV_TASK_DONE), d0
    cmp     0, d0
    beq     ce_park                 # wait for the game task to leave first
    mov     0xFE, d0                # done: hand the instrument back
    movbu   d0, (a0)
    mov     1, d0
    mov     d0, (CV_ENDED)
    bra     ce_ret
ce_park:
    mov     5, d0                   # request 5: show our text, call us again
    movbu   d0, (a0)
    mov     msg_play, a1
    mov     (CV_LOAD_ERR), d0
    cmp     0, d0
    beq     ce_copy
    mov     msg_err, a1
ce_copy:
    inc     a0
ce_cpy:
    movbu   (a1), d0
    movbu   d0, (a0)
    inc     a0
    inc     a1
    cmp     0, d0
    bne     ce_cpy
ce_ret:
    ret     [d2,d3,a2,a3], 0x30

# =================================================================================
# DLY_TSK(d0 = ms): every yield of the VM and the help screen comes through here (display.s,
# interp.s, help.s call DLY_TSK). If the entry has asked us to quit, end the task here, between
# frames; otherwise it is the firmware's dly_tsk.
DLY_TSK:
    mov     (CV_QUIT_REQ), d1
    cmp     0, d1
    bne     dq_quit
    mov     FW_DLY_TSK, a0
    jmp     (a0)                    # tail call: dly_tsk returns to our caller
dq_quit:
    mov     1, d1
    mov     d1, (CV_TASK_DONE)
    mov     FW_EXD_TSK, a0
    calls   (a0)                    # exit and delete this task; does not return
dq_hang:
    bra     dq_hang

# Create and start the game task, trying slot 10 then 9.
StartTask:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     TASK_ID_FIRST, d2
st_try:
    mov     d2, d0
    mov     game_ctsk, a0
    mov     FW_CRE_TSK, a1
    calls   (a1)
    cmp     0, d0                    # E_OK
    beq     st_start
    add     -1, d2
    cmp     TASK_ID_LAST, d2
    bge     st_try
    mov     1, d0                    # no free slot: nothing runs, so EXIT can end at once
    mov     d0, (CV_TASK_DONE)
    bra     st_done
st_start:
    mov     d2, (CV_TASK_ID)
    mov     d2, d0
    clr     d1
    mov     FW_STA_TSK, a1
    calls   (a1)
st_done:
    ret     [d2,d3,a2,a3], 0x20

# =================================================================================
# CnvLoad: font + strings + every resource, from the floppy's current folder (the one STYLE
# CONVERT listed). Skipped when a previous run left everything in RAM (AW_LOADED_FLAG). A bar along
# the bottom of the LCD shows the progress.
CnvLoad:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (AW_LOADED_FLAG), d0
    cmp     0x600D, d0
    beq     cl_done
    clr     d0
    call    Progress, 0, 0
    mov     name_font, a0
    mov     AW_FONT, a1
    mov     AW_FONT_SZ, d0
    call    ReadFile, 0, 0
    mov     name_stridx, a0
    mov     AW_STRIDX, a1
    mov     AW_STRIDX_SZ, d0
    call    ReadFile, 0, 0
    mov     name_strdat, a0
    mov     AW_STRDAT, a1
    mov     AW_STRDAT_SZ, d0
    call    ReadFile, 0, 0
    clr     d0
    mov     d0, (CV_BANK)
    mov     BankRec, a0
    mov     a0, (CV_REC)
cl_bank:
    mov     (CV_BANK), d0           # the name BANKxx
    asl     2, d0
    mov     BankNo, a0
    add     d0, a0
    mov     (a0), d0
    mov     d0, d1
    lsr     4, d1
    call    HexDigit, 0, 0
    movbu   d1, (name_bank_xx)
    mov     d0, d1
    call    HexDigit, 0, 0
    movbu   d1, (name_bank_xx + 1)
    mov     (CV_BANK), d0           # read the whole bank file to BANK_STAGE
    asl     2, d0
    mov     BankSize, a0
    add     d0, a0
    mov     (a0), d0
    mov     name_bank, a0
    mov     BANK_STAGE, a1
    call    ReadFile, 0, 0
cl_rec:                             # unpack every resource of this bank
    mov     (CV_REC), a2
    mov     BankRec + BANK_RECS*20, d0
    mov     a2, d1
    cmp     d0, d1
    bcc     cl_next_bank            # all records done
    movbu   (a2), d0                # this record's bank number
    mov     (CV_BANK), d1
    asl     2, d1
    mov     BankNo, a0
    add     d1, a0
    mov     (a0), d1
    cmp     d1, d0
    bne     cl_next_bank            # it belongs to the next bank
    mov     (4, a2), d0             # offset in the bank file
    mov     BANK_STAGE, a0
    add     d0, a0                  # a0 = packed data
    mov     (8, a2), d0             # packed size
    mov     (16, a2), a1            # destination
    mov     (12, a2), d1            # unpacked size
    movbu   (1, a2), d2
    cmp     0, d2
    beq     cl_copy
    call    BkUnpack, 0, 0          # d0 = crc (0 = good)
    cmp     0, d0
    beq     cl_rec_next
    mov     0x02000000, d0          # kind 2: unpack failure, detail = resource id
    mov     (CV_REC), a2
    movhu   (2, a2), d1
    or      d1, d0
    call    LogError, 0, 0
    bra     cl_rec_next
cl_copy:                            # stored as is: copy d1 bytes a0 -> a1
    cmp     0, d1
    beq     cl_rec_next
cl_copy_b:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d1
    bne     cl_copy_b
cl_rec_next:
    mov     (CV_REC), a2
    add     20, a2
    mov     a2, (CV_REC)
    bra     cl_rec
cl_next_bank:
    mov     (CV_BANK), d0
    inc     d0
    mov     d0, (CV_BANK)
    call    Progress, 0, 0
    mov     (CV_BANK), d0
    cmp     BANK_FILES, d0
    blt     cl_bank
    mov     (CV_LOAD_ERR), d0
    cmp     0, d0
    bne     cl_done
    mov     0x600D, d0
    mov     d0, (AW_LOADED_FLAG)
cl_done:
    ret     [d2,d3,a2,a3], 0x30

# HexDigit(d1 = value): d1 = the upper-case hex digit of its low nibble. Leaf; keeps d0.
HexDigit:
    and     15, d1
    cmp     10, d1
    blt     hd_num
    add     7, d1
hd_num:
    add     0x30, d1
    rets

# LogError(d0 = (kind << 24) | detail): count it and keep the first 32. Leaf.
LogError:
    mov     (CV_LOAD_ERR), d1
    cmp     32, d1
    bcc     le_count
    asl     2, d1
    mov     CV_ERRLOG, a0
    add     d1, a0
    mov     d0, (a0)
le_count:
    mov     (CV_LOAD_ERR), d1
    inc     d1
    mov     d1, (CV_LOAD_ERR)
    rets

# Progress(d0 = banks done, 0..BANK_FILES): a white bar along the LCD's bottom rows.
Progress:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     600, d1                 # bar width = 600 * done / BANK_FILES
    mulu    d0, d1
    mov     BANK_FILES, d2
    divu    d2, d1
    cmp     0, d1
    beq     pg_done
    mov     FB + 228*FB_STRIDE + 20*2, a1
    mov     6, d3                   # rows
pg_row:
    mov     a1, a0
    mov     d1, d2
pg_px:
    mov     0xFFFF, d0
    movhu   d0, (a0)
    add     2, a0
    add     -1, d2
    bne     pg_px
    add     FB_STRIDE, a1
    add     -1, d3
    bne     pg_row
pg_done:
    ret     [d2,d3,a2,a3], 0x20

# ReadFile(a0 = 8.3 name, a1 = destination, d0 = bytes): open it in the floppy's current folder
# and read it through the work-RAM bounce buffer, BOUNCE_SIZE at a time (the floppy read is a DMA
# into work RAM). A failure is logged (kind 1: open, kind 3: short read; detail = bytes left).
# The firmware's routines store their arguments in the caller's frame at sp+4..sp+0x10, so
# nothing of ours lives there.
ReadFile:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a1, (CV_FILE_DST)
    mov     d0, (CV_FILE_LEFT)
    mov     mode_rb, a1             # a0 = name
    mov     FW_OPEN_HERE, a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    bge     rf_chunk
    mov     0x01000000, d0          # kind 1: the open failed
    mov     (CV_FILE_LEFT), d1
    or      d1, d0
    call    LogError, 0, 0
    bra     rf_ret
rf_chunk:
    mov     (CV_FILE_LEFT), d0
    cmp     0, d0
    beq     rf_close
    mov     BOUNCE_SIZE, d1
    cmp     d1, d0
    bls     rf_n
    mov     d1, d0
rf_n:
    mov     d0, (0x14, sp)          # this chunk's length
    mov     BOUNCE, a0
    mov     FW_FMMREAD, a3
    calls   (a3)                    # d0 = bytes read
    mov     (0x14, sp), d1
    cmp     d1, d0
    bne     rf_short
    mov     BOUNCE, a0              # copy the chunk up: d1 bytes, BOUNCE -> CV_FILE_DST
    mov     (CV_FILE_DST), a1
    mov     d1, d2
rf_copy:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     rf_copy
    mov     a1, (CV_FILE_DST)
    mov     (CV_FILE_LEFT), d0
    sub     d1, d0
    mov     d0, (CV_FILE_LEFT)
    bra     rf_chunk
rf_short:
    mov     0x03000000, d0          # kind 3: a short read
    mov     (CV_FILE_LEFT), d1
    or      d1, d0
    call    LogError, 0, 0
rf_close:
    mov     FW_FMMCLOSE, a3
    calls   (a3)
rf_ret:
    ret     [d2,d3,a2,a3], 0x30

# =================================================================================
# BkUnpack(a0 = packed data, d0 = packed size, a1 = destination, d1 = unpacked size) -> d0 = crc
# (0 = intact). ByteKiller, as tools/aw_extract.py unpack(): 32-bit big-endian words are read from
# the END of the packed data (unpacked size, crc, then the first bit-buffer word); the output is
# written backwards from its last byte. a2 = next word to read, d3 = bit buffer, a3 = output.
BkUnpack:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d1, (BK_LEFT)
    mov     a1, a3
    add     d1, a3
    add     -1, a3                  # last output byte
    add     d0, a0
    add     -8, a0
    mov     a0, a2
    call    ReadBE, 0, 0            # d3 = crc word
    mov     d3, (BK_CRC)
    add     -4, a2
    call    ReadBE, 0, 0            # d3 = first bit-buffer word
    add     -4, a2
    mov     (BK_CRC), d0
    xor     d3, d0
    mov     d0, (BK_CRC)
bk_loop:
    mov     (BK_LEFT), d0
    cmp     0, d0
    ble     bk_done
    mov     1, d0
    call    GetBits, 0, 0
    cmp     0, d0
    bne     bk_1
    mov     1, d0
    call    GetBits, 0, 0
    cmp     0, d0
    bne     bk_01
    mov     3, d0                   # 00: literal run of 1..8 bytes
    call    GetBits, 0, 0
    add     1, d0
    mov     d0, d1
    bra     bk_literal
bk_01:                              # 01: copy 2 bytes from an 8-bit offset
    mov     8, d0
    call    GetBits, 0, 0
    mov     d0, d2
    mov     2, d1
    bra     bk_copy
bk_1:
    mov     2, d0
    call    GetBits, 0, 0
    cmp     3, d0
    bne     bk_1x
    mov     8, d0                   # 11: literal run of 9..264 bytes
    call    GetBits, 0, 0
    add     9, d0
    mov     d0, d1
    bra     bk_literal
bk_1x:
    cmp     2, d0
    bne     bk_1y
    mov     8, d0                   # 10: copy 1..256 bytes from a 12-bit offset
    call    GetBits, 0, 0
    add     1, d0
    mov     d0, d1
    mov     12, d0
    call    GetBits, 0, 0
    mov     d0, d2
    bra     bk_copy
bk_1y:
    cmp     1, d0
    bne     bk_1z
    mov     10, d0                  # 01 after 1: copy 4 bytes from a 10-bit offset
    call    GetBits, 0, 0
    mov     d0, d2
    mov     4, d1
    bra     bk_copy
bk_1z:
    mov     9, d0                   # 00 after 1: copy 3 bytes from a 9-bit offset
    call    GetBits, 0, 0
    mov     d0, d2
    mov     3, d1
bk_copy:                            # d1 bytes from d2 above the output pointer
    call    Clamp, 0, 0
bk_copy_b:
    cmp     0, d1
    beq     bk_loop
    mov     a3, a0
    add     d2, a0
    movbu   (a0), d0
    movbu   d0, (a3)
    add     -1, a3
    add     -1, d1
    bra     bk_copy_b
bk_literal:                         # d1 bytes, 8 bits each
    call    Clamp, 0, 0
bk_lit_b:
    cmp     0, d1
    beq     bk_loop
    mov     8, d0
    call    GetBits, 0, 0
    movbu   d0, (a3)
    add     -1, a3
    add     -1, d1
    bra     bk_lit_b
bk_done:
    mov     (BK_CRC), d0
    cmp     0, d0                   # also fail if the stream ran past the expected size
    bne     bk_ret
    mov     (BK_LEFT), d0
bk_ret:
    ret     [d2,d3,a2,a3], 0x20

# Clamp: BK_LEFT -= d1, never writing past the start of the output (corrupt data). Leaf.
Clamp:
    mov     (BK_LEFT), d0
    cmp     d1, d0
    bcc     cp_ok
    mov     d0, d1                  # only what is left
cp_ok:
    sub     d1, d0
    mov     d0, (BK_LEFT)
    rets

# ReadBE: d3 = the big-endian 32-bit word at a2. Leaf; uses d0.
ReadBE:
    movbu   (a2), d3
    asl     8, d3
    movbu   (1, a2), d0
    or      d0, d3
    asl     8, d3
    movbu   (2, a2), d0
    or      d0, d3
    asl     8, d3
    movbu   (3, a2), d0
    or      d0, d3
    rets

# GetBits(d0 = n): d0 = the next n bits, first bit most significant. Keeps d1, d2 (saved in RAM);
# advances the bit buffer d3 and the word pointer a2, folding each new word into BK_CRC.
GetBits:
    mov     d1, (BK_D1)
    mov     d2, (BK_D2)
    mov     d0, d2                  # bits still to take
    clr     d1                      # value
gb_bit:
    mov     d3, d0
    and     1, d0
    lsr     1, d3
    cmp     0, d3
    bne     gb_have
    movbu   (a2), d3                # refill: d3 = the next big-endian word (inline: a leaf
    asl     8, d3                   # entered with `call x, 0, 0` must not call -- the nested
    movbu   (1, a2), d0             # call would overwrite its return address at (sp))
    or      d0, d3
    asl     8, d3
    movbu   (2, a2), d0
    or      d0, d3
    asl     8, d3
    movbu   (3, a2), d0
    or      d0, d3
    add     -4, a2
    mov     (BK_CRC), d0
    xor     d3, d0
    mov     d0, (BK_CRC)
    mov     d3, d0
    and     1, d0
    lsr     1, d3
    or      0x80000000, d3
gb_have:
    asl     1, d1
    or      d0, d1
    add     -1, d2
    bne     gb_bit
    mov     d1, d0
    mov     (BK_D1), d1
    mov     (BK_D2), d2
    rets

# =================================================================================
.include "display.s"
    .align  4
name_font:
    .asciz  "AWFONT.AW"
    .align  2
name_stridx:
    .asciz  "AWSTRIDX.AW"
    .align  2
name_strdat:
    .asciz  "AWSTRDAT.AW"
    .align  2
name_bank:
    .ascii  "BANK"
name_bank_xx:
    .asciz  "00"
    .align  2
mode_rb:
    .asciz  "rb"
    .align  2
msg_play:
    .asciz  "HOLD EXIT TO QUIT"
    .align  2
msg_err:
    .asciz  "GAME FILES MISSING"
    .align  4
.include "vm.s"
.include "interp.s"
.include "help.s"
.include "awres_tab.s"              # generated: ResAddr, ResSize, ResType (and the SD packs)
.include "awbank_tab.s"             # generated: BankNo, BankSize, BankRec
