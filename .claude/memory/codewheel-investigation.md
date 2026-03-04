# Code Wheel Investigation Report (2026-02-11)

## Problem
When the user enters correct code wheel combinations in Part 0 (Protection), the game should proceed to splash screens then Part 1 (Intro). Instead, the code wheel screen reloads indefinitely. The bypass path (skipping code wheel entirely, starting from Part 1) works correctly.

## Branch
All investigation code saved on branch: `codewheel-investigation`

## What Was Done

### Diagnostic Infrastructure
- Added VRAM-direct diagnostic bars drawn AFTER `UPDATE_DISPLAY` (visible on first line of game area at 0x1A1900)
  - Cols 0-3: flashing frame counter (proves VM frames running)
  - Cols 4-7: constant white (proves end-of-frame reached)
  - Cols 8-11: green if initForPart called for non-Protection part (sticky flag)
  - Cols 12-15: red if LOAD triggered part switch (sticky flag)
- Added `DIAG_FRAME_COUNTER`, `DIAG_INITPART_FLAG`, `DIAG_LOAD_FLAG` variables in main.asm

### Part 0 Bytecode Analysis (resource-0x15.bin)

#### Code Wheel Flow
1. Thread 0 starts at PC=0x0000, does video init, sets thread 20=0x02CE, kills itself
2. Thread 20 runs code wheel UI at 0x02CE
3. UI initialization: fills pages, draws strings, sets up thread 60 (display loop) and thread 30 (var[0x31]=0 loop)
4. Interaction loop at 0x0B0A reads input vars (0xFA=action, 0xE5=up/down, 0xFC=left/right)
5. When ACTION pressed → 0x0D80 handler

#### Symbol Lookup (subroutine 0x023D)
- var[0x05] = cursor position (0-15)
- Sets var[0x06] from symbol array var[0x0A]-[0x19]:
  - Row 1 (positions 0-7): values 1,2,16,4,5,6,0,**99(0x63)**
  - Row 2 (positions 8-15): values 7,8,9,10,11,12,0,**98(0x62)**
  - Position 7 (val=0x63) and position 15 (val=0x62) are end-of-dial markers

#### Action Handler (0x0D80)
- Calls 0x0AD9 (checks if var[0x02]==4 → all inputs collected → RET via 0x109D)
- Calls 0x023D (sets var[0x06] from cursor position)
- var[0x06]==0x63 → JUMP 0x0C2A (first dial confirmed)
- var[0x06]==0x62 → fall through to 0x0DA0 (second dial confirmed)
- Other → JUMP 0x0DBD (record symbol, increment var[0x02])
- After processing: debounce loop (0x0DFD → PAUSE → check ACTION released → JUMP 0x0B0A)

#### Success Path (0x0CC2 — NOT 0x0CC0!)
- **IMPORTANT**: 0x0CC0 is NOT an instruction boundary! It's the last 2 bytes of `SET_VECT thread 30 = 0x0D78` at 0x0CBE. The actual success path starts at **0x0CC2**.
- Previous sessions incorrectly assumed 0x0CC0 was `SELECT_PAGE 0x78`.

Actual instruction flow (decoded from raw bytes at 0x0C9C):
```
0C9C: COND_JUMP if var[0x2C] == var[0x1E] then JUMP 0x0CB7
0CA2: COND_JUMP if var[0x2C] == var[0x1F] then JUMP 0x0CB7
0CA8: COND_JUMP if var[0x2C] == var[0x20] then JUMP 0x0CB7
0CAE: COND_JUMP if var[0x2C] == var[0x21] then JUMP 0x0CB7
0CB4: JUMP 0x0D4F          ← ALL CHECKS FAILED → restart
0CB7: CALL 0x0A15
0CBA: SET_VECT thread 10 = 0x0D70   (sets var[0x31]=1 each frame)
0CBE: SET_VECT thread 30 = 0x0D78   (sets var[0x31]=0 each frame)
0CC2: COND_JUMP if var[0x31] == 1 then JUMP 0x0CD7  (second visit → validate)
0CC8: MOV_CONST var[0x31] = 1        (first visit)
0CCC: MOV var[0xBC] = var[0x37]
0CCF: OR var[0xBC] |= 0x0010
0CD3: JUMP 0x02D1                    (reload code wheel for round 2)
```

#### Two-Round Mechanism
- First round: user enters symbols, reaches 0x0CC2, var[0x31]!=1 → set var[0x31]=1, reload code wheel (0x02D1)
- Second round reload: at 0x02ED checks var[0x31]==1 → sets thread 60=0x10C1 (var[0x1B]=0x0015)
- Second round: user enters symbols again, reaches 0x0CC2, var[0x31]==1 (set by thread 10 which runs before thread 20) → JUMP 0x0CD7

#### Final Validation (0x0CD7)
```
0CD7: COND_JUMP if var[0x1B] != 0x0015 then JUMP 0x0D4F  (fail)
0CDD: AND var[0x32] &= 0x001F
0CE1: COND_JUMP if var[0x32] < 0x0006 then JUMP 0x0D4F   (fail)
0CE7: COND_JUMP if var[0x64] < 0x0014 then JUMP 0x0D4F   (fail)
0CED: ... proceed to set up threads for splash screens
```

## Unfinished Analysis

### Key Unknown: How Does 0x0C9C Get Reached?
The 4 COND_JUMPs at 0x0C9C-0x0CB3 check `var[0x2C]` against `var[0x1E]-[0x21]`. This is the gate to the success path. Need to:
1. Find what sets var[0x2C] — likely the "expected" code value
2. Find what code path reaches 0x0C9C — probably via the 0x0D4F restart which sets var[0xC9]=1, and then some thread checks var[0xC9]
3. Understand why the user's combinations fail the check

### Possible Root Causes for Infinite Reload
1. **var[0x2C] mismatch**: The expected code (var[0x2C]) doesn't match any of the collected inputs (var[0x1E-0x21])
2. **Validation at 0x0CD7 fails**: var[0x32] < 6 or var[0x64] < 20
3. **Thread ordering issue**: thread 10/20/30 timing affects var[0x31]
4. **Input variable bleed**: our INPUT_UPDATE_PLAYER overwrites vars the code wheel expects to control

### Raw Byte Decode (0x0C9C-0x0CB7)
```
0C9C: 0A 80 2C 1E 0C B7  → COND_JUMP var[0x2C]==var[0x1E] → 0x0CB7
0CA2: 0A 80 2C 1F 0C B7  → COND_JUMP var[0x2C]==var[0x1F] → 0x0CB7
0CA8: 0A 80 2C 20 0C B7  → COND_JUMP var[0x2C]==var[0x20] → 0x0CB7
0CAE: 0A 80 2C 21 0C B7  → COND_JUMP var[0x2C]==var[0x21] → 0x0CB7
0CB4: 07 0D 4F            → JUMP 0x0D4F
0CB7: 04 0A 15            → CALL 0x0A15
0CBA: 08 0A 0D 70         → SET_VECT 10=0x0D70
0CBE: 08 1E 0D 78         → SET_VECT 30=0x0D78
```

## Related Files
- Part 0 bytecode: `src/resources/resource-0x15.bin`
- Disassembler: `/tmp/aw_disasm.py` (also in project for reference)
- Reference HLE: `../../kn5000-roms-disasm/mame_driver/src/devices/cpu/anotherworld/`
