#!/usr/bin/env python3
# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
#
# Ground-truth for the DRAW_STRING (op 0x12) rendering check: using vm-gui's OWN decoder
# and the canonical scheduler semantics (same as reference_trace.py), replay the intro
# bytecode and report, per VM frame, every DRAW_STRING and the exact text/position/colour
# it should draw. The text comes from the SAME str_index/str_data blobs the KN7000 port
# loads from the SD card, so the port's render can be checked glyph-for-glyph against this.
#
# Question it answers: at frame F, which strings should be on the AW canvas, where?
#
#   python3 -I drawstring_oracle.py [frame ...]
# With frame args, prints the strings visible at each (nearest DRAW_STRING frame <= F,
# since text is redrawn every frame while on screen). With none, lists all 0x12 ops.
import sys, struct

VM_GUI = "/home/fsanches/compartilhado/another-world-vm-gui"
BYTECODE = ("/home/fsanches/compartilhado/custom-kn5000-roms/"
            "anotherworld/src/resources/resource-0x18.bin")
STRIDX = ("/home/fsanches/compartilhado/custom-kn5000-roms/"
          "anotherworld/src/hardcoded_data/str_index.rom")
STRDAT = ("/home/fsanches/compartilhado/custom-kn5000-roms/"
          "anotherworld/src/hardcoded_data/str_data.rom")

sys.path.insert(0, VM_GUI)
from vm_gui.scheduler import Scheduler
from vm_gui.state import VMState, NUM_CHANNELS, PC_UNSET
from vm_gui.interpreter import StubBackend, CallStack, execute
from vm_gui.opcodes import decode, DecodeError

# Canonical KILL: do not clear pc_next (matches Fabien Sanglard / the KN7000 port).
def _kill(self, ch):
    self.channels[ch].pc = PC_UNSET
VMState.kill_channel = _kill

RESET_VARS = {0xE4: 0x14, 0x3C: 0x1234, 0x54: 0x81, 0xBC: 0x10,
              0xC6: 0x80, 0xF2: 0x0FA0, 0xDC: 0x21}


def load():
    bc = open(BYTECODE, "rb").read()
    idx = open(STRIDX, "rb").read()
    dat = open(STRDAT, "rb").read()
    def strof(sid):
        if sid * 2 + 1 >= len(idx):
            return "<id oob>"
        off = struct.unpack_from("<H", idx, sid * 2)[0]
        if off >= len(dat):
            return "<off oob>"
        e = dat.find(b"\0", off)
        return dat[off:(e if e >= 0 else len(dat))].decode("latin1").replace("\n", "\\n")
    return bc, strof


def replay(bc):
    """Return {frame: [(sid, x, y, color), ...]} for every DRAW_STRING, stopping at the
    part-switch LOAD 0x3E8x (end of the intro)."""
    st = VMState()
    sched = Scheduler(bc, st, StubBackend(), CallStack())
    sched.reset()
    for i, v in RESET_VARS.items():
        st.write_var(i, v)
    per = {}
    stop = False
    for frame in range(20000):
        for ch in st.channels:
            if ch.pc_next != PC_UNSET:
                ch.pc = PC_UNSET if ch.pc_next == 0xFFFE else ch.pc_next
                ch.pc_next = PC_UNSET
        for ci in range(NUM_CHANNELS):
            ch = st.channels[ci]
            if not ch.is_runnable():
                continue
            n = 0
            while n < Scheduler.INSTR_BUDGET:
                pcb = ch.pc
                try:
                    d = decode(bc, ch.pc)
                except (DecodeError, IndexError):
                    ch.frozen = True
                    break
                b0 = d.raw_first_byte & 0xFF
                if b0 == 0x12:
                    sid = (bc[pcb + 1] << 8) | bc[pcb + 2]
                    per.setdefault(frame, []).append((sid, bc[pcb + 3], bc[pcb + 4], bc[pcb + 5]))
                if b0 == 0x0C and bc[pcb + 3] == 0x02:
                    for c in range(bc[pcb + 1], (bc[pcb + 2] & 0x3F) + 1):
                        if 0 <= c < NUM_CHANNELS:
                            st.channels[c].pc_next = 0xFFFE
                    ch.pc = d.pc_after
                    n += 1
                    continue
                if b0 == 0x19 and pcb + 2 < len(bc):
                    w = (bc[pcb + 1] << 8) | bc[pcb + 2]
                    if (w & 0xFFF0) == 0x3E80:
                        stop = True
                        break
                a = execute(d, st, ci, sched.callstack, StubBackend())
                n += 1
                if a in ("yield", "killed", "frozen"):
                    break
            if stop:
                break
        sched.tick_count += 1
        if stop:
            break
    return per


def main():
    bc, strof = load()
    per = replay(bc)
    frames = [int(a) for a in sys.argv[1:]]
    if not frames:
        for fr in sorted(per):
            for sid, x, y, col in per[fr]:
                print(f"frame {fr}: id=0x{sid:03X} x={x} y={y} col={col}  {strof(sid)!r}")
        return
    for tf in frames:
        fr = tf
        while fr >= 0 and fr not in per:
            fr -= 1
        ops = per.get(fr, [])
        print(f"\n=== frame {tf} (last DRAW_STRING at {fr}): {len(ops)} string(s) ===")
        for sid, x, y, col in ops:
            print(f"   id=0x{sid:03X} x={x} y={y} col={col}  {strof(sid)!r}")


if __name__ == "__main__":
    main()
