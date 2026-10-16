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
.include "vm.inc"
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
    ret     [d2,d3,a2,a3], 0x20

# =================================================================================
GameTask:
    add     -0x10, sp
    mov     2500, d0                # let the firmware finish loading first
    mov     DLY_TSK, a1
    calls   (a1)
    call    GameInit, 0, 0
gt_loop:
    call    GameFrame, 0, 0
    mov     20, d0                  # ~50 Hz
    mov     DLY_TSK, a1
    calls   (a1)
    bra     gt_loop

# -------- VM test: clear page 0, fill a diamond polygon, blit ---------------------
GameInit:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    # 16-colour palette ramp (index 0 = black)
    mov     palette, a0
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
    # page 0 is the draw target; clear to colour 0
    mov     PAGE_BITMAP_0, a0
    mov     a0, (CUR_PAGE)
    mov     a0, a2                  # inline clear page to 0 (FillPage-via-call is flaky; TODO)
    mov     PAGE_SIZE, d2
gi_clear:
    clr     d0
    movbu   d0, (a2)
    inc     a2
    add     -1, d2
    bne     gi_clear
    # A solid trapezoid, bbox 100x100. Another World orders a polygon's vertices by
    # scanline pairs -- pt[0]=top-right, pt[1]=bottom-right, pt[2]=bottom-left,
    # pt[3]=top-left -- so fillPolygon walks the right edge (pt0->pt1) against the
    # left edge (pt3->pt2). This one is narrow at the top (x30..70) and widens to the
    # full 100 at the bottom, exercising both edge slopes in opposite directions.
    mov     100, d0
    movhu   d0, (POLY_BBOX_W)
    movhu   d0, (POLY_BBOX_H)
    mov     4, d0
    movbu   d0, (POLY_NUM_POINTS)
    mov     POLY_POINTS, a0
    mov     70, d0
    movhu   d0, (a0)                # p0 = (70,0)    top-right
    clr     d0
    movhu   d0, (2, a0)
    mov     100, d0
    movhu   d0, (4, a0)             # p1 = (100,100) bottom-right
    mov     100, d0
    movhu   d0, (6, a0)
    clr     d0
    movhu   d0, (8, a0)             # p2 = (0,100)   bottom-left
    mov     100, d0
    movhu   d0, (10, a0)
    mov     30, d0
    movhu   d0, (12, a0)            # p3 = (30,0)    top-left
    clr     d0
    movhu   d0, (14, a0)
    mov     11, d0                  # colour index 11
    movbu   d0, (DRAW_COLOR)
    mov     160, d0                 # centre (160,100)
    mov     100, d1
    call    FillPolygon, 0, 0
    ret     [d2,d3,a2,a3], 0x18

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
    ret     [d2,d3,a2,a3], 0x20

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
.include "vm.s"
