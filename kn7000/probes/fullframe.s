# Ride-along add-on: keep BASEEXT, but run a task that fills the WHOLE 640x240
# frame with a moving pattern every 20 ms. Tests whether a full-screen blit
# persists on the firmware's (static) SP7001 screen.
.include "../src/platform.inc"
.mnbase 0x502B6000
hook:
    add     -0x20, sp
    mov     d0, (0x10, sp)
    mov     d1, (0x14, sp)
    mov     a0, (0x18, sp)
    mov     a1, (0x1c, sp)
    call    start, 0, 0
    mov     (0x10, sp), d0
    mov     (0x14, sp), d1
    mov     (0x18, sp), a0
    mov     (0x1c, sp), a1
    add     0x20, sp
    movm    [a2,a3], (sp)
    add     -8, sp
    jmp     0x5029B005
start:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     TASK_ID, d0
    mov     ctsk, a0
    mov     CRE_TSK_X, a1
    calls   (a1)
    mov     TASK_ID, d0
    clr     d1
    mov     STA_TSK, a1
    calls   (a1)
    ret     [d2,d3,a2,a3], 0x10
task:
    add     -0x10, sp
loop:
    mov     (SYS_MS), d3
    lsr     5, d3                   # slow colour march
    mov     FB, a2
    mov     FB_W*FB_H, d2           # pixel count
px:
    mov     d2, d0
    add     d3, d0
    asl     6, d0
    movhu   d0, (a2)
    add     2, a2
    add     -1, d2
    bne     px
    mov     20, d0
    mov     DLY_TSK, a1
    calls   (a1)
    bra     loop
    .align 4
ctsk:
    .long 0
    .long 1
    .long task
    .word TASK_PRI
    .word 0
    .long TASK_STACK
