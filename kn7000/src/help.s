# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# The help screens (HELP button), after the KN5000 port's HELP_SCREEN: the game pauses and four
# pages show the controls, the fifteen level codes and the speed figures (perf.s PerfPageBuild). PAGE UP / PAGE DOWN turn the pages; EXIT,
# HELP again, or any game control returns to the game once everything is released.

# ================================================================================
# HelpScreen: called from ReadInput while HELP is held. The VM does not run meanwhile. The pages
# are drawn into HELP_BUF with their own palette; the game's palette is saved and put back and the
# game's front page is blitted again on the way out.
HelpScreen:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     PH_PAUSE, d0            # not part of any frame (perf.s)
    call    PerfPhase, 0, 0
    mov     d0, d3                  # the phase to go back to
    call    AudioPause, 0, 0        # silence; the music waits (audio.s)
    mov     palette, a0             # save the game's palette, install the help colours
    mov     HELP_PAL_SAVE, a1
    call    hs_copy_pal, 0, 0
    mov     help_palette, a0
    mov     palette, a1
    call    hs_copy_pal, 0, 0
    clr     d0
    mov     d0, (HELP_PAGE_NO)
    mov     d0, (HELP_TICK)
hs_wait_help:                       # let go of HELP first
    call    HelpSleep, 0, 0
    mov     (FWV_PANEL), a0
    movbu   (BTN_HELP_OFS, a0), d0
    and     BTN_HELP_BIT, d0
    bne     hs_wait_help
    call    HelpDrawPage, 0, 0
hs_poll:
    call    HelpSleep, 0, 0
    mov     (FWV_PANEL), a0
    movbu   (BTN_PAGE_OFS, a0), d0
    and     BTN_EXIT_BIT, d0
    bne     hs_exit
    mov     (FWV_PANEL), a0
    movbu   (BTN_HELP_OFS, a0), d0
    and     BTN_HELP_BIT, d0
    bne     hs_exit
    call    HelpGameInput, 0, 0
    cmp     0, d0
    bne     hs_exit
    mov     (FWV_PANEL), a0
    movbu   (BTN_PAGE_OFS, a0), d0
    and     BTN_PAGEUP_BIT, d0
    beq     hs_no_up
    mov     (HELP_PAGE_NO), d0      # PAGE UP: previous page
    cmp     0, d0
    beq     hs_page_wait
    add     -1, d0
    mov     d0, (HELP_PAGE_NO)
    bra     hs_page_draw
hs_no_up:
    mov     (FWV_PANEL), a0
    movbu   (BTN_PAGE_OFS, a0), d0
    and     BTN_PAGEDN_BIT, d0
    beq     hs_idle
    mov     (HELP_PAGE_NO), d0      # PAGE DOWN: next page
    cmp     HELP_PAGES - 1, d0
    beq     hs_page_wait
    inc     d0
    mov     d0, (HELP_PAGE_NO)
hs_page_draw:
    call    HelpDrawPage, 0, 0
hs_page_wait:                       # wait for PAGE UP / DOWN to be released
    call    HelpSleep, 0, 0
    mov     (FWV_PANEL), a0
    movbu   (BTN_PAGE_OFS, a0), d0
    and     BTN_PAGEUP_BIT | BTN_PAGEDN_BIT, d0
    bne     hs_page_wait
    mov     HELP_BUF, a0            # show the page again: the firmware may have repainted
    call    BlitPage, 0, 0          # the screen for the button press
    bra     hs_poll
hs_idle:                            # nothing pressed: re-show the page every HELP_REFRESH
    mov     (HELP_TICK), d0         # polls, in case the firmware repainted the screen (the blit
    inc     d0                      # writes only what the sentinels find changed)
    mov     d0, (HELP_TICK)
    cmp     HELP_REFRESH, d0
    blt     hs_poll
    clr     d0
    mov     d0, (HELP_TICK)
    call    PerfSentinels, 0, 0
    mov     HELP_BUF, a0
    call    BlitPage, 0, 0
    bra     hs_poll
hs_exit:                            # wait until every control is released
    call    HelpSleep, 0, 0
    mov     (FWV_PANEL), a0
    movbu   (BTN_PAGE_OFS, a0), d0
    and     BTN_EXIT_BIT, d0
    bne     hs_exit
    mov     (FWV_PANEL), a0
    movbu   (BTN_HELP_OFS, a0), d0
    and     BTN_HELP_BIT, d0
    bne     hs_exit
    call    HelpGameInput, 0, 0
    cmp     0, d0
    bne     hs_exit
    mov     HELP_PAL_SAVE, a0       # the game's palette and picture back
    mov     palette, a1
    call    hs_copy_pal, 0, 0
    mov     (CUR_PAGE_2), a0
    call    BlitPage, 0, 0
    mov     (PF_STATE), d0          # PAGE UP / DOWN pressed in here are not the game's
    or      6, d0
    mov     d0, (PF_STATE)
    mov     d3, d0
    call    PerfPhase, 0, 0
    call    AudioResume, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# hs_copy_pal(a0 = from, a1 = to): copy a 16-entry RGB565 palette (32 bytes). Leaf.
hs_copy_pal:
    mov     8, d1
hs_cp_loop:
    mov     (a0), d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d1
    bne     hs_cp_loop
    rets

# HelpSleep: wait 30 ms, keeping the keybed/MIDI note trackers up to date.
HelpSleep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     30, d0
    mov     DLY_TSK, a1
    calls   (a1)
    call    NotePoll, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# HelpGameInput -> d0 != 0 while any game control is held: a keybed or MIDI note, or one of the
# five panel buttons of the D-pad and fire.
HelpGameInput:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d2
    mov     (FWV_PANEL), a0
    movbu   (BTN_LEFT_OFS, a0), d0
    and     BTN_LEFT_BIT, d0
    or      d0, d2
    mov     (FWV_PANEL), a0
    movbu   (BTN_RIGHT_OFS, a0), d0
    and     BTN_RIGHT_BIT, d0
    or      d0, d2
    mov     (FWV_PANEL), a0
    movbu   (BTN_UP_OFS, a0), d0
    and     BTN_UP_BIT, d0
    or      d0, d2
    mov     (FWV_PANEL), a0
    movbu   (BTN_DOWN_OFS, a0), d0
    and     BTN_DOWN_BIT, d0
    or      d0, d2
    mov     (FWV_PANEL), a0
    movbu   (BTN_FIRE_OFS, a0), d0
    and     BTN_FIRE_BIT, d0
    or      d0, d2
    clr     d0                      # any note 0..127
    mov     127, d1
    call    NotesAnyHeld, 0, 0
    or      d2, d0
    ret     [d2,d3,a2,a3], 0x20

# HelpDrawPage: draw page HELP_PAGE_NO (help_pages) into HELP_BUF and show it.
HelpDrawPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     HELP_BUF, a0            # black page
    mov     PAGE_SIZE / 4, d1
    clr     d0
hd_clear:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     hd_clear
    mov     (CUR_PAGE_1), d0        # DrawChar draws on CUR_PAGE_1
    mov     d0, (4, sp)
    mov     HELP_BUF, a0
    mov     a0, (CUR_PAGE_1)
    call    DspModeText, 0, 0       # the sound mode's line (page 1)
    mov     (HELP_PAGE_NO), d0
    cmp     3, d0                   # the speed page: its text, now
    bne     hd_page
    call    PerfPageBuild, 0, 0
hd_page:
    mov     (HELP_PAGE_NO), d0
    asl     2, d0
    mov     help_pages, a0
    add     d0, a0
    mov     (a0), a2                # a2 = this page's text items
hd_item:
    movhu   (a2), d0                # x (0xFFFF ends the page)
    cmp     0xFFFF, d0
    beq     hd_done
    movhu   (2, a2), d1             # y
    movhu   (4, a2), d2             # colour
    mov     (8, a2), a3             # text
    call    HelpText, 0, 0
    add     12, a2
    bra     hd_item
hd_done:
    mov     (4, sp), d0
    mov     d0, (CUR_PAGE_1)
    mov     HELP_BUF, a0
    call    BlitPage, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# HelpText(a3 = NUL-terminated text, d0 = x, d1 = y, d2 = colour): 8x8 glyphs from AW_FONT.
HelpText:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, (4, sp)
    mov     d1, (8, sp)
ht_loop:
    movbu   (a3), d3
    cmp     0, d3
    beq     ht_done
    inc     a3
    mov     (4, sp), d0
    mov     (8, sp), d1
    call    DrawChar, 0, 0          # preserves d2 (colour), d3, a2, a3
    mov     (4, sp), d0
    add     8, d0
    mov     d0, (4, sp)
    bra     ht_loop
ht_done:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# The pages. Each item: .word x, y, colour, 0 then .long text (12 bytes, 4-byte aligned for the
# .long); a page ends with .word 0xFFFF, 0.
# Colours (help_palette): 1 white, 2 cyan, 3 yellow. 40 columns of 8 px, 200 rows.
    .align  4
help_palette:
    .word   0x0000, 0xFFFF, 0x055F, 0xFFE0
    .word   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
help_pages:
    .long   help_page0, help_page1, help_page2, PF_ITEMS

help_page0:
    .word   108, 8, 2, 0
    .long   hs_title1
    .word   116, 20, 2, 0
    .long   hs_title2
    .word   8, 40, 1, 0
    .long   hs_controls
    .word   80, 40, 2, 0
    .long   hs_col_keys
    .word   184, 40, 2, 0
    .long   hs_col_panel
    .word   8, 56, 3, 0
    .long   hs_up
    .word   80, 56, 1, 0
    .long   hs_up_key
    .word   184, 56, 1, 0
    .long   hs_up_btn
    .word   8, 68, 3, 0
    .long   hs_down
    .word   80, 68, 1, 0
    .long   hs_down_key
    .word   184, 68, 1, 0
    .long   hs_down_btn
    .word   8, 80, 3, 0
    .long   hs_left
    .word   80, 80, 1, 0
    .long   hs_left_key
    .word   184, 80, 1, 0
    .long   hs_left_btn
    .word   8, 92, 3, 0
    .long   hs_right
    .word   80, 92, 1, 0
    .long   hs_right_key
    .word   184, 92, 1, 0
    .long   hs_right_btn
    .word   8, 104, 3, 0
    .long   hs_action
    .word   80, 104, 1, 0
    .long   hs_action_key
    .word   184, 104, 1, 0
    .long   hs_action_btn
    .word   8, 124, 3, 0
    .long   hs_codes
    .word   80, 124, 1, 0
    .long   hs_codes_btn
    .word   8, 136, 3, 0
    .long   hs_help
    .word   80, 136, 1, 0
    .long   hs_help_btn
    .word   8, 148, 3, 0
    .long   hs_page
    .word   80, 148, 1, 0
    .long   hs_page_btn
    .word   8, 160, 3, 0
    .long   hs_exit_lbl
    .word   80, 160, 1, 0
    .long   hs_exit_btn
    .word   8, 172, 3, 0
    .long   hs_sound
    .word   80, 172, 1, 0
    .long   hs_sound_btn
    .word   8, 184, 2, 0
    .long   DV_MODETXT              # "NOW: DSP SAMPLES" ...: dsp.s DspModeText, before every page
    .word   256, 184, 1, 0
    .long   hs_page_1
    .word   0xFFFF, 0               # end of page (4 bytes, so the next page stays aligned)

help_page1:
    .word   108, 8, 2, 0
    .long   hs_title1
    .word   116, 20, 2, 0
    .long   hs_title2
    .word   8, 40, 1, 0
    .long   hs_level_codes
    .word   8, 56, 3, 0
    .long   hs_c1
    .word   56, 56, 1, 0
    .long   hs_l1
    .word   8, 70, 3, 0
    .long   hs_c2
    .word   56, 70, 1, 0
    .long   hs_l2
    .word   8, 84, 3, 0
    .long   hs_c3
    .word   56, 84, 1, 0
    .long   hs_l3
    .word   8, 98, 3, 0
    .long   hs_c4
    .word   56, 98, 1, 0
    .long   hs_l4
    .word   8, 112, 3, 0
    .long   hs_c5
    .word   56, 112, 1, 0
    .long   hs_l5
    .word   8, 126, 3, 0
    .long   hs_c6
    .word   56, 126, 1, 0
    .long   hs_l6
    .word   8, 140, 3, 0
    .long   hs_c7
    .word   56, 140, 1, 0
    .long   hs_l7
    .word   8, 154, 3, 0
    .long   hs_c8
    .word   56, 154, 1, 0
    .long   hs_l8
    .word   128, 184, 1, 0
    .long   hs_page_2
    .word   0xFFFF, 0               # end of page (4 bytes, so the next page stays aligned)

help_page2:
    .word   108, 8, 2, 0
    .long   hs_title1
    .word   116, 20, 2, 0
    .long   hs_title2
    .word   8, 40, 1, 0
    .long   hs_level_codes2
    .word   8, 56, 3, 0
    .long   hs_c9
    .word   56, 56, 1, 0
    .long   hs_l9
    .word   8, 70, 3, 0
    .long   hs_c10
    .word   56, 70, 1, 0
    .long   hs_l10
    .word   8, 84, 3, 0
    .long   hs_c11
    .word   56, 84, 1, 0
    .long   hs_l11
    .word   8, 98, 3, 0
    .long   hs_c12
    .word   56, 98, 1, 0
    .long   hs_l12
    .word   8, 112, 3, 0
    .long   hs_c13
    .word   56, 112, 1, 0
    .long   hs_l13
    .word   8, 126, 3, 0
    .long   hs_c14
    .word   56, 126, 1, 0
    .long   hs_l14
    .word   8, 140, 3, 0
    .long   hs_c15
    .word   56, 140, 1, 0
    .long   hs_l15
    .word   60, 160, 2, 0
    .long   hs_url1
    .word   84, 170, 2, 0
    .long   hs_url2
    .word   128, 184, 1, 0
    .long   hs_page_3
    .word   0xFFFF, 0               # end of page (4 bytes, so the next page stays aligned)

hs_title1:       .asciz "ANOTHER WORLD"
hs_title2:       .asciz "KN7000 PORT"
hs_controls:     .asciz "CONTROLS"
hs_col_keys:     .asciz "KEYBED/MIDI"
hs_col_panel:    .asciz "PANEL"
hs_up:           .asciz "UP"
hs_up_key:       .asciz "Bb5 or B5"
hs_up_btn:       .asciz "R1/R2 OCTAVE +"
hs_down:         .asciz "DOWN"
hs_down_key:     .asciz "A5"
hs_down_btn:     .asciz "R1/R2 OCTAVE -"
hs_left:         .asciz "LEFT"
hs_left_key:     .asciz "F5"
hs_left_btn:     .asciz "PART SEL LEFT"
hs_right:        .asciz "RIGHT"
hs_right_key:    .asciz "C6"
hs_right_btn:    .asciz "PART SEL RIGHT 1"
hs_action:       .asciz "ACTION"
hs_action_key:   .asciz "C4 or lower"
hs_action_btn:   .asciz "SUSTAIN"
hs_codes:        .asciz "CODES"
hs_codes_btn:    .asciz "OTHER PART & FR: enter a code"
hs_help:         .asciz "HELP"
hs_help_btn:     .asciz "this screen"
hs_page:         .asciz "PAGE"
hs_page_btn:     .asciz "PAGE UP / PAGE DOWN"
hs_exit_lbl:     .asciz "EXIT"
hs_exit_btn:     .asciz "EXIT, or any game control"
hs_sound:        .asciz "SOUND"
hs_sound_btn:    .asciz "PART SEL RIGHT 2: DSP/TG/OFF"
hs_page_1:       .asciz "Page 1/4"
hs_page_2:       .asciz "Page 2/4"
hs_page_3:       .asciz "Page 3/4"
hs_level_codes:  .asciz "LEVEL CODES:"
hs_level_codes2: .asciz "LEVEL CODES (cont.):"
hs_c1:           .asciz "LDKD"
hs_l1:           .asciz "By the lake"
hs_c2:           .asciz "HTDC"
hs_l2:           .asciz "Trapped in the cage"
hs_c3:           .asciz "CLLD"
hs_l3:           .asciz "Crawling in ducts"
hs_c4:           .asciz "LBKG"
hs_l4:           .asciz "Fight the guard"
hs_c5:           .asciz "XDDJ"
hs_l5:           .asciz "Down in the caves"
hs_c6:           .asciz "FXLC"
hs_l6:           .asciz "Deeper in the caves"
hs_c7:           .asciz "KRFK"
hs_l7:           .asciz "Cause a flood"
hs_c8:           .asciz "KLFB"
hs_l8:           .asciz "On to the castle"
hs_c9:           .asciz "TTCT"
hs_l9:           .asciz "Swim to the depths"
hs_c10:          .asciz "XRJT"
hs_l10:          .asciz "Back up to the top"
hs_c11:          .asciz "HBHK"
hs_l11:          .asciz "Dash through doors"
hs_c12:          .asciz "TFBB"
hs_l12:          .asciz "Lester to the rescue"
hs_c13:          .asciz "TXHF"
hs_l13:          .asciz "Wait before you shoot"
hs_c14:          .asciz "CKJL"
hs_l14:          .asciz "In the armoured car"
hs_c15:          .asciz "LFCK"
hs_l15:          .asciz "The grand finale"
hs_url1:         .asciz "github.com/felipesanches/"
hs_url2:         .asciz "kn5000-anotherworld"
    .align  4
