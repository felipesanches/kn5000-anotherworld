#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# ic23_guard.py -- does any constant, label or operand of a KN7000 build name an address in IC23 or
# in the user-memory pools (or, for an application of KN7LOAD.CNV, write into the loader)?
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
# and, with --loader KN7CNV.INC (the loader's contract, technics-roms-disasm kn7000/tools/cnv_romdump),
#   * the loader's resident area [CNV_BASE, APP_BASE) = 0x502B8000-0x502B9FFF (and its view at
#     0x902B8000): KN7LOAD.CNV's code, line buffer, variables and service table, which stay in RAM
#     and run on every converter call while the application runs. The application may only READ the
#     service table: the one use allowed there is an absolute load `mov (SVC + SV_x), REG` whose
#     address lies in the table [SVC, SVC + its last SV_ field + 4). A name defined by .equ there
#     (CNV_BASE, SVC, ...) is not a use; a label there, an immediate (mov SVC, a0), a store, a .long
#     or any other address in the area is a hit.
#
#   python3 -I tools/ic23_guard.py <dir of xapasm.py> SRC.s [-I DIR ...] [--loader KN7CNV.INC]
# Prints every hit (file:line, expression, value, region) and a last line, "ic23_guard: SRC: clean"
# or "ic23_guard: SRC: N reference(s) into IC23, the user pools or the loader"; exit status 0 only
# when clean. With --loader it also prints how many service-table loads it allowed. The Makefile runs
# it before assembling KN7APP.BIN (which must be clean, with --loader) and the SP7001 build (which
# must NOT be: it lives in CS1 and is MAME-only, so a clean verdict there means this check broke).
#
# How: assembles with the toolchain's own xapasm (unchanged) through a subclass whose eval() records
# every value an expression produces on the final pass -- operands of every instruction, .long data,
# .equ right-hand sides -- with file:line, then checks those and every final symbol. A value is
# checked as an address in [lo, hi); a base + size extent is not. Addresses computed at run time
# (base + index) are not seen: that is what the run-time guard is for (cnv_main.s GuardRange,
# vm.s GuardPage) and what the MAME tests measure (probes/cnv/README.md).
import os
import re
import sys

FORBIDDEN = [(0x44000000, 0x48000000, "CS1: IC23, the backup SRAM (panel memories)"),
             (0x84000000, 0x88000000, "CS1 uncached view: IC23"),
             (0x50180000, 0x50298000, "user-memory pool (kept across power-off)"),
             (0x90180000, 0x90298000, "user-memory pool, uncached view")]


LOADER = "the loader's resident area (KN7LOAD.CNV: code, variables, service table)"


def bad(v):
    v &= 0xFFFFFFFF
    for lo, hi, what in FORBIDDEN:
        if lo <= v < hi:
            return what
    return None


def loader_area(inc):
    """[CNV_BASE, APP_BASE) and the service table [SVC, SVC + last SV_ field + 4), from kn7cnv.inc."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from aw_extract import layout_consts  # noqa: E402
    L = layout_consts(inc)
    sv_end = max(v for k, v in L.items() if k.startswith("SV_")) + 4
    return L["CNV_BASE"], L["APP_BASE"], L["SVC"], L["SVC"] + sv_end


def code_of(raw):
    """A source line without its comment and label: (op, [operands])."""
    line, quoted = "", False
    for ch in raw:
        if ch == '"':
            quoted = not quoted
        elif ch in "#;" and not quoted:
            break
        line += ch
    line = re.sub(r"^\s*[A-Za-z_][\w.]*:", "", line).strip()
    op, _, rest = line.partition(" ")
    ops, depth, cur = [], 0, ""
    for ch in rest:
        if ch == "," and depth == 0:
            ops.append(cur.strip())
            cur = ""
            continue
        depth += ch == "("
        depth -= ch == ")"
        cur += ch
    if cur.strip():
        ops.append(cur.strip())
    return op.lower(), ops


def main():
    sys.path.insert(0, sys.argv[1])
    import xapasm  # noqa: E402  (the toolchain's assembler, technics-roms-disasm kn7000/tools)

    args = sys.argv[2:]
    src, inc = args[0], [args[i + 1] for i, a in enumerate(args) if a == "-I"]
    svc = None
    if "--loader" in args:
        lo, hi, s0, s1 = loader_area(args[args.index("--loader") + 1])
        FORBIDDEN.extend([(lo, hi, LOADER), (lo | 0x40000000, hi | 0x40000000, LOADER + ", uncached view")])
        svc = (s0, s1)

    class Guard(xapasm.XapAsm):
        def __init__(self, incdirs):
            super().__init__(incdirs)
            self.hits, self.where, self.raw, self.svc_loads = [], "?", "", set()

        def _file(self, path):
            for n, raw in enumerate(open(path), 1):
                self.where, self.raw = f"{os.path.relpath(path)}:{n}", raw
                try:
                    self._line(raw, os.path.dirname(os.path.abspath(path)))
                except (xapasm.AsmError, xapasm.enc.EncError) as e:
                    raise xapasm.AsmError(f"{path}:{n}: {e}") from None

        def allowed(self, expr, v, what):
            """In the loader's area: a definition, or a load from the service table."""
            if not what.startswith(LOADER):
                return False
            op, ops = code_of(self.raw)
            if op == ".equ":
                return True
            if (op == "mov" and len(ops) == 2 and ops[0].startswith("(") and ops[0].endswith(")")
                    and ops[0][1:-1].strip() == expr and ops[1].lower() in xapasm.REGS
                    and svc[0] <= v < svc[1] and v % 4 == 0):
                self.svc_loads.add(self.where)
                return True
            return False

        def eval(self, expr):
            v = super().eval(expr)
            what = bad(v) if self.final else None
            if what and not self.allowed(expr.strip(), v & 0xFFFFFFFF, what):
                self.hits.append((self.where, expr.strip(), v, what))
            return v

    g = Guard(inc)
    g.assemble(src)
    seen = set()
    for where, expr, v, what in g.hits:
        if (where, v) not in seen:
            seen.add((where, v))
            print(f"{where}: {expr} = 0x{v & 0xFFFFFFFF:08X} -> {what}")
    # a symbol's value: a label anywhere forbidden, or an .equ name in CS1 or the pools (a name
    # defined in the loader's area is the contract's, CNV_BASE, SVC, ...: its uses are checked above)
    syms = [(k, v) for k, v in g.syms.items() if bad(v) and (k in g.labels or not bad(v).startswith(LOADER))]
    for k, v in sorted(syms, key=lambda kv: kv[1]):
        print(f"symbol {k} = 0x{v & 0xFFFFFFFF:08X} -> {bad(v)}")
    n = len(seen) + len(syms)
    if svc:
        print(f"ic23_guard: {len(g.svc_loads)} load(s) from the loader's service table "
              f"0x{svc[0]:08X}-0x{svc[1] - 1:08X} allowed, nothing else in 0x{lo:08X}-0x{hi - 1:08X}")
    print(f"ic23_guard: {src}: {n} reference(s) into IC23, the user pools or the loader" if n
          else f"ic23_guard: {src}: clean")
    sys.exit(1 if n else 0)


if __name__ == "__main__":
    main()
