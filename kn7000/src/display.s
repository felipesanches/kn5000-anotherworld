# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Shared by both KN7000 builds (main.s: SP7001 plug-in; cnv_main.s: STYLE CONVERT .CNV):
# the game task, the page blit and the border fill, and their data.

.equ SG_REASONS,      5             # StopGame's reasons (sg_why), GUARD_PAGE .. GUARD_FILE

# =================================================================================
# The game task: let the firmware settle, reset the VM, then run it until the run-time guard
# refuses a write (vm.inc GUARD_*), which stops the game.
GameTask:
    add     -0x10, sp
    mov     2500, d0                # let the firmware reach its static screen first
    mov     DLY_TSK, a1
    calls   (a1)
    call    GameReset, 0, 0
gt_loop:
    call    ExecuteInstruction, 0, 0
    mov     (GUARD_WHAT), d0
    cmp     0, d0
    beq     gt_loop
    call    StopGame, 0, 0          # does not return

# StopGame: the game cannot go on (vm.inc GUARD_WHAT says why). Show it on the LCD, with the
# address involved, and keep yielding: the platform ends the task from DLY_TSK when the player
# quits (cnv_main.s). The text uses the help screens' font, palette and HelpText (help.s).
StopGame:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     HELP_BUF, a0            # a black page of its own
    mov     PAGE_SIZE / 4, d1
    clr     d0
sg_clear:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     sg_clear
    mov     HELP_BUF, a0            # HelpText draws on CUR_PAGE_1 (the VM is not running)
    mov     a0, (CUR_PAGE_1)
    mov     help_palette, a0
    mov     palette, a1
    call    hs_copy_pal, 0, 0
    mov     sg_title, a3
    mov     76, d0
    mov     64, d1
    mov     2, d2
    call    HelpText, 0, 0
    mov     (GUARD_WHAT), d0        # the reason: sg_why[GUARD_WHAT - 1]
    add     -1, d0
    cmp     SG_REASONS, d0
    bcs     sg_known
    mov     SG_REASONS - 1, d0      # out of range: the last, generic one
sg_known:
    asl     2, d0
    mov     sg_why, a0
    add     d0, a0
    mov     (a0), a3
    mov     16, d0
    mov     88, d1
    mov     1, d2
    call    HelpText, 0, 0
    mov     (GUARD_ADDR), d0        # "AT 0x12345678"
    mov     GUARD_TEXT, a0
    call    HexText, 0, 0
    mov     GUARD_TEXT, a3
    mov     16, d0
    mov     102, d1
    mov     1, d2
    call    HelpText, 0, 0
    mov     sg_quit, a3
    mov     16, d0
    mov     130, d1
    mov     3, d2
    call    HelpText, 0, 0
sg_loop:
    mov     HELP_BUF, a0            # show it, again every second: the firmware may repaint
    call    BlitPage, 0, 0
    mov     1000, d0
    mov     DLY_TSK, a1
    calls   (a1)
    bra     sg_loop

# HexText(d0 = value, a0 = 16-byte buffer): "AT 0x" and eight upper-case hex digits, NUL-ended.
# Leaf; uses d0, d1, a0, a1.
HexText:
    mov     d0, a1                  # the value, shifted left a nibble per digit
    mov     0x30205441, d0          # "AT 0"
    mov     d0, (a0)
    mov     0x78, d0                # "x"
    movbu   d0, (4, a0)
    add     5, a0
    mov     8, d1
ht_digit:
    mov     a1, d0
    lsr     28, d0                  # the top nibble
    cmp     10, d0
    bcs     ht_dec
    add     7, d0
ht_dec:
    add     0x30, d0
    movbu   d0, (a0)
    inc     a0
    mov     a1, d0
    asl     4, d0
    mov     d0, a1
    add     -1, d1
    bne     ht_digit
    clr     d0
    movbu   d0, (a0)
    rets

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
    .align  4
sg_why:                             # GUARD_WHAT 1.. (vm.inc)
    .long   sg_page, sg_stack, sg_load, sg_bitmap, sg_file     # SG_REASONS of them
sg_title:   .asciz  "ANOTHER WORLD STOPPED"
sg_page:    .asciz  "a page pointer was not a page"
sg_stack:   .asciz  "the VM stack ran over"
sg_load:    .asciz  "a load outside the game's RAM"
sg_bitmap:  .asciz  "a bitmap that was not loaded"
sg_file:    .asciz  "a game file was missing or bad"
sg_quit:    .asciz  "Hold EXIT to quit."
    .align  4
