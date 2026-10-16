# Offline rasterizer simulation

Runs the Another World polygon rasterizer (`../src/vm.s`) in the MN10300 interpreter
from `kn7000_disassembly/tools/mn10300_sim.py`, with the VM state and page in sim RAM,
so the edge-walk can be traced without the ~1-minute MAME cycle.

    python3 -I sim/run_sim.py     # assembles sim/sim_test.bin first via `make`, then runs

Note: the simulator's `divu` is incomplete, so the step magnitudes differ from the real
CPU; it is used to validate control flow (the loop runs, spans are drawn), not exact
fixed-point values. The rasterizer draws correctly in the sim; a KN7000-specific
`STEP2 = 0` discrepancy remains to be resolved on real MAME.
