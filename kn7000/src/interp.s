# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World VM -- the bytecode interpreter, thread scheduler, page/palette
# operations and the SD game-data loader, ported from the KN5000 TLCS-900 source
# (another_world_vm.asm) to the MN10300. Opcode semantics and variable names mirror
# the KN5000 version so the two read together. The polygon rasterizer and the
# polygon-hierarchy parser live in vm.s.
#
# Calling convention (whole port): d0,d1,a0,a1 are caller-saved args/scratch;
# d2,d3,a2,a3 are callee-saved (movm prologue). Because every subroutine preserves
# a2/a3, ExecuteInstruction keeps the live bytecode cursor in a2 across its helper
# calls for free. ret adj = locals + 0x10 (pops locals AND the four saved regs).

# ================================================================================
# ReadVar(d0 = index) -> d0 = var value (raw u16 in low half)
ReadVar:
    movm    [a2,a3], (sp)
    add     -8, sp
    and     0xff, d0
    asl     1, d0
    mov     VM_VARIABLES, a2
    add     d0, a2
    movhu   (a2), d0
    ret     [a2,a3], 0x10

# WriteVar(d0 = index, d1 = value)
WriteVar:
    movm    [a2,a3], (sp)
    add     -8, sp
    and     0xff, d0
    asl     1, d0
    mov     VM_VARIABLES, a2
    add     d0, a2
    movhu   d1, (a2)
    ret     [a2,a3], 0x10

# GetPagePtr(d0 = pageId) -> a0 = page base
#   0xFF -> CUR_PAGE_3, 0xFE -> CUR_PAGE_2, 0..3 -> PAGE_BITMAP_n, else page 0.
GetPagePtr:
    and     0xff, d0
    cmp     0xff, d0
    bne     gp_not_ff
    mov     (CUR_PAGE_3), a0
    rets
gp_not_ff:
    cmp     0xfe, d0
    bne     gp_not_fe
    mov     (CUR_PAGE_2), a0
    rets
gp_not_fe:
    cmp     0, d0
    bne     gp_not_0
    mov     PAGE_BITMAP_0, a0
    rets
gp_not_0:
    cmp     1, d0
    bne     gp_not_1
    mov     PAGE_BITMAP_1, a0
    rets
gp_not_1:
    cmp     2, d0
    bne     gp_not_2
    mov     PAGE_BITMAP_2, a0
    rets
gp_not_2:
    cmp     3, d0
    bne     gp_not_3
    mov     PAGE_BITMAP_3, a0
    rets
gp_not_3:
    mov     PAGE_BITMAP_0, a0
    rets

# ================================================================================
# VideoStart: initial page pointers (page2 = front, page1 = back).
VideoStart:
    mov     PAGE_BITMAP_2, a0
    mov     a0, (CUR_PAGE_1)
    mov     a0, (CUR_PAGE_2)
    mov     PAGE_BITMAP_1, a0
    mov     a0, (CUR_PAGE_3)
    rets

# ================================================================================
# InitForPart(d0 = partId): reset threads and load this part's resource pointers.
# For the port we only run part GAME_PART_INTRO; the resource pointers come from the
# AWDATA header rather than a PART_RESOURCE_TABLE.
InitForPart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    movhu   d0, (CURRENT_PART_ID)
    mov     VM_STACK, a0
    mov     a0, (VM_SP_PTR)
    # all threads inactive, unfrozen
    clr     d2                      # thread index
ifp_loop:
    mov     d2, d0
    asl     2, d0
    mov     THREADS_DATA, a2
    add     d0, a2
    mov     INACTIVE_THREAD, d1
    movhu   d1, (PC_OFFSET, a2)
    mov     NO_REQUEST, d1
    movhu   d1, (REQ_PC_OFFSET, a2)
    mov     d2, d0
    asl     1, d0
    mov     VM_CHAN_STATE, a2
    add     d0, a2
    mov     ST_NOT_FROZEN, d1
    movbu   d1, (CUR_STATE, a2)
    movbu   d1, (REQ_STATE, a2)
    inc     d2
    cmp     64, d2
    bne     ifp_loop
    # thread 0 starts at PC 0
    mov     THREADS_DATA, a2
    clr     d1
    movhu   d1, (PC_OFFSET, a2)
    # var[0xE4] = 0x14
    mov     0xE4, d0
    mov     0x14, d1
    call    WriteVar, 0, 0
    # resource pointers for this part (video2 is shared by all parts)
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E82, d0
    beq     ifp_part2
    # part 0x3E81 (intro): the first preloaded resource region
    mov     AW_BYTECODE, a0
    mov     a0, (CUR_BYTECODE)
    mov     AW_VIDEO1, a0
    mov     a0, (CUR_VIDEO_DATA)
    mov     a0, (CUR_VIDEO_1)
    mov     AW_PALETTES, a0
    mov     a0, (CUR_PALETTES)
    bra     ifp_vid2
ifp_part2:
    # part 0x3E82 (water): the second preloaded resource region
    mov     AW2_BYTECODE, a0
    mov     a0, (CUR_BYTECODE)
    mov     AW2_VIDEO1, a0
    mov     a0, (CUR_VIDEO_DATA)
    mov     a0, (CUR_VIDEO_1)
    mov     AW2_PALETTES, a0
    mov     a0, (CUR_PALETTES)
ifp_vid2:
    mov     AW_VIDEO2, a0           # video2 (resource 0x11) shared by all parts
    mov     a0, (CUR_VIDEO_2)
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# GameReset: zero VM vars, set up threads, apply the copy-protection bypass vars,
# and start on the intro part.
GameReset:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0                      # reset the instruction trace
    mov     TRACE_COUNT, a0
    mov     d0, (a0)
    mov     FRAME_NO, a0
    mov     d0, (a0)
    call    VideoStart, 0, 0
    # zero 256 vars (512 bytes)
    mov     VM_VARIABLES, a2
    mov     256, d2
gr_zero:
    clr     d0
    movhu   d0, (a2)
    add     2, a2
    add     -1, d2
    bne     gr_zero
    clr     d0
    movbu   d0, (CURRENT_THREAD)
    movhu   d0, (VM_PC)
    mov     VM_STACK, a0
    mov     a0, (VM_SP_PTR)
    # all threads inactive/unfrozen, thread 0 at PC 0
    clr     d2
gr_threads:
    mov     d2, d0
    asl     2, d0
    mov     THREADS_DATA, a2
    add     d0, a2
    mov     INACTIVE_THREAD, d1
    movhu   d1, (PC_OFFSET, a2)
    mov     NO_REQUEST, d1
    movhu   d1, (REQ_PC_OFFSET, a2)
    mov     d2, d0
    asl     1, d0
    mov     VM_CHAN_STATE, a2
    add     d0, a2
    mov     ST_NOT_FROZEN, d1
    movbu   d1, (CUR_STATE, a2)
    movbu   d1, (REQ_STATE, a2)
    inc     d2
    cmp     64, d2
    bne     gr_threads
    mov     THREADS_DATA, a2
    clr     d1
    movhu   d1, (PC_OFFSET, a2)
    # random seed var[0x3C] = 0x1234
    mov     0x3C, d0
    mov     0x1234, d1
    call    WriteVar, 0, 0
    # VM_HACK var[0x54] = 0x81 (Interplay logo)
    mov     0x54, d0
    mov     0x81, d1
    call    WriteVar, 0, 0
    # copy-protection bypass: var[0xBC]=0x10, [0xC6]=0x80, [0xF2]=0xFA0, [0xDC]=0x21
    mov     0xBC, d0
    mov     0x10, d1
    call    WriteVar, 0, 0
    mov     0xC6, d0
    mov     0x80, d1
    call    WriteVar, 0, 0
    mov     0xF2, d0
    mov     0xFA0, d1
    call    WriteVar, 0, 0
    mov     0xDC, d0
    mov     0x21, d1
    call    WriteVar, 0, 0
    clr     d0
    movhu   d0, (REQ_NEXT_PART)
    mov     0x3E81, d0              # GAME_PART_INTRO
    call    InitForPart, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# SetupPalette(d0 = palette index 0..31): build the 16-entry RGB565 palette[] that
# BlitPage reads. Source format: 2 bytes/colour, 0x0RGB with 4 bits per channel
# (byte0 low nibble = R; byte1 high nibble = G, low nibble = B). 4-bit -> RGB565.
SetupPalette:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    and     0xff, d0
    asl     1, d0
    asl     4, d0                   # index * 32
    mov     (CUR_PALETTES), a2
    add     d0, a2                  # a2 = source colour pair pointer
    mov     palette, a3             # a3 = dest RGB565 table
    mov     16, d2
sp_loop:
    movbu   (a2), d0                # byte0: low nibble = red (4-bit)
    and     0x0f, d0
    mov     d0, d1
    asl     1, d1                   # r5 = r4 << 1
    asl     11, d1                  # into bits 15..11
    mov     d1, d3                  # d3 = pixel accumulator
    movbu   (1, a2), d0             # byte1: high nibble = green, low = blue
    mov     d0, d1
    lsr     4, d1                   # green 4-bit
    asl     2, d1                   # g6 = g4 << 2
    asl     5, d1                   # into bits 10..5
    or      d1, d3
    and     0x0f, d0                # blue 4-bit
    asl     1, d0                   # b5 = b4 << 1
    or      d0, d3
    movhu   d3, (a3)
    add     2, a2
    add     2, a3
    add     -1, d2
    bne     sp_loop
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# UpdateDisplay(d0 = pageId): pick the page to show, then palette-blit it to the LCD.
#   0xFE -> show CUR_PAGE_2 as-is; 0xFF -> swap CUR_PAGE_2/3 then show; else show page(id).
UpdateDisplay:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    and     0xff, d0
    cmp     0xfe, d0
    beq     ud_show
    cmp     0xff, d0
    beq     ud_swap
    call    GetPagePtr, 0, 0
    mov     a0, (CUR_PAGE_2)
    bra     ud_show
ud_swap:
    mov     (CUR_PAGE_2), a2
    mov     (CUR_PAGE_3), a3
    mov     a3, (CUR_PAGE_2)
    mov     a2, (CUR_PAGE_3)
ud_show:
    mov     (CUR_PAGE_2), a0
    call    BlitPage, 0, 0          # a0 = page -> palette-blit to the LCD frame
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# FillPage(d0 = pageId, d1 = colour): fill a page with one colour index.
FillPageOp:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d1, d3                  # save colour
    call    GetPagePtr, 0, 0        # d0 = pageId -> a0 = page
    mov     a0, a2
    and     0xff, d3
    mov     PAGE_SIZE, d2
fpo_loop:
    movbu   d3, (a2)
    inc     a2
    add     -1, d2
    bne     fpo_loop
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# CopyPage(d0 = srcId, d1 = dstId): plain full-page copy (scroll modes not ported;
# the intro does not use vertical scroll). srcId >= 0xFE and the masked/plain paths
# all reduce to a straight 64000-byte copy here.
CopyPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d1, d3                  # dstId
    mov     d0, d2                  # srcId
    mov     d3, d0
    call    GetPagePtr, 0, 0
    mov     a0, a3                  # a3 = dst
    # Resolve the source page id. srcId >= 0xFE (0xFE front / 0xFF back) is used
    # UNMASKED; a normal page id has the 0x40 bit stripped. (The 0xBF-masked form
    # with bit 7 set selects vertical-scroll copy mode, which the intro never uses;
    # match the KN5000 by treating 0xFE/0xFF specially before masking.)
    mov     d2, d0
    and     0xff, d0
    cmp     0xff, d0
    beq     cp_src
    cmp     0xfe, d0
    beq     cp_src
    and     0xbf, d0                # normal page: strip the 0x40 bit
cp_src:
    call    GetPagePtr, 0, 0
    mov     a0, a2                  # a2 = src
    mov     PAGE_SIZE, d2
cp_loop:
    movbu   (a2), d0
    movbu   d0, (a3)
    inc     a2
    inc     a3
    add     -1, d2
    bne     cp_loop
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# ReadInput: map the KN7000 keybed to the Another World fire button so the player
# can skip the intro. The intro bytecode polls var[0xFE] (ACTION_MASK) and jumps to
# the first playable part (0x3E82) when fire is pressed. We only drive input during
# the intro; gameplay input mapping for the water part is a later step.
# Source: the firmware's first voice-slot "key active" flag at 0x50149690 -- any held
# keybed key sets it (0 while no key is down during the intro).
ReadInput:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E81, d0              # intro only
    bne     ri_ret
    mov     0x50149690, a0
    movhu   (a0), d0                # a keybed key is held?
    cmp     0, d0
    beq     ri_clear
    mov     0xFA, d0               # var[0xFA] = 1  (HERO_ACTION)
    mov     1, d1
    call    WriteVar, 0, 0
    mov     0xFE, d0               # var[0xFE] = 0x80 (HERO_ACTION_MASK = fire)
    mov     0x80, d1
    call    WriteVar, 0, 0
    bra     ri_ret
ri_clear:
    mov     0xFA, d0
    clr     d1
    call    WriteVar, 0, 0
    mov     0xFE, d0
    clr     d1
    call    WriteVar, 0, 0
ri_ret:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# NextThread: advance CURRENT_THREAD to the next active, unfrozen thread. When the
# scan wraps past 63 it is end-of-frame: apply requested thread states/PCs and show
# the front page. Loads the chosen thread's PC into VM_PC.
NextThread:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    movbu   (CURRENT_THREAD), d2    # d2 = current thread index
nt_loop:
    inc     d2
    cmp     64, d2
    bne     nt_not_eof
    # end of frame
    clr     d0
    movbu   d0, (CURRENT_THREAD)
    call    CheckThreadRequests, 0, 0
    mov     0xFE, d0
    call    UpdateDisplay, 0, 0
    mov     FRAME_NO, a2            # advance the VM frame (tick) number for the trace
    movhu   (a2), d0
    inc     d0
    movhu   d0, (a2)
    mov     30, d0                  # ~30 ms/frame: paces the VM and yields to firmware
    mov     DLY_TSK, a1
    calls   (a1)
    call    ReadInput, 0, 0         # map the keybed to the fire button (intro skip)
    # deferred part switch, requested by OpLoad (0x19 with id >= 0x3E80). The intro
    # issues it at its end, or immediately when the player presses fire (skip).
    mov     REQ_NEXT_PART, a2
    movhu   (a2), d0
    cmp     0, d0
    beq     nt_noswitch
    clr     d1
    movhu   d1, (a2)                # clear the request
    call    InitForPart, 0, 0       # d0 = partId: re-point resources + reset threads
nt_noswitch:
    clr     d2
nt_not_eof:
    # frozen?
    mov     d2, d0
    asl     1, d0
    mov     VM_CHAN_STATE, a2
    add     d0, a2
    movbu   (CUR_STATE, a2), d0
    cmp     ST_FROZEN, d0
    beq     nt_loop
    # inactive PC?
    mov     d2, d0
    asl     2, d0
    mov     THREADS_DATA, a2
    add     d0, a2
    movhu   (PC_OFFSET, a2), d0
    cmp     INACTIVE_THREAD, d0
    beq     nt_loop
    # selected
    mov     d2, d0
    movbu   d0, (CURRENT_THREAD)
    movhu   (PC_OFFSET, a2), d0
    movhu   d0, (VM_PC)
    ret     [d2,d3,a2,a3], 0x20

# CheckThreadRequests: apply requested_state -> state and requested_pc -> pc for all
# 64 threads, clearing the request.
CheckThreadRequests:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d2
ctr_loop:
    # state = requested_state
    mov     d2, d0
    asl     1, d0
    mov     VM_CHAN_STATE, a2
    add     d0, a2
    movbu   (REQ_STATE, a2), d0
    movbu   d0, (CUR_STATE, a2)
    # requested_pc
    mov     d2, d0
    asl     2, d0
    mov     THREADS_DATA, a2
    add     d0, a2
    movhu   (REQ_PC_OFFSET, a2), d0
    cmp     NO_REQUEST, d0
    beq     ctr_next
    cmp     DELETE_THREAD, d0
    bne     ctr_set
    mov     INACTIVE_THREAD, d0
ctr_set:
    movhu   d0, (PC_OFFSET, a2)
    mov     NO_REQUEST, d0
    movhu   d0, (REQ_PC_OFFSET, a2)
ctr_next:
    inc     d2
    cmp     64, d2
    bne     ctr_loop
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# ExecuteInstruction: run one bytecode instruction of the current thread.
# a2 = live bytecode cursor (CUR_BYTECODE + VM_PC), preserved across helper calls.
ExecuteInstruction:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    movhu   (VM_PC), d0
    mov     (CUR_BYTECODE), a2
    add     d0, a2
    movbu   (a2), d1                # d1 = opcode
    inc     a2
    # --- VM instruction trace: (frame u16, thread u8, opcode u8, pc u16) ---
    mov     (TRACE_COUNT), d0
    cmp     TRACE_MAX, d0
    bge     ei_notrace
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
ei_notrace:
    # --- 0x80: VIDEO (cinematic, CUR_VIDEO_1) ---
    mov     d1, d0
    and     0x80, d0
    beq     ei_not80
    bra     Op80
ei_not80:
    mov     d1, d0
    and     0x40, d0
    beq     ei_not40
    bra     Op40
ei_not40:
    # standard opcodes 0x00..0x1A (d1 = opcode)
    cmp     0x00, d1
    bne     ei_n00
    bra     OpMovConst
ei_n00:
    cmp     0x01, d1
    bne     ei_n01
    bra     OpMov
ei_n01:
    cmp     0x02, d1
    bne     ei_n02
    bra     OpAdd
ei_n02:
    cmp     0x03, d1
    bne     ei_n03
    bra     OpAddConst
ei_n03:
    cmp     0x04, d1
    bne     ei_n04
    bra     OpCall
ei_n04:
    cmp     0x05, d1
    bne     ei_n05
    bra     OpRet
ei_n05:
    cmp     0x06, d1
    bne     ei_n06
    bra     OpPauseThread
ei_n06:
    cmp     0x07, d1
    bne     ei_n07
    bra     OpJump
ei_n07:
    cmp     0x08, d1
    bne     ei_n08
    bra     OpSetVect
ei_n08:
    cmp     0x09, d1
    bne     ei_n09
    bra     OpDjnz
ei_n09:
    cmp     0x0A, d1
    bne     ei_n0a
    bra     OpCondJump
ei_n0a:
    cmp     0x0B, d1
    bne     ei_n0b
    bra     OpSetPalette
ei_n0b:
    cmp     0x0C, d1
    bne     ei_n0c
    bra     OpResetThread
ei_n0c:
    cmp     0x0D, d1
    bne     ei_n0d
    bra     OpSelectPage
ei_n0d:
    cmp     0x0E, d1
    bne     ei_n0e
    bra     OpFillPage
ei_n0e:
    cmp     0x0F, d1
    bne     ei_n0f
    bra     OpCopyPage
ei_n0f:
    cmp     0x10, d1
    bne     ei_n10
    bra     OpBlit
ei_n10:
    cmp     0x11, d1
    bne     ei_n11
    bra     OpKillThread
ei_n11:
    cmp     0x12, d1
    bne     ei_n12
    bra     OpDrawString
ei_n12:
    cmp     0x13, d1
    bne     ei_n13
    bra     OpSub
ei_n13:
    cmp     0x14, d1
    bne     ei_n14
    bra     OpAnd
ei_n14:
    cmp     0x15, d1
    bne     ei_n15
    bra     OpOr
ei_n15:
    cmp     0x16, d1
    bne     ei_n16
    bra     OpShl
ei_n16:
    cmp     0x17, d1
    bne     ei_n17
    bra     OpShr
ei_n17:
    cmp     0x18, d1
    bne     ei_n18
    bra     OpPlaySound
ei_n18:
    cmp     0x19, d1
    bne     ei_n19
    bra     OpLoad
ei_n19:
    cmp     0x1A, d1
    bne     ei_end                  # unknown opcode: just advance PC
    bra     OpPlayMusic

# ---- dispatch tails ------------------------------------------------------------
# ei_end: VM_PC = a2 - CUR_BYTECODE, then return.
ei_end:
    mov     a2, d0
    mov     (CUR_BYTECODE), a1
    mov     a1, d1
    sub     d1, d0
    movhu   d0, (VM_PC)
ei_ret:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# Helper: fetch a big-endian u16 from the cursor a2 into d0, advancing a2 by 2.
# (inlined where speed/locals matter; used by several handlers via macro-like copy)

# ---- 0x00 MOV_CONST: var[id] = imm16(BE) --------------------------------------
OpMovConst:
    movbu   (a2), d2                # id
    inc     a2
    movbu   (a2), d0                # hi
    inc     a2
    asl     8, d0
    movbu   (a2), d1                # lo
    inc     a2
    or      d1, d0
    mov     d0, d1
    mov     d2, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x01 MOV: var[dst] = var[src] --------------------------------------------
OpMov:
    movbu   (a2), d3                # dst
    inc     a2
    movbu   (a2), d0                # src
    inc     a2
    call    ReadVar, 0, 0           # d0 = var[src]
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x02 ADD: var[dst] += var[src] -------------------------------------------
OpAdd:
    movbu   (a2), d3                # dst
    inc     a2
    movbu   (a2), d0                # src
    inc     a2
    call    ReadVar, 0, 0           # d0 = var[src]
    mov     d0, d2                  # keep src value
    mov     d3, d0
    call    ReadVar, 0, 0           # d0 = var[dst]
    add     d2, d0
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x03 ADD_CONST: var[id] += imm16(BE) -------------------------------------
OpAddConst:
    movbu   (a2), d3                # id
    inc     a2
    movbu   (a2), d0                # hi
    inc     a2
    asl     8, d0
    movbu   (a2), d1                # lo
    inc     a2
    or      d1, d0
    mov     d0, d2                  # imm
    mov     d3, d0
    call    ReadVar, 0, 0
    add     d2, d0
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x04 CALL: push PC+3, PC = imm16(BE) -------------------------------------
OpCall:
    movbu   (a2), d0                # hi
    movbu   (1, a2), d1             # lo
    asl     8, d0
    or      d1, d0                  # d0 = target
    mov     d0, d3                  # keep target
    # return address = current VM_PC + 3 (opcode + 2 bytes)
    movhu   (VM_PC), d0
    add     3, d0
    mov     (VM_SP_PTR), a3
    movhu   d0, (a3)
    add     2, a3
    mov     a3, (VM_SP_PTR)
    movhu   d3, (VM_PC)
    bra     ei_ret

# ---- 0x05 RET: PC = pop -------------------------------------------------------
OpRet:
    mov     (VM_SP_PTR), a3
    add     -2, a3
    movhu   (a3), d0
    mov     a3, (VM_SP_PTR)
    movhu   d0, (VM_PC)
    bra     ei_ret

# ---- 0x06 PAUSE_THREAD: save PC as requested, next thread ---------------------
OpPauseThread:
    movbu   (CURRENT_THREAD), d0
    asl     2, d0
    mov     THREADS_DATA, a3
    add     d0, a3
    movhu   (REQ_PC_OFFSET, a3), d0
    cmp     NO_REQUEST, d0
    bne     opt_next
    # requested_pc = cursor - CUR_BYTECODE
    mov     a2, d0
    mov     (CUR_BYTECODE), a1
    mov     a1, d1
    sub     d1, d0
    movhu   d0, (REQ_PC_OFFSET, a3)
opt_next:
    call    NextThread, 0, 0
    bra     ei_ret

# ---- 0x07 JUMP: PC = imm16(BE) ------------------------------------------------
OpJump:
    movbu   (a2), d0
    movbu   (1, a2), d1
    asl     8, d0
    or      d1, d0
    movhu   d0, (VM_PC)
    bra     ei_ret

# ---- 0x08 SET_VECT: thread[id].requested_pc = imm16(BE) -----------------------
OpSetVect:
    movbu   (a2), d2                # thread id
    inc     a2
    and     0x3f, d2
    movbu   (a2), d0                # hi
    inc     a2
    asl     8, d0
    movbu   (a2), d1                # lo
    inc     a2
    or      d1, d0
    mov     d2, d1
    asl     2, d1
    mov     THREADS_DATA, a3
    add     d1, a3
    movhu   d0, (REQ_PC_OFFSET, a3)
    bra     ei_end

# ---- 0x09 DJNZ: var[id]--; if !=0 PC = imm16(BE) ------------------------------
OpDjnz:
    movbu   (a2), d3                # id
    inc     a2
    movbu   (a2), d0                # hi
    inc     a2
    asl     8, d0
    movbu   (a2), d1                # lo
    inc     a2
    or      d1, d0
    mov     d0, d2                  # target
    mov     d3, d0
    call    ReadVar, 0, 0
    add     -1, d0
    and     0xffff, d0
    mov     d0, d1
    mov     d3, d0
    mov     d1, d3                  # keep new value in d3
    call    WriteVar, 0, 0
    cmp     0, d3
    beq     ei_end
    movhu   d2, (VM_PC)
    bra     ei_ret

# ---- 0x0A COND_JUMP -----------------------------------------------------------
# sub(0), v, c, target(BE). b = var[v]. a depends on subopcode bits 7/6.
OpCondJump:
    movbu   (a2), d3                # subopcode
    inc     a2
    movbu   (a2), d0                # v
    inc     a2
    call    ReadVar, 0, 0           # d0 = b = var[v]
    mov     d0, (0xc, sp)             # stash b
    movbu   (a2), d2                # c
    inc     a2
    # determine a
    mov     d3, d0
    and     0x80, d0
    beq     cj_not_var
    mov     d2, d0
    call    ReadVar, 0, 0           # a = var[c]
    bra     cj_have_a
cj_not_var:
    mov     d3, d0
    and     0x40, d0
    beq     cj_byte
    # a = (c<<8)|fetch_byte
    mov     d2, d0
    asl     8, d0
    movbu   (a2), d1
    inc     a2
    or      d1, d0
    bra     cj_have_a
cj_byte:
    mov     d2, d0                  # a = c (zero-extended)
cj_have_a:
    mov     d0, d2                  # d2 = a (RHS)
    # fetch target (big-endian), advancing past it so the fall-through PC is correct
    movbu   (a2), d0
    movbu   (1, a2), d1
    add     2, a2
    asl     8, d0
    or      d1, d0
    mov     d0, (4, sp)             # stash target
    mov     (0xc, sp), d1             # d1 = b (LHS)
    # sign-extend both to 32-bit for signed compares
    exth    d1
    exth    d2
    and     7, d3                   # comparison type
    cmp     0, d3
    bne     cj_c1
    cmp     d2, d1
    beq     cj_take
    bra     ei_end
cj_c1:
    cmp     1, d3
    bne     cj_c2
    cmp     d2, d1
    bne     cj_take
    bra     ei_end
cj_c2:
    cmp     2, d3
    bne     cj_c3
    cmp     d2, d1
    bgt     cj_take
    bra     ei_end
cj_c3:
    cmp     3, d3
    bne     cj_c4
    cmp     d2, d1
    bge     cj_take
    bra     ei_end
cj_c4:
    cmp     4, d3
    bne     cj_c5
    cmp     d2, d1
    blt     cj_take
    bra     ei_end
cj_c5:
    cmp     d2, d1                  # case 5 (and default): le
    ble     cj_take
    bra     ei_end
cj_take:
    mov     (4, sp), d0
    movhu   d0, (VM_PC)
    bra     ei_ret

# ---- 0x0B SET_PALETTE: SETUP_PALETTE(first byte of the BE word) ---------------
OpSetPalette:
    movbu   (a2), d0                # palette index = first byte
    add     2, a2                   # skip 2-byte word
    call    SetupPalette, 0, 0
    bra     ei_end

# ---- 0x0C RESET_THREAD: freeze/unfreeze/delete thread range [first..last] -----
OpResetThread:
    movbu   (a2), d2                # first
    inc     a2
    movbu   (a2), d3                # last
    inc     a2
    and     0x3f, d3
    movbu   (a2), d0                # type
    inc     a2
    cmp     0, d0
    bne     ort_not0
    # type 0: unfreeze
ort_unf:
    mov     d2, d0
    asl     1, d0
    mov     VM_CHAN_STATE, a3
    add     d0, a3
    mov     ST_NOT_FROZEN, d0
    movbu   d0, (REQ_STATE, a3)
    inc     d2
    cmp     d3, d2
    ble     ort_unf
    bra     ei_end
ort_not0:
    cmp     1, d0
    bne     ort_del
    # type 1: freeze
ort_frz:
    mov     d2, d0
    asl     1, d0
    mov     VM_CHAN_STATE, a3
    add     d0, a3
    mov     ST_FROZEN, d0
    movbu   d0, (REQ_STATE, a3)
    inc     d2
    cmp     d3, d2
    ble     ort_frz
    bra     ei_end
ort_del:
    # type 2 (and others): delete (requested_pc = DELETE_THREAD)
ort_dloop:
    mov     d2, d0
    asl     2, d0
    mov     THREADS_DATA, a3
    add     d0, a3
    mov     DELETE_THREAD, d0
    movhu   d0, (REQ_PC_OFFSET, a3)
    inc     d2
    cmp     d3, d2
    ble     ort_dloop
    bra     ei_end

# ---- 0x0D SELECT_VIDEO_PAGE: CUR_PAGE_1 = page(id) ----------------------------
OpSelectPage:
    movbu   (a2), d0
    inc     a2
    call    GetPagePtr, 0, 0
    mov     a0, (CUR_PAGE_1)
    bra     ei_end

# ---- 0x0E FILL_VIDEO_PAGE: fill page(id) with colour --------------------------
OpFillPage:
    movbu   (a2), d0                # pageId
    inc     a2
    movbu   (a2), d1                # colour
    inc     a2
    call    FillPageOp, 0, 0
    bra     ei_end

# ---- 0x0F COPY_VIDEO_PAGE: copy src -> dst ------------------------------------
OpCopyPage:
    movbu   (a2), d0                # srcId
    inc     a2
    movbu   (a2), d1                # dstId
    inc     a2
    call    CopyPage, 0, 0
    bra     ei_end

# ---- 0x10 BLIT_FRAMEBUFFER: UpdateDisplay(pageId) -----------------------------
OpBlit:
    movbu   (a2), d0                # pageId
    inc     a2
    call    UpdateDisplay, 0, 0
    bra     ei_end

# ---- 0x11 KILL_THREAD ---------------------------------------------------------
OpKillThread:
    movbu   (CURRENT_THREAD), d0
    asl     2, d0
    mov     THREADS_DATA, a3
    add     d0, a3
    mov     INACTIVE_THREAD, d0
    movhu   d0, (PC_OFFSET, a3)
    call    NextThread, 0, 0
    bra     ei_ret

# ---- 0x12 DRAW_STRING: stringId(BE), x, y, colour -----------------------------
OpDrawString:
    # operands: stringId (BE word), x (byte, char column), y (byte, pixels), colour.
    # DrawString preserves a2 (its movm/ret save-set), so the cursor survives the call.
    movbu   (a2), d0                # stringId hi
    movbu   (1, a2), d1             # stringId lo
    asl     8, d0
    or      d1, d0                  # d0 = stringId
    movbu   (2, a2), d1             # x (char column)
    movbu   (3, a2), d2             # y (pixels)
    movbu   (4, a2), d3             # colour
    add     5, a2
    call    DrawString, 0, 0
    bra     ei_end

# ---- 0x13 SUB: var[dst] -= var[src] -------------------------------------------
OpSub:
    movbu   (a2), d3                # dst
    inc     a2
    movbu   (a2), d0                # src
    inc     a2
    call    ReadVar, 0, 0
    mov     d0, d2                  # src value
    mov     d3, d0
    call    ReadVar, 0, 0
    sub     d2, d0
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x14 AND: var[id] &= imm16(BE) -------------------------------------------
OpAnd:
    movbu   (a2), d3
    inc     a2
    movbu   (a2), d0
    inc     a2
    asl     8, d0
    movbu   (a2), d1
    inc     a2
    or      d1, d0
    mov     d0, d2                  # imm
    mov     d3, d0
    call    ReadVar, 0, 0
    and     d2, d0
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x15 OR: var[id] |= imm16(BE) --------------------------------------------
OpOr:
    movbu   (a2), d3
    inc     a2
    movbu   (a2), d0
    inc     a2
    asl     8, d0
    movbu   (a2), d1
    inc     a2
    or      d1, d0
    mov     d0, d2                  # imm
    mov     d3, d0
    call    ReadVar, 0, 0
    or      d2, d0
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x16 SHL: var[id] <<= amount(low byte of BE word) ------------------------
OpShl:
    movbu   (a2), d3
    inc     a2
    add     1, a2                   # skip hi byte of the shift word
    movbu   (a2), d2                # amount (low byte)
    inc     a2
    mov     d3, d0
    call    ReadVar, 0, 0
    and     0xffff, d0
    and     0x0f, d2
    cmp     0, d2
    beq     shl_done
shl_loop:
    asl     1, d0
    add     -1, d2
    bne     shl_loop
shl_done:
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x17 SHR: var[id] >>= amount(low byte of BE word) ------------------------
OpShr:
    movbu   (a2), d3
    inc     a2
    add     1, a2                   # skip hi byte
    movbu   (a2), d2                # amount
    inc     a2
    mov     d3, d0
    call    ReadVar, 0, 0
    exth    d0                      # arithmetic shift (signed var)
    and     0x0f, d2
    cmp     0, d2
    beq     shr_done
shr_loop:
    asr     1, d0
    add     -1, d2
    bne     shr_loop
shr_done:
    mov     d0, d1
    mov     d3, d0
    call    WriteVar, 0, 0
    bra     ei_end

# ---- 0x18 PLAY_SOUND: not supported; skip 5 bytes -----------------------------
OpPlaySound:
    add     5, a2
    bra     ei_end

# ---- 0x19 LOAD: resource load / part switch -----------------------------------
# We run only the intro from AWDATA, and screen-bitmap resources are not loaded in
# this build, so: resourceId 0 = no-op; > NUM_MEM_LIST = part switch request (we
# ignore, single part); otherwise ignore (screen bitmaps unsupported here).
OpLoad:
    movbu   (a2), d0
    movbu   (1, a2), d1
    add     2, a2
    asl     8, d0
    or      d1, d0                  # d0 = resourceId
    cmp     0, d0
    beq     ei_end
    cmp     0x91, d0                # NUM_MEM_LIST
    ble     ei_end                  # known resource / screen: ignore (not loaded)
    movhu   d0, (REQ_NEXT_PART)     # part switch request (unused with one part)
    bra     ei_end

# ---- 0x1A PLAY_MUSIC: not supported; skip 5 bytes -----------------------------
OpPlayMusic:
    add     5, a2
    bra     ei_end

# ================================================================================
# Op80 / Op40: the two VIDEO opcodes. They parse x/y/zoom from the stream, set up
# the polygon data pointer, then call ReadAndDrawPolygon (in vm.s). d1 = opcode.
#
# ReadAndDrawPolygon args (our convention): a0 = polygon data pointer, d0 = x (s16),
# d1 = y (s16), d2 = colour (0xFF = use embedded), CUR_ZOOM set in memory.

# ---- 0x80 ---------------------------------------------------------------------
Op80:
    # offset_raw = (opcode<<8)|next ; x = next ; y = next
    mov     d1, d3                  # opcode
    asl     8, d3
    movbu   (a2), d0
    inc     a2
    or      d0, d3                  # d3 = offset_raw
    movbu   (a2), d0                # x
    inc     a2
    mov     d0, (0xc, sp)             # stash x
    movbu   (a2), d0                # y
    inc     a2
    mov     d0, (4, sp)             # stash y
    # VM_PC = cursor - CUR_BYTECODE  (all 4 bytes consumed)
    mov     a2, d0
    mov     (CUR_BYTECODE), a1
    mov     a1, d1
    sub     d1, d0
    movhu   d0, (VM_PC)
    # polygon pointer = CUR_VIDEO_1 + offset_raw*2 (u16 wrap)
    mov     d3, d0
    asl     1, d0
    and     0xffff, d0
    mov     (CUR_VIDEO_1), a0
    add     d0, a0
    # y>199 adjust: x += y-199 ; y = 199
    mov     (0xc, sp), d0             # x
    mov     (4, sp), d1             # y
    cmp     199, d1
    ble     o80_yok
    add     d1, d0
    add     -199, d0
    mov     199, d1
o80_yok:
    mov     0x40, d2
    movhu   d2, (CUR_ZOOM)
    clr     d3                      # reset the per-op polygon budget + recursion depth
    mov     DRAW_BUDGET, a1
    mov     d3, (a1)
    mov     DRAW_DEPTH, a1
    mov     d3, (a1)
    mov     0xFF, d2                # colour = BLACK/embedded
    call    ReadAndDrawPolygon, 0, 0
    bra     ei_ret

# ---- 0x40 ---------------------------------------------------------------------
Op40:
    mov     d1, d3                  # opcode (bit6 set); bits control x/y/zoom modes
    # offset = fetch_word(BE) * 2
    movbu   (a2), d0
    inc     a2
    asl     8, d0
    movbu   (a2), d1
    inc     a2
    or      d1, d0
    asl     1, d0
    and     0xffff, d0
    mov     d0, (8, sp)             # stash offset*2
    # x = fetch_byte, then addressing mode by bits 5,4
    movbu   (a2), d0                # x byte
    inc     a2
    mov     d3, d1
    and     0x20, d1
    bne     o40_x_b5
    mov     d3, d1
    and     0x10, d1
    bne     o40_x_var
    # 16-bit immediate: x = (x<<8)|fetch
    asl     8, d0
    movbu   (a2), d1
    inc     a2
    or      d1, d0
    bra     o40_x_done
o40_x_var:
    call    ReadVar, 0, 0           # x = var[x]
    bra     o40_x_done
o40_x_b5:
    mov     d3, d1
    and     0x10, d1
    beq     o40_x_done
    add     0x100, d0               # x += 0x100
o40_x_done:
    mov     d0, (0xc, sp)             # stash x
    # y = fetch_byte, addressing by bits 3,2
    movbu   (a2), d0                # y byte
    inc     a2
    mov     d3, d1
    and     0x08, d1
    bne     o40_y_done
    mov     d3, d1
    and     0x04, d1
    bne     o40_y_var
    # 16-bit immediate
    asl     8, d0
    movbu   (a2), d1
    inc     a2
    or      d1, d0
    bra     o40_y_done
o40_y_var:
    call    ReadVar, 0, 0           # y = var[y]
o40_y_done:
    mov     d0, (4, sp)             # stash y
    # zoom mode by bits 1,0 ; default 0x40 ; default data = CUR_VIDEO_DATA
    mov     0x40, d0
    movhu   d0, (CUR_ZOOM)
    mov     (CUR_VIDEO_1), a0
    mov     a0, (CUR_VIDEO_DATA)
    mov     d3, d0
    and     3, d0
    cmp     0, d0
    beq     o40_zoom_done
    cmp     1, d0
    bne     o40_z_not1
    # zoom = var[fetch_byte]
    movbu   (a2), d0
    inc     a2
    call    ReadVar, 0, 0
    movhu   d0, (CUR_ZOOM)
    bra     o40_zoom_done
o40_z_not1:
    cmp     2, d0
    bne     o40_z_c3
    # zoom = fetch_byte
    movbu   (a2), d0
    inc     a2
    movhu   d0, (CUR_ZOOM)
    bra     o40_zoom_done
o40_z_c3:
    # case 3: use CUR_VIDEO_2, zoom stays 0x40
    mov     (CUR_VIDEO_2), a0
    mov     a0, (CUR_VIDEO_DATA)
o40_zoom_done:
    # VM_PC = cursor - CUR_BYTECODE
    mov     a2, d0
    mov     (CUR_BYTECODE), a1
    mov     a1, d1
    sub     d1, d0
    movhu   d0, (VM_PC)
    # data pointer = CUR_VIDEO_DATA + offset
    mov     (8, sp), d0             # offset*2
    mov     (CUR_VIDEO_DATA), a0
    add     d0, a0
    mov     (0xc, sp), d0             # x
    mov     (4, sp), d1             # y
    clr     d2                      # reset the per-op polygon budget + recursion depth
    mov     DRAW_BUDGET, a1
    mov     d2, (a1)
    mov     DRAW_DEPTH, a1
    mov     d2, (a1)
    mov     0xFF, d2                # colour
    call    ReadAndDrawPolygon, 0, 0
    # reset CUR_VIDEO_DATA to CUR_VIDEO_1
    mov     (CUR_VIDEO_1), a0
    mov     a0, (CUR_VIDEO_DATA)
    bra     ei_ret
