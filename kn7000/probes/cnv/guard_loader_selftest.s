# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# guard_loader_selftest.s -- what tools/ic23_guard.py --loader must find (run_cnv_tests.sh `guard`).
# Never run: each line marked HIT names the loader's resident area (or IC23, or a pool) in a way the
# application must not; the lines marked ok are the one allowed use, a load from the service table,
# and definitions. The guard must report exactly the 7 HIT lines; were it to call this file clean,
# the check itself would be broken.
.include "kn7cnv.inc"
.mnbase APP_BASE
.equ MY_TABLE,  SVC + SV_OPEN       # ok: a definition
    mov     (SVC+SV_OPEN), a0       # ok: a load from the service table
    mov     (SVC + SV_MSCOUNT), d0  # ok: the same
    mov     d0, (SVC+SV_OPEN)       # HIT: a store into the service table
    mov     SVC, a0                 # HIT: the table's address taken (a write through it would follow)
    mov     (LOADER_VARS), d0       # HIT: the loader's variables, not its service table
    movbu   (SVC+SV_FOUND), d0      # HIT: only whole-word loads are expected
    mov     (CNV_BASE+0x100), d1    # HIT: the loader's code
    .long   SVC+SV_READ             # HIT: an address in the area as data
    mov     (0x44000100), d0        # HIT: IC23
selftest_end:
