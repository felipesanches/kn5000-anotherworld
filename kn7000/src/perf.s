# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# perf.s -- where a frame's time goes, measured on the instrument itself (README-CNV.md, "Speed"). The
# KN7APP.BIN build's (the SP7001 build has perf_stub.s instead).
#   * A fine clock: Stamp reads the kernel's millisecond counter and timer 4's down-counter (vm.inc TM4_*),
#     the clock pass 8 of the ROM dumper's DSP probe proved on the owner's unit.
#   * Phases: PerfPhase charges the time since the last switch to the phase that was running and starts
#     another (vm.inc PH_*). PerfFrameEnd closes a VM frame (NextThread, after the end-of-frame yield):
#     per phase, per one-second window, per part and over the whole game.
#   * A benchmark before the game starts (PerfBench): stores and loads to the LCD frame and to work RAM,
#     ns per access; and the bus controller's settings as the firmware left them (PerfRegs).
#   * The figures on the LCD: an overlay in the left border that PAGE UP turns on and off (PerfInput,
#     PerfOverlay); the help screen's fourth page (PerfPageBuild, help.s); and the text of AWPERF.TXT,
#     which cnv_main.s writes to the SD card at quit (ReportBuild).
#   * PAGE DOWN switches the blit mode (PF_MODE): 0, the new blit (only what changed, the border once);
#     1, the old one (every pixel, 16 bits at a time, and the whole border, on every blit; and the old
#     8 ms floor on the yield). Each mode has its own totals, so one run gives both.
#   * PerfSentinels: 16 pixels of the LCD that tell when something else drew on it (the blit, display.s,
#     then repaints everything).
# Convention as the rest of the port: d0, d1, a0, a1 scratch; d2, d3, a2, a3 kept; a routine that calls
# makes a frame first.

.equ SENT_COUNT,      47            # sent_tab's sentinel pixels

# =================================================================================
# Stamp -> d0 = now, in counts of 1/2001 ms: ms * 2001 + (2000 - TM4BC), the counter read on both sides
# of TM4BC until it holds. Differences are right modulo 2^32 (35 minutes). Leaf; uses d0, d1, a0.
Stamp:
    movm    [d2,d3], (sp)
    mov     (FWV_KERNEL_MS), a0
    mov     STAMP_TRIES, d3
stp_try:
    mov     (a0), d0
    movhu   (TM4BC), d1
    mov     (a0), d2
    cmp     d0, d2
    beq     stp_held
    add     -1, d3
    bne     stp_try
stp_held:
    cmp     TM4_TOP, d1             # (no count above the base register's)
    bls     stp_bc
    mov     TM4_TOP, d1
stp_bc:
    mov     TM4_TOP + 1, d2
    mul     d2, d0
    add     TM4_TOP, d0
    sub     d1, d0
    ret     [d2,d3], 8

# Div(d0 = a, d1 = b) -> d0 = a / b, d1 = a % b, unsigned (0, 0 when b = 0). Leaf; uses a0, MDR.
Div:
    cmp     0, d1
    beq     dv_zero
    mov     d1, a0
    clr     d1
    mov     d1, mdr
    mov     a0, d1
    divu    d1, d0
    mov     mdr, d1
    rets
dv_zero:
    clr     d0
    clr     d1
    rets

# =================================================================================
# PerfPhase(d0 = phase PH_*) -> d0 = the phase that was running. Charges the time since the last switch to
# that phase (PF_ACC) and times the new one from now.
PerfPhase:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    call    Stamp, 0, 0
    mov     (PF_T_LAST), d1
    mov     d0, (PF_T_LAST)
    sub     d1, d0                  # counts since the last switch
    bge     pph_pos
    clr     d0                      # (a stamp a tick early: nothing)
pph_pos:
    mov     (PF_CUR), d1
    and     PH_COUNT - 1, d1
    asl     2, d1
    mov     PF_ACC, a0
    add     d1, a0
    mov     (a0), d1
    add     d0, d1
    mov     d1, (a0)
    mov     (PF_CUR), d0
    mov     d2, (PF_CUR)
    ret     [d2,d3,a2,a3], 0x20

# PerfInit: a new game. Clears the block, times the VM from now, asks the first blit to paint everything.
PerfInit:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     VM_PERF_BASE, a0
    mov     0x1000 / 4, d1
    clr     d0
pin_zero:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     pin_zero
    call    Stamp, 0, 0
    mov     d0, (PF_T_LAST)
    mov     d0, (PF_WIN_T0)
    mov     PFD_START, d0
    mov     d0, (PF_DAMAGE)
    mov     PF_PAL, a0              # a palette the game never has, so the first blit builds the pairs
    mov     8, d1
    mov     -1, d0
pin_pal:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     pin_pal
    ret     [d2,d3,a2,a3], 0x20

# PerfRestart: time from now (after the benchmark, which no frame should carry).
PerfRestart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    Stamp, 0, 0
    mov     d0, (PF_T_LAST)
    mov     d0, (PF_WIN_T0)
    ret     [d2,d3,a2,a3], 0x20

# PerfFrameEnd: the VM frame has ended (NextThread, just after the end-of-frame yield). Charges the yield,
# adds the frame to its window, its part and the game, and closes the window after a second.
PerfFrameEnd:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     PH_VM, d0
    call    PerfPhase, 0, 0
    movhu   (CURRENT_PART_ID), d0   # this part's record
    add     -PART_FIRST, d0
    cmp     10, d0
    bcs     pfe_part
    mov     9, d0
pfe_part:
    mov     PR_LEN, d1
    mul     d1, d0
    mov     PF_PART, a3
    add     d0, a3
    mov     (PF_MODE), d0           # ... of this blit mode
    cmp     0, d0
    beq     pfe_mode
    add     PR_SET, a3
pfe_mode:
    mov     PF_ACC, a0
    mov     PF_WIN, a1
    mov     a3, a2
    add     PR_SUM, a2
    mov     PH_COUNT, d2
    clr     d3                      # d3 = the frame, us (all phases but LOAD and PAUSE, the last two)
pfe_ph:
    mov     (a0), d0
    lsr     1, d0                   # counts -> us (0.49975 us each)
    clr     d1
    mov     d1, (a0)
    mov     (a1), d1
    add     d0, d1
    mov     d1, (a1)
    mov     (a2), d1
    add     d0, d1
    mov     d1, (a2)
    cmp     2, d2
    bls     pfe_nof
    add     d0, d3
pfe_nof:
    add     4, a0
    add     4, a1
    add     4, a2
    add     -1, d2
    bne     pfe_ph
    mov     (PF_WIN_FRAMES), d0
    inc     d0
    mov     d0, (PF_WIN_FRAMES)
    mov     (PF_WIN_MAX), d0
    cmp     d0, d3
    bls     pfe_wmax
    mov     d3, (PF_WIN_MAX)
pfe_wmax:
    mov     (PR_FRAMES, a3), d0
    inc     d0
    mov     d0, (PR_FRAMES, a3)
    mov     (PR_MAX, a3), d0
    cmp     d0, d3
    bls     pfe_pmax
    mov     d3, (PR_MAX, a3)
pfe_pmax:
    call    ModeTotals, 0, 0        # a2 = this mode's totals
    mov     (TR_MAX, a2), d0
    cmp     d0, d3
    bls     pfe_tmax
    mov     d3, (TR_MAX, a2)
pfe_tmax:
    mov     (PF_FRAME_PX), d0
    clr     d1
    mov     d1, (PF_FRAME_PX)
    mov     (PF_WIN_PX), d1
    add     d0, d1
    mov     d1, (PF_WIN_PX)
    mov     (TR_PX, a2), d1
    add     d0, d1
    mov     d1, (TR_PX, a2)
    mov     (PF_ASKED), d0
    mov     (PF_WIN_ASKED), d1
    add     d0, d1
    mov     d1, (PF_WIN_ASKED)
    mov     (PF_SINCE_REP), d0      # a full repaint now and then, whatever the sentinels say
    inc     d0
    mov     d0, (PF_SINCE_REP)
    cmp     REPAINT_FRAMES, d0
    bcs     pfe_rep
    mov     (PF_DAMAGE), d0
    or      PFD_PERIODIC, d0
    mov     d0, (PF_DAMAGE)
pfe_rep:
    mov     (PF_POSTLOAD), d0       # after a part's load: a full repaint 5 and 30 frames on
    cmp     0, d0
    beq     pfe_win
    add     -1, d0
    mov     d0, (PF_POSTLOAD)
    beq     pfe_pl
    cmp     POSTLOAD_FRAMES - 5, d0
    bne     pfe_win
pfe_pl:
    mov     (PF_DAMAGE), d0
    or      PFD_LOAD, d0
    mov     d0, (PF_DAMAGE)
pfe_win:
    mov     (PF_T_LAST), d0         # the stamp PerfPhase just took
    mov     (PF_WIN_T0), d1
    sub     d1, d0
    cmp     WINDOW_COUNTS, d0
    bcs     pfe_ret
    call    PerfWindowEnd, 0, 0
pfe_ret:
    ret     [d2,d3,a2,a3], 0x20

# PerfWindowEnd: the window ends (a second has passed, or the game is quitting): its figures into
# PF_SHOW, its sums into the game's, a new window, and the overlay redrawn.
PerfWindowEnd:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (PF_WIN_FRAMES), d2     # d2 = frames
    cmp     0, d2
    beq     pwe_ret
    mov     (PF_T_LAST), d0
    mov     (PF_WIN_T0), d1
    mov     d0, (PF_WIN_T0)
    sub     d1, d0
    lsr     1, d0                   # the window, us
    mov     (PF_WIN + 4 * PH_LOAD), d1
    sub     d1, d0
    mov     (PF_WIN + 4 * PH_PAUSE), d1
    sub     d1, d0                  # ... less loads and pauses: the frames' time
    bge     pwe_run
    clr     d0
pwe_run:
    mov     d0, (0x10, sp)          # run us
    call    ModeTotals, 0, 0
    mov     a2, (0x1C, sp)          # this mode's totals
    mov     (TR_FRAMES, a2), d1
    add     d2, d1
    mov     d1, (TR_FRAMES, a2)
    mov     (TR_WINDOWS, a2), d1
    inc     d1
    mov     d1, (TR_WINDOWS, a2)
    mov     (PF_MODE), d1
    mov     d1, (PF_SHOW + PS_MODE)
    mov     (0x10, sp), d0          # frames per second x 10 = frames * 1e6 / (run us / 10)
    mov     10, d1
    call    Div, 0, 0
    mov     d0, d1
    mov     d2, d0
    mov     1000000, d3
    mul     d3, d0
    call    Div, 0, 0
    mov     d0, (PF_SHOW + PS_FPS)
    mov     (0x10, sp), d0          # the game's run time, ms
    mov     1000, d1
    call    Div, 0, 0
    mov     (0x1C, sp), a2
    mov     (TR_RUN, a2), d1
    add     d0, d1
    mov     d1, (TR_RUN, a2)
    mov     d2, d3                  # d3 = frames * 100: us -> ms x 10 per frame
    mov     100, d0
    mul     d0, d3
    clr     d0                      # the frame: the phases but LOAD and PAUSE
    mov     d0, (0x14, sp)
    mov     (0x1C, sp), a3          # TR_PH
    mov     PF_WIN, a2
    clr     d2                      # phase
pwe_ph:
    mov     (a2), d0
    mov     d0, (0x18, sp)          # this phase's us in the window
    cmp     PH_LOAD, d2
    bcc     pwe_tot
    mov     (0x14, sp), d1
    add     d0, d1
    mov     d1, (0x14, sp)
    mov     d3, d1                  # ms x 10 per frame
    call    Div, 0, 0
    bra     pwe_show
pwe_tot:
    mov     100, d1                 # LOAD, PAUSE: ms x 10 in the window
    call    Div, 0, 0
pwe_show:
    mov     d2, d1
    asl     2, d1
    mov     PF_SHOW + PS_PH, a0
    add     d1, a0
    mov     d0, (a0)
    mov     (0x18, sp), d0          # into the game's sum, ms (rounded)
    add     500, d0
    mov     1000, d1
    call    Div, 0, 0
    mov     (a3), d1
    add     d0, d1
    mov     d1, (a3)
    clr     d0
    mov     d0, (a2)
    add     4, a2
    add     4, a3
    inc     d2
    cmp     PH_COUNT, d2
    bne     pwe_ph
    mov     (0x14, sp), d0
    mov     d3, d1
    call    Div, 0, 0
    mov     d0, (PF_SHOW + PS_FRAME)
    mov     (PF_WIN_MAX), d0
    mov     100, d1
    call    Div, 0, 0
    mov     d0, (PF_SHOW + PS_MAX)
    mov     (PF_WIN_ASKED), d0
    mov     (0x1C, sp), a2
    mov     (TR_ASKED, a2), d1
    add     d0, d1
    mov     d1, (TR_ASKED, a2)
    mov     10, d1                  # ms x 10 per frame
    mul     d1, d0
    mov     (PF_WIN_FRAMES), d1
    call    Div, 0, 0
    mov     d0, (PF_SHOW + PS_ASKED)
    mov     (PF_WIN_PX), d0
    mov     (PF_WIN_FRAMES), d1
    call    Div, 0, 0
    mov     d0, (PF_SHOW + PS_PX)
    clr     d0
    mov     d0, (PF_WIN_FRAMES)
    mov     d0, (PF_WIN_MAX)
    mov     d0, (PF_WIN_PX)
    mov     d0, (PF_WIN_ASKED)
    mov     1, d0
    mov     d0, (PF_OVL_DUE)        # the new figures at the next blit
pwe_ret:
    ret     [d2,d3,a2,a3], 0x30

# PerfSentinels: do the sentinel pixels of the LCD frame (sent_tab: the border's bands and strips, and a
# grid in the window) still hold what the game drew there? If one does not, something else drew on the LCD (the
# firmware), and the next blit repaints everything (PF_DAMAGE). The overlay never covers a border
# sentinel. Leaf; uses d0, d1, a0, a1 and saves d2, d3, a2.
PerfSentinels:
    movm    [d2,d3,a2], (sp)
    mov     (PF_LAST_SRC), d0       # nothing shown yet
    cmp     0, d0
    beq     psn_ret
    mov     (PF_DAMAGE), d0         # already asked for
    cmp     0, d0
    bne     psn_ret
    mov     sent_tab, a2
    mov     SENT_COUNT, d3
psn_one:
    mov     (a2), a0                # the LCD pixel
    movhu   (a0), d2
    mov     (4, a2), d0             # the window's pixel offset, or -1 for the border (black)
    cmp     -1, d0
    beq     psn_black
    mov     SHADOW, a1
    movbu   (d0, a1), d0
    and     15, d0
    asl     1, d0
    mov     PF_PAL, a1
    movhu   (d0, a1), d1
    bra     psn_cmp
psn_black:
    clr     d1
psn_cmp:
    cmp     d1, d2
    bne     psn_bad
    add     8, a2
    add     -1, d3
    bne     psn_one
psn_ret:
    ret     [d2,d3,a2], 0xC
psn_bad:
    mov     (PF_DAMAGE), d0
    or      PFD_SENTINEL, d0
    mov     d0, (PF_DAMAGE)
    mov     (PF_SENT_BAD), d0
    inc     d0
    mov     d0, (PF_SENT_BAD)
    bra     psn_ret

# ModeTotals -> a2 = the totals record of the blit mode in use (PF_TOTS). Leaf; uses d0.
ModeTotals:
    mov     PF_TOTS, a2
    mov     (PF_MODE), d0
    cmp     0, d0
    beq     mt_ret
    add     TR_LEN, a2
mt_ret:
    rets

# =================================================================================
# PerfInput: called from ReadInput every frame (not while the help screen runs, which turns its pages
# with PAGE UP and PAGE DOWN). On a press: PAGE UP turns the overlay on and off; PAGE DOWN switches the
# blit mode (PF_MODE), after closing the window, so that each mode's figures stay its own.
PerfInput:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (FWV_PANEL), a0
    movbu   (BTN_PAGE_OFS, a0), d2  # d2 = the PAGE buttons now
    mov     (PF_STATE), d3
    btst    BTN_PAGEUP_BIT, d2
    beq     pip_up_rel
    btst    2, d3                   # PAGE UP: held since an earlier frame?
    bne     pip_dn
    or      2, d3
    xor     1, d3                   # the overlay on / off
    btst    1, d3
    bne     pip_on
    mov     (PF_DAMAGE), d0         # off: the next blit paints the border black again
    or      PFD_OVERLAY, d0
    mov     d0, (PF_DAMAGE)
    bra     pip_dn
pip_on:
    mov     1, d0
    mov     d0, (PF_OVL_DUE)
    bra     pip_dn
pip_up_rel:
    and     0xFFFFFFFD, d3
pip_dn:
    btst    BTN_PAGEDN_BIT, d2
    beq     pip_dn_rel
    btst    4, d3                   # PAGE DOWN: held since an earlier frame?
    bne     pip_ret
    or      4, d3
    mov     d3, (PF_STATE)
    call    PerfWindowEnd, 0, 0     # the window so far belongs to the mode it ran in
    mov     (PF_MODE), d0
    xor     1, d0
    mov     d0, (PF_MODE)
    mov     (PF_SWITCHES), d0
    inc     d0
    mov     d0, (PF_SWITCHES)
    mov     (PF_DAMAGE), d0         # either way, start from a full repaint
    or      PFD_MODE, d0
    mov     d0, (PF_DAMAGE)
    mov     1, d0
    mov     d0, (PF_OVL_DUE)
    bra     pip_ret
pip_dn_rel:
    and     0xFFFFFFFB, d3
pip_ret:
    mov     d3, (PF_STATE)
    ret     [d2,d3,a2,a3], 0x20

# PerfOverlay: if the overlay is on, write the blit mode and the last window's figures into the left
# border (x 8-159, y 24-191), white on black: frames per second, then ms per frame and per phase. The
# time it takes is phase PAUSE, not part of any frame's (in the old mode it is drawn after every blit,
# whose border fill wipes it).
PerfOverlay:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    clr     d0
    mov     d0, (PF_OVL_DUE)
    mov     (PF_STATE), d0
    btst    1, d0
    beq     pov_ret
    mov     PH_PAUSE, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
    mov     ov_new, a0              # the mode
    mov     (PF_MODE), d0
    cmp     0, d0
    beq     pov_mode
    mov     ov_old, a0
pov_mode:
    mov     8, d0
    mov     24, d1
    call    LcdText, 0, 0
    mov     ovl_tab, a2
    mov     40, d2                  # y
pov_line:
    mov     (a2), a1                # the label (0 ends the table)
    cmp     0, a1
    beq     pov_done
    mov     PF_TEXT, a0
    call    StrPut, 0, 0
    mov     (4, a2), a1             # the value's address
    mov     (a1), d0
    mov     (8, a2), d1             # its format
    call    FmtNum, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     PF_TEXT, a0
    mov     8, d0
    mov     d2, d1
    call    LcdText, 0, 0
    add     12, a2
    add     12, d2
    bra     pov_line
pov_done:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
pov_ret:
    ret     [d2,d3,a2,a3], 0x30

# LcdText(a0 = text, d0 = x (even), d1 = y): 8x8 glyphs of AW_FONT straight into the LCD frame, white on
# black, two pixels per 32-bit store.
LcdText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    mov     FB_STRIDE, d2
    mul     d1, d2
    asl     1, d0
    add     d0, d2
    mov     FB, a3
    add     d2, a3                  # the first glyph's top-left pixel
lt_char:
    movbu   (a2), d0
    cmp     0, d0
    beq     lt_done
    inc     a2
    add     -0x20, d0
    cmp     0x60, d0
    bcs     lt_glyph
    clr     d0                      # outside the font: a space
lt_glyph:
    asl     3, d0
    mov     AW_FONT, a0
    add     d0, a0
    mov     a3, a1
    mov     8, d3
lt_row:
    movbu   (a0), d2                # 8 pixels, the leftmost in bit 7
    inc     a0
    clr     d0
    btst    0x80, d2
    beq     lt_b6
    or      0xFFFF, d0
lt_b6:
    btst    0x40, d2
    beq     lt_w0
    or      0xFFFF0000, d0
lt_w0:
    mov     d0, (a1)
    clr     d0
    btst    0x20, d2
    beq     lt_b4
    or      0xFFFF, d0
lt_b4:
    btst    0x10, d2
    beq     lt_w1
    or      0xFFFF0000, d0
lt_w1:
    mov     d0, (4, a1)
    clr     d0
    btst    0x08, d2
    beq     lt_b2
    or      0xFFFF, d0
lt_b2:
    btst    0x04, d2
    beq     lt_w2
    or      0xFFFF0000, d0
lt_w2:
    mov     d0, (8, a1)
    clr     d0
    btst    0x02, d2
    beq     lt_b0
    or      0xFFFF, d0
lt_b0:
    btst    0x01, d2
    beq     lt_w3
    or      0xFFFF0000, d0
lt_w3:
    mov     d0, (12, a1)
    add     FB_STRIDE, a1
    add     -1, d3
    bne     lt_row
    add     16, a3
    bra     lt_char
lt_done:
    ret     [d2,d3,a2,a3], 0x20

# =================================================================================
# Text. StrPut(a1 = NUL-terminated text, a0 = where) -> a0 past it (no NUL written). Leaf; uses d0.
StrPut:
    movbu   (a1), d0
    cmp     0, d0
    beq     spu_ret
    movbu   d0, (a0)
    inc     a0
    inc     a1
    bra     StrPut
spu_ret:
    rets

# FmtNum(d0 = value, d1 = width | decimals << 8, a0 = where) -> a0 past it: the unsigned value in decimal,
# right-aligned in width characters (wider if it needs more), with one decimal digit when decimals is 1
# (the value is then in tenths). No NUL.
FmtNum:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, a2
    mov     d1, d3
    mov     d0, (0x10, sp)          # what is left of the value
    mov     PF_DIGITS + 31, a3      # the characters, backwards
    clr     d2                      # characters made
fn_dig:
    mov     (0x10, sp), d0
    mov     10, d1
    call    Div, 0, 0
    mov     d0, (0x10, sp)
    add     0x30, d1
    add     -1, a3
    movbu   d1, (a3)
    inc     d2
    mov     d3, d0
    lsr     8, d0
    cmp     d2, d0                  # that many decimals made: the point
    bne     fn_more
    add     -1, a3
    mov     0x2E, d1
    movbu   d1, (a3)
    inc     d2
fn_more:
    mov     (0x10, sp), d0          # on while digits are left ...
    cmp     0, d0
    bne     fn_dig
    mov     d3, d0                  # ... and, with a decimal, until "0.d"
    lsr     8, d0
    cmp     0, d0
    beq     fn_width
    cmp     3, d2
    bcs     fn_dig
fn_width:
    mov     d3, d1                  # pad to the width
    and     0xFF, d1
    sub     d2, d1
    ble     fn_copy
    mov     0x20, d0
fn_pad:
    movbu   d0, (a2)
    inc     a2
    add     -1, d1
    bne     fn_pad
fn_copy:
    movbu   (a3), d0
    movbu   d0, (a2)
    inc     a2
    inc     a3
    add     -1, d2
    bne     fn_copy
    mov     a2, a0
    ret     [d2,d3,a2,a3], 0x30

# FmtHex(d0 = value, d1 = digits, a0 = where) -> a0 past it: upper-case hex, the low d1 digits. Leaf;
# uses d0, d1, a0, a1.
FmtHex:
    mov     d1, a1
    add     a1, a1
    add     a1, a1                  # 4 * digits: the first one's shift + 4
    mov     a1, d1
fh_dig:
    add     -4, d1
    mov     d0, a1
    lsr     d1, d0
    and     15, d0
    cmp     10, d0
    bcs     fh_dec
    add     7, d0
fh_dec:
    add     0x30, d0
    movbu   d0, (a0)
    inc     a0
    mov     a1, d0
    cmp     0, d1
    bne     fh_dig
    rets

# =================================================================================
# PerfRegs: what the firmware set the bus controller, the cache and timer 4 to, and the program build
# (read only). Leaf.
PerfRegs:
    mov     0x32000020, a0          # MEMCTR0-7, 16 bits each
    mov     PF_REGS, a1
    mov     8, d1
prg_mem:
    movhu   (a0), d0
    mov     d0, (a1)
    add     2, a0
    add     4, a1
    add     -1, d1
    bne     prg_mem
    movhu   (0x32000040), d0
    mov     d0, (PF_REGS + 0x20)
    movhu   (0x32000042), d0
    mov     d0, (PF_REGS + 0x24)
    mov     0x20000070, a0          # CHCTR
    mov     (a0), d0
    mov     d0, (PF_REGS + 0x28)
    movbu   (TM4MD), d0
    mov     d0, (PF_REGS + 0x2C)
    movhu   (TM4BR), d0
    mov     d0, (PF_REGS + 0x30)
    mov     (FWV_BUILD), d0
    mov     d0, (PF_REGS + 0x34)
    rets

# PerfBench: before the game starts, how long each kind of access takes on this instrument. Each test
# (bench_tab: kernel, target, turns of 8 accesses, accesses) runs three times; the shortest counts, as ns
# per access x 10 in PF_BENCH. The LCD tests write black into the top border rows, which the game paints
# black anyway; the RAM tests use the help buffer, free until the game starts; the uncached test only
# reads. The tick interrupt and the firmware's other interrupts run meanwhile: the shortest of three
# keeps them out.
PerfBench:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     bench_tab, a2
    clr     d2                      # the test
pbn_test:
    mov     -1, d0
    mov     d0, (0x14, sp)          # the shortest so far
    mov     3, d3
pbn_run:
    call    Stamp, 0, 0
    mov     d0, (0x10, sp)
    mov     (4, a2), a0             # target
    mov     (8, a2), d1             # turns
    clr     d0
    mov     (a2), a1                # kernel (a leaf)
    calls   (a1)
    call    Stamp, 0, 0
    mov     (0x10, sp), d1
    sub     d1, d0
    mov     (0x14, sp), d1
    cmp     d1, d0
    bcc     pbn_longer
    mov     d0, (0x14, sp)
pbn_longer:
    add     -1, d3
    bne     pbn_run
    mov     (0x14, sp), d0          # ns x 10 per access: counts * 4998 / accesses
    mov     4998, d1
    mul     d1, d0
    mov     (12, a2), d1
    call    Div, 0, 0
    mov     d2, d1
    asl     2, d1
    mov     PF_BENCH, a0
    add     d1, a0
    mov     d0, (a0)
    add     16, a2
    inc     d2
    cmp     BN_COUNT, d2
    bne     pbn_test
    ret     [d2,d3,a2,a3], 0x30

# The kernels: (a0 = target, d1 = turns, d0 = 0), 8 accesses a turn. Entered with `calls`: rets.
bk_alu:
    add     1, d0
    add     1, d0
    add     1, d0
    add     1, d0
    add     1, d0
    add     1, d0
    add     1, d0
    add     1, d0
    add     -1, d1
    bne     bk_alu
    rets
bk_w16:
    movhu   d0, (0, a0)
    movhu   d0, (2, a0)
    movhu   d0, (4, a0)
    movhu   d0, (6, a0)
    movhu   d0, (8, a0)
    movhu   d0, (10, a0)
    movhu   d0, (12, a0)
    movhu   d0, (14, a0)
    add     16, a0
    add     -1, d1
    bne     bk_w16
    rets
bk_w32:
    mov     d0, (0, a0)
    mov     d0, (4, a0)
    mov     d0, (8, a0)
    mov     d0, (12, a0)
    mov     d0, (16, a0)
    mov     d0, (20, a0)
    mov     d0, (24, a0)
    mov     d0, (28, a0)
    add     32, a0
    add     -1, d1
    bne     bk_w32
    rets
bk_r16:
    movhu   (0, a0), d0
    movhu   (2, a0), d0
    movhu   (4, a0), d0
    movhu   (6, a0), d0
    movhu   (8, a0), d0
    movhu   (10, a0), d0
    movhu   (12, a0), d0
    movhu   (14, a0), d0
    add     16, a0
    add     -1, d1
    bne     bk_r16
    rets
bk_w8:
    movbu   d0, (0, a0)
    movbu   d0, (1, a0)
    movbu   d0, (2, a0)
    movbu   d0, (3, a0)
    movbu   d0, (4, a0)
    movbu   d0, (5, a0)
    movbu   d0, (6, a0)
    movbu   d0, (7, a0)
    add     8, a0
    add     -1, d1
    bne     bk_w8
    rets
bk_r8:
    movbu   (0, a0), d0
    movbu   (1, a0), d0
    movbu   (2, a0), d0
    movbu   (3, a0), d0
    movbu   (4, a0), d0
    movbu   (5, a0), d0
    movbu   (6, a0), d0
    movbu   (7, a0), d0
    add     8, a0
    add     -1, d1
    bne     bk_r8
    rets
bk_r32:
    mov     (0, a0), d0
    mov     (4, a0), d0
    mov     (8, a0), d0
    mov     (12, a0), d0
    mov     (16, a0), d0
    mov     (20, a0), d0
    mov     (24, a0), d0
    mov     (28, a0), d0
    add     32, a0
    add     -1, d1
    bne     bk_r32
    rets

# =================================================================================
# PerfPageBuild: the help screen's fourth page (help.s), in PF_ITEMS (the items) and PF_LINES (their
# text), one line per page_tab entry, 40 columns from x 0, 9 pixels apart: the last window and the whole game side by side,
# the benchmark, the bus controller.
PerfPageBuild:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     PF_ITEMS, a2            # the next item
    mov     PF_LINES, a3            # the next line's text
    mov     page_tab, d0
    mov     d0, (0x10, sp)          # the next page_tab entry
    mov     2, d3                   # y
ppb_line:
    mov     (0x10, sp), a1
    mov     (a1), d0                # kind (0 ends)
    cmp     0, d0
    beq     ppb_end
    mov     a3, a0                  # the line: its label, then what its kind adds
    mov     (8, a1), a1
    call    StrPut, 0, 0
    mov     (0x10, sp), a1
    mov     (a1), d0
    call    PageValues, 0, 0
    clr     d0
    movbu   d0, (a0)
    clr     d0                      # the item: x 0 (40 columns), y, colour, text
    movhu   d0, (a2)
    movhu   d3, (2, a2)
    mov     (0x10, sp), a1
    mov     (4, a1), d0
    movhu   d0, (4, a2)
    clr     d0
    movhu   d0, (6, a2)
    mov     a3, (8, a2)
    add     12, a2
    add     PF_LINE_LEN, a3
    mov     (0x10, sp), d0
    add     16, d0
    mov     d0, (0x10, sp)
    add     9, d3
    bra     ppb_line
ppb_end:
    mov     0xFFFF, d0              # the end of the page
    movhu   d0, (a2)
    clr     d0
    movhu   d0, (2, a2)
    ret     [d2,d3,a2,a3], 0x30

# PageValues(d0 = kind, a1 = its page_tab entry, a0 = where) -> a0 past what it wrote.
#   1 nothing (a heading);  2 a figure: the last window's (PF_SHOW + arg), then the whole game's in the new
#   and in the old blit mode;  3 the program build and the blit mode in use;  4 up to four benchmark
#   results (arg: BN_ indices, one per byte, 0xFF ends);  5 four registers from PF_REGS index arg, in hex;
#   6 loads, pauses, repaints;  7 frames, per blit mode.
PageValues:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a1, a2
    cmp     2, d0
    beq     pv_fig
    cmp     3, d0
    beq     pv_build
    cmp     4, d0
    beq     pv_bench
    cmp     5, d0
    beq     pv_regs
    cmp     6, d0
    beq     pv_misc
    cmp     7, d0
    beq     pv_frames
    bra     pv_ret
pv_fig:
    mov     (12, a2), d2
    mov     PF_SHOW, a1
    add     d2, a1
    mov     (a1), d0
    mov     0x109, d1
    cmp     PS_PX, d2
    bne     pv_f1
    mov     0x009, d1
pv_f1:
    call    FmtNum, 0, 0
    clr     d3                      # the new mode, then the old one
pv_f2:
    mov     a0, a3
    mov     d2, d0
    mov     d3, d1
    call    GameFigure, 0, 0        # d0 = the figure over the whole game in mode d3, d1 = its format
    mov     a3, a0
    call    FmtNum, 0, 0
    inc     d3
    cmp     2, d3
    bne     pv_f2
    bra     pv_ret
pv_build:
    mov     (PF_REGS + 0x34), d0
    mov     0x004, d1
    call    FmtNum, 0, 0
    mov     spg_now, a1
    call    StrPut, 0, 0
    mov     spg_new, a1
    mov     (PF_MODE), d0
    cmp     0, d0
    beq     pv_bmode
    mov     spg_old, a1
pv_bmode:
    call    StrPut, 0, 0
    bra     pv_ret
pv_frames:
    mov     0x20, d0                # no window figure: 9 spaces (bytes: a0 need not be aligned)
    mov     9, d1
pv_sp:
    movbu   d0, (a0)
    inc     a0
    add     -1, d1
    bne     pv_sp
    mov     (PF_TOTS + TR_FRAMES), d0
    mov     0x009, d1
    call    FmtNum, 0, 0
    mov     (PF_TOTS + TR_LEN + TR_FRAMES), d0
    mov     0x009, d1
    call    FmtNum, 0, 0
    bra     pv_ret
pv_bench:
    mov     (12, a2), d2
    mov     4, d3
pv_b1:
    mov     d2, d0
    and     0xFF, d0
    cmp     0xFF, d0
    beq     pv_ret
    asl     2, d0
    mov     PF_BENCH, a1
    add     d0, a1
    mov     (a1), d0
    add     5, d0                   # ns, rounded
    mov     a0, a3
    mov     10, d1
    call    Div, 0, 0
    mov     a3, a0
    mov     0x005, d1
    call    FmtNum, 0, 0
    lsr     8, d2
    add     -1, d3
    bne     pv_b1
    bra     pv_ret
pv_regs:
    mov     (12, a2), d2
    mov     4, d3
pv_r1:
    mov     0x20, d0
    movbu   d0, (a0)
    inc     a0
    mov     d2, d0
    asl     2, d0
    mov     PF_REGS, a1
    add     d0, a1
    mov     (a1), d0
    mov     4, d1
    call    FmtHex, 0, 0
    inc     d2
    add     -1, d3
    bne     pv_r1
    bra     pv_ret
pv_misc:
    mov     (PF_TOTS + TR_PH + 4 * PH_LOAD), d0
    mov     (PF_TOTS + TR_LEN + TR_PH + 4 * PH_LOAD), d1
    add     d1, d0
    mov     0x006, d1
    call    FmtNum, 0, 0
    mov     spg_pause, a1
    call    StrPut, 0, 0
    mov     (PF_TOTS + TR_PH + 4 * PH_PAUSE), d0
    mov     (PF_TOTS + TR_LEN + TR_PH + 4 * PH_PAUSE), d1
    add     d1, d0
    mov     0x006, d1
    call    FmtNum, 0, 0
    mov     spg_repaint, a1
    call    StrPut, 0, 0
    mov     (PF_REPAINTS), d0
    mov     0x004, d1
    call    FmtNum, 0, 0
pv_ret:
    ret     [d2,d3,a2,a3], 0x30

# GameFigure(d0 = PS_ offset, d1 = blit mode) -> d0 = that figure over the whole game in that mode (the
# windows closed so far), d1 = a FmtNum format for it.
GameFigure:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     PF_TOTS, a2
    cmp     0, d1
    beq     gf_rec
    add     TR_LEN, a2
gf_rec:
    mov     (TR_FRAMES, a2), d3
    cmp     PS_FPS, d2
    bne     gf_frame
    mov     d3, d0                  # frames x 10 per s: frames * 10000 / run ms
    mov     10000, d1
    mul     d1, d0
    mov     (TR_RUN, a2), d1
    call    Div, 0, 0
    bra     gf_tenths
gf_frame:
    cmp     PS_FRAME, d2
    bne     gf_max
    mov     a2, a0                  # the phases but LOAD and PAUSE, ms
    clr     d0
    mov     PH_LOAD, d1
gf_sum:
    mov     (a0), a1
    add     a1, d0
    add     4, a0
    add     -1, d1
    bne     gf_sum
    bra     gf_per
gf_max:
    cmp     PS_MAX, d2
    bne     gf_px
    mov     (TR_MAX, a2), d0
    mov     100, d1
    call    Div, 0, 0
    bra     gf_tenths
gf_px:
    cmp     PS_PX, d2
    bne     gf_asked
    mov     (TR_PX, a2), d0
    mov     d3, d1
    call    Div, 0, 0
    mov     0x009, d1
    bra     gf_ret
gf_asked:
    cmp     PS_ASKED, d2
    bne     gf_ph
    mov     (TR_ASKED, a2), d0
    bra     gf_per
gf_ph:
    add     -PS_PH, d2              # PS_PH + 4 * phase: that phase over the game, ms
    mov     a2, a0
    add     d2, a0
    mov     (a0), d0
    lsr     2, d2
    cmp     PH_LOAD, d2
    bcc     gf_whole
gf_per:
    mov     10, d1                  # ms x 10 per frame
    mul     d1, d0
    mov     d3, d1
    call    Div, 0, 0
    bra     gf_tenths
gf_whole:
    mov     10, d1                  # LOAD, PAUSE: ms over the game, x 10
    mul     d1, d0
gf_tenths:
    mov     0x109, d1
gf_ret:
    ret     [d2,d3,a2,a3], 0x20

# =================================================================================
# ReportBuild -> d0 = the length of AWPERF.TXT's text, built in REPORT_BUF: the speed page's lines, the
# figures per part, the counters, the benchmark and the registers in full (cnv_main.s writes it to the
# SD card at quit). Lines end in CR LF.
ReportBuild:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    call    PerfPageBuild, 0, 0
    mov     REPORT_BUF, a0
    mov     rp_head, a1
    call    StrPut, 0, 0
    mov     PF_ITEMS, a2            # the speed page, line by line
rb_page:
    movhu   (a2), d0
    cmp     0xFFFF, d0
    beq     rb_parts
    mov     (8, a2), a1
    call    StrPut, 0, 0
    call    PutCrLf, 0, 0
    add     12, a2
    bra     rb_page
rb_parts:
    mov     rp_parts, a1
    call    StrPut, 0, 0
    mov     PF_PART, a2
    clr     d2                      # 0..9: the parts in the new blit mode, 10..19 in the old one
rb_part:
    mov     (PR_FRAMES, a2), d3
    cmp     0, d3
    beq     rb_pnext
    mov     spg_new, a1
    mov     d2, d0
    cmp     10, d0
    bcs     rb_tag
    mov     spg_old, a1
    add     -10, d0
rb_tag:
    mov     d0, (0x18, sp)
    call    StrPut, 0, 0
    mov     rp_part, a1
    call    StrPut, 0, 0
    mov     (0x18, sp), d0
    add     PART_FIRST, d0
    mov     4, d1
    call    FmtHex, 0, 0
    mov     d3, d0
    mov     0x008, d1
    call    FmtNum, 0, 0
    mov     d3, d0                  # a3 = frames * 100: us -> ms x 10 per frame
    mov     100, d1
    mul     d1, d0
    mov     d0, a3
    mov     a2, a1                  # the frame: the phases but LOAD and PAUSE
    add     PR_SUM, a1
    clr     d0
    mov     PH_LOAD, d1
rb_fsum:
    mov     (a1), d3
    add     d3, d0
    add     4, a1
    add     -1, d1
    bne     rb_fsum
    call    PutPerFrame, 0, 0
    mov     a2, a1
    add     PR_SUM, a1
    mov     a1, (0x10, sp)
    mov     PH_LOAD, d3
rb_ph:
    mov     (0x10, sp), a1
    mov     (a1), d0
    add     4, a1
    mov     a1, (0x10, sp)
    call    PutPerFrame, 0, 0
    add     -1, d3
    bne     rb_ph
    mov     (PR_MAX, a2), d0        # the longest frame, ms x 10
    mov     a0, (0x14, sp)
    mov     100, d1
    call    Div, 0, 0
    mov     (0x14, sp), a0
    mov     0x109, d1
    call    FmtNum, 0, 0
    call    PutCrLf, 0, 0
rb_pnext:
    add     PR_LEN, a2
    inc     d2
    cmp     20, d2
    bne     rb_part
    mov     rp_count, a1            # the counters: PF_REPAINTS, PF_SENT_BAD, PF_BLITS, PF_SKIPS
    call    StrPut, 0, 0
    mov     PF_REPAINTS, a2
    mov     4, d3
rb_cnt:
    mov     (a2), d0
    mov     0x008, d1
    call    FmtNum, 0, 0
    add     4, a2
    add     -1, d3
    bne     rb_cnt
    mov     (PF_PAIR_N), d0
    mov     0x008, d1
    call    FmtNum, 0, 0
    mov     (PF_SWITCHES), d0
    mov     0x008, d1
    call    FmtNum, 0, 0
    mov     (PF_TOTS + TR_WINDOWS), d0
    mov     0x008, d1
    call    FmtNum, 0, 0
    mov     (PF_TOTS + TR_LEN + TR_WINDOWS), d0
    mov     0x008, d1
    call    FmtNum, 0, 0
    mov     (PF_TOTS + TR_RUN), d0
    mov     0x00A, d1
    call    FmtNum, 0, 0
    mov     (PF_TOTS + TR_LEN + TR_RUN), d0
    mov     0x00A, d1
    call    FmtNum, 0, 0
    call    PutCrLf, 0, 0
    mov     rp_bench, a1            # the benchmark, ns x 10
    call    StrPut, 0, 0
    mov     PF_BENCH, a2
    mov     BN_COUNT, d3
rb_bn:
    mov     (a2), d0
    mov     0x108, d1
    call    FmtNum, 0, 0
    add     4, a2
    add     -1, d3
    bne     rb_bn
    call    PutCrLf, 0, 0
    mov     rp_regs, a1             # the registers, in hex
    call    StrPut, 0, 0
    mov     PF_REGS, a2
    mov     RG_COUNT, d3
rb_rg:
    mov     0x20, d0
    movbu   d0, (a0)
    inc     a0
    mov     (a2), d0
    mov     8, d1
    call    FmtHex, 0, 0
    add     4, a2
    add     -1, d3
    bne     rb_rg
    call    PutCrLf, 0, 0
    mov     a0, d0
    mov     REPORT_BUF, d1
    sub     d1, d0
    ret     [d2,d3,a2,a3], 0x30

# PutPerFrame(d0 = us, a3 = frames * 100, a0 = where) -> a0 past it: " " and ms x 10 per frame, 8 wide.
PutPerFrame:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    mov     a3, d1
    call    Div, 0, 0
    mov     a2, a0
    mov     0x108, d1
    call    FmtNum, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# PutCrLf(a0 = where) -> a0 past CR LF. Leaf.
PutCrLf:
    mov     0x0D, d0
    movbu   d0, (a0)
    mov     0x0A, d0
    movbu   d0, (1, a0)
    add     2, a0
    rets

# =================================================================================
    .align  4
# The sentinels: the LCD pixel, and its offset in the window (SHADOW), or -1 for the black border. The
# top and bottom bands at x 2, 160, 320, 480, 637 (y 10 and 236, below the load bar's rows 228-233); the
# side strips at x 2, 158 (left of and right of the overlay's x 8-151) and 482, 637, every 30 rows from
# y 24; and a 3 x 3 grid in the window. (A box the firmware drew across the screen at y 114-176,
# x 40-606, when the intro loaded the lake in MAME, missed the first, coarser grid: probes/cnv/README.md.)
sent_tab:
    .long   FB + 10*FB_STRIDE + 2*2, -1
    .long   FB + 10*FB_STRIDE + 160*2, -1
    .long   FB + 10*FB_STRIDE + 320*2, -1
    .long   FB + 10*FB_STRIDE + 480*2, -1
    .long   FB + 10*FB_STRIDE + 637*2, -1
    .long   FB + 236*FB_STRIDE + 2*2, -1
    .long   FB + 236*FB_STRIDE + 160*2, -1
    .long   FB + 236*FB_STRIDE + 320*2, -1
    .long   FB + 236*FB_STRIDE + 480*2, -1
    .long   FB + 236*FB_STRIDE + 637*2, -1
    .long   FB + 24*FB_STRIDE + 2*2, -1
    .long   FB + 24*FB_STRIDE + 158*2, -1
    .long   FB + 24*FB_STRIDE + 482*2, -1
    .long   FB + 24*FB_STRIDE + 637*2, -1
    .long   FB + 54*FB_STRIDE + 2*2, -1
    .long   FB + 54*FB_STRIDE + 158*2, -1
    .long   FB + 54*FB_STRIDE + 482*2, -1
    .long   FB + 54*FB_STRIDE + 637*2, -1
    .long   FB + 84*FB_STRIDE + 2*2, -1
    .long   FB + 84*FB_STRIDE + 158*2, -1
    .long   FB + 84*FB_STRIDE + 482*2, -1
    .long   FB + 84*FB_STRIDE + 637*2, -1
    .long   FB + 114*FB_STRIDE + 2*2, -1
    .long   FB + 114*FB_STRIDE + 158*2, -1
    .long   FB + 114*FB_STRIDE + 482*2, -1
    .long   FB + 114*FB_STRIDE + 637*2, -1
    .long   FB + 144*FB_STRIDE + 2*2, -1
    .long   FB + 144*FB_STRIDE + 158*2, -1
    .long   FB + 144*FB_STRIDE + 482*2, -1
    .long   FB + 144*FB_STRIDE + 637*2, -1
    .long   FB + 174*FB_STRIDE + 2*2, -1
    .long   FB + 174*FB_STRIDE + 158*2, -1
    .long   FB + 174*FB_STRIDE + 482*2, -1
    .long   FB + 174*FB_STRIDE + 637*2, -1
    .long   FB + 204*FB_STRIDE + 2*2, -1
    .long   FB + 204*FB_STRIDE + 158*2, -1
    .long   FB + 204*FB_STRIDE + 482*2, -1
    .long   FB + 204*FB_STRIDE + 637*2, -1
    .long   FB + 60*FB_STRIDE + 200*2, (60-AW_Y0)*AW_W + 200-AW_X0
    .long   FB + 60*FB_STRIDE + 320*2, (60-AW_Y0)*AW_W + 320-AW_X0
    .long   FB + 60*FB_STRIDE + 440*2, (60-AW_Y0)*AW_W + 440-AW_X0
    .long   FB + 120*FB_STRIDE + 200*2, (120-AW_Y0)*AW_W + 200-AW_X0
    .long   FB + 120*FB_STRIDE + 320*2, (120-AW_Y0)*AW_W + 320-AW_X0
    .long   FB + 120*FB_STRIDE + 440*2, (120-AW_Y0)*AW_W + 440-AW_X0
    .long   FB + 180*FB_STRIDE + 200*2, (180-AW_Y0)*AW_W + 200-AW_X0
    .long   FB + 180*FB_STRIDE + 320*2, (180-AW_Y0)*AW_W + 320-AW_X0
    .long   FB + 180*FB_STRIDE + 440*2, (180-AW_Y0)*AW_W + 440-AW_X0

# The benchmark: kernel, target, turns of 8 accesses, accesses (in BN_ order).
bench_tab:
    .long   bk_alu, 0, 1024, 8192                       # BN_ALU
    .long   bk_w16, FB, 512, 4096                       # BN_LCD_W16: 8 KB of the top border rows
    .long   bk_w32, FB, 512, 4096                       # BN_LCD_W32: 16 KB
    .long   bk_r16, FB, 512, 4096                       # BN_LCD_R16
    .long   bk_w8, HELP_BUF, 8000, 64000                # BN_RAM_W8: the help buffer, free until the game starts
    .long   bk_w32, HELP_BUF, 2000, 16000               # BN_RAM_W32
    .long   bk_r8, HELP_BUF, 8000, 64000                # BN_RAM_R8
    .long   bk_r32, HELP_BUF, 2000, 16000               # BN_RAM_R32
    .long   bk_r32, HELP_BUF + 0x40000000, 2000, 16000  # BN_UNC_R32: its uncached view, read only

# The overlay's lines: label, the value's address, its FmtNum format.
ovl_tab:
    .long   ov_fps, PF_SHOW + PS_FPS, 0x106
    .long   ov_frame, PF_SHOW + PS_FRAME, 0x106
    .long   ov_max, PF_SHOW + PS_MAX, 0x106
    .long   ov_vm, PF_SHOW + PS_PH + 4 * PH_VM, 0x106
    .long   ov_draw, PF_SHOW + PS_PH + 4 * PH_DRAW, 0x106
    .long   ov_page, PF_SHOW + PS_PH + 4 * PH_PAGE, 0x106
    .long   ov_blit, PF_SHOW + PS_PH + 4 * PH_BLIT, 0x106
    .long   ov_bord, PF_SHOW + PS_PH + 4 * PH_BORD, 0x106
    .long   ov_wait, PF_SHOW + PS_PH + 4 * PH_WAIT, 0x106
    .long   ov_asked, PF_SHOW + PS_ASKED, 0x106
    .long   ov_load, PF_SHOW + PS_PH + 4 * PH_LOAD, 0x106
    .long   ov_px, PF_SHOW + PS_PX, 0x006
    .long   ov_rep, PF_REPAINTS, 0x006
    .long   0
ov_new:     .asciz  "NEW BLIT  PGDN:OLD"
ov_old:     .asciz  "OLD BLIT  PGDN:NEW"
ov_fps:     .asciz  "FPS     "
ov_frame:   .asciz  "FRAME   "
ov_max:     .asciz  "LONGEST "
ov_vm:      .asciz  " VM     "
ov_draw:    .asciz  " POLYGON"
ov_page:    .asciz  " PAGE OP"
ov_blit:    .asciz  " BLIT   "
ov_bord:    .asciz  " BORDER "
ov_wait:    .asciz  " YIELD  "
ov_asked:   .asciz  "ASKED   "
ov_load:    .asciz  "LOAD/S  "
ov_px:      .asciz  "PIXELS  "
ov_rep:     .asciz  "REPAINT "
    .align  4

# The help page's lines: kind (PageValues), colour (help_palette: 1 white, 2 cyan, 3 yellow), label,
# argument.
page_tab:
    .long   3, 2, spg_title, 0
    .long   1, 2, spg_head, 0
    .long   7, 1, spg_frames, 0
    .long   2, 1, spg_fps, PS_FPS
    .long   2, 1, spg_frame, PS_FRAME
    .long   2, 1, spg_max, PS_MAX
    .long   2, 3, spg_vm, PS_PH + 4 * PH_VM
    .long   2, 3, spg_draw, PS_PH + 4 * PH_DRAW
    .long   2, 3, spg_page, PS_PH + 4 * PH_PAGE
    .long   2, 3, spg_blit, PS_PH + 4 * PH_BLIT
    .long   2, 3, spg_bord, PS_PH + 4 * PH_BORD
    .long   2, 3, spg_wait, PS_PH + 4 * PH_WAIT
    .long   2, 1, spg_asked, PS_ASKED
    .long   2, 1, spg_px, PS_PX
    .long   6, 1, spg_load, 0
    .long   1, 2, spg_benchh, 0
    .long   4, 1, spg_bench1, BN_ALU | BN_LCD_W16 << 8 | BN_LCD_W32 << 16 | BN_LCD_R16 << 24
    .long   4, 1, spg_bench2, BN_RAM_W8 | BN_RAM_W32 << 8 | BN_RAM_R8 << 16 | BN_RAM_R32 << 24
    .long   4, 1, spg_bench3, BN_UNC_R32 | 0xFFFFFF00
    .long   5, 1, spg_mem0, 0
    .long   5, 1, spg_mem4, 4
    .long   5, 1, spg_mem8, 8
    .long   0
spg_title:   .asciz  "SPEED  4/4  program "
spg_now:     .asciz  "  now: "
spg_new:     .asciz  "new blit"
spg_old:     .asciz  "old blit"
spg_head:    .asciz  "ms per frame  last 1 s new blit old blit"
spg_frames:  .asciz  "VM frames    "
spg_fps:     .asciz  "frames/s     "
spg_frame:   .asciz  "frame        "
spg_max:     .asciz  "longest      "
spg_vm:      .asciz  " VM          "
spg_draw:    .asciz  " polygons    "
spg_page:    .asciz  " page ops    "
spg_blit:    .asciz  " blit        "
spg_bord:    .asciz  " border      "
spg_wait:    .asciz  " yield       "
spg_asked:   .asciz  "yield asked  "
spg_px:      .asciz  "LCD pixels   "
spg_load:    .asciz  "load ms"
spg_pause:   .asciz  " pause"
spg_repaint: .asciz  " repaints"
spg_benchh:  .asciz  "ns per access  (PAGE DOWN: other blit)"
spg_bench1:  .asciz  "ALU, LCD w16 w32 r16"
spg_bench2:  .asciz  "RAM w8 w32 r8 r32   "
spg_bench3:  .asciz  "RAM uncached r32    "
spg_mem0:    .asciz  "bus 20-26"
spg_mem4:    .asciz  "bus 28-2E"
spg_mem8:    .asciz  "40 42 CHCTR TM4MD"
rp_head:
    .ascii  "Another World for the KN7000 (KN7APP.BIN): speed report, AWPERFn.TXT"
    .byte   13, 10
    .ascii  "Times from the KN7000's timer 4 and its millisecond counter (README-CNV.md, Speed)."
    .byte   13, 10, 13, 10, 0
rp_parts:
    .byte   13, 10
    .ascii  "per part, ms per frame:"
    .byte   13, 10
    .ascii  "blit      part  frames   frame      VM polygons pageops    blit  border   yield longest"
    .byte   13, 10, 0
rp_part:    .asciz  "  "
rp_count:
    .byte   13, 10
    .ascii  "full repaints, by a sentinel, blits written, skipped, palettes, mode switches, windows new / old, run ms new / old:"
    .byte   13, 10, 0
rp_bench:
    .ascii  "benchmark, ns x 10: ALU LCDw16 LCDw32 LCDr16 RAMw8 RAMw32 RAMr8 RAMr32 UNCr32"
    .byte   13, 10, 0
rp_regs:
    .ascii  "MEMCTR0-7, 32000040, 32000042, CHCTR, TM4MD, TM4BR, program build (hex):"
    .byte   13, 10, 0
    .align  4
