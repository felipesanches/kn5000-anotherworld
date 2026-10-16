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
.equ DRAW_FUNC,       VM_STATE + 0x39   # byte: 0 = flat (N), 1 = copy page0 (P), 2 = blend

# POLY_POINTS: up to 50 (x,y) pairs, u16 each, interleaved. Kept last.
# Spans VM_STATE+0x40 .. +0x108 (200 bytes). The interpreter state below starts a
# long way clear of it.
.equ POLY_POINTS,     VM_STATE + 0x40

# ================================================================================
# Interpreter state (the VM proper), ported from the KN5000 main.asm declarations.
# Arrays first, then scalars. All in the 0x44 scratch window.
.equ VM_VARIABLES,    0x44070000      # 256 x s16   (var[0..255])
.equ THREADS_DATA,    0x44070400      # 64 x {u16 pc @+0, u16 requested_pc @+2}
.equ VM_CHAN_STATE,   0x44070600      # 64 x {u8 state @+0, u8 requested_state @+1}
.equ VM_STACK,        0x44070800      # 256 x u16   (VM call stack)

.equ PC_OFFSET,         0             # within a THREADS_DATA entry
.equ REQ_PC_OFFSET,     2
.equ CUR_STATE,         0             # within a VM_CHAN_STATE entry
.equ REQ_STATE,         1

.equ INACTIVE_THREAD,   0xFFFF
.equ DELETE_THREAD,     0xFFFE
.equ NO_REQUEST,        0xFFFF
.equ ST_FROZEN,         0
.equ ST_NOT_FROZEN,     1

# scalars
.equ CURRENT_THREAD,  0x44071000      # u8
.equ VM_PC,           0x44071002      # u16
.equ VM_SP_PTR,       0x44071004      # u32  (points into VM_STACK)
.equ CUR_PAGE_1,      0x44071008      # u32  draw target page
.equ CUR_PAGE_2,      0x4407100C      # u32  display page
.equ CUR_PAGE_3,      0x44071010      # u32  work/back page
.equ CUR_VIDEO_DATA,  0x44071014      # u32  active polygon source
.equ CUR_VIDEO_1,     0x44071018      # u32  cinematic polygon source
.equ CUR_VIDEO_2,     0x4407101C      # u32  secondary polygon source
.equ CUR_BYTECODE,    0x44071020      # u32
.equ CUR_PALETTES,    0x44071024      # u32
.equ CUR_ZOOM,        0x44071028      # u16
.equ CURRENT_PART_ID, 0x4407102A      # u16
.equ REQ_NEXT_PART,   0x4407102C      # u16

# Game resources are loaded from the SD card as four separate files (the firmware's
# fread_api has a 16-bit count and no working sequential reads, so each resource is one
# fopen+fread+fclose, and each must be <= 65535 bytes -- all four are). Fixed load
# addresses in the 0x44 scratch window, clear of the pages and the VM state. Sizes are
# the intro resources' exact byte lengths; keep them in step with the SD files.
.equ AW_BYTECODE,     0x44400000     # resource 0x18, 9871 bytes
.equ AW_VIDEO1,       0x44420000     # resource 0x19, 65230 bytes
.equ AW_VIDEO2,       0x44440000     # resource 0x11, 25108 bytes
.equ AW_PALETTES,     0x44460000     # resource 0x17, 2048 bytes
.equ AW_BYTECODE_SZ,  9871
.equ AW_VIDEO1_SZ,    65230
.equ AW_VIDEO2_SZ,    25108
.equ AW_PALETTES_SZ,  2048
.equ AW_LOADED_FLAG,  0x44080020     # set to 0x600D once all four are loaded

.equ DRAW_BUDGET,     0x44080070     # per-VIDEO-op polygon budget (anti-hang guard)
.equ DRAW_BUDGET_MAX, 4000
.equ DRAW_DEPTH,      0x44080074     # polygon-hierarchy recursion depth (stack guard)
.equ DRAW_DEPTH_MAX,  12             # AW hierarchies are shallow; cap to protect the stack

# VM instruction trace (for diffing against the vm-gui reference). Each entry is 8
# bytes: frame(u16)@0, thread(u8)@2, opcode(u8)@3, pc(u16)@4. Dumped by probes/awtrace.lua.
.equ TRACE_COUNT,     0x44080078     # entries logged so far
.equ FRAME_NO,        0x4408007C     # current VM frame (tick) number
.equ TRACE_BUF,       0x44800000     # 8 bytes/entry (up to ~1.6 MB here, clear of all else)
.equ TRACE_MAX,       200000         # enough to hold the whole intro
