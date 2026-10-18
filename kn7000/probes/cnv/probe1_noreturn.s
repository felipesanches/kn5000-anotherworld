# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# probe1_noreturn.s -- does a .CNV that never returns keep the KN7000 (941) usable?
# Loaded by DISK MENU > STYLE CONVERT at 0x502B8000 and called on the main task. Never
# returns: each pass records the panel switch bitmaps, the MIDI rings and the kernel
# millisecond counter into SCRATCH, moves a square across the LCD, and yields with dly_tsk.
.mnbase 0x502B8000
.equ DLY_TSK,   0x4C03DD6F      # 941 dly_tsk (942 0x4C03E295, matched by bytes)
.equ KERNEL_MS, 0x500D3C58      # 941 (942: 0x500D3C68)
.equ PANEL,     0x5006BE40      # 0x80 bytes around the switch bitmaps (942 CPR at 0x5006BE60)
.equ MOUT_WR,   0x5001F870      # 941 MIDI OUT 1 ring header 0x5001F864 + 0x0C
.equ MIN_WR,    0x5001F05C      # 941 MIDI IN 1 ring header 0x5001F050 + 0x0C
.equ SCRATCH,   0x502E0000      # inside the converter's own zeroed 0x30000-byte area
.equ FB,        0x9CE00000
Entry:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
loop:
    mov     SCRATCH, a2
    mov     (a2), d0            # heartbeat
    inc     d0
    mov     d0, (a2)
    mov     (MOUT_WR), d0
    mov     d0, (0x10, a2)
    mov     (MIN_WR), d0
    mov     d0, (0x14, a2)
    mov     (KERNEL_MS), d0
    mov     d0, (0x18, a2)
    mov     PANEL, a0
    mov     SCRATCH + 0x100, a1     # current bitmap bytes
    mov     SCRATCH + 0x200, a3     # every bit seen set since start
    mov     0x80, d2
cp:
    movbu   (a0), d0
    movbu   d0, (a1)
    movbu   (a3), d1
    or      d0, d1
    movbu   d1, (a3)
    inc     a0
    inc     a1
    inc     a3
    add     -1, d2
    bne     cp
    # a 16x16 square at x = heartbeat mod 512, row 100
    mov     (a2), d0
    and     511, d0
    asl     1, d0
    mov     FB + 100*1280, a0
    add     d0, a0
    mov     16, d3
sq_row:
    mov     a0, a1
    mov     16, d2
    mov     0xF800, d1
sq_px:
    movhu   d1, (a1)
    add     2, a1
    add     -1, d2
    bne     sq_px
    add     1280, a0
    add     -1, d3
    bne     sq_row
    mov     16, d0
    mov     DLY_TSK, a1
    calls   (a1)
    bra     loop
