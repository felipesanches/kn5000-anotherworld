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
#   0xFF -> CUR_PAGE_3 (back), 0xFE -> CUR_PAGE_2 (front), anything else -> page (id & 3).
# The &3 matches Another World's PageSelector::from (Page(e & 0x3)): the 0x40/0x80 bits a
# copyVideoPage source carries are NOT page bits, so e.g. 0x83 is page 3, not page 0.
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
    and     3, d0
    asl     16, d0                  # (id & 3) * 0x10000  (page stride)
    mov     PAGE_BITMAP_0, a0
    add     d0, a0                  # a0 = PAGE_BITMAP_0 + (id & 3) * 0x10000
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
# PartTable: per part 0x3E80..0x3E89, the resource ids of its palette, bytecode, video1 and
# video2 (0 = none) -- the original engine's part list (rustyworld GAME_PARTS, rawgl).
PartTable:
    .byte   0x14, 0x15, 0x16, 0x00  # 0x3E80 protection (code wheel)
    .byte   0x17, 0x18, 0x19, 0x00  # 0x3E81 intro
    .byte   0x1A, 0x1B, 0x1C, 0x11  # 0x3E82 water (first playable)
    .byte   0x1D, 0x1E, 0x1F, 0x11  # 0x3E83 prison
    .byte   0x20, 0x21, 0x22, 0x11  # 0x3E84 city
    .byte   0x23, 0x24, 0x25, 0x00  # 0x3E85 arena
    .byte   0x26, 0x27, 0x28, 0x11  # 0x3E86 baths
    .byte   0x29, 0x2A, 0x2B, 0x11  # 0x3E87 final
    .byte   0x7D, 0x7E, 0x7F, 0x00  # 0x3E88 password screen
    .byte   0x7D, 0x7E, 0x7F, 0x00  # 0x3E89 password screen
    .align  4

# ResPtr(d0 = resource id) -> a0 = where the resource is resident (ResAddr, awres.inc).
ResPtr:
    and     0xff, d0
    asl     2, d0
    mov     ResAddr, a0
    add     d0, a0
    mov     (a0), a0
    rets

# LoadBitmap(d0 = resource id): draw a 320x200 screen bitmap into page 0, as the original
# engine's copyBitmapPtr. The MS-DOS bitmap is four 8000-byte bit planes; plane k supplies
# bit k of every pixel, and within a byte the MSB is the leftmost of its 8 pixels
# (rustyworld video.rs load_bg). Page 0 is cleared, then each plane ORs its bit in. The
# platform's BitmapData gives the planes (the KN7APP.BIN build keeps bitmaps packed and
# unpacks one here); a bitmap that is not there leaves page 0 alone.
LoadBitmap:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2
    mov     PH_PAGE, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
    mov     d2, d0
    call    BitmapData, 0, 0        # d0 = id -> a0 = the 32,000 bytes of planes, or 0
    cmp     0, a0
    beq     lb_ret
    mov     a0, a2                  # a2 = next plane byte (the planes are consecutive)
    mov     PAGE_BITMAP_0, a0
    call    PerfMarkDirty, 0, 0
    mov     PAGE_BITMAP_0, a3
    mov     PAGE_SIZE / 4, d2
    clr     d0
lb_clear:
    mov     d0, (a3)
    add     4, a3
    add     -1, d2
    bne     lb_clear
    mov     1, d3                   # d3 = this plane's pixel bit: 1, 2, 4, 8
lb_plane:
    mov     PAGE_BITMAP_0, a3       # a3 = first of the 8 pixels the byte covers
    mov     PAGE_SIZE / 8, d2       # 8000 bytes per plane
lb_byte:
    movbu   (a2), d1
    inc     a2
    btst    0x80, d1
    beq     lb_b6
    movbu   (0, a3), d0
    or      d3, d0
    movbu   d0, (0, a3)
lb_b6:
    btst    0x40, d1
    beq     lb_b5
    movbu   (1, a3), d0
    or      d3, d0
    movbu   d0, (1, a3)
lb_b5:
    btst    0x20, d1
    beq     lb_b4
    movbu   (2, a3), d0
    or      d3, d0
    movbu   d0, (2, a3)
lb_b4:
    btst    0x10, d1
    beq     lb_b3
    movbu   (3, a3), d0
    or      d3, d0
    movbu   d0, (3, a3)
lb_b3:
    btst    0x08, d1
    beq     lb_b2
    movbu   (4, a3), d0
    or      d3, d0
    movbu   d0, (4, a3)
lb_b2:
    btst    0x04, d1
    beq     lb_b1
    movbu   (5, a3), d0
    or      d3, d0
    movbu   d0, (5, a3)
lb_b1:
    btst    0x02, d1
    beq     lb_b0
    movbu   (6, a3), d0
    or      d3, d0
    movbu   d0, (6, a3)
lb_b0:
    btst    0x01, d1
    beq     lb_next
    movbu   (7, a3), d0
    or      d3, d0
    movbu   d0, (7, a3)
lb_next:
    add     8, a3
    add     -1, d2
    bne     lb_byte
    asl     1, d3
    cmp     0x10, d3
    bne     lb_plane
lb_ret:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# ================================================================================
# InitForPart(d0 = partId): make the part's resources resident (the platform's EnsurePart: a
# no-op where everything is resident, a load from the SD card in the KN7APP.BIN build), reset
# threads and point the VM at them (PartTable). An id outside 0x3E80..0x3E89 is ignored.
InitForPart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    and     0xffff, d0
    cmp     PART_FIRST, d0
    blt     ifp_ret
    cmp     PART_LAST, d0
    bgt     ifp_ret
    mov     d0, d2
    call    AudioStopAll, 0, 0      # nothing sounds across a part switch (rawgl restartAt), and the
    mov     d2, d0                  # module player must not read MUSIC_BUF while the next part loads
    call    EnsurePart, 0, 0        # d0 = partId; returns once its resources are resident
    mov     d2, d0
    movhu   d0, (CURRENT_PART_ID)
    mov     PREV_LR_BITS, a0        # reset the sticky direction state on a part switch
    clr     d1
    movhu   d1, (a0)
    mov     PREV_UD_BITS, a0
    movhu   d1, (a0)
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
    # resource pointers for this part, from PartTable
    movhu   (CURRENT_PART_ID), d0
    add     -PART_FIRST, d0
    asl     2, d0
    mov     PartTable, a2
    add     d0, a2                  # a2 = this part's {palette, bytecode, video1, video2}
    movbu   (a2), d0
    call    ResPtr, 0, 0
    mov     a0, (CUR_PALETTES)
    movbu   (1, a2), d0
    call    ResPtr, 0, 0
    mov     a0, (CUR_BYTECODE)
    movbu   (2, a2), d0
    call    ResPtr, 0, 0
    mov     a0, (CUR_VIDEO_DATA)
    mov     a0, (CUR_VIDEO_1)
    # video2 is the shared polygon resource 0x11. Parts listed without one never draw from it;
    # the original engine leaves its pointer as it was, so keep it valid for every part.
    mov     RES_VIDEO2, d0
    call    ResPtr, 0, 0
    mov     a0, (CUR_VIDEO_2)
ifp_ret:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# GameReset: zero VM vars, set up threads, apply the copy-protection bypass vars,
# and start on the intro part.
GameReset:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (GUARD_WHAT)        # a new game: nothing refused yet
    mov     d0, (GUARD_ADDR)
    mov     d0, (GUARD_COUNT)
    mov     TRACE_COUNT, a0         # reset the instruction trace
    mov     d0, (a0)
    mov     FRAME_NO, a0
    mov     d0, (a0)
    mov     PREV_LR_BITS, a0        # reset the sticky direction state
    movhu   d0, (a0)
    mov     PREV_UD_BITS, a0
    movhu   d0, (a0)
    call    NotesInit, 0, 0         # start tracking keybed + MIDI notes afresh
    call    AudioInit, 0, 0         # sound on, nothing playing (audio.s)
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
    mov     (NO_SPLASH), d0         # a probe asked for the old start: the intro at tick 0
    mov     NO_SPLASH_MAGIC, d1
    cmp     d1, d0
    beq     gr_intro
    # Splash, as the KN5000 port: the copy-protection part's logo and credits sequence, which
    # loads the intro when it ends (or when action is pressed). Thread 0 starts at SPLASH_PC
    # instead of 0x0000 (whose thread 20 is the code wheel); 0x0000 would also have started the
    # display loop on thread 60 and set var[0xFF] = 2, so do those here.
    mov     PART_PROTECTION, d0
    call    InitForPart, 0, 0
    mov     THREADS_DATA, a2
    mov     SPLASH_PC, d1
    movhu   d1, (PC_OFFSET, a2)
    movhu   d1, (VM_PC)             # thread 0 is the one about to run: its live PC too
    mov     SPLASH_LOOP_PC, d1
    movhu   d1, (60 * 4 + PC_OFFSET, a2)
    mov     VAR_PAUSE_SLICES, d0
    mov     2, d1
    call    WriteVar, 0, 0
    ret     [d2,d3,a2,a3], 0x20
gr_intro:
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
# The colour byte in all four bytes of a word, 8 words a turn (pages are 0x10000-aligned). Phase PAGE.
FillPageOp:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d1, d3                  # save colour
    mov     d0, d2
    mov     PH_PAGE, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
    mov     d2, d0
    call    GetPagePtr, 0, 0        # d0 = pageId -> a0 = page
    call    GuardPage, 0, 0         # refuse a page pointer that is not a page
    cmp     0, d0
    bne     fpo_ret
    call    PerfMarkDirty, 0, 0
    mov     a0, a2
    and     0xff, d3
    mov     0x01010101, d0
    mul     d0, d3                  # d3 = the colour, four times
    mov     PAGE_SIZE / 32, d2
fpo_loop:
    mov     d3, (a2)
    mov     d3, (4, a2)
    mov     d3, (8, a2)
    mov     d3, (12, a2)
    mov     d3, (16, a2)
    mov     d3, (20, a2)
    mov     d3, (24, a2)
    mov     d3, (28, a2)
    add     32, a2
    add     -1, d2
    bne     fpo_loop
fpo_ret:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# ================================================================================
# CopyPage(d0 = srcId, d1 = dstId): copy one page to another, matching Another World's
# copyVideoPage. GetPagePtr resolves ids (0xFE front / 0xFF back / else id&3). When
# srcId < 0xFE and bit 0x80 is set, the copy is shifted vertically by VAR_SCROLL_Y
# (var 0xF9) -- the water part uses src=0x83 each scroll frame to carry the whole
# composited scene (background + sprites) forward. Without this the dynamic layer is
# lost every scroll frame. Self-copies (src page == dst page) are a no-op.
CopyPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2                  # srcId (raw; keep for the scroll-flag test)
    mov     d1, d3
    mov     PH_PAGE, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
    mov     d3, d0                  # dstId
    call    GetPagePtr, 0, 0
    mov     a0, a3                  # a3 = dst base
    mov     d2, d0                  # srcId
    call    GetPagePtr, 0, 0
    mov     a0, a2                  # a2 = src base
    call    GuardPage, 0, 0         # refuse page pointers that are not pages
    cmp     0, d0
    bne     cp_ret
    mov     a3, a0
    call    GuardPage, 0, 0
    cmp     0, d0
    bne     cp_ret
    call    PerfMarkDirty, 0, 0     # a0 = the destination
    # self-copy guard (matches the oracle's early returns)
    mov     a2, d0
    mov     a3, d1
    cmp     d0, d1
    beq     cp_ret
    # vscroll = (srcId < 0xFE && srcId & 0x80) ? (s16)var[0xF9] : 0
    clr     d3
    mov     d2, d0
    and     0xff, d0
    cmp     0xfe, d0
    bge     cp_novscroll            # 0xFE/0xFF: no scroll
    and     0x80, d0
    beq     cp_novscroll
    mov     0xF9, d0
    call    ReadVar, 0, 0           # d0 = var[0xF9]
    exth    d0                      # sign-extend to s32
    mov     d0, d3                  # d3 = vscroll
cp_novscroll:
    cmp     0, d3
    bne     cp_scrolled
    # plain full-page copy, 32-bit words, 8 a turn (pages are 0x10000-aligned, PAGE_SIZE % 32 == 0)
    mov     PAGE_SIZE/32, d2
cp_loop:
    mov     (a2), d0
    mov     (4, a2), d1
    mov     d0, (a3)
    mov     d1, (4, a3)
    mov     (8, a2), d0
    mov     (12, a2), d1
    mov     d0, (8, a3)
    mov     d1, (12, a3)
    mov     (16, a2), d0
    mov     (20, a2), d1
    mov     d0, (16, a3)
    mov     d1, (20, a3)
    mov     (24, a2), d0
    mov     (28, a2), d1
    mov     d0, (24, a3)
    mov     d1, (28, a3)
    add     32, a2
    add     32, a3
    add     -1, d2
    bne     cp_loop
    bra     cp_ret
cp_scrolled:
    # abs(vscroll) in d2; direction kept in d3 (sign). The original engine copies only for
    # -199 <= vscroll <= 199 and skips the copy otherwise (raw/rawgl Video::copyPage); the
    # final part scrolls past that range.
    mov     d3, d2
    cmp     0, d3
    bge     cp_absrange
    clr     d0
    sub     d2, d0                  # -vscroll
    mov     d0, d2
cp_absrange:
    cmp     199, d2
    bgt     cp_ret
cp_off:
    # off_bytes = abs*320 -> a1
    mov     d2, d0
    asl     8, d0                   # abs*256
    mov     d2, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0                  # abs*64
    add     a0, d0                  # abs*320
    mov     d0, a1                  # a1 = off_bytes
    # n_bytes = (200-abs)*320 -> d2
    mov     200, d0
    sub     d2, d0                  # n_rows
    mov     d0, d1
    asl     8, d1                   # n_rows*256
    mov     d0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0
    add     a0, a0                  # n_rows*64
    add     a0, d1                  # n_rows*320
    mov     d1, d2                  # d2 = n_bytes
    # vscroll >= 0 shifts content DOWN (dst += off); < 0 shifts UP (src += off)
    cmp     0, d3
    blt     cp_up
    add     a1, a3
    bra     cp_scopy
cp_up:
    add     a1, a2
cp_scopy:
    lsr     2, d2                   # n_words = n_bytes / 4 (both offsets are 320-aligned)
    cmp     0, d2
    beq     cp_ret
cp_sloop:
    mov     (a2), d0
    mov     d0, (a3)
    add     4, a2
    add     4, a3
    add     -1, d2
    bne     cp_sloop
cp_ret:
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# ================================================================================
# ReadInput: feed KN7000 controls to the Another World hero variables.
#
#   * Intro (0x3E81): any held keybed/MIDI key -> fire, so the player can skip the intro.
#     The intro bytecode polls var[0xFE] (ACTION_MASK) and jumps to the first playable
#     part.
#   * Every other part: the keybed/MIDI note map drives a full D-pad + fire; the six hero
#     variables are written exactly as rustyworld's update_player does. The original engine
#     reads input the same way in every part. No control-panel button moves the player (they
#     did until 2026-10-21: R1/R2 OCTAVE +/-, PART SELECT LEFT / RIGHT 1, SUSTAIN); the panel
#     keeps HELP, OTHER PART & FR, PAGE UP/DOWN, PART SELECT RIGHT 2 and EXIT.
# Keys come from the note trackers (vm.inc NOTES_*), brought up to date here each frame.
ReadInput:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    PerfInput, 0, 0         # PAGE UP: the speed overlay; PAGE DOWN: the blit mode (perf.s)
    mov     (FWV_PANEL), a0         # HELP: pause and show the help screens (help.s)
    movbu   (BTN_HELP_OFS, a0), d0
    and     BTN_HELP_BIT, d0
    beq     ri_nohelp
    call    HelpScreen, 0, 0
ri_nohelp:
    mov     (FWV_PANEL), a0         # OTHER PART & FR: the level-code screen, as the DOS
    movbu   (BTN_CODES_OFS, a0), d0
    and     BTN_CODES_BIT, d0       # game's C key -- not from the protection or code screens
    beq     ri_nocodes
    movhu   (CURRENT_PART_ID), d0
    cmp     PART_PROTECTION, d0
    beq     ri_nocodes
    cmp     PART_PASSWORD, d0
    bge     ri_nocodes              # 0x3E88 / 0x3E89 (the last part ids)
    mov     PART_PASSWORD, d0
    movhu   d0, (REQ_NEXT_PART)
ri_nocodes:
    movhu   (CURRENT_PART_ID), d0
    cmp     0x3E81, d0
    bne     ri_gameplay

# ---- intro: any keybed/MIDI key = fire (skip) ----
ri_intro:
    call    NotePoll, 0, 0
    clr     d0                      # any note 0..127 held?
    mov     127, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     ri_clear
    mov     VAR_HERO_ACTION, d0     # var[0xFA] = 1
    mov     1, d1
    call    WriteVar, 0, 0
    mov     VAR_HERO_ACT_MASK, d0   # var[0xFE] = 0x80 (fire)
    mov     0x80, d1
    call    WriteVar, 0, 0
    bra     ri_ret
ri_clear:
    mov     VAR_HERO_ACTION, d0
    clr     d1
    call    WriteVar, 0, 0
    mov     VAR_HERO_ACT_MASK, d0
    clr     d1
    call    WriteVar, 0, 0
    bra     ri_ret

# ---- gameplay: keybed/MIDI D-pad + fire. Build the AW input mask in d2, then derive and
#      write the six hero variables (d2 is preserved across WriteVar). ----
ri_gameplay:
    clr     d2                      # d2 = OR of held inputs' AW masks (the keybed and MIDI IN only:
                                    # no panel button is a game control, Felipe 2026-10-21)
    # --- fold in the held keybed/MIDI notes: note <= 60 (bass + C4) = action; F5 left,
    #     A5 down, C6 right, Ab5/Bb5 up. Every held direction's bit is OR'd in; an opposing
    #     pair is left for the sticky derive below, and diagonals keep both bits. ---
    call    NotePoll, 0, 0          # bring the note trackers up to date
    clr     d3                      # note mask accumulator
    clr     d0                      # action: any note 0..KBD_ACTION_MAX
    mov     KBD_ACTION_MAX, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     rkb_na
    or      0x80, d3
rkb_na:
    mov     KBD_LEFT_NOTE, d0
    mov     d0, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     rkb_nl
    or      2, d3
rkb_nl:
    mov     KBD_DOWN_NOTE, d0
    mov     d0, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     rkb_nd
    or      4, d3
rkb_nd:
    mov     KBD_UP_NOTE_A, d0       # Ab5 -> up
    mov     d0, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     rkb_nua
    or      8, d3
rkb_nua:
    mov     KBD_UP_NOTE_B, d0       # Bb5 -> up (not a range: A5 between them is DOWN)
    mov     d0, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     rkb_nu
    or      8, d3
rkb_nu:
    mov     KBD_RIGHT_NOTE, d0
    mov     d0, d1
    call    NotesAnyHeld, 0, 0
    cmp     0, d0
    beq     rkb_done
    or      1, d3
rkb_done:
    or      d3, d2                  # d2 = the note mask
    # d2 = the note mask (bits R=1 L=2 D=4 U=8 A=0x80), possibly with BOTH bits of
    # an axis set when opposing keys are held at once. Resolve each axis with a STICKY rule:
    # one direction alone wins; both held keeps the LAST-APPLIED direction (PREV_*_BITS) until a
    # key is released; neither = 0. Sticky is deterministic and brush-proof: a quick brush of
    # the opposite key never changes the direction you are already holding. d3 accumulates the
    # RESOLVED mask (one bit per axis + action) for var[0xFD]/[0xFE], matching the hero deltas
    # the way a joystick (which cannot hold opposing directions) would. Diagonals (different
    # axes) keep both.
    clr     d3                      # resolved-mask accumulator
    # --- L/R (var[0xFC]) ---
    mov     d2, d1
    and     3, d1                   # d1 = L/R bits held (0/1/2/3)
    cmp     3, d1
    bne     rig_lr_ok
    movhu   (PREV_LR_BITS), d1      # both held -> keep the last-applied L/R bit
rig_lr_ok:
    movhu   d1, (PREV_LR_BITS)      # remember the resolved bit
    or      d1, d3                  # resolved mask |= L/R bit
    cmp     1, d1                   # right(1) -> +1, left(2) -> -1, else 0
    beq     rig_lr_vr
    cmp     2, d1
    beq     rig_lr_vl
    clr     d1
    bra     rig_lr_vw
rig_lr_vr:
    mov     1, d1
    bra     rig_lr_vw
rig_lr_vl:
    mov     -1, d1
rig_lr_vw:
    mov     VAR_HERO_LR, d0
    call    WriteVar, 0, 0
    # --- U/D (var[0xE5]) ---
    mov     d2, d1
    and     0xC, d1                 # d1 = U/D bits held (0/4/8/0xC)
    cmp     0xC, d1
    bne     rig_ud_ok
    movhu   (PREV_UD_BITS), d1      # both held -> keep the last-applied U/D bit
rig_ud_ok:
    movhu   d1, (PREV_UD_BITS)
    or      d1, d3                  # resolved mask |= U/D bit
    cmp     4, d1                   # down(4) -> +1, up(8) -> -1, else 0
    beq     rig_ud_vd
    cmp     8, d1
    beq     rig_ud_vu
    clr     d1
    bra     rig_ud_vw
rig_ud_vd:
    mov     1, d1
    bra     rig_ud_vw
rig_ud_vu:
    mov     -1, d1
rig_ud_vw:
    mov     VAR_HERO_UD, d0
    call    WriteVar, 0, 0
    mov     VAR_HERO_JUMP, d0       # var[0xFB] = var[0xE5] (d1 still holds the UD value)
    call    WriteVar, 0, 0
    # --- action (var[0xFA]) ---
    mov     d2, d1
    and     0x80, d1
    beq     rig_act0
    or      0x80, d3                # resolved mask |= action bit
    mov     1, d1
    bra     rig_act_w
rig_act0:
    clr     d1
rig_act_w:
    mov     VAR_HERO_ACTION, d0
    call    WriteVar, 0, 0
    # --- masks: var[0xFD] and var[0xFE] = the resolved mask (d3) ---
    mov     VAR_HERO_POS_MASK, d0
    mov     d3, d1
    call    WriteVar, 0, 0
    mov     VAR_HERO_ACT_MASK, d0
    mov     d3, d1
    call    WriteVar, 0, 0
ri_ret:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# Note trackers (vm.inc NOTES_*): held keybed + MIDI notes from the firmware's MIDI rings.
#
# NotesInit: point each tracker at its ring. The read pointer is left 0, so the first poll
# syncs to the ring's newest byte and starts with no notes held.
NotesInit:
    mov     (FWV_MIDIIN1), d0
    mov     d0, (NOTES_MIDI + NS_HDR)
    mov     (FWV_MIDIOUT1), d0
    mov     d0, (NOTES_KBD + NS_HDR)
    clr     d0
    mov     d0, (NOTES_MIDI + NS_RP)
    mov     d0, (NOTES_KBD + NS_RP)
    rets

# NotePoll: parse the bytes both rings received since the last poll.
NotePoll:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     NOTES_MIDI, a0
    call    NotePollSource, 0, 0
    mov     NOTES_KBD, a0
    call    NotePollSource, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# NotePollSource(a0 = tracker): read the ring's new bytes from the tracker's own read pointer
# (the firmware's consumer is never touched) and apply them as MIDI: note-on sets the channel's
# bit in NS_MASK[note], note-off / note-on velocity 0 clears it, CC 120 and 123..127 (all
# sound / all notes off, mode changes) clear the channel. Running status as the MIDI spec has
# it: realtime bytes (>= 0xF8) are skipped, system bytes (0xF0..0xF7) cancel it. A read pointer
# outside the ring, or a backlog over half the ring (the ring was reset under us), resyncs to
# the newest byte with no notes held.
NotePollSource:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a3                  # a3 = tracker
    mov     (NS_HDR, a3), a0        # a0 = ring header
    mov     (QH_START, a0), d2      # d2 = start
    mov     (QH_LAST, a0), d3       # d3 = last
    mov     (QH_WR, a0), d1         # write pointer, sampled once (the producer may be an ISR)
    mov     d1, (0, sp)             # (0,sp) = wr (the loop makes no calls)
    cmp     0, d2
    beq     nps_ret                 # ring not set up by the firmware yet
    cmp     d2, d1
    blt     nps_ret                 # wr outside the ring: leave everything as it is
    cmp     d3, d1
    bgt     nps_ret
    mov     (NS_RP, a3), a2         # a2 = our read pointer
    mov     a2, d0
    cmp     d2, d0
    blt     nps_resync              # 0 (fresh) or outside the ring
    cmp     d3, d0
    bgt     nps_resync
    sub     d0, d1                  # d1 = backlog = wr - rp (mod ring size)
    bge     nps_nowrap
    add     d3, d1
    sub     d2, d1
    inc     d1
nps_nowrap:
    mov     d3, d0
    sub     d2, d0
    lsr     1, d0                   # half the ring
    cmp     d0, d1
    bgt     nps_resync
nps_loop:
    mov     a2, d0
    mov     (0, sp), d1
    cmp     d1, d0
    beq     nps_done                # caught up with the producer
    movbu   (a2), d0                # d0 = next byte
    mov     a2, d1
    cmp     d3, d1
    bne     nps_inc
    mov     d2, a2                  # wrap
    bra     nps_byte
nps_inc:
    inc     a2
nps_byte:
    cmp     0xF8, d0
    bge     nps_loop                # realtime: skipped, running status kept
    cmp     0xF0, d0
    bge     nps_sys
    cmp     0x80, d0
    bge     nps_status
    movbu   (NS_STATUS, a3), d1     # data byte
    cmp     0, d1
    beq     nps_loop                # no running status: not ours to interpret
    movbu   (NS_CNT, a3), d1
    cmp     0, d1
    bne     nps_second
    movbu   d0, (NS_D1, a3)         # first data byte
    movbu   (NS_STATUS, a3), d1
    and     0xE0, d1                # 0xC0/0xD0 (program change, channel pressure): one data byte
    cmp     0xC0, d1
    beq     nps_loop
    mov     1, d1
    movbu   d1, (NS_CNT, a3)
    bra     nps_loop
nps_sys:
    clr     d1
    movbu   d1, (NS_STATUS, a3)
    movbu   d1, (NS_CNT, a3)
    bra     nps_loop
nps_status:
    movbu   d0, (NS_STATUS, a3)
    clr     d1
    movbu   d1, (NS_CNT, a3)
    bra     nps_loop
nps_second:
    clr     d1                      # message complete; running status stays
    movbu   d1, (NS_CNT, a3)
    movbu   (NS_STATUS, a3), d1
    and     0xF0, d1
    cmp     0x90, d1
    beq     nps_noteon
    cmp     0x80, d1
    beq     nps_noteoff
    cmp     0xB0, d1
    bne     nps_loop
    movbu   (NS_D1, a3), d1         # control change: which controller?
    cmp     120, d1
    beq     nps_chanoff
    cmp     123, d1
    bge     nps_chanoff
    bra     nps_loop
nps_noteon:
    cmp     0, d0
    beq     nps_noteoff             # velocity 0 = note-off
    movbu   (NS_D1, a3), d0
    asl     1, d0
    mov     a3, a0
    add     d0, a0                  # a0 + NS_MASK = &mask[note]
    movbu   (NS_STATUS, a3), d1
    and     0x0F, d1
    mov     1, d0
    asl     d1, d0                  # d0 = 1 << channel
    movhu   (NS_MASK, a0), d1
    or      d0, d1
    movhu   d1, (NS_MASK, a0)
    bra     nps_loop
nps_noteoff:
    movbu   (NS_D1, a3), d0
    asl     1, d0
    mov     a3, a0
    add     d0, a0
    movbu   (NS_STATUS, a3), d1
    and     0x0F, d1
    mov     1, d0
    asl     d1, d0
    not     d0                      # d0 = ~(1 << channel)
    movhu   (NS_MASK, a0), d1
    and     d0, d1
    movhu   d1, (NS_MASK, a0)
    bra     nps_loop
nps_chanoff:
    movbu   (NS_STATUS, a3), d1
    and     0x0F, d1
    mov     1, d0
    asl     d1, d0
    not     d0                      # d0 = ~(1 << channel)
    mov     a3, a0
    add     NS_MASK, a0
    mov     128, d1
    mov     d1, (4, sp)
nps_coloop:
    movhu   (a0), d1
    and     d0, d1
    movhu   d1, (a0)
    add     2, a0
    mov     (4, sp), d1
    add     -1, d1
    mov     d1, (4, sp)
    cmp     0, d1
    bne     nps_coloop
    bra     nps_loop
nps_done:
    mov     a2, (NS_RP, a3)
nps_ret:
    ret     [d2,d3,a2,a3], 0x20
nps_resync:
    mov     (0, sp), d0
    mov     d0, (NS_RP, a3)         # continue from the newest byte
    clr     d0
    movbu   d0, (NS_STATUS, a3)
    movbu   d0, (NS_CNT, a3)
    mov     a3, a0
    add     NS_MASK, a0
    mov     128, d1
nps_rsclr:
    movhu   d0, (a0)
    add     2, a0
    add     -1, d1
    bne     nps_rsclr
    bra     nps_ret

# NotesAnyHeld(d0 = lowest note, d1 = highest note) -> d0 = OR of the channel masks of every
# note in [d0, d1] in both trackers: nonzero while any key in the range is held.
NotesAnyHeld:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    sub     d0, d1
    inc     d1                      # d1 = notes in the range
    asl     1, d0
    mov     NOTES_MIDI + NS_MASK, a0
    add     d0, a0
    mov     NOTES_KBD + NS_MASK, a1
    add     d0, a1
    clr     d0
nah_loop:
    movhu   (a0), d2
    and     MIDI_IN_CHANNELS, d2    # MIDI IN: the player's channels only (audio.s plays on 4-16 there)
    or      d2, d0
    movhu   (a1), d2
    or      d2, d0
    add     2, a0
    add     2, a1
    add     -1, d1
    bne     nah_loop
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# NextThread: advance CURRENT_THREAD to the next active, unfrozen thread. When the
# scan wraps past 63 it is end-of-frame: apply requested thread states/PCs and show
# the front page. Loads the chosen thread's PC into VM_PC.
NextThread:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    call    AudioPoll, 0, 0         # the music's rows and the notes' ends, between threads (audio.s)
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
    # Pace to the AW model: this frame should last var[0xFF] * SLICE_MS ms. Sleep only
    # the remainder after the work already done this frame (measured with the firmware's
    # 1 kHz counter, FWV_KERNEL_MS), clamped to [MIN_YIELD_MS, MAX_YIELD_MS] so the firmware always
    # gets time and a bad slice count can't freeze us. A frame that has overrun its time yields
    # only MIN_YIELD_MS (2 ms; 8 before 2026-10-20, and still in the old blit mode): the firmware's
    # tasks run when they are ready whatever the yield asks, and a longer one only spins. Then the
    # frame's end for the speed figures (perf.s), and the next frame's start.
    mov     VAR_PAUSE_SLICES, d0
    call    ReadVar, 0, 0           # d0 = var[0xFF] (slice count)
    and     0xffff, d0
    mov     SLICE_MS, d1
    mul     d1, d0                  # d0 = target_ms = slices * SLICE_MS
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d1                # now
    mov     (FRAME_START_MS), d2    # start of this frame
    sub     d2, d1                  # d1 = elapsed work ms
    sub     d1, d0                  # d0 = sleep_ms = target - elapsed
    mov     MIN_YIELD_MS, d1
    mov     (PF_MODE), d2
    cmp     0, d2
    beq     nt_floor
    mov     MIN_YIELD_OLD, d1
nt_floor:
    cmp     d1, d0
    bge     nt_minok
    mov     d1, d0
nt_minok:
    cmp     MAX_YIELD_MS, d0
    ble     nt_maxok
    mov     MAX_YIELD_MS, d0
nt_maxok:
    mov     d0, d2                  # the yield, kept across the measuring
    mov     d0, (PF_ASKED)
    mov     PH_WAIT, d0
    call    PerfPhase, 0, 0
    mov     d2, d0
    mov     DLY_TSK, a1
    calls   (a1)                    # yield sleep_ms to the firmware
    call    PerfSentinels, 0, 0     # did the firmware draw on the LCD meanwhile? (perf.s)
    call    PerfFrameEnd, 0, 0
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (FRAME_START_MS)    # next frame starts now (after the sleep)
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
    call    TraceInsn, 0, 0         # the platform's instruction trace (d1 = opcode, kept; vm.inc)
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
    mov     a3, d1                  # guard: the push must land inside VM_STACK
    cmp     VM_STACK, d1
    bcs     oc_bad
    cmp     VM_STACK + VM_STACK_SIZE - 2, d1
    bhi     oc_bad
    movhu   d0, (a3)
    add     2, a3
    mov     a3, (VM_SP_PTR)
    movhu   d3, (VM_PC)
    bra     ei_ret
oc_bad:
    mov     GUARD_VMSTACK, d0       # d1 = the stack pointer: refuse the call, stop the game
    call    GuardTrip, 0, 0
    bra     ei_ret

# ---- 0x05 RET: PC = pop -------------------------------------------------------
OpRet:
    mov     (VM_SP_PTR), a3
    add     -2, a3
    mov     a3, d1                  # guard: the pop must come from inside VM_STACK
    cmp     VM_STACK, d1
    bcs     or_bad
    cmp     VM_STACK + VM_STACK_SIZE - 2, d1
    bhi     or_bad
    movhu   (a3), d0
    mov     a3, (VM_SP_PTR)
    movhu   d0, (VM_PC)
    bra     ei_ret
or_bad:
    mov     GUARD_VMSTACK, d0       # d1 = the stack pointer: refuse the return, stop the game
    call    GuardTrip, 0, 0
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
    call    DrawStringTop, 0, 0
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

# ---- 0x18 PLAY_SOUND: resource u16, frequency index, volume, channel (the platform's AudioSound:
# a note on the KN7000's tone generator in the KN7APP.BIN build, audio.s; nothing in the SP7001 one)
OpPlaySound:
    mov     a2, a0
    call    AudioSound, 0, 0
    add     5, a2
    bra     ei_end

# ---- 0x19 LOAD: resource load / part switch -----------------------------------
# Every resource is already resident (LoadGameData), so: resourceId 0 = stop sound and
# music (AudioStopAll); a part id (0x3E80..) = deferred part switch request; a bitmap resource
# is drawn into page 0 now, as the original engine's copyBitmapPtr; any other resource
# (sound, music, ...) needs nothing.
OpLoad:
    movbu   (a2), d0
    movbu   (1, a2), d1
    add     2, a2
    asl     8, d0
    or      d1, d0                  # d0 = resourceId
    cmp     0, d0
    beq     ol_stop
    cmp     RES_COUNT, d0
    bge     ol_part
    mov     ResType, a0
    add     d0, a0
    movbu   (a0), d1
    cmp     RES_TYPE_BITMAP, d1
    bne     ei_end
    call    LoadBitmap, 0, 0        # d0 = resource id
    bra     ei_end
ol_stop:
    call    AudioStopAll, 0, 0
    bra     ei_end
ol_part:
    cmp     PART_FIRST, d0
    blt     ei_end
    movhu   d0, (REQ_NEXT_PART)     # applied at the end of the frame (NextThread)
    bra     ei_end

# ---- 0x1A PLAY_MUSIC: resource u16, delay u16, order u8 (the platform's AudioMusic: the module
# player of audio.s in the KN7APP.BIN build, which also writes the intro's sync mark var 0xF4)
OpPlayMusic:
    mov     a2, a0
    call    AudioMusic, 0, 0
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
    call    DrawPolyTop, 0, 0
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
    call    DrawPolyTop, 0, 0
    # reset CUR_VIDEO_DATA to CUR_VIDEO_1
    mov     (CUR_VIDEO_1), a0
    mov     a0, (CUR_VIDEO_DATA)
    bra     ei_ret

# ================================================================================
# The two drawing ops' entries, for the speed figures (perf.s) and the blit (display.s): phase DRAW
# while they run, and the page they draw on (CUR_PAGE_1) marked as drawn on.
# DrawPolyTop: ReadAndDrawPolygon's arguments (a0 = data, d0 = x, d1 = y, d2 = colour).
DrawPolyTop:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     a0, (0x10, sp)
    mov     d0, (0x14, sp)
    mov     d1, (0x18, sp)
    mov     PH_DRAW, d0
    call    PerfPhase, 0, 0
    mov     d0, d3                  # the phase to go back to
    mov     (CUR_PAGE_1), a0
    call    PerfMarkDirty, 0, 0
    mov     (0x10, sp), a0
    mov     (0x14, sp), d0
    mov     (0x18, sp), d1
    call    ReadAndDrawPolygon, 0, 0
    mov     d3, d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# DrawStringTop: DrawString's arguments (d0 = string id, d1 = x, d2 = y, d3 = colour).
DrawStringTop:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x10, sp)
    mov     d1, (0x14, sp)
    mov     PH_DRAW, d0
    call    PerfPhase, 0, 0
    mov     d0, (0x18, sp)
    mov     (CUR_PAGE_1), a0
    call    PerfMarkDirty, 0, 0
    mov     (0x10, sp), d0
    mov     (0x14, sp), d1
    call    DrawString, 0, 0        # keeps d2, d3
    mov     (0x18, sp), d0
    call    PerfPhase, 0, 0
    ret     [d2,d3,a2,a3], 0x30
