# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Shared by both KN7000 builds (main.s: SP7001 plug-in; cnv_main.s: STYLE CONVERT .CNV):
# the game task, the page blit and the border fill, and their data.

# =================================================================================
# The game task: let the firmware settle, reset the VM, then run it forever.
GameTask:
    add     -0x10, sp
    mov     2500, d0                # let the firmware reach its static screen first
    mov     DLY_TSK, a1
    calls   (a1)
    call    GameReset, 0, 0
gt_loop:
    call    ExecuteInstruction, 0, 0
    bra     gt_loop

# =================================================================================
# BlitPage(a0 = a 320x200 8-bit-indexed page): draw it centred into the 640x240
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
    call    FillBorder, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# FillBorder: paint everything around the 320x200 game window black -- the 20-row bands above
# and below it and the 160-pixel strips beside it -- so the SP7001 screen behind the game never
# shows. Done on every blit: the firmware repaints the whole frame now and then (e.g. when the
# R1/R2 OCTAVE buttons, the panel's UP/DOWN, are pressed). 32-bit stores, 8 per loop.
FillBorder:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     FB, a0                  # top band: rows 0..AW_Y0-1, full width
    mov     AW_Y0 * FB_STRIDE / 32, d1
    call    fb_run, 0, 0
    mov     FB + (AW_Y0 + AW_H) * FB_STRIDE, a0   # bottom band
    mov     (FB_H - AW_Y0 - AW_H) * FB_STRIDE / 32, d1
    call    fb_run, 0, 0
    mov     FB + AW_Y0 * FB_STRIDE, a1            # side strips, one row at a time
    mov     AW_H, d2
fb_row:
    mov     a1, a0                  # left strip: x 0..AW_X0-1
    mov     AW_X0 * 2 / 32, d1
    call    fb_run, 0, 0
    mov     a1, a0                  # right strip: x AW_X0+AW_W..FB_W-1
    add     (AW_X0 + AW_W) * 2, a0
    mov     (FB_W - AW_X0 - AW_W) * 2 / 32, d1
    call    fb_run, 0, 0
    add     FB_STRIDE, a1
    add     -1, d2
    bne     fb_row
    ret     [d2,d3,a2,a3], 0x20

# fb_run(a0 = start, d1 = 32-byte blocks, d0 = 0): store d1 * 8 zero words from a0. Leaf.
fb_run:
    mov     d0, (a0)
    mov     d0, (4, a0)
    mov     d0, (8, a0)
    mov     d0, (12, a0)
    mov     d0, (16, a0)
    mov     d0, (20, a0)
    mov     d0, (24, a0)
    mov     d0, (28, a0)
    add     32, a0
    add     -1, d1
    bne     fb_run
    rets

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
