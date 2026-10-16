# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World on the Technics SX-KN7000 -- platform layer.
#
# A port of the Another World bytecode VM from the KN5000 version
# (github.com/felipesanches/kn5000-anotherworld, TLCS-900) to the KN7000's
# Panasonic MN10300, running as a ride-along module in the SP7001 SD plug-in.
#
# This file is the platform layer; the VM is being ported into vm.s. What is
# proven to work here (see ../README.md):
#   * the hook runs on the firmware's loading task, where the file API is valid;
#   * a task of ours blits a 320x200 8-bit-indexed page to the 640x240 RGB565
#     frame, through a 16-colour palette, and it persists on the static screen.
# The current build blits a test page to demonstrate the platform; the VM will
# fill the page instead.

.include "platform.inc"
.mnbase 0x502B6000                  # where xap_addon.py places this module

# =================================================================================
# The hook. Entered exactly as BASEEXT's XapEntry (a0 = framework, a1 = context,
# d0/d1 = &compile/&plug-in id), on the firmware's loading task. We start our task,
# run the two displaced instructions, and resume XapEntry so BASEEXT still works.
# (SD loading will go here too, where the file API is valid.)
Hook:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x10, sp)
    mov     d1, (0x14, sp)
    mov     a0, (0x18, sp)
    mov     a1, (0x1c, sp)
    call    StartTask, 0, 0
    mov     (0x10, sp), d0
    mov     (0x14, sp), d1
    mov     (0x18, sp), a0
    mov     (0x1c, sp), a1
    add     0x20, sp
    movm    (sp), [d2,d3,a2,a3]
    movm    [a2,a3], (sp)           # the two displaced XapEntry instructions
    add     -8, sp
    jmp     XAP_RESUME

StartTask:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     TASK_ID, d0
    mov     game_ctsk, a0
    mov     CRE_TSK_X, a1
    calls   (a1)
    cmp     0, d0
    bne     st_done
    mov     TASK_ID, d0
    clr     d1
    mov     STA_TSK, a1
    calls   (a1)
st_done:
    ret     [d2,d3,a2,a3], 0x10

# =================================================================================
GameTask:
    add     -0x10, sp
    call    GameInit, 0, 0
gt_loop:
    call    GameFrame, 0, 0
    mov     20, d0                  # ~50 Hz
    mov     DLY_TSK, a1
    calls   (a1)
    bra     gt_loop

# -------- platform demo: a test page + palette; the VM will replace this ----------
GameInit:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    mov     palette, a0             # a 16-colour ramp
    clr     d2
pi_loop:
    mov     d2, d0
    asl     1, d0
    mov     d0, d1
    asl     6, d1
    or      d1, d0
    mov     d2, d1
    asl     11, d1
    or      d1, d0
    movhu   d0, (a0)
    add     2, a0
    add     1, d2
    cmp     16, d2
    bne     pi_loop
    mov     PAGE_BITMAP_0, a2       # page 0 = (x xor y) & 15 plaid
    clr     d3
gi_y:
    clr     d2
gi_x:
    mov     d2, d0
    xor     d3, d0
    and     15, d0
    movbu   d0, (a2)
    inc     a2
    add     1, d2
    cmp     AW_W, d2
    bne     gi_x
    add     1, d3
    cmp     AW_H, d3
    bne     gi_y
    ret     [d2,d3,a2,a3], 8

GameFrame:
    add     -8, sp
    mov     PAGE_BITMAP_0, a0
    call    BlitPage, 0, 0
    ret     0, 8

# =================================================================================
# BlitPage: a0 = a 320x200 8-bit-indexed page. Draw it centred into the 640x240
# RGB565 frame through the 16-entry palette, one source pixel per frame pixel.
BlitPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2                  # source page
    mov     FB + (AW_Y0*FB_STRIDE) + (AW_X0*2), a3
    mov     AW_H, d3
bp_row:
    mov     a3, a1
    mov     AW_W, d2
bp_px:
    movbu   (a2), d0
    inc     a2
    and     15, d0
    asl     1, d0
    mov     palette, a0
    add     d0, a0
    movhu   (a0), d0
    movhu   d0, (a1)
    add     2, a1
    add     -1, d2
    bne     bp_px
    mov     a3, d0
    add     FB_STRIDE, d0
    mov     d0, a3
    add     -1, d3
    bne     bp_row
    ret     [d2,d3,a2,a3], 0x10

# =================================================================================
    .align  4
game_ctsk:
    .long   0
    .long   1
    .long   GameTask
    .word   TASK_PRI
    .word   0
    .long   TASK_STACK
    .align  4
palette:
    .space  16*2, 0
