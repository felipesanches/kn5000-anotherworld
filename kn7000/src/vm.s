# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World VM -- the polygon rasterizer, ported from the KN5000 TLCS-900
# source (src/another_world_vm.asm) to the MN10300. This is the first VM component;
# the bytecode interpreter follows. The algorithm (a convex-polygon scanline fill
# walking two edges in 16.16 fixed point) and the variable names match the KN5000
# version so the two can be read together.
#
# Signed 16-bit values are held in d-registers and sign-extended with `exth` where
# a comparison or multiply needs the full 32 bits.

# ================================================================================
# FillPage(d0 = colour): memset the current page to a colour index.
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
    ret     [d2,d3,a2,a3], 8

# ================================================================================
# DrawPoint: d0 = x, d1 = y, colour in DRAW_COLOR. page[y*320 + x] = colour.
DrawPoint:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    mov     d1, d2
    asl     8, d2                   # y*256
    mov     d1, a2
    add     a2, a2
    add     a2, a2
    add     a2, a2
    add     a2, a2
    add     a2, a2                  # a2 = y*64
    add     a2, d2                  # d2 = y*320
    add     d0, d2
    mov     (CUR_PAGE), a2
    add     d2, a2
    movbu   (DRAW_COLOR), d0
    movbu   d0, (a2)
    ret     [d2,d3,a2,a3], 8

# ================================================================================
# DrawSpanN: fill the current scanline (CUR_LINE) from min(X1,X2) to max(X1,X2).
# Colour in DRAW_COLOR. (The "N" line routine: a flat colour span.)
DrawSpanN:
    movm    [d2,d3,a2,a3], (sp)
    add     -8, sp
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0                  # xmin = min(X1,X2)
    ble     ds_min_ok
    mov     d1, d2
    bra     ds_have_min
ds_min_ok:
    mov     d0, d2                  # d2 = xmin
ds_have_min:
    movhu   (X1), d0
    exth    d0
    movhu   (X2), d1
    exth    d1
    cmp     d1, d0                  # xmax = max(X1,X2)
    bge     ds_max_ok
    mov     d1, d0
ds_max_ok:
    sub     d2, d0                  # d0 = xmax - xmin
    add     1, d0                   # inclusive span width
    mov     (CUR_LINE), a2
    add     d2, a2                  # a2 = CUR_LINE + xmin
    movbu   (DRAW_COLOR), d1
ds_loop:
    movbu   d1, (a2)
    inc     a2
    add     -1, d0
    bne     ds_loop
    ret     [d2,d3,a2,a3], 8

# ================================================================================
# CalcStep(a0 = &STEP, a1 = &p1, a2 = &p2): STEP = (p2.x - p1.x) * (0x4000/dy) * 4,
# dy = p2.y - p1.y, and sets POLY_H = dy. Fixed-point slope for one edge.
CalcStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a3                  # &STEP
    movhu   (a2), d0                # p2.x
    movhu   (a1), d1                # p1.x
    sub     d1, d0
    exth    d0                      # d0 = dx (signed)
    mov     d0, d3                  # keep dx
    movhu   (2, a2), d0             # p2.y
    movhu   (2, a1), d1             # p1.y
    sub     d1, d0
    exth    d0                      # d0 = dy
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
    mul     d1, d0                  # d0 = dx * v (signed enough for our range)
    asl     2, d0                   # * 4
    mov     d0, (a3)                # STEP = dx*v*4
    ret     [d2,d3,a2,a3], 0x10

# ================================================================================
# FillPolygon(d0 = cx, d1 = cy, colour in DRAW_COLOR): fill the polygon whose
# POLY_POINTS/BBOX are already set, centred at (cx, cy) in the current page.
# Ported from fillPolygon. (The "point" fast-path and non-N line styles are left
# for later; this draws flat-colour convex polygons, which is most of the game.)
FillPolygon:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, (0x10, sp)          # cx
    mov     d1, (0x14, sp)          # cy
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
    # clip whole polygon: if xmin>=320 || xmax<0 || ymin>=200 || ymax<0 return
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
    # i = &points[0]; j = &points[num-1]
    mov     POLY_POINTS, a2         # a2 = i
    movbu   (POLY_NUM_POINTS), d0
    add     -1, d0
    asl     2, d0
    mov     POLY_POINTS, a3
    add     d0, a3                  # a3 = j
    # x2 = points[i].x + xmin ; x1 = points[j].x + xmin
    movhu   (a2), d0
    movhu   (POLY_XMIN), d1
    add     d1, d0
    movhu   d0, (X2)
    movhu   (a3), d0
    add     d1, d0
    movhu   d0, (X1)
    add     4, a2                   # i++
    add     -4, a3                  # j--
    mov     a2, (0x18, sp)          # save i
    mov     a3, (0x1c, sp)          # save j
    # cpt1 = X1<<16 ; cpt2 = X2<<16
    movhu   (X1), d0
    exth    d0
    asl     16, d0
    mov     d0, (CPT1)
    movhu   (X2), d0
    exth    d0
    asl     16, d0
    mov     d0, (CPT2)

poly_raster:
    # num -= 2 ; if num==0 done
    movbu   (POLY_NUM_POINTS), d0
    add     -2, d0
    movbu   d0, (POLY_NUM_POINTS)
    cmp     0, d0
    beq     poly_done
    # step1 = CalcStep(&STEP1, points[j+1], points[j])
    mov     (0x1c, sp), a3          # j
    mov     STEP1, a0
    mov     a3, a1
    add     4, a1                   # j+1
    mov     a3, a2                  # j
    call    CalcStep, 0, 0
    # step2 = CalcStep(&STEP2, points[i-1], points[i])
    mov     (0x18, sp), a2          # i
    mov     STEP2, a0
    mov     a2, a1
    add     -4, a1                  # i-1
    call    CalcStep, 0, 0
    # CUR_LINE = CUR_PAGE + HLINEY*320  (signed)
    movhu   (HLINEY), d0
    exth    d0
    mov     320, d1
    mul     d1, d0                  # HLINEY*320 (signed via two's complement; ok)
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
    # if POLY_H == 0 -> still advance the edges once
    movhu   (POLY_H), d0
    exth    d0
    cmp     0, d0
    beq     poly_hzero

poly_hloop:
    movhu   (HLINEY), d0
    exth    d0
    cmp     0, d0
    blt     poly_after_draw         # HLINEY < 0: skip drawing this line
    mov     (CPT1), d0
    lsr     16, d0
    movhu   d0, (X1)
    mov     (CPT2), d0
    lsr     16, d0
    movhu   d0, (X2)
    # if X1<320 && X2>=0
    movhu   (X1), d0
    exth    d0
    cmp     320, d0
    bge     poly_after_draw
    movhu   (X2), d0
    exth    d0
    cmp     0, d0
    blt     poly_after_draw
    movhu   (X1), d0                # clamp X1 >= 0
    exth    d0
    cmp     0, d0
    bge     poly_x1ok
    clr     d0
    movhu   d0, (X1)
poly_x1ok:
    movhu   (X2), d0                # clamp X2 <= 319
    exth    d0
    cmp     319, d0
    ble     poly_x2ok
    mov     319, d0
    movhu   d0, (X2)
poly_x2ok:
    call    DrawSpanN, 0, 0

poly_after_draw:
    mov     (STEP1), d0             # cpt1 += step1
    mov     (CPT1), d1
    add     d0, d1
    mov     d1, (CPT1)
    mov     (STEP2), d0             # cpt2 += step2
    mov     (CPT2), d1
    add     d0, d1
    mov     d1, (CPT2)
    movhu   (HLINEY), d0            # HLINEY++
    add     1, d0
    movhu   d0, (HLINEY)
    mov     (CUR_LINE), a2          # CUR_LINE += 320
    add     320, a2
    mov     a2, (CUR_LINE)
    movhu   (HLINEY), d0            # if HLINEY > 199 done
    exth    d0
    cmp     199, d0
    bgt     poly_done
    movhu   (POLY_H), d0            # --POLY_H; loop while != 0
    add     -1, d0
    movhu   d0, (POLY_H)
    exth    d0
    cmp     0, d0
    bne     poly_hloop
    bra     poly_raster

poly_hzero:                         # POLY_H==0: advance edges once, next edge pair
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
    ret     [d2,d3,a2,a3], 0x20
