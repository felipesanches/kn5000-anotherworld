# Code Review: KN5000 Another World VM Port

## Comparison with reference MAME HLE implementation

Reference commit: https://github.com/felipesanches/mame/commit/7cbb93bc3ee05f5ffdd083081530ac0daa2dfa84

### Fully Implemented
- **Opcode 0x00** (movConst) - OK
- **Opcode 0x04** (CALL) - OK
- **Opcode 0x05** (RET) - OK
- **Opcode 0x06** (pauseThread/BREAK) - OK
- **Opcode 0x07** (JMP) - OK
- **Opcode 0x08** (setVect) - OK
- **Opcode 0x09** (DJNZ) - OK
- **Opcode 0x0B** (setPalette) - OK
- **Opcode 0x0D** (selectVideoPage) - OK
- **Opcode 0x0E** (fillVideoPage) - OK
- **Opcode 0x10** (blitFramebuffer) - OK (missing pause-slices timing, but functional)
- **Opcode 0x11** (killThread) - OK
- **Opcode 0x80** (video instruction high bit) - OK
- Polygon rendering pipeline (readVertices, fillPolygon, calcStep, readAndDrawPolygonHierarchy) - OK
- Thread scheduler (NEXT_THREAD, CHECK_THREAD_REQUESTS) - OK
- Video page management (GET_PAGE_PTR, UPDATE_DISPLAY, VIDEO_START) - OK
- Character/string drawing - OK

---

### Critical Missing/Broken Items

#### 1. **Opcode 0x01 (MOV) - BUG: doesn't actually copy the value**
(`another_world_vm.asm:1148-1165`)

The MOV instruction reads `srcVariableId` and `dstVariableId` but the write at line 1163 writes to `XIY` which still points to `VM_VARIABLES + srcVariableId`, not `dstVariableId`. The `POP WA` on line 1162 restores dstVariableId, but XIY is never recalculated to point at it. The variable index in XWA is never used to recompute the destination address.

#### 2. **Opcode 0x02 (ADD) - BUG: same as MOV, doesn't add**
(`another_world_vm.asm:1168-1186`)

This is literally a copy of MOV's code. It reads the source value but never adds it to the destination. It should: read dst value, read src value, add them, write back to dst.

#### 3. **Opcode 0x03 (addConst) - Endianness bug**
(`another_world_vm.asm:1189-1203`)

The `fetch_word()` at line 1199 reads 2 bytes from the bytecode. But the reference uses big-endian reads (`READ_WORD_AW` = `READ_BYTE(A) << 8 | READ_BYTE(A+1)`), while `LD WA, (XIX)` reads in native little-endian order. The bytecode is big-endian (Amiga/68k origin). **This same endianness issue likely affects all `fetch_word()` operations throughout the code** (opcodes 0x00, 0x03, 0x04, 0x07, 0x08, 0x09, 0x0A, 0x0B, etc.).

#### 4. **Opcode 0x0A (condJmp) - NOT IMPLEMENTED**
(`another_world_vm.asm:1316-1325`)

This just skips 5 bytes and does nothing. The conditional jump is essential for all game logic (branches, comparisons). Without it, the game can only run linear sequences. The reference has 6 comparison modes (eq, ne, gt, ge, lt, le) plus variable-length operands depending on subopcode bits 6-7.

#### 5. **Opcode 0x0C (resetThread) - NOT IMPLEMENTED**
(`another_world_vm.asm:1339-1344`)

Doesn't even consume its 3 bytes of arguments (first, last, type). This will desynchronize the bytecode parser, causing every subsequent instruction to decode incorrectly. The reference implementation freezes/unfreezes/deletes ranges of threads.

#### 6. **Opcode 0x0F (copyVideoPage) - Ignores vscroll parameter**
(`another_world_vm.asm:1379-1399`)

The reference reads `VM_VARIABLE_SCROLL_Y` and supports vertical scrolling with source/dest Y offsets. The KN5000 version does a plain memcpy. Also ignores the conditional `srcPageId & 0x80` / `srcPageId & 0xBF` logic for special scroll behavior.

#### 7. **Opcode 0x12 (drawString) - NOT IMPLEMENTED**
(`another_world_vm.asm:1427-1431`)

Doesn't consume its 5 bytes of arguments (word stringId, byte x, byte y, byte color). Will desync the bytecode stream. The DRAW_STRING routine exists but is never called from here.

#### 8. **Opcode 0x13 (SUB) - NOT IMPLEMENTED**
(`another_world_vm.asm:1434-1439`)

Doesn't consume its 2 bytes. Will desync.

#### 9. **Opcode 0x14 (AND) - NOT IMPLEMENTED**
(`another_world_vm.asm:1442-1447`)

Doesn't consume its 3 bytes. Will desync.

#### 10. **Opcode 0x15 (OR) - NOT IMPLEMENTED**
(`another_world_vm.asm:1450-1455`)

Doesn't consume its 3 bytes. Will desync.

#### 11. **Opcode 0x16 (SHL) - NOT IMPLEMENTED**
(`another_world_vm.asm:1458-1463`)

Doesn't consume its 3 bytes. Will desync.

#### 12. **Opcode 0x17 (SHR) - NOT IMPLEMENTED**
(`another_world_vm.asm:1466-1471`)

Doesn't consume its 3 bytes. Will desync.

#### 13. **Opcode 0x19 (LOAD/updateMemList) - NOT IMPLEMENTED**
(`another_world_vm.asm:1484-1490`)

Skips the word argument but does nothing. In the reference, this handles:
- `resourceId == 0`: stop all sound
- `resourceId > 0x91`: switch to a new game part (level change)
- Otherwise: load a screen bitmap resource

#### 14. **Opcode 0x40 (video with extended addressing) - NOT IMPLEMENTED**
(`another_world_vm.asm:1072-1125`)

The entire opcode 0x40 block is commented out and jumps to end without consuming any bytes. This handles polygon rendering with variable X/Y addressing modes and zoom. It's required for most in-game polygon graphics. **The variable-length encoding means skipping an unknown number of bytes, so this will definitely desync the VM.**

#### 15. **drawLineP - NOT IMPLEMENTED (falls through to drawLineN)**
(`another_world_vm.asm:89-102`)

Should copy pixels from page_bitmaps[0] to curPagePtr1, but just draws solid color.

#### 16. **drawLineBlend - NOT IMPLEMENTED (falls through to drawLineN)**
(`another_world_vm.asm:104-117`)

Should read the existing pixel and apply `(color & 7) | 8`, but just draws solid color.

#### 17. **INPUT_UPDATE_PLAYER - NOT IMPLEMENTED**
(`another_world_vm.asm:908-910`)

Returns immediately. Without input handling, the game can never be interactive. The reference reads button/keyboard state and sets ~8 VM variables for hero movement, action, and mask.

#### 18. **LOAD_SCREEN - Hardcoded to single bitmap**
(`another_world_vm.asm:747-753`)

Ignores the `screen_id` parameter entirely. The reference has 12 screen resources that get selected by index. Only one bitmap is ever loaded.

#### 19. **Part/level switching not implemented**
The reference has `initForPart()` / `setupPart()` which bank-switches bytecode, palettes, and video data when the game transitions between parts (intro, lake, jail, etc.). The KN5000 port hardcodes `INTRO_BYTECODE`, `INTRO_PALETTES`, `INTRO_VIDEO_1` labels, with no bank switching. `m_requestedNextPart` checking is commented out in `CHECK_THREAD_REQUESTS`.

#### 20. **VM hacks not implemented**
The reference has several critical hacks:
- `VM_HACK_SWITCH_FROM_INTRO_TO_LAKE`: Sets var 0xDC when transitioning from intro
- `VM_HACK_INIT_VAR_54_WITH_81`: Required for the Interplay logo to show
- `VM_VARIABLE_RANDOM_SEED`: Never initialized (noted as TODO on line 228)

---

### Summary by Severity

**Will crash/desync the VM** (bytecode not consumed correctly):
- Opcode 0x0C (resetThread) - missing 3 bytes
- Opcode 0x12 (drawString) - missing 5 bytes
- Opcode 0x13 (SUB) - missing 2 bytes
- Opcode 0x14 (AND) - missing 3 bytes
- Opcode 0x15 (OR) - missing 3 bytes
- Opcode 0x16 (SHL) - missing 3 bytes
- Opcode 0x17 (SHR) - missing 3 bytes
- Opcode 0x40 (video extended) - variable length, unparsed
- Opcode 0x0A (condJmp) - skips 5 bytes, but actual length is variable (5-6 bytes depending on subopcode)

**Wrong behavior (logic bugs):**
- Opcode 0x01 (MOV) - writes to wrong variable
- Opcode 0x02 (ADD) - doesn't add, just copies (also to wrong dest)
- Big-endian fetch_word not handled (affects most word-reading opcodes)

**Missing but won't desync:**
- Input handling
- Part/level switching
- Sound (understandable given hardware constraints)

The port currently can only play the intro cinematic in a linear fashion (no branching, no interaction). To reach "complete and functional" status, the highest priority items would be: fixing the endianness issue, implementing condJmp (0x0A), fixing MOV/ADD, implementing the bytecode-consuming stubs to prevent desync, and then implementing opcode 0x40 for full polygon rendering.
