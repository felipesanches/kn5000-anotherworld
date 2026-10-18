# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# probe2_task.s -- design (B): start a task of our own, then return to the firmware parked on the
# style converter's text screen (request 5). Records what the task can see while the UI is live.
.mnbase 0x502B8000
.equ CRE_TSK,   0x4C03D0C8      # 941 cre_tsk(d0 = id, a0 = &T_CTSK)
.equ STA_TSK,   0x4C03D8AB      # 941 sta_tsk(d0 = id, d1 = start code)
.equ DLY_TSK,   0x4C03DD6F      # 941 dly_tsk(d0 = ms)
.equ KERNEL_MS, 0x500D3C58
.equ PANEL,     0x5006BE40
.equ MOUT_WR,   0x5001F870
.equ TITLE_MAIN,0x5000099C      # GetTitleNow's table: main task's current title (0xF0000 + n)
.equ MAILBOX,   0x5031BC00      # byte 0 = request to the firmware; text from byte 1 for request 5
.equ SCRATCH,   0x502E0000
.equ FB,        0x9CE00000
Entry:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     SCRATCH, a2
    mov     (0x20, a2), d0      # entry count
    inc     d0
    mov     d0, (0x20, a2)
    cmp     1, d0
    bne     park
    mov     10, d2              # create + start our task: id 10, else 9
try:
    mov     d2, d0
    mov     probe_ctsk, a0
    mov     CRE_TSK, a1
    calls   (a1)
    mov     d0, (0x24, a2)      # last cre_tsk result
    cmp     0, d0
    beq     start
    add     -1, d2
    cmp     9, d2
    bge     try
    bra     park
start:
    mov     d2, (0x28, a2)      # task id used
    mov     d2, d0
    clr     d1
    mov     STA_TSK, a1
    calls   (a1)
    mov     d0, (0x2C, a2)      # sta_tsk result
park:
    mov     MAILBOX, a0         # request 5: show our text
    mov     5, d0
    movbu   d0, (a0)
    mov     msg, a1
    inc     a0
cpy:
    movbu   (a1), d0
    movbu   d0, (a0)
    inc     a0
    inc     a1
    cmp     0, d0
    bne     cpy
    ret     [d2,d3,a2,a3], 0x30

ProbeTask:
    add     -0x10, sp
loop:
    mov     SCRATCH, a2
    mov     (a2), d0
    inc     d0
    mov     d0, (a2)
    mov     (MOUT_WR), d0
    mov     d0, (0x10, a2)
    mov     (TITLE_MAIN), d0
    mov     d0, (0x14, a2)
    mov     (TITLE_MAIN + 4), d0
    mov     d0, (0x1C, a2)
    mov     (KERNEL_MS), d0
    mov     d0, (0x18, a2)
    mov     PANEL, a0
    mov     SCRATCH + 0x100, a1
    mov     SCRATCH + 0x200, a3
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
    mov     (a2), d0
    and     511, d0
    asl     1, d0
    mov     FB + 100*1280, a0
    add     d0, a0
    mov     16, d3
sq_row:
    mov     a0, a1
    mov     16, d2
    mov     0x07E0, d1
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

    .align  4
probe_ctsk:
    .long   0
    .long   1
    .long   ProbeTask
    .word   3
    .word   0
    .long   0x1000
msg:
    .asciz  "ANOTHER WORLD"
