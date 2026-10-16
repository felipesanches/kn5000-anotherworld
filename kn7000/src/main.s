# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World on the Technics SX-KN7000 -- platform layer.
#
# A port of the Another World bytecode VM from the KN5000 version
# (github.com/felipesanches/kn5000-anotherworld, TLCS-900) to the KN7000's
# Panasonic MN10300, running as a ride-along module in the SP7001 SD plug-in.
#
# Flow (see ../README.md):
#   * The hook runs as BASEEXT's XapEntry, on the firmware's loading task -- the
#     only context where the SD file API is valid. It loads AWDATA.AW (the intro's
#     bytecode + polygon + palette resources) from the card into the 0x44 scratch
#     window, starts our game task, then resumes XapEntry so BASEEXT still works.
#   * The game task runs the VM: GameReset, then ExecuteInstruction forever. The VM
#     blits its front page to the 640x240 RGB565 LCD frame through a 16-colour
#     palette; it persists on the static SP7001 screen (the firmware repaints only
#     what changes). The per-frame yield lives in NextThread.

.include "platform.inc"
.include "vm.inc"
.mnbase 0x502B6000                  # where xap_addon.py places this module

# =================================================================================
# The hook. Entered exactly as BASEEXT's XapEntry (a0 = framework, a1 = context,
# d0/d1 = &compile/&plug-in id), on the firmware's loading task.
Hook:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x10, sp)
    mov     d1, (0x14, sp)
    mov     a0, (0x18, sp)
    mov     a1, (0x1c, sp)
    call    LoadGameData, 0, 0      # SD load here, where the file API is valid
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

# Create and start the game task, trying slot 10 then 9 (once per power-on).
StartTask:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     TASK_ID_FIRST, d2
st_try:
    mov     d2, d0
    mov     game_ctsk, a0
    mov     CRE_TSK_X, a1
    calls   (a1)
    cmp     0, d0                    # E_OK
    beq     st_start
    add     -1, d2
    cmp     TASK_ID_LAST, d2
    bge     st_try
    bra     st_done
st_start:
    mov     d2, d0
    clr     d1
    mov     STA_TSK, a1
    calls   (a1)
st_done:
    ret     [d2,d3,a2,a3], 0x20

# =================================================================================
# LoadOneFile(a0 = path, a1 = dest in 0x44 window, d0 = byte count): fopen + a single
# fread into work RAM + copy to dest + fclose. The firmware's fread has a 16-bit count
# and no working sequential reads, so each resource is one file read whole in one call;
# the SD DMA target must be work RAM (STAGING_BIG), not the 0x44 window.
# CRITICAL: firmware file calls scribble on 0..0xF(sp), so locals live at 0x10+.

# fopen_api/fread_api stash their arguments in the CALLER's frame at [sp+4 .. sp+0x10]
# (per the disassembly of 0x48585E2A/0x48585E50), so persistent locals there get
# clobbered. The firmware calls need a caller frame of at least 0x20; we use one and
# keep dest/count/FILE*/diag only in the SAFE slots (0, 0x14, 0x18, 0x1c), all outside
# the 4..0x10 stash range.
LoadOneFile:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a1, (0, sp)             # dest   (safe)
    mov     d0, (0x14, sp)          # count  (safe)
    mov     d1, (0x1c, sp)          # diag slot (safe)
    mov     aw_mode, a1             # a0 still = path
    mov     FOPEN, a3
    calls   (a3)                    # a0 = FILE*
    mov     (0x1c, sp), a3
    mov     a0, (0, a3)             # diag: FILE*
    cmp     0, a0
    beq     lof_done
    mov     a0, (0x18, sp)          # FILE*  (safe)
    mov     STAGING_BIG, a0         # buffer (work RAM, DMA target)
    mov     (0x18, sp), a1          # FILE*
    mov     1, d0                   # size = 1
    mov     (0x14, sp), d1          # count = byte count
    mov     FREAD, a3
    calls   (a3)                    # d0 = bytes read
    mov     (0x1c, sp), a3
    mov     d0, (4, a3)             # diag: bytes read
    cmp     0, d0
    beq     lof_close
    mov     d0, d2                  # copy counter
    mov     STAGING_BIG, a0         # src
    mov     (0, sp), a1             # dest (safe slot -- not clobbered by fread)
lof_copy:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lof_copy
lof_close:
    mov     (0x18, sp), a0          # FILE*
    mov     FCLOSE, a3
    calls   (a3)
lof_done:
    ret     [d2,d3,a2,a3], 0x30

# LoadGameData: preload the intro part's four resources (eager per-part load, like the
# KN5000 initForPart). One-shot, guarded by AW_LOADED_FLAG. Runs on the firmware task.
# The firmware file calls only work when invoked DIRECTLY on the hook's own call chain
# (a nested helper's fread returns a count but never fills the buffer -- the file API
# stashes its arguments up the stack in a way the extra frame breaks). So the four
# resource loads are inlined here rather than factored into a helper.
# Safe stack slot: (0x18,sp) for FILE* (outside fopen/fread's [sp+4..sp+0x10] stash).
LoadGameData:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (AW_LOADED_FLAG), d0
    cmp     0x600D, d0
    beq     lgd_done
    # --- bytecode ---
    mov     path_byte, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_v1
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_BYTECODE_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_BYTECODE, a1
lgd_c0:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c0
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- video1 ---
lgd_v1:
    mov     path_vid1, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_v2
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_VIDEO1_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_VIDEO1, a1
lgd_c1:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c1
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- video2 ---
lgd_v2:
    mov     path_vid2, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_pal
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_VIDEO2_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_VIDEO2, a1
lgd_c2:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c2
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- palettes ---
lgd_pal:
    mov     path_pal, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_font
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_PALETTES_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_PALETTES, a1
lgd_c3:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c3
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- font (DRAW_STRING glyphs) ---
lgd_font:
    mov     path_font, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_stridx
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_FONT_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_FONT, a1
lgd_c4:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c4
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- string index ---
lgd_stridx:
    mov     path_stridx, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_strdat
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_STRIDX_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_STRIDX, a1
lgd_c5:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c5
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- string data ---
lgd_strdat:
    mov     path_strdat, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_flag
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW_STRDAT_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW_STRDAT, a1
lgd_c6:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_c6
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- part 0x3E82 (water) bytecode (resource 0x1B) ---
    mov     path_byte2, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_vid12
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW2_BYTECODE_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW2_BYTECODE, a1
lgd_cb2:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_cb2
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- part 0x3E82 video1 (resource 0x1C) ---
lgd_vid12:
    mov     path_vid12, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_pal2
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW2_VIDEO1_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW2_VIDEO1, a1
lgd_cv12:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_cv12
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
    # --- part 0x3E82 palette (resource 0x1A) ---
lgd_pal2:
    mov     path_pal2, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_flag
    mov     a0, (0x18, sp)
    mov     STAGING_BIG, a0
    mov     (0x18, sp), a1
    mov     1, d0
    mov     AW2_PALETTES_SZ, d1
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2
    mov     STAGING_BIG, a0
    mov     AW2_PALETTES, a1
lgd_cp2:
    movbu   (a0), d0
    movbu   d0, (a1)
    inc     a0
    inc     a1
    add     -1, d2
    bne     lgd_cp2
    mov     (0x18, sp), a0
    mov     FCLOSE, a3
    calls   (a3)
lgd_flag:
    mov     0x600D, d0
    mov     AW_LOADED_FLAG, a0
    mov     d0, (a0)
lgd_done:
    ret     [d2,d3,a2,a3], 0x30

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
path_byte:
    .asciz "C:\TECHNICS\DATA\AWBYTE.AW"
    .align 2
path_vid1:
    .asciz "C:\TECHNICS\DATA\AWVID1.AW"
    .align 2
path_vid2:
    .asciz "C:\TECHNICS\DATA\AWVID2.AW"
    .align 2
path_pal:
    .asciz "C:\TECHNICS\DATA\AWPAL.AW"
    .align 2
path_font:
    .asciz "C:\TECHNICS\DATA\AWFONT.AW"
    .align 2
path_stridx:
    .asciz "C:\TECHNICS\DATA\AWSTRIDX.AW"
    .align 2
path_strdat:
    .asciz "C:\TECHNICS\DATA\AWSTRDAT.AW"
    .align 2
path_byte2:
    .asciz "C:\TECHNICS\DATA\AWBYTE2.AW"
    .align 2
path_vid12:
    .asciz "C:\TECHNICS\DATA\AWVID12.AW"
    .align 2
path_pal2:
    .asciz "C:\TECHNICS\DATA\AWPAL2.AW"
    .align 2
aw_mode:
    .asciz "rb"
    .align 4
.include "vm.s"
.include "interp.s"
