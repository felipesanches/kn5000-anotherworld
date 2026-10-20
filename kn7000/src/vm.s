# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World VM -- the polygon pipeline, ported from the KN5000 TLCS-900 source
# (another_world_vm.asm) to the MN10300: the recursive polygon-hierarchy reader, the
# vertex reader (with zoom scaling), and the convex-polygon scanline rasterizer that
# walks two edges in 16.16 fixed point. Variable names mirror the KN5000 version.
#
# Convention: d0,d1,a0,a1 caller-saved args/scratch; d2,d3,a2,a3 callee-saved.
# ret adj = locals + 0x10 (pops locals AND the four movm-saved registers). Signed
# 16-bit values are sign-extended with `exth` before a comparison/multiply.

# ================================================================================
# Scale(d0 = byte) -> d0 = (byte * CUR_ZOOM) >> 6. Zoom scaling for bbox/vertices.
Scale:
    movm    [a2,a3], (sp)
    add     -8, sp
    and     0xff, d0
    movhu   (CUR_ZOOM), d1
    mulu    d1, d0                  # product < 2^24, fits in d0
    lsr     6, d0
    ret     [a2,a3], 0x10

# ================================================================================
# The run-time guard's checks (vm.inc GUARD_*). Every write the VM makes goes through a page
# pointer (GetPagePtr: one of the four pages), the VM stack (OpCall), the variables (index & 0xFF),
# the thread tables (index & 0x3F) or the rasterizer, which clips to the page; the checks below
# catch a page pointer or stack pointer that something has corrupted. A refused write is skipped
# and recorded, and GameTask (display.s) stops the game after the instruction.
#
# GuardPage(a0 = page) -> d0 = 0 when a0 is one of the four pages, else 1 (recorded). Leaf.
GuardPage:
    mov     a0, d0
    mov     PAGE_BITMAP_0, d1
    sub     d1, d0                  # page - page 0: 0, 0x10000, 0x20000 or 0x30000
    and     0xFFFCFFFF, d0
    bne     gpg_bad
    rets
gpg_bad:
    mov     GUARD_PAGE, d0
    mov     a0, d1
# GuardTrip(d0 = GUARD_* reason, d1 = the refused address): record it; d0 = 1. Leaf.
GuardTrip:
    mov     d0, (GUARD_WHAT)
    mov     d1, (GUARD_ADDR)
    mov     (GUARD_COUNT), d0
    inc     d0
    mov     d0, (GUARD_COUNT)
    mov     1, d0
    rets

# ================================================================================
# FillPage(d0 = colour): memset CUR_PAGE to a colour index.
FillPage:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    mov     d0, d1
    mov     (CUR_PAGE), a2
    mov     PAGE_SIZE, d2
fp_loop:
    movbu   d1, (a2)
    inc     a2
    add     -1, d2
    bne     fp_loop
    ret     [d2,d3,a2,a3], 0x18

# ================================================================================
# DrawPoint(d0 = x, d1 = y): CUR_PAGE[y*320 + x] = DRAW_COLOR. Clipped to the page
# (the KN5000 source does not clip; we do, to protect the scratch RAM from stray
# off-screen "point" polygons -- on-screen output is identical).
DrawPoint:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2                  # x
    exth    d2
    cmp     0, d2
    blt     dp_ret
    cmp     320, d2
    bge     dp_ret
    mov     d1, d3                  # y
    exth    d3
    cmp     0, d3
    blt     dp_ret
    cmp     200, d3
    bge     dp_ret
    mov     d3, d0                  # y*320
    asl     8, d0                   # y*256
    mov     d3, a2
    add     a2, a2                  # 2y
    add     a2, a2                  # 4y
    add     a2, a2                  # 8y
    add     a2, a2                  # 16y
    add     a2, a2                  # 32y
    add     a2, a2                  # a2 = y*64 (six doublings)
    add     a2, d0                  # d0 = y*256 + y*64 = y*320
    add     d2, d0                  # + x
    mov     (CUR_PAGE), a2
    add     d0, a2
    movbu   (DRAW_COLOR), d0
    movbu   d0, (a2)
dp_ret:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# DrawSpanN: flat-colour span on CUR_LINE from min(X1,X2) to max(X1,X2), DRAW_COLOR. A span of 8 or more
# is written 4 bytes at a time between its unaligned ends (the same bytes: fewer stores to RAM).
DrawSpanN:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0
    ble     dn_min
    mov     d1, d2
    bra     dn_hmin
dn_min:
    mov     d0, d2                  # xmin
dn_hmin:
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0
    bge     dn_max
    mov     d1, d0
dn_max:
    sub     d2, d0
    add     1, d0                   # inclusive width
    mov     (CUR_LINE), a2
    add     d2, a2
    movbu   (DRAW_COLOR), d1
    cmp     8, d0
    bcs     dn_loop                 # short: a byte at a time
dn_head:
    mov     a2, d2                  # up to a word boundary
    and     3, d2
    beq     dn_words
    movbu   d1, (a2)
    inc     a2
    add     -1, d0
    bra     dn_head
dn_words:
    mov     0x01010101, d2
    mul     d1, d2                  # the colour in all four bytes
    mov     d0, d3
    lsr     2, d3
dn_wloop:
    mov     d2, (a2)
    add     4, a2
    add     -1, d3
    bne     dn_wloop
    and     3, d0                   # what is left
    beq     dn_done
dn_loop:
    movbu   d1, (a2)
    inc     a2
    add     -1, d0
    bne     dn_loop
dn_done:
    ret     [d2,d3,a2,a3], 0x18

# ================================================================================
# DrawSpanP: copy a span from PAGE_BITMAP_0 to CUR_LINE (drawLineP: "transparent to
# the background" segments copy the backdrop page through). Both rows lie at the same offset in their
# 0x10000-aligned pages, so a span of 8 or more is copied 4 bytes at a time between its ends.
DrawSpanP:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0
    ble     dpn_min
    mov     d1, d2
    bra     dpn_hmin
dpn_min:
    mov     d0, d2
dpn_hmin:
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0
    bge     dpn_max
    mov     d1, d0
dpn_max:
    sub     d2, d0
    add     1, d0
    mov     d0, d3                  # width
    mov     (CUR_LINE), a3
    add     d2, a3                  # dst = CUR_LINE + xmin
    movhu   (HLINEY), d0
    exth    d0
    mov     320, d1
    mul     d1, d0                  # HLINEY*320
    mov     PAGE_BITMAP_0, a2
    add     d0, a2
    add     d2, a2                  # src = page0 + HLINEY*320 + xmin
    cmp     8, d3
    bcs     dpn_loop                # short: a byte at a time
dpn_head:
    mov     a3, d0                  # up to a word boundary (the same for both)
    and     3, d0
    beq     dpn_words
    movbu   (a2), d0
    movbu   d0, (a3)
    inc     a2
    inc     a3
    add     -1, d3
    bra     dpn_head
dpn_words:
    mov     d3, d2
    lsr     2, d2
dpn_wloop:
    mov     (a2), d0
    mov     d0, (a3)
    add     4, a2
    add     4, a3
    add     -1, d2
    bne     dpn_wloop
    and     3, d3                   # what is left
    beq     dpn_done
dpn_loop:
    movbu   (a2), d0
    movbu   d0, (a3)
    inc     a2
    inc     a3
    add     -1, d3
    bne     dpn_loop
dpn_done:
    ret     [d2,d3,a2,a3], 0x18

# ================================================================================
# DrawSpanBlend: blend a span in place -- pixel = (pixel & 7) | 8 (half-bright); a span of 8 or more 4
# pixels at a time between its ends.
DrawSpanBlend:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0
    ble     db_min
    mov     d1, d2
    bra     db_hmin
db_min:
    mov     d0, d2
db_hmin:
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0
    bge     db_max
    mov     d1, d0
db_max:
    sub     d2, d0
    add     1, d0
    mov     d0, d3
    mov     (CUR_LINE), a3
    add     d2, a3
    cmp     8, d3
    bcs     db_loop                 # short: a byte at a time
db_head:
    mov     a3, d0                  # up to a word boundary
    and     3, d0
    beq     db_words
    movbu   (a3), d0
    and     7, d0
    or      8, d0
    movbu   d0, (a3)
    inc     a3
    add     -1, d3
    bra     db_head
db_words:
    mov     d3, d2
    lsr     2, d2
db_wloop:
    mov     (a3), d0
    and     0x07070707, d0
    or      0x08080808, d0
    mov     d0, (a3)
    add     4, a3
    add     -1, d2
    bne     db_wloop
    and     3, d3                   # what is left
    beq     db_done
db_loop:
    movbu   (a3), d0
    and     7, d0
    or      8, d0
    movbu   d0, (a3)
    inc     a3
    add     -1, d3
    bne     db_loop
db_done:
    ret     [d2,d3,a2,a3], 0x18

# ================================================================================
# CalcStep(a0 = &STEP, a1 = &p1, a2 = &p2): STEP = (p2.x - p1.x) * (0x4000/dy) * 4,
# dy = p2.y - p1.y, and POLY_H = dy. Fixed-point slope for one edge.
CalcStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a3                  # &STEP
    movhu   (a2), d0                # p2.x
    movhu   (a1), d1                # p1.x
    sub     d1, d0
    exth    d0                      # dx
    mov     d0, d3
    movhu   (2, a2), d0             # p2.y
    movhu   (2, a1), d1             # p1.y
    sub     d1, d0
    exth    d0                      # dy
    movhu   d0, (POLY_H)
    mov     0x4000, d2              # v = 0x4000
    cmp     0, d0
    ble     cs_dy_le_0
    mov     0x4000, d1
    clr     d2
    mov     d2, mdr
    exth    d0
    divu    d0, d1                  # d1 = 0x4000 / dy  (dy > 0)
    mov     d1, d2
cs_dy_le_0:
    mov     d3, d0                  # dx
    mov     d2, d1                  # v
    exth    d0
    exth    d1
    mul     d1, d0                  # dx * v (signed)
    asl     2, d0                   # * 4
    mov     d0, (a3)                # STEP
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# ReadVertices(a0 = polygon data): read bbox_w, bbox_h, numPoints and the points
# into the POLY_* fields, each coordinate scaled by CUR_ZOOM. Advances its own copy.
ReadVertices:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2                  # cursor
    movbu   (a2), d0                # bbox_w
    inc     a2
    call    Scale, 0, 0
    movhu   d0, (POLY_BBOX_W)
    movbu   (a2), d0                # bbox_h
    inc     a2
    call    Scale, 0, 0
    movhu   d0, (POLY_BBOX_H)
    movbu   (a2), d0                # numPoints
    inc     a2
    mov     d0, d3
    cmp     50, d3                  # cap to the POLY_POINTS capacity (50 pairs)
    ble     rv_cap_ok
    mov     50, d3
rv_cap_ok:
    movbu   d3, (POLY_NUM_POINTS)
    cmp     0, d3                   # guard: num==0 would underflow the loop (~4 billion)
    beq     rv_ret
    mov     POLY_POINTS, a3         # dst
rv_loop:
    movbu   (a2), d0                # point.x
    inc     a2
    call    Scale, 0, 0
    movhu   d0, (a3)
    add     2, a3
    movbu   (a2), d0                # point.y
    inc     a2
    call    Scale, 0, 0
    movhu   d0, (a3)
    add     2, a3
    add     -1, d3
    bne     rv_loop
rv_ret:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# ReadAndDrawPolygon(a0 = data, d0 = x, d1 = y, d2 = colour). If the first byte is
# >= 0xC0 this is a leaf polygon: read its vertices and fill it. Otherwise it is a
# hierarchy of child polygons offset from (x,y).
ReadAndDrawPolygon:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     DRAW_BUDGET, a3         # anti-hang: bound total polygons per VIDEO op
    mov     (a3), d3
    inc     d3
    mov     d3, (a3)
    cmp     DRAW_BUDGET_MAX, d3
    bgt     radp_done               # pathological tree (garbage data): bail out
    mov     a0, a2                  # cursor
    mov     d0, (0xc, sp)             # x
    mov     d1, (4, sp)             # y
    mov     d2, (8, sp)             # colour
    movbu   (a2), d3                # marker
    inc     a2
    cmp     0xc0, d3
    blt     radp_hier               # marker < 0xC0 -> hierarchy (values are 0..255)
    # leaf: if the incoming colour has bit 7 set, colour = marker & 0x3F
    mov     (8, sp), d0
    and     0xff, d0
    cmp     0x80, d0
    blt     radp_color_ok
    mov     d3, d0
    and     0x3f, d0
    mov     d0, (8, sp)
radp_color_ok:
    mov     a2, a0
    call    ReadVertices, 0, 0
    mov     (0xc, sp), d0
    mov     (4, sp), d1
    mov     (8, sp), d2
    call    FillPolygon, 0, 0
    bra     radp_done
radp_hier:
    mov     a2, a0
    mov     (0xc, sp), d0
    mov     (4, sp), d1
    mov     (8, sp), d2
    call    ReadAndDrawPolygonHierarchy, 0, 0
radp_done:
    ret     [d2,d3,a2,a3], 0x20

# ================================================================================
# ReadAndDrawPolygonHierarchy(a0 = data, d0 = x, d1 = y, d2 = colour): parent point
# (x,y) is first offset by two scaled bytes, then each child polygon is read at
# (offset, scaled dx, scaled dy, optional colour) and drawn recursively.
# a2 holds the data cursor; it survives the recursive ReadAndDrawPolygon call because
# that callee preserves a2.
# locals: (0)=ptx (4)=pty (8)=childCount (0x10)=childOffset (0x14)=pox (0x18)=poy (0x1c)=childColor
ReadAndDrawPolygonHierarchy:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    # recursion-depth guard: protect the task stack from deep/garbage hierarchies
    mov     DRAW_DEPTH, a3
    mov     (a3), d3
    inc     d3
    mov     d3, (a3)
    cmp     DRAW_DEPTH_MAX, d3
    bgt     rdh_exit                # too deep: unwind (depth is decremented at rdh_exit)
    mov     a0, a2                  # cursor
    # ptx = x - scale(*cursor++)
    mov     d0, (0xc, sp)
    mov     d1, (4, sp)
    movbu   (a2), d0
    inc     a2
    call    Scale, 0, 0
    mov     (0xc, sp), d1
    sub     d0, d1
    mov     d1, (0xc, sp)             # ptx
    # pty = y - scale(*cursor++)
    movbu   (a2), d0
    inc     a2
    call    Scale, 0, 0
    mov     (4, sp), d1
    sub     d0, d1
    mov     d1, (4, sp)             # pty
    # childCount = *cursor++ + 1
    movbu   (a2), d0
    inc     a2
    add     1, d0
    mov     d0, (8, sp)
rdh_loop:
    # childOffset = big-endian word ; cursor += 2
    movbu   (a2), d0
    movbu   (1, a2), d1
    add     2, a2
    asl     8, d0
    or      d1, d0
    mov     d0, (0x10, sp)
    # pox = ptx + scale(*cursor++)
    movbu   (a2), d0
    inc     a2
    call    Scale, 0, 0
    mov     (0xc, sp), d1
    add     d0, d1
    mov     d1, (0x14, sp)
    # poy = pty + scale(*cursor++)
    movbu   (a2), d0
    inc     a2
    call    Scale, 0, 0
    mov     (4, sp), d1
    add     d0, d1
    mov     d1, (0x18, sp)
    # colour = 0xFF, unless offset bit 15 set -> colour = (*cursor) & 0x7F, cursor += 2
    mov     0xff, d2
    mov     (0x10, sp), d0
    and     0x8000, d0
    beq     rdh_nocolor
    movbu   (a2), d2
    and     0x7f, d2
    add     2, a2
rdh_nocolor:
    mov     d2, (0x1c, sp)
    # childData = CUR_VIDEO_DATA + (offset & 0x7FFF) * 2
    mov     (0x10, sp), d0
    and     0x7fff, d0
    asl     1, d0
    mov     (CUR_VIDEO_DATA), a0
    add     d0, a0
    mov     (0x14, sp), d0          # pox
    mov     (0x18, sp), d1          # poy
    mov     (0x1c, sp), d2          # colour
    call    ReadAndDrawPolygon, 0, 0
    mov     (8, sp), d0             # --childCount
    add     -1, d0
    mov     d0, (8, sp)
    bne     rdh_loop
rdh_exit:
    mov     DRAW_DEPTH, a3          # leaving this hierarchy level
    mov     (a3), d3
    add     -1, d3
    mov     d3, (a3)
    ret     [d2,d3,a2,a3], 0x30

# ================================================================================
# FillPolygon(d0 = x/cx, d1 = y/cy, d2 = colour): fill the polygon in POLY_* at the
# centre (cx,cy) on CUR_PAGE_1. Selects the span routine from the colour, handles the
# single-point fast path, then rasterizes edge pairs.
FillPolygon:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x10, sp)          # cx
    mov     d1, (0x14, sp)          # cy
    mov     (CUR_PAGE_1), a0        # draw to the current page
    call    GuardPage, 0, 0         # (keeps d2) refuse a page pointer that is not a page
    cmp     0, d0
    bne     poly_done
    mov     a0, (CUR_PAGE)
    and     0xff, d2
    mov     d2, d0
    movbu   d0, (DRAW_COLOR)
    # draw function: ==0x10 blend, >0x10 copy (P), else flat (N). colour is 0..0x7F.
    cmp     0x10, d2
    beq     fp_blend
    bgt     fp_lineP
    clr     d0
    bra     fp_setfunc
fp_blend:
    mov     2, d0
    bra     fp_setfunc
fp_lineP:
    mov     1, d0
fp_setfunc:
    movbu   d0, (DRAW_FUNC)
    # point fast path: bbox_w == 0 && bbox_h == 1 && numPoints == 4
    movhu   (POLY_BBOX_W), d0
    cmp     0, d0
    bne     fp_poly
    movhu   (POLY_BBOX_H), d0
    cmp     1, d0
    bne     fp_poly
    movbu   (POLY_NUM_POINTS), d0
    cmp     4, d0
    bne     fp_poly
    mov     (0x10, sp), d0          # cx
    mov     (0x14, sp), d1          # cy
    call    DrawPoint, 0, 0
    bra     poly_done
fp_poly:
    # xmin = cx - bbox_w/2 ; xmax = cx + bbox_w/2
    movhu   (POLY_BBOX_W), d2
    lsr     1, d2
    mov     (0x10, sp), d0
    sub     d2, d0
    movhu   d0, (POLY_XMIN)
    mov     (0x10, sp), d0
    add     d2, d0
    movhu   d0, (POLY_XMAX)
    # ymin = cy - bbox_h/2 ; ymax = cy + bbox_h/2
    movhu   (POLY_BBOX_H), d2
    lsr     1, d2
    mov     (0x14, sp), d0
    sub     d2, d0
    movhu   d0, (POLY_YMIN)
    mov     (0x14, sp), d0
    add     d2, d0
    movhu   d0, (POLY_YMAX)
    # clip whole polygon
    movhu   (POLY_XMIN), d0
    exth    d0
    cmp     320, d0
    bge     poly_done
    movhu   (POLY_XMAX), d0
    exth    d0
    cmp     0, d0
    blt     poly_done
    movhu   (POLY_YMIN), d0
    exth    d0
    cmp     200, d0
    bge     poly_done
    movhu   (POLY_YMAX), d0
    exth    d0
    cmp     0, d0
    blt     poly_done
    # HLINEY = ymin
    movhu   (POLY_YMIN), d0
    movhu   d0, (HLINEY)
    # i = &points[0] ; j = &points[num-1]
    mov     POLY_POINTS, a2
    movbu   (POLY_NUM_POINTS), d0
    add     -1, d0
    asl     2, d0
    mov     POLY_POINTS, a3
    add     d0, a3
    # x2 = points[i].x + xmin ; x1 = points[j].x + xmin
    movhu   (a2), d0
    movhu   (POLY_XMIN), d1
    add     d1, d0
    movhu   d0, (X2)
    movhu   (a3), d0
    add     d1, d0
    movhu   d0, (X1)
    add     4, a2
    add     -4, a3
    mov     a2, (0x18, sp)          # i
    mov     a3, (0x1c, sp)          # j
    # cpt1 = X1 << 16 ; cpt2 = X2 << 16
    movhu   (X1), d0
    exth    d0
    asl     16, d0
    mov     d0, (CPT1)
    movhu   (X2), d0
    exth    d0
    asl     16, d0
    mov     d0, (CPT2)

poly_raster:
    movbu   (POLY_NUM_POINTS), d0
    add     -2, d0
    cmp     0, d0                   # stop on <= 0 (signed): terminates for odd/garbage
    ble     poly_done               # counts too, not just the exact-zero even case
    movbu   d0, (POLY_NUM_POINTS)
    # step1 = CalcStep(&STEP1, points[j+1], points[j])
    mov     (0x1c, sp), a3
    mov     STEP1, a0
    mov     a3, a1
    add     4, a1
    mov     a3, a2
    call    CalcStep, 0, 0
    # step2 = CalcStep(&STEP2, points[i-1], points[i])
    mov     (0x18, sp), a2
    mov     STEP2, a0
    mov     a2, a1
    add     -4, a1
    call    CalcStep, 0, 0
    # CUR_LINE = CUR_PAGE + HLINEY*320
    movhu   (HLINEY), d0
    exth    d0
    mov     320, d1
    mul     d1, d0
    mov     (CUR_PAGE), a2
    add     d0, a2
    mov     a2, (CUR_LINE)
    # i++ ; j--
    mov     (0x18, sp), a2
    add     4, a2
    mov     a2, (0x18, sp)
    mov     (0x1c, sp), a3
    add     -4, a3
    mov     a3, (0x1c, sp)
    # cpt1 low = 0x7FFF ; cpt2 low = 0x8000
    mov     (CPT1), d0
    and     0xffff0000, d0
    or      0x7fff, d0
    mov     d0, (CPT1)
    mov     (CPT2), d0
    and     0xffff0000, d0
    or      0x8000, d0
    mov     d0, (CPT2)
    movhu   (POLY_H), d0
    exth    d0
    cmp     0, d0
    beq     poly_hzero

poly_hloop:
    movhu   (HLINEY), d0
    exth    d0
    cmp     0, d0
    blt     poly_after_draw
    mov     (CPT1), d0
    lsr     16, d0
    movhu   d0, (X1)
    mov     (CPT2), d0
    lsr     16, d0
    movhu   d0, (X2)
    movhu   (X1), d0
    exth    d0
    cmp     320, d0
    bge     poly_after_draw
    movhu   (X2), d0
    exth    d0
    cmp     0, d0
    blt     poly_after_draw
    movhu   (X1), d0
    exth    d0
    cmp     0, d0
    bge     poly_x1ok
    clr     d0
    movhu   d0, (X1)
poly_x1ok:
    movhu   (X2), d0
    exth    d0
    cmp     319, d0
    ble     poly_x2ok
    mov     319, d0
    movhu   d0, (X2)
poly_x2ok:
    movbu   (DRAW_FUNC), d0
    cmp     0, d0
    bne     pf_not0
    call    DrawSpanN, 0, 0
    bra     poly_after_draw
pf_not0:
    cmp     2, d0
    bne     pf_useP
    call    DrawSpanBlend, 0, 0
    bra     poly_after_draw
pf_useP:
    call    DrawSpanP, 0, 0

poly_after_draw:
    mov     (STEP1), d0
    mov     (CPT1), d1
    add     d0, d1
    mov     d1, (CPT1)
    mov     (STEP2), d0
    mov     (CPT2), d1
    add     d0, d1
    mov     d1, (CPT2)
    movhu   (HLINEY), d0
    add     1, d0
    movhu   d0, (HLINEY)
    mov     (CUR_LINE), a2
    add     320, a2
    mov     a2, (CUR_LINE)
    movhu   (HLINEY), d0
    exth    d0
    cmp     199, d0
    bgt     poly_done
    movhu   (POLY_H), d0
    add     -1, d0
    movhu   d0, (POLY_H)
    exth    d0
    cmp     0, d0
    bne     poly_hloop
    bra     poly_raster

poly_hzero:
    mov     (STEP1), d0
    mov     (CPT1), d1
    add     d0, d1
    mov     d1, (CPT1)
    mov     (STEP2), d0
    mov     (CPT2), d1
    add     d0, d1
    mov     d1, (CPT2)
    bra     poly_raster

poly_done:
    ret     [d2,d3,a2,a3], 0x30

# ================================================================================
# DrawString(d0 = stringId, d1 = x [char column], d2 = y [pixels], d3 = colour):
# render an Another World string from the str_index/str_data tables, 8x8 glyphs from
# AW_FONT, onto CUR_PAGE_1. Ported from the KN5000 DRAW_STRING. Locals live at (4,sp)+
# because `call DrawChar` writes its return address at (0,sp).
DrawString:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x18, sp
    asl     3, d1                   # x = 8 * col  (pixel column; matches the original VM)
    mov     d1, (4, sp)             # x
    mov     d1, (0xc, sp)           # x0 (line start)
    mov     d2, (8, sp)             # y
    mov     d3, (0x10, sp)          # colour
    mov     d0, (0x14, sp)          # stringId
    mov     (CUR_PAGE_1), a0        # the page DrawChar draws on must be a page
    call    GuardPage, 0, 0
    cmp     0, d0
    bne     dstr_done
    mov     (0x14, sp), d0
    and     0xffff, d0              # stringId
    asl     1, d0
    cmp     AW_STRIDX_SZ, d0        # guard: id out of the index table -> draw nothing
    bge     dstr_done
    mov     AW_STRIDX, a2
    add     d0, a2
    movhu   (a2), d0                # offset into str_data (LE u16)
    cmp     AW_STRDAT_SZ, d0        # guard: offset out of str_data
    bge     dstr_done
    mov     AW_STRDAT, a2
    add     d0, a2                  # char pointer
dstr_loop:
    movbu   (a2), d3                # char
    inc     a2
    cmp     0, d3
    beq     dstr_done               # NUL terminator
    cmp     10, d3                  # '\n'
    bne     dstr_char
    mov     (8, sp), d0             # y += 8
    add     8, d0
    mov     d0, (8, sp)
    mov     (0xc, sp), d0           # x = x0
    mov     d0, (4, sp)
    bra     dstr_loop
dstr_char:
    mov     (4, sp), d0             # x
    mov     (8, sp), d1             # y
    mov     (0x10, sp), d2          # colour
    call    DrawChar, 0, 0          # d3 = char (preserved across the call)
    mov     (4, sp), d0             # x += 8
    add     8, d0
    mov     d0, (4, sp)
    bra     dstr_loop
dstr_done:
    ret     [d2,d3,a2,a3], 0x28

# ================================================================================
# DrawChar(d0 = x, d1 = y, d2 = colour, d3 = char): plot an 8x8 glyph at (x,y) on
# CUR_PAGE_1. Clipped to the 320x200 page (the KN5000 page is 320x240; ours is 200).
DrawChar:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d2, (0, sp)             # colour (no calls here, so (0,sp) is safe)
    mov     d3, (4, sp)             # char
    exth    d0
    cmp     0, d0                   # clip x to [0, 312] (col 0..39; glyph fits 8 px)
    blt     dchr_ret
    cmp     313, d0
    bge     dchr_ret
    exth    d1
    cmp     0, d1                   # clip y to [0, 192] (glyph fits 8 px into 200)
    blt     dchr_ret
    cmp     193, d1
    bge     dchr_ret
    mov     (4, sp), d2             # char -> font pointer
    and     0xff, d2
    add     -0x20, d2
    asl     3, d2
    mov     AW_FONT, a2
    add     d2, a2
    mov     320, d2                 # dst = CUR_PAGE_1 + y*320 + x
    mul     d2, d1
    mov     (CUR_PAGE_1), a3
    add     d1, a3
    add     d0, a3
    mov     8, d3                   # 8 rows
dchr_jloop:
    movbu   (a2), d1                # row bits (bit 7 = leftmost)
    inc     a2
    mov     8, d2                   # 8 columns
dchr_iloop:
    mov     d1, d0
    and     0x80, d0
    beq     dchr_noplot
    movbu   (0, sp), d0             # colour
    movbu   d0, (a3)
dchr_noplot:
    asl     1, d1
    inc     a3
    add     -1, d2
    bne     dchr_iloop
    add     312, a3                 # next scanline (back 8, down 320)
    add     -1, d3
    bne     dchr_jloop
dchr_ret:
    ret     [d2,d3,a2,a3], 0x20
