#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# ic23_guard.py -- does any constant, label or operand of a KN7000 build name an address in IC23 or
# in the user-memory pools?
#
# Question it answers: before a build reaches a real KN7000, prove that no address the program
# names lands in
#   * chip select CS1, 0x44000000-0x47FFFFFF, and its uncached view 0x84000000-0x87FFFFFF: IC23, the
#     256 KB battery-backed SRAM with the panel settings and the 104 PANEL MEMORY records, which
#     repeats every 256 KB through the whole chip select (confirmed on the owner's unit, 2026-10-20;
#     kn7000_mame notes/ic23-nvram-2026-10-20);
#   * the user-memory pools 0x50180000-0x50297FFF and their view 0x90180000-0x90297FFF: COMPOSER
#     styles, pads and the rest of the user data the firmware never clears and keeps across
#     power-off (technics-roms-disasm kn7000/notes/work-ram-map.md; 893's boot starts zeroing at the
#     same 0x50298000, research-scratch aw-memory-plan/prefill893.lua).
#
#   python3 -I tools/ic23_guard.py <dir of xapasm.py> SRC.s [-I DIR ...]
# Prints every hit (file:line, expression, value, region) and a last line, "ic23_guard: SRC: clean"
# or "ic23_guard: SRC: N reference(s) into IC23 or the user pools"; exit status 0 only when clean.
# The Makefile runs it before assembling AW.CNV (which must be clean) and the SP7001 build (which
# must NOT be: it lives in CS1 and is MAME-only, so a clean verdict there means this check broke).
#
# How: assembles with the toolchain's own xapasm (unchanged) through a subclass whose eval() records
# every value an expression produces on the final pass -- operands of every instruction, .long data,
# .equ right-hand sides -- with file:line, then checks those and every final symbol. A value is
# checked as an address in [lo, hi); a base + size extent is not. Addresses computed at run time
# (base + index) are not seen: that is what the run-time guard is for (cnv_main.s GuardRange,
# vm.s GuardPage) and what the MAME tests measure (probes/cnv/README.md).
import os
import sys

FORBIDDEN = [(0x44000000, 0x48000000, "CS1: IC23, the backup SRAM (panel memories)"),
             (0x84000000, 0x88000000, "CS1 uncached view: IC23"),
             (0x50180000, 0x50298000, "user-memory pool (kept across power-off)"),
             (0x90180000, 0x90298000, "user-memory pool, uncached view")]


def bad(v):
    v &= 0xFFFFFFFF
    for lo, hi, what in FORBIDDEN:
        if lo <= v < hi:
            return what
    return None


def main():
    sys.path.insert(0, sys.argv[1])
    import xapasm  # noqa: E402  (the toolchain's assembler, technics-roms-disasm kn7000/tools)

    class Guard(xapasm.XapAsm):
        def __init__(self, incdirs):
            super().__init__(incdirs)
            self.hits, self.where = [], "?"

        def _file(self, path):
            for n, raw in enumerate(open(path), 1):
                self.where = f"{os.path.relpath(path)}:{n}"
                try:
                    self._line(raw, os.path.dirname(os.path.abspath(path)))
                except (xapasm.AsmError, xapasm.enc.EncError) as e:
                    raise xapasm.AsmError(f"{path}:{n}: {e}") from None

        def eval(self, expr):
            v = super().eval(expr)
            if self.final and bad(v):
                self.hits.append((self.where, expr.strip(), v, bad(v)))
            return v

    args = sys.argv[2:]
    src, inc = args[0], [args[i + 1] for i, a in enumerate(args) if a == "-I"]
    g = Guard(inc)
    g.assemble(src)
    seen = set()
    for where, expr, v, what in g.hits:
        if (where, v) not in seen:
            seen.add((where, v))
            print(f"{where}: {expr} = 0x{v & 0xFFFFFFFF:08X} -> {what}")
    syms = [(k, v) for k, v in g.syms.items() if bad(v)]
    for k, v in sorted(syms, key=lambda kv: kv[1]):
        print(f"symbol {k} = 0x{v & 0xFFFFFFFF:08X} -> {bad(v)}")
    n = len(seen) + len(syms)
    print(f"ic23_guard: {src}: {n} reference(s) into IC23 or the user pools" if n else f"ic23_guard: {src}: clean")
    sys.exit(1 if n else 0)


if __name__ == "__main__":
    main()
