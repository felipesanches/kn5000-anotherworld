# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# KN7000 STYLE CONVERT build (cnv_main.s): the platform definitions. No firmware address is built
# in: fwfind.s finds the file routines, the task services, the millisecond counter, the panel
# bitmaps and the MIDI rings by their code on the first call, so one AW.CNV runs on program 893
# (v1.3), 935, 941 (v1.6) and 942 (tools/aw_find_fw.py runs the same searches over each).
#
# DISK MENU > STYLE CONVERT lists the floppy's *.CNV files, reads the chosen one whole to
# 0x502B8000 (after zeroing 0x30000 bytes there) and calls its first byte with `calls (a0)` on the
# firmware's main task (941 0x48479929, 893 0x4847976C). Each time it returns, the firmware reads a
# request from the mailbox at 0x5031BC00, serves it, writes 0xFF there and calls again. Request 5
# shows the NUL-terminated text that follows it in the mailbox on title 0x4A (_TT_STYLCNVTXT); the
# firmware then keeps calling (about 20 times a second), so answering 5 every time parks the UI on
# the converter while our own task runs. Request 0xFE ends the conversion (title 0x4C, then EXIT
# goes back to DISK MENU). See technics-roms-disasm kn7000/notes/style-converter.md and
# README-CNV.md here. 893 has the same load address, zeroed area and mailbox (its STYLE CONVERT
# code reads 0x5031BC00; the ROM dumper's loader ran there with them on 2026-10-19).

# ---- display: LCD frame, 640x240 RGB565, 1280 bytes/row ------------------------
.equ FB,              0x9CE00000
.equ FB_W,            640
.equ FB_H,            240
.equ FB_STRIDE,       1280
.equ AW_W,            320
.equ AW_H,            200
.equ AW_X0,           160           # (640-320)/2
.equ AW_Y0,           20            # (240-200)/2

# ---- the converter area and the mailbox ------------------------------------------------
.equ CNV_BASE,        0x502B8000    # where the firmware loads AW.CNV (this module's .mnbase)
.equ CNV_END,         0x502E8000    # end of the 0x30000 bytes the firmware zeroes before each load
.equ MAILBOX,         0x5031BC00    # byte 0: our request; request 5's text follows from byte 1
.equ MAILBOX_PAGE,    0x5031B000    # the firmware writes 0x5031BC00.. and 0x5031BFFC: never ours
.equ MAILBOX_PAGE_END, 0x5031C000

# ---- where the game lives (README-CNV.md, "Memory") ------------------------------------
# All of it in the work RAM STYLE CONVERT leaves to a converter, measured on program 893 in MAME
# (research-scratch aw-memory-plan: taps893_ranges.out): 0x502B8000-0x50379FFF stays untouched by
# the firmware through boot, idle, DISK MENU and a converter run, except the mailbox page. Nothing
# of the game is in CS1 (0x44000000-0x47FFFFFF and its view 0x84000000-0x87FFFFFF: IC23, the
# battery-backed SRAM with the panel settings and the PANEL MEMORY records, repeating every 256 KB
# through the whole chip select) nor in the user-memory pools 0x50180000-0x50297FFF (COMPOSER
# styles, pads; kept across power-off). tools/ic23_guard.py checks every address this build
# names; tools/cnv_layout.py checks the regions below; the run-time guard (cnv_main.s GuardRange,
# vm.s GuardPage) refuses a computed one outside [AW_LO, AW_HI) or on the mailbox page.
.equ AW_LO,           0x502B8000    # every byte the game writes is in [AW_LO, AW_HI) ...
.equ AW_HI,           0x5037A000    # ... (0x5037A000 on holds boot data) minus the mailbox page
.equ IMAGE_END_MAX,   0x502BE000    # AW.CNV itself (code and tables) must end before this
.equ AW_FONT,         0x502BE000    # anotherworld_chargen.rom, 768 bytes
.equ AW_STRIDX,       0x502BE300    # str_index.rom, 2048 bytes
.equ AW_STRDAT,       0x502BEB00    # str_data.rom, 4096 bytes, to 0x502BFAFF
.equ CNV_VARS,        0x502C0000    # the converter's and the loader's variables (cnv_main.s)
.equ FW_VARS,         0x502C0400    # what fwfind.s found (below), then its scratch from +0x40
.equ VM_POLY_BASE,    0x502C1000    # vm.inc: rasterizer scratch, 0x200 bytes
.equ VM_INTERP_BASE,  0x502C2000    # vm.inc: the interpreter, 0x1100 bytes
.equ VM_MISC_BASE,    0x502C4000    # vm.inc: the rest, 0x1400 bytes
.equ RES_TAB,         0x502C6000    # u32 per resource id: where it is resident now (0 = not)
.equ HELP_BUF,        0x502C8000    # 64,000 bytes: help pages, the stop screen, and the buffer a
.equ BITMAP_BUF,      HELP_BUF      #   packed bitmap is unpacked into before LoadBitmap draws it
.equ VIDEO2_AT,       0x502E8000    # the shared polygons (resource 0x11, 25,108 bytes), loaded once
.equ PART_AREA,       0x502EE400    # the current part's palette, bytecode, polygons, bitmaps
.equ PART_END,        0x5031B000    #   (largest part, the city: 164,407 bytes; aw_extract.py --parts)
.equ PAGE_BITMAP_0,   0x50320000    # four 320x200 pages, one per 0x10000 (interp.s GetPagePtr)
.equ PAGE_BITMAP_1,   0x50330000
.equ PAGE_BITMAP_2,   0x50340000
.equ PAGE_BITMAP_3,   0x50350000    # to 0x5035F9FF
.equ PAGE_SIZE,       AW_W*AW_H

# ---- task ------------------------------------------------------------------------
# Every firmware task runs at priority 3 and micro-ITRON does not time-slice, so ours runs at 3
# too and yields every frame (DLY_TSK). Slots 10, then 9, are free. The kernel allocates the
# task's stack itself (cre_tsk) and frees it at exd_tsk.
.equ TASK_ID_FIRST,   10
.equ TASK_ID_LAST,    9
.equ TASK_PRI,        3
.equ TASK_STACK,      0x2000         # room for the VM's polygon-hierarchy recursion

# ---- quitting ----------------------------------------------------------------------
.equ EXIT_OFS,        0x30+11       # EXIT = CPC_SEG11 SW7: PANEL_CPL + 11 (vm.inc FWV_PANEL)
.equ EXIT_BIT,        0x80
.equ QUIT_HOLD_MS,    1500          # hold EXIT this long to leave the game

# ---- what fwfind.s finds (FwStep), in FW_VARS ----------------------------------------
.equ FW_STEPS,        6
.equ FW_OPEN,         FW_VARS + 0x00   # OpenHere(a0 = name, a1 = mode) -> d0 (16-bit, < 0 = error)
.equ FW_READ,         FW_VARS + 0x04   # fmmread(a0 = buffer, d0 = bytes) -> d0 = bytes read
.equ FW_CLOSE,        FW_VARS + 0x08   # fmmclose(): the one open file
.equ FW_CRE,          FW_VARS + 0x0C   # ER cre_tsk(d0 = id, a0 = &T_CTSK)
.equ FW_STA,          FW_VARS + 0x10   # ER sta_tsk(d0 = id, d1 = start code)
.equ FW_DLY,          FW_VARS + 0x14   # the firmware's yield: d0 = ms (adds to the ms counter, rotates the ready queue)
.equ FW_EXD,          FW_VARS + 0x18   # exd_tsk(): exit and delete the calling task
.equ FW_FMMOPEN,      FW_VARS + 0x1C   # fmmopen, which FW_OPEN must call (the cross-check)
# The RAM addresses the shared VM reads (the ms counter, the panel bitmaps, the MIDI rings) go to
# vm.inc's FWV_* variables.
