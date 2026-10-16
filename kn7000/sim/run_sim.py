# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
# Offline MN10300-simulator harness for the Another World rasterizer.
#!/usr/bin/env python3
# Run the rasterizer in the MN10300 simulator and report STEP1/STEP2 + spans drawn.
import sys, os
sys.path.insert(0, os.path.abspath("/home/fsanches/compartilhado/kn7000_disassembly/tools"))
import mn10300_sim as S
code = open("/home/fsanches/compartilhado/kn5000-anotherworld/kn7000/sim/sim_test.bin", "rb").read()
mem = S.Mem.__new__(S.Mem)
mem.ram = bytearray(0x2000000); mem.devram = bytearray(0x100000); mem.io_log = []
mem.program = b""; mem.table = b""
# place our code at 0x50000000 (RAM region base)
mem.ram[0:len(code)] = code
sim = S.Sim(mem); sim.hle = False
sim.pc = 0x50000000
sim.sp = 0x50080000               # a stack in sim RAM
VM = 0x50100000
steps = 0
while steps < 5_000_000:
    if sim.pc == 0x5000006E:       # reached `done`
        break
    try:
        sim.step()
    except Exception as e:
        print(f"stop at pc=0x{sim.pc:08X} after {steps} steps: {e}"); break
    steps += 1
else:
    print("step cap hit")
def u16(a): return int.from_bytes(mem.ram[a-0x50000000:a-0x50000000+2],"little")
def s16(a): v=u16(a); return v-0x10000 if v>=0x8000 else v
def u32(a): return int.from_bytes(mem.ram[a-0x50000000:a-0x50000000+4],"little")
print(f"ran {steps} steps, pc=0x{sim.pc:08X}")
print(f"NUM={mem.ram[VM-0x50000000]} XMIN={s16(VM+6)} XMAX={s16(VM+8)} YMIN={s16(VM+0xA)} YMAX={s16(VM+0xC)}")
print(f"STEP1={u32(VM+0x2C)} ({u32(VM+0x2C) if u32(VM+0x2C)<0x80000000 else u32(VM+0x2C)-0x100000000}) STEP2={u32(VM+0x30)} POLY_H={s16(VM+0x1A)} HLINEY={s16(VM+0xE)}")
page=0x50200000-0x50000000
nz=sum(1 for i in range(64000) if mem.ram[page+i])
print(f"page non-zero: {nz}")
