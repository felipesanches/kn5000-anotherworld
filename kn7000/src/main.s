# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World on the Technics SX-KN7000 -- platform layer of the SP7001 ride-along build.
#
# *** MAME ONLY. NOT FOR A REAL INSTRUMENT. *** It keeps the game in the 0x44000000 window, which on
# a real KN7000 is IC23, the battery-backed SRAM with the panel settings and memories (platform.inc).
# The real-instrument build is the STYLE CONVERT one, cnv_main.s (README-CNV.md).
#
# A port of the Another World bytecode VM from the KN5000 version
# (github.com/felipesanches/kn5000-anotherworld, TLCS-900) to the KN7000's
# Panasonic MN10300, running as a ride-along module in the SP7001 SD plug-in.
#
# Flow (see ../README.md):
#   * The hook runs as BASEEXT's XapEntry, on the firmware's loading task -- the
#     only context where the SD file API is valid. It loads every game resource
#     (C:\TECHNICS\DATA\AWRxx.AW) plus the font and strings from the card into the 0x44
#     window (MAME's placeholder RAM; IC23 on an instrument), starts our game task, then resumes
#     XapEntry so BASEEXT still works.
#   * The game task runs the VM: GameReset, then ExecuteInstruction forever. The VM
#     blits its front page to the 640x240 RGB565 LCD frame through a 16-colour
#     palette; it persists on the static SP7001 screen (the firmware repaints only
#     what changes). The per-frame yield lives in NextThread.

.include "platform.inc"
.include "vm.inc"
.include "awres.inc"                # generated: RES_COUNT, RES_BASE, RES_END
.mnbase 0x502B4D80                  # where xap_addon.py places this module (Makefile MODULE_AT)

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
    mov     KERNEL_MS, d0           # program 942's addresses for the shared code (vm.inc FWV_*)
    mov     d0, (FWV_KERNEL_MS)
    mov     PANEL_CPR, d0
    mov     d0, (FWV_PANEL)
    mov     MIDIIN1_RXQ, d0
    mov     d0, (FWV_MIDIIN1)
    mov     MIDIOUT1_TXQ, d0
    mov     d0, (FWV_MIDIOUT1)
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

# LoadGameData: preload the font, the string tables and EVERY game resource (all parts,
# bitmaps, sounds, music) -- the file API only works here, on the firmware task, so nothing
# can be loaded later. One-shot, guarded by AW_LOADED_FLAG.
# The firmware file calls only work when invoked DIRECTLY on the hook's own call chain
# (a nested helper's fread returns a count but never fills the buffer -- the file API
# stashes its arguments up the stack in a way the extra frame breaks). So the loads are
# inlined here (the resources as one loop) rather than factored into a helper.
# Safe stack slots: 0, 0x14, 0x18, 0x1c (outside fopen/fread's [sp+4..sp+0x10] stash).
LoadGameData:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (AW_LOADED_FLAG), d0
    cmp     0x600D, d0
    beq     lgd_done
    # --- font (DRAW_STRING glyphs) ---
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
    beq     lgd_resources
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
    # --- every Another World resource, as pack files C:\TECHNICS\DATA\AWPxx.AW: each pack is
    # the RAM image of a span of resources, copied to PackAddr[xx] (tables in awres_tab.s).
    # Packs instead of one file per resource: each file costs ~71 ms to open (awloadtime.lua), so 31 packs load in
    # a fraction of the time 140 files take. The firmware's file calls write all over this
    # frame (sp+0..0x1C at least), so the loop state lives in static RAM: LOAD_PACK, LOAD_FILE.
lgd_resources:
    clr     d0
    mov     d0, (LOAD_PACK)
lgd_pack:
    mov     (LOAD_PACK), d0         # the pack index as two upper-case hex digits in res_path_xx
    lsr     4, d0
    and     15, d0
    cmp     10, d0
    blt     lgd_ph1
    add     7, d0                   # 'A' - '0' - 10
lgd_ph1:
    add     0x30, d0
    movbu   d0, (res_path_xx)
    mov     (LOAD_PACK), d0
    and     15, d0
    cmp     10, d0
    blt     lgd_ph2
    add     7, d0
lgd_ph2:
    add     0x30, d0
    movbu   d0, (res_path_xx + 1)
    mov     res_path, a0
    mov     aw_mode, a1
    mov     FOPEN, a3
    calls   (a3)
    cmp     0, a0
    beq     lgd_pnext
    mov     a0, (LOAD_FILE)
    mov     (LOAD_PACK), d0         # count = PackSize[pack]
    asl     1, d0
    mov     PackSize, a0
    add     d0, a0
    movhu   (a0), d1
    mov     STAGING_BIG, a0
    mov     (LOAD_FILE), a1
    mov     1, d0
    mov     FREAD, a3
    calls   (a3)
    mov     d0, d2                  # bytes read
    mov     (LOAD_PACK), d0
    asl     2, d0
    mov     PackAddr, a0
    add     d0, a0
    mov     (a0), a1                # dest = PackAddr[pack] (4-byte aligned, as is STAGING_BIG)
    mov     STAGING_BIG, a0
    add     3, d2
    lsr     2, d2                   # whole words
    cmp     0, d2
    beq     lgd_pclose
lgd_pcopy:
    mov     (a0), d0
    mov     d0, (a1)
    add     4, a0
    add     4, a1
    add     -1, d2
    bne     lgd_pcopy
lgd_pclose:
    mov     (LOAD_FILE), a0
    mov     FCLOSE, a3
    calls   (a3)
lgd_pnext:
    mov     (LOAD_PACK), d0
    inc     d0
    mov     d0, (LOAD_PACK)
    cmp     PACK_COUNT, d0
    blt     lgd_pack
lgd_flag:
    mov     0x600D, d0
    mov     AW_LOADED_FLAG, a0
    mov     d0, (a0)
lgd_done:
    ret     [d2,d3,a2,a3], 0x30

# =================================================================================
# The shared VM's platform hooks (interp.s). Every resource is resident here.
# EnsurePart(d0 = part id): nothing to load. Leaf.
EnsurePart:
    rets

# BitmapData(d0 = resource id) -> a0 = its 32,000 bytes of planes (resident, unpacked). Leaf.
BitmapData:
    and     0xff, d0
    asl     2, d0
    mov     ResAddr, a0
    add     d0, a0
    mov     (a0), a0
    rets

# TraceInsn(d1 = opcode, kept): log (frame u16, thread u8, opcode u8, pc u16) to TRACE_BUF.
TraceInsn:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (TRACE_COUNT), d0
    cmp     TRACE_MAX, d0
    bge     ti_ret
    mov     d0, d3
    asl     3, d3
    mov     TRACE_BUF, a3
    add     d3, a3
    movhu   (FRAME_NO), d3
    movhu   d3, (a3)
    movbu   (CURRENT_THREAD), d3
    movbu   d3, (2, a3)
    movbu   d1, (3, a3)
    movhu   (VM_PC), d3
    movhu   d3, (4, a3)
    inc     d0
    mov     TRACE_COUNT, a3
    mov     d0, (a3)
ti_ret:
    ret     [d2,d3,a2,a3], 0x20

.include "display.s"
path_font:
    .asciz "C:\TECHNICS\DATA\AWFONT.AW"
    .align 2
path_stridx:
    .asciz "C:\TECHNICS\DATA\AWSTRIDX.AW"
    .align 2
path_strdat:
    .asciz "C:\TECHNICS\DATA\AWSTRDAT.AW"
    .align 2
res_path:                           # C:\TECHNICS\DATA\AWPxx.AW, xx patched per pack
    .ascii  "C:\TECHNICS\DATA\AWP"
res_path_xx:
    .asciz  "00.AW"
    .align 2
aw_mode:
    .asciz "rb"
    .align 4
.include "vm.s"
.include "interp.s"
.include "help.s"
.include "awres_tab.s"              # generated: ResAddr, ResSize, ResType
