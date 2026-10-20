# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# KN7000 program 941 (no SP7001) platform definitions for the STYLE CONVERT build (cnv_main.s).
#
# DISK MENU > STYLE CONVERT lists the floppy's *.CNV files, reads the chosen one whole to
# 0x502B8000 (after zeroing 0x30000 bytes there) and calls its first byte with `calls (a0)` on the
# firmware's main task (0x48479929). Each time it returns, the firmware reads a request from the
# mailbox at 0x5031BC00, serves it, writes 0xFF there and calls again. Request 5 shows the
# NUL-terminated text that follows it in the mailbox on title 0x4A (_TT_STYLCNVTXT); the firmware
# then keeps calling (about 20 times a second), so answering 5 every time parks the UI on the
# converter while our own task runs. Request 0xFE ends the conversion (title 0x4C, then EXIT goes
# back to DISK MENU). See kn7000_disassembly notes/style-converter.md and README-CNV.md here.
#
# Every RAM address below is program 942's (platform.inc) minus 0x10, measured on 941 in MAME
# (probes/cnv/): the MIDI ring headers, the panel switch bitmaps, the kernel millisecond counter.

# ---- the converter area ------------------------------------------------------------
.equ CNV_BASE,        0x502B8000    # where the firmware loads AW.CNV (this module's .mnbase)
.equ CNV_END,         0x502E8000    # end of the 0x30000 bytes the firmware zeroes first
.equ BOUNCE,          0x502D0000    # 64 KB work-RAM buffer for floppy reads (DMA target)
.equ BOUNCE_SIZE,     0x10000
.equ CNV_VARS,        0x502E0000    # our variables (zeroed with the area on every load)
.equ MAILBOX,         0x5031BC00    # byte 0: our request; request 5's text follows from byte 1

# ---- firmware routines (program 941; `calls`-compatible starts, i.e. with their prologue) ----
# The task services are paired with 942's by the kernel routine each entry stub enters
# (kn7000_disassembly tools/itron_stubs.py; its ported symbol file had named 0x4C03D8AB ext_tsk
# until 2026-10-18). 941's own firmware does cre_tsk, then sta_tsk(8, 0), the same way.
.equ FW_CRE_TSK,      0x4C03D0C8    # ER cre_tsk(d0 = id, a0 = &T_CTSK)             (942 0x4C03D46B)
.equ FW_STA_TSK,      0x4C03D8AB    # ER sta_tsk(d0 = id, d1 = start code)          (942 0x4C03DCD3)
.equ FW_DLY_TSK,      0x4C03DD6F    # ER dly_tsk(d0 = ms): adds to KERNEL_MS, rotates the ready queue (942 0x4C03E295)
.equ FW_EXD_TSK,      0x4C03D5A1    # exd_tsk(): exit and delete the calling task   (942 0x4C03D944)
.equ FW_OPEN_HERE,    0x48531AC5    # d0 = open(a0 = name, a1 = mode) in the current drive + folder
.equ FW_FMMREAD,      0x48532463    # d0 = fmmread(a0 = buffer, d0 = bytes): from the open file
.equ FW_FMMCLOSE,     0x485323BC    # fmmclose(): the one open file

# ---- RAM the VM reads ----------------------------------------------------------------
.equ KERNEL_MS,       0x500D3C58    # kernel 1 kHz millisecond counter (942: 0x500D3C68)
.equ PANEL_CPR,       0x5006BE50    # CPR_SEGn switch bitmap at PANEL_CPR + n (942: 0x5006BE60)
.equ PANEL_CPL,       0x5006BE80    # CPL/CPC_SEGn bitmap at PANEL_CPL + n (942: 0x5006BE90)
.equ MIDIIN1_RXQ,     0x5001F050    # MIDI IN 1 receive ring header (942: 0x5001F060)
.equ MIDIOUT1_TXQ,    0x5001F864    # MIDI OUT 1 transmit ring header, the keybed (942: 0x5001F874)
.equ EXIT_BYTE,       PANEL_CPL+11  # EXIT = CPC_SEG11 SW7
.equ EXIT_BIT,        0x80
.equ QUIT_HOLD_MS,    1500          # hold EXIT this long to leave the game

# ---- task ------------------------------------------------------------------------
# Every firmware task runs at priority 3 and micro-ITRON does not time-slice, so ours runs at 3
# too and yields every frame (DLY_TSK). Slots 10, then 9, are free.
.equ TASK_ID_FIRST,   10
.equ TASK_ID_LAST,    9
.equ TASK_PRI,        3
.equ TASK_STACK,      0x2000         # room for the VM's polygon-hierarchy recursion

# ---- display: LCD frame, 640x240 RGB565, 1280 bytes/row ------------------------
.equ FB,              0x9CE00000
.equ FB_W,            640
.equ FB_H,            240
.equ FB_STRIDE,       1280
.equ AW_W,            320
.equ AW_H,            200
.equ AW_X0,           160           # (640-320)/2
.equ AW_Y0,           20            # (240-200)/2

# ---- RAM for the game ------------------------------------------------------------
# The firmware writes only 0x44000000-0x4403FFFF of the 0x44000000 window (measured on 941 through
# boot and STYLE CONVERT, probes/cnv/ram44.lua); everything the game uses sits above 0x44050000.
.equ GAME_RAM,        0x44000000
.equ PAGE_BITMAP_0,   0x44100000    # four 320x200 pages, one per 0x10000
.equ PAGE_BITMAP_1,   0x44110000
.equ PAGE_BITMAP_2,   0x44120000
.equ PAGE_BITMAP_3,   0x44130000
.equ PAGE_SIZE,       AW_W*AW_H
.equ BANK_STAGE,      0x44600000    # one BANKxx file at a time, copied up from BOUNCE
