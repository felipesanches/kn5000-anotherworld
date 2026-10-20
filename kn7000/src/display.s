# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Shared by both KN7000 builds (main.s: SP7001 plug-in; cnv_main.s: KN7APP.BIN for KN7LOAD.CNV):
# the game task, the page blit (only what changed) and the border fill, and their data.

.equ SG_REASONS,      5             # StopGame's reasons (sg_why), GUARD_PAGE .. GUARD_FILE

# =================================================================================
# The game task: let the firmware settle, reset the VM, then run it until the run-time guard
# refuses a write (vm.inc GUARD_*), which stops the game.
GameTask:
    add     -0x10, sp
    mov     2500, d0                # let the firmware reach its static screen first
    mov     DLY_TSK, a1
    calls   (a1)
    call    PerfInit, 0, 0          # the speed measurement (perf.s): from here on
    call    PerfRegs, 0, 0
    call    PerfBench, 0, 0
    call    PerfRestart, 0, 0
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
    call    AudioStopAll, 0, 0      # no note left sounding (audio.s)
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
    mov     PH_PAUSE, d0
    call    PerfPhase, 0, 0
sg_loop:
    mov     (PF_DAMAGE), d0         # show it, all of it, again every second: the firmware may repaint
    or      PFD_STOP, d0
    mov     d0, (PF_DAMAGE)
    mov     HELP_BUF, a0
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
# BlitPage(a0 = a 320x200 8-bit-indexed page): show it centred in the 640x240 RGB565 LCD frame through
# the 16-entry palette. The LCD is slow to write (README-CNV.md, "Speed"), so only what it does not show
# already is written: SHADOW holds the colour indices the window shows, PF_PAL the palette it was drawn
# with, and each group of four pixels whose indices differ from SHADOW is written as two 32-bit stores of
# two pixels each (PF_PAIR: the RGB565 of both pixels of an index pair). The window is written whole when
# the palette has changed, and border and window both when the LCD may not hold what was drawn
# (PF_DAMAGE: nothing shown yet, the load bar, the overlay going off, a sentinel pixel that changed
# under us, the periodic repaint, the stop screen, a switch of the blit mode). The page shown last,
# when nothing has drawn on it since (PF_DIRTY), is not even compared. Phase BLIT (BORD for the
# border). In the old blit mode (PF_MODE = 1, PAGE DOWN: perf.s) it does what it did before
# 2026-10-20 instead, for comparison on the instrument: BlitOld and FillBorder, every time.
BlitPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2                  # the page
    mov     PH_BLIT, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)          # the phase to go back to
    mov     (PF_MODE), d0
    cmp     0, d0
    beq     bp_new
    mov     a2, a0                  # the old blit
    call    BlitOld, 0, 0
    call    FillBorder, 0, 0
    clr     d0
    mov     d0, (PF_LAST_SRC)       # (the shadow no longer says what the LCD shows)
    mov     (PF_FRAME_PX), d0
    add     AW_W * AW_H, d0
    mov     d0, (PF_FRAME_PX)
    call    PerfOverlay, 0, 0       # the border fill wiped it
    bra     bp_done
bp_new:
    call    PalCheck, 0, 0          # d0 = 1: a new palette, the pair table rebuilt
    mov     d0, d3                  # d3 = 1: write the whole window
    mov     (PF_DAMAGE), d0
    cmp     0, d0
    beq     bp_shown
    call    FillBorder, 0, 0        # repaint everything
    clr     d0
    mov     d0, (PF_DAMAGE)
    mov     d0, (PF_SINCE_REP)
    mov     (PF_REPAINTS), d0
    inc     d0
    mov     d0, (PF_REPAINTS)
    mov     1, d0
    mov     d0, (PF_OVL_DUE)
    mov     1, d3
    bra     bp_write
bp_shown:
    cmp     0, d3
    bne     bp_write
    mov     (PF_LAST_SRC), a0       # the page on the LCD, not drawn on since: nothing to do
    cmp     a2, a0
    bne     bp_write
    call    PageDirty, 0, 0
    cmp     0, d0
    bne     bp_write
    mov     (PF_SKIPS), d0
    inc     d0
    mov     d0, (PF_SKIPS)
    bra     bp_overlay
bp_write:
    mov     a2, a0
    mov     d3, d0
    call    BlitWindow, 0, 0
    mov     a2, (PF_LAST_SRC)
    mov     a2, a0
    call    PageClean, 0, 0
    mov     (PF_BLITS), d0
    inc     d0
    mov     d0, (PF_BLITS)
bp_overlay:
    mov     (PF_OVL_DUE), d0        # the overlay, after a repaint or when it was turned on
    cmp     0, d0
    beq     bp_done
    call    PerfOverlay, 0, 0
bp_done:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# BlitOld(a0 = page): the blit as it was before 2026-10-20 (the old blit mode): every pixel, through the
# palette, one 16-bit store each.
BlitOld:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2                  # source page
    mov     FB + (AW_Y0*FB_STRIDE) + (AW_X0*2), a3
    mov     AW_H, d3
bo_row:
    mov     a3, a1
    mov     AW_W, d2
bo_px:
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
    bne     bo_px
    mov     a3, d0
    add     FB_STRIDE, d0
    mov     d0, a3
    add     -1, d3
    bne     bo_row
    ret     [d2,d3,a2,a3], 0x20

# BlitWindow(a0 = page, d0 = 1 to write every pixel, 0 to write only those SHADOW does not hold): the
# page into the window, through PF_PAIR, and into SHADOW. Counts the pixels written (PF_FRAME_PX).
BlitWindow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2                  # a2 = the page
    mov     d0, (0x18, sp)
    mov     SHADOW, a3              # a3 = what the window shows
    mov     FB + (AW_Y0*FB_STRIDE) + (AW_X0*2), a1
    mov     PF_PAIR, a0
    mov     AW_H, d0
    mov     d0, (0x10, sp)          # rows left
    clr     d0
    mov     d0, (0x14, sp)          # groups of four pixels written
bw_row:
    mov     (0x18, sp), d0
    cmp     0, d0
    bne     bw_all_row
    mov     AW_W / 8, d2            # eight pixels a turn: two groups of four, compared as words
bw_two:
    mov     (a2), d0                # (the loads interleaved: a load used at once stalls)
    mov     (a3), d1
    mov     (4, a2), d3
    xor     d1, d0                  # d0 = what differs in group 0
    mov     (4, a3), d1
    xor     d3, d1                  # d1 = ... in group 1
    or      d1, d0
    bne     bw_put
bw_next:
    add     8, a2
    add     8, a3
    add     16, a1
    add     -1, d2
    bne     bw_two
    bra     bw_eol
bw_put:                             # one of the two groups changed, or both: each in turn
    mov     (a2), d0
    mov     (a3), d1
    cmp     d1, d0
    beq     bw_put1
    mov     d0, (a3)
    mov     d0, d1                  # pixels 0, 1: PF_PAIR[(i0 & 15) | (i1 & 15) << 4]
    and     0x0F, d1
    mov     d0, d3
    lsr     4, d3
    and     0xF0, d3
    or      d3, d1
    asl     2, d1
    mov     (d1, a0), d3
    mov     d3, (a1)
    lsr     16, d0                  # pixels 2, 3
    mov     d0, d1
    and     0x0F, d1
    lsr     4, d0
    and     0xF0, d0
    or      d0, d1
    asl     2, d1
    mov     (d1, a0), d3
    mov     d3, (4, a1)
    mov     (0x14, sp), d0
    inc     d0
    mov     d0, (0x14, sp)
bw_put1:
    mov     (4, a2), d0
    mov     (4, a3), d1
    cmp     d1, d0
    beq     bw_next
    mov     d0, (4, a3)
    mov     d0, d1                  # pixels 4, 5
    and     0x0F, d1
    mov     d0, d3
    lsr     4, d3
    and     0xF0, d3
    or      d3, d1
    asl     2, d1
    mov     (d1, a0), d3
    mov     d3, (8, a1)
    lsr     16, d0                  # pixels 6, 7
    mov     d0, d1
    and     0x0F, d1
    lsr     4, d0
    and     0xF0, d0
    or      d0, d1
    asl     2, d1
    mov     (d1, a0), d3
    mov     d3, (12, a1)
    mov     (0x14, sp), d0
    inc     d0
    mov     d0, (0x14, sp)
    bra     bw_next
bw_all_row:
    mov     AW_W / 4, d2
bw_all:                             # every group of the row
    mov     (a2), d0
    mov     d0, (a3)
    mov     d0, d1
    and     0x0F, d1
    mov     d0, d3
    lsr     4, d3
    and     0xF0, d3
    or      d3, d1
    asl     2, d1
    mov     (d1, a0), d3
    mov     d3, (a1)
    lsr     16, d0
    mov     d0, d1
    and     0x0F, d1
    lsr     4, d0
    and     0xF0, d0
    or      d0, d1
    asl     2, d1
    mov     (d1, a0), d3
    mov     d3, (4, a1)
    add     4, a2
    add     4, a3
    add     8, a1
    add     -1, d2
    bne     bw_all
    mov     (0x14, sp), d0
    add     AW_W / 4, d0
    mov     d0, (0x14, sp)
bw_eol:
    add     FB_STRIDE - AW_W*2, a1
    mov     (0x10, sp), d0
    add     -1, d0
    mov     d0, (0x10, sp)
    bne     bw_row
    mov     (0x14, sp), d0          # pixels written
    asl     2, d0
    mov     (PF_FRAME_PX), d1
    add     d0, d1
    mov     d1, (PF_FRAME_PX)
    ret     [d2,d3,a2,a3], 0x30

# PalCheck -> d0 = 1 when palette is not the one the LCD was drawn with (PF_PAL): PF_PAL becomes it and
# the pair table PF_PAIR is rebuilt (entry i0 | i1 << 4 = palette[i0] | palette[i1] << 16, pixel 0 in the
# low half, at the lower address); else 0. Leaf (saves d2, d3, a2).
PalCheck:
    movm    [d2,d3,a2], (sp)
    mov     palette, a0
    mov     PF_PAL, a1
    mov     8, d1
pk_cmp:
    mov     (a0), d0
    mov     (a1), d2
    cmp     d2, d0
    bne     pk_new
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     pk_cmp
    clr     d0
    ret     [d2,d3,a2], 0xC
pk_new:
    mov     palette, a0
    mov     PF_PAL, a1
    mov     8, d1
pk_copy:
    mov     (a0), d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     pk_copy
    mov     PF_PAL, a1
    mov     PF_PAIR, a2
    clr     d2
pk_pair:
    mov     d2, d0
    and     15, d0
    asl     1, d0
    movhu   (d0, a1), d3            # pixel 0's colour
    mov     d2, d0
    lsr     4, d0
    asl     1, d0
    movhu   (d0, a1), d0            # pixel 1's
    asl     16, d0
    or      d3, d0
    mov     d0, (a2)
    add     4, a2
    inc     d2
    cmp     256, d2
    bne     pk_pair
    mov     (PF_PAIR_N), d0
    inc     d0
    mov     d0, (PF_PAIR_N)
    mov     1, d0
    ret     [d2,d3,a2], 0xC

# PerfMarkDirty(a0 = a page about to be drawn on): note it, so that the blit does not skip it. Anything
# that is not one of the four pages is ignored. Leaf; uses d0, d1, a1; keeps a0.
PerfMarkDirty:
    mov     a0, d0
    mov     PAGE_BITMAP_0, d1
    sub     d1, d0
    mov     d0, d1
    and     0xFFFCFFFF, d1
    bne     pmd_ret
    lsr     16, d0
    mov     PF_DIRTY, a1
    mov     1, d1
    movbu   d1, (d0, a1)
pmd_ret:
    rets

# PageDirty(a0 = page) -> d0 = 0 when a0 is one of the four pages and nothing has drawn on it since it
# was shown, else 1. Leaf; uses d0, d1, a1; keeps a0.
PageDirty:
    mov     a0, d0
    mov     PAGE_BITMAP_0, d1
    sub     d1, d0
    mov     d0, d1
    and     0xFFFCFFFF, d1
    bne     pdy_yes
    lsr     16, d0
    mov     PF_DIRTY, a1
    movbu   (d0, a1), d0
    rets
pdy_yes:
    mov     1, d0
    rets

# PageClean(a0 = page): the LCD shows it as it is now. Leaf; uses d0, d1, a1; keeps a0.
PageClean:
    mov     a0, d0
    mov     PAGE_BITMAP_0, d1
    sub     d1, d0
    mov     d0, d1
    and     0xFFFCFFFF, d1
    bne     pcl_ret
    lsr     16, d0
    mov     PF_DIRTY, a1
    clr     d1
    movbu   d1, (d0, a1)
pcl_ret:
    rets

# FillBorder: paint everything around the 320x200 game window black -- the 20-row bands above and
# below it and the 160-pixel strips beside it -- so that the firmware's screen behind the game never
# shows. Done when BlitPage repaints everything (PF_DAMAGE), no longer on every blit (but in the old
# blit mode). 32-bit stores, 8 per loop. Phase BORD.
FillBorder:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     PH_BORD, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
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
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

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
