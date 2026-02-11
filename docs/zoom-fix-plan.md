# Zoom Rendering Fix Plan

## Problem
Lester shrinks and grows incorrectly during walking scenes. The original game does not have such intense zooming in those scenes.

## Root Cause Analysis

Comparing our opcode 0x40 handler with the [reference implementation](https://github.com/fabiensanglard/Another-World-Bytecode-Interpreter/blob/master/src/vm.cpp), I found two bugs:

### Bug 1: Case 3 (video2 select) corrupts VM_PC

In the reference, zoom cases 0 and 3 push back the tentatively-fetched zoom byte (`--_scriptPtr.pc`). Our code correctly doesn't consume a byte for these cases, BUT case 3 overwrites XIX with INTRO_VIDEO_2 before VM_PC is computed:

```asm
_0x40_zoom_case3:
    LD XIX, INTRO_VIDEO_2      ; <-- CLOBBERS XIX (was bytecode pointer!)
    LD (CUR_VIDEO_DATA), XIX
_0x40_zoom_done:
    LD XDE, XIX                ; XDE = INTRO_VIDEO_2 (WRONG! Should be bytecode)
    SUB XDE, INTRO_BYTECODE
    LD (VM_PC), DE             ; VM_PC = garbage offset
```

After readAndDrawPolygon returns, `JP _after_PC_update` reloads XIX from the corrupted VM_PC. The VM starts executing video polygon data as bytecode, randomly modifying VM variables (including zoom, position, etc.), causing visual artifacts.

### Bug 2: Case 2 (literal zoom byte) discards the zoom value

Reference case 2: the fetched byte IS the zoom value (used as-is).
Our code: byte consumed (`INC XIX`) but zoom stays at 0x40 (default).

```asm
; CURRENT (wrong):
    INC XIX              ; consume byte but ignore it
    JP _0x40_zoom_done   ; C still = 0x40

; SHOULD BE:
    LD C, (XIX)          ; C = zoom byte
    INC XIX
    JP _0x40_zoom_done
```

## Fix

### Fix 1: Case 3 — save/restore XIX around CUR_VIDEO_DATA update

```asm
_0x40_zoom_case3:
    ; case 3: m_useVideo2 = true, zoom = 0x40
    PUSH XIX
    LD XIX, INTRO_VIDEO_2
    LD (CUR_VIDEO_DATA), XIX
    POP XIX                    ; restore bytecode pointer
```

### Fix 2: Case 2 — use byte as zoom value

```asm
_0x40_zoom_not_1:
    CP A, 2
    JP NE, _0x40_zoom_case3
    ; case 2: zoom = fetch_byte() (literal zoom value)
    LD C, (XIX)
    INC XIX
    JP _0x40_zoom_done
```

## Files to Change

- `src/another_world_vm.asm`: Two edits in the opcode 0x40 zoom section (~lines 1450-1462)
