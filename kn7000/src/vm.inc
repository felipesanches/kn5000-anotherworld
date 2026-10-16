# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World VM state for the KN7000 port. The VM's working variables live in a
# small block of the 0x44 scratch window (CPU-writable; not used by the firmware).
# Field names and sizes mirror the KN5000 TLCS-900 source so the two stay readable
# side by side.

.equ VM_STATE,        0x44050000

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

# POLY_POINTS: up to 50 (x,y) pairs, u16 each, interleaved. Kept last.
.equ POLY_POINTS,     VM_STATE + 0x40
