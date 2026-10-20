# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# noop_cnv.s -- the control converter of the IC23 checks (awcnv_test.lua AWT_MODE=control): it ends the
# conversion on its first call (request 0xFE) and touches nothing but the mailbox. run_cnv_tests.sh
# puts it on a copy of the game floppy as AW.CNV, so the control run walks the same menus, lists the
# same files and runs a converter, without the game.
.mnbase 0x502B8000
.equ MAILBOX,   0x5031BC00      # byte 0 = the request to the firmware
NoopEntry:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     MAILBOX, a0
    mov     0xFE, d0
    movbu   d0, (a0)
    ret     [d2,d3,a2,a3], 0x20
