# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
# Offline MN10300-simulator harness for the Another World rasterizer.
# Offline sim harness for the rasterizer: state and page in sim RAM (0x50...).
.equ AW_W, 320
.equ AW_H, 200
.equ PAGE_SIZE, AW_W*AW_H

.equ VM_STATE,        0x50100000

.equ POLY_NUM_POINTS, VM_STATE + 0x00   # byte
.equ POLY_BBOX_W,     VM_STATE + 0x02   # u16
.equ POLY_BBOX_H,     VM_STATE + 0x04   # u16
.equ POLY_XMIN,       VM_STATE + 0x06   # s16
.equ POLY_XMAX,       VM_STATE + 0x08   # s16
.equ POLY_YMIN,       VM_STATE + 0x0A   # s16
.equ POLY_YMAX,       VM_STATE + 0x0C   # s16
.equ HLINEY,          VM_STATE + 0x0E   # s16
.equ X1,              VM_STATE + 0x10   # s16
.equ X2,              VM_STATE + 0x12   # s16
.equ DX,              VM_STATE + 0x14   # s16
.equ LINE_XMIN,       VM_STATE + 0x16   # s16
.equ LINE_XMAX,       VM_STATE + 0x18   # s16
.equ POLY_H,          VM_STATE + 0x1A   # s16 (dy / remaining scanlines)
.equ STEP_V,          VM_STATE + 0x1C   # s16 scratch for calcStep
.equ CUR_LINE,        VM_STATE + 0x20   # u32 pointer into the page
.equ CPT1,            VM_STATE + 0x24   # u32 fixed-point edge x (left)
.equ CPT2,            VM_STATE + 0x28   # u32 fixed-point edge x (right)
.equ STEP1,           VM_STATE + 0x2C   # s32 per-scanline delta for CPT1
.equ STEP2,           VM_STATE + 0x30   # s32 per-scanline delta for CPT2
.equ CUR_PAGE,        VM_STATE + 0x34   # u32 base of the page being drawn
.equ DRAW_COLOR,      VM_STATE + 0x38   # byte

.equ POLY_POINTS,     VM_STATE + 0x40
.equ PAGE_BITMAP_0, 0x50200000
.mnbase 0x50000000
_start:
    mov     PAGE_BITMAP_0, a0
    mov     a0, (CUR_PAGE)
    # clear page
    mov     a0, a2
    mov     PAGE_SIZE, d2
cl: clr     d0
    movbu   d0, (a2)
    inc     a2
    add     -1, d2
    bne     cl
    # diamond bbox 100x100
    mov     100, d0
    movhu   d0, (POLY_BBOX_W)
    movhu   d0, (POLY_BBOX_H)
    mov     4, d0
    movbu   d0, (POLY_NUM_POINTS)
    mov     POLY_POINTS, a0
    mov     50, d0
    movhu   d0, (a0)
    clr     d0
    movhu   d0, (2, a0)
    mov     100, d0
    movhu   d0, (4, a0)
    mov     50, d0
    movhu   d0, (6, a0)
    mov     50, d0
    movhu   d0, (8, a0)
    mov     100, d0
    movhu   d0, (10, a0)
    clr     d0
    movhu   d0, (12, a0)
    mov     50, d0
    movhu   d0, (14, a0)
    mov     11, d0
    movbu   d0, (DRAW_COLOR)
    mov     160, d0
    mov     100, d1
    call    FillPolygon, 0, 0
done:
    bra     done
.include "../src/vm.s"
