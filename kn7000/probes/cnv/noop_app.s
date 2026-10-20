# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# noop_app.s -- the control application of the IC23 checks (awcnv_test.lua AWT_MODE=control): a
# KN7APP.BIN for the loader KN7LOAD.CNV (kn7cnv.inc) that ends the conversion on its first call
# (request 0xFE) and touches nothing but the mailbox. run_cnv_tests.sh puts it on the card as
# KN7APP.BIN beside the same game files, so the control run walks the same menus, runs the same
# loader from the same floppy and has it load and call an application, without the game.
# (Assembled with xapasm -I <the loader's folder>, then the loader's mkapp.py.)
.include "kn7cnv.inc"
.mnbase APP_BASE
NoopHeader:
    .ascii  "KN7A"                  # AH_MAGIC
    .long   LOADER_ABI              # AH_ABI
    .long   0                       # AH_SIZE (mkapp.py)
    .long   NoopEntry               # AH_ENTRY
    .long   0                       # AH_CRC (mkapp.py)
    .long   APP_BASE                # AH_BASE
    .long   0, 0
    .ascii  "NO-OP CONTROL"         # AH_NAME
    .space  NoopHeader + 0x40 - .
NoopEntry:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     MAILBOX, a0
    mov     0xFE, d0
    movbu   d0, (a0)
    ret     [d2,d3,a2,a3], 0x20
