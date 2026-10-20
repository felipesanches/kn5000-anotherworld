# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# perf_stub.s -- the SP7001 build's (MAME only) stand-ins for perf.s, the KN7APP.BIN build's speed
# measurement: no clock, no figures, the help screen's fourth page empty, the new blit only. The block
# at VM_PERF_BASE still holds the blit's state (display.s), so PerfInit clears it.

PerfInit:
    mov     VM_PERF_BASE, a0
    mov     0x1000 / 4, d1
    clr     d0
psi_zero:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     psi_zero
    mov     PFD_START, d0
    mov     d0, (PF_DAMAGE)
    mov     PF_PAL, a0              # a palette the game never has, so the first blit builds the pairs
    mov     8, d1
    mov     -1, d0
psi_pal:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     psi_pal
    rets

PerfPageBuild:
    mov     0xFFFF, d0
    movhu   d0, (PF_ITEMS)
    rets

PerfOverlay:
    clr     d0
    mov     d0, (PF_OVL_DUE)
    rets

PerfPhase:
PerfRestart:
PerfRegs:
PerfBench:
PerfFrameEnd:
PerfWindowEnd:
PerfSentinels:
PerfInput:
    rets
