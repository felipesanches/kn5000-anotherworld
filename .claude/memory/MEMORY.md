# Another World VM Port - Key Notes

## STRICT POLICY: Commit Each Attempt (BOTH Repos)
- Every MAME driver fix attempt MUST be committed to git in BOTH repos before moving on:
  1. **Anotherworld repo** (`/home/fsanches/devel/custom-kn5000-roms/anotherworld/`): attempt logs, VM changes, docs
  2. **MAME driver repo** (`/home/fsanches/devel/kn5000-roms-disasm/`): driver source changes
- Commit message format: "Attempt NN: short description"
- One commit per attempt per repo — never skip either repo if changes were made
- This ensures full history is preserved and the user can track all changes

## STRICT POLICY: Save Reasoning Logs for Each Attempt
- Before each MAME driver fix attempt, write TWO files to `docs/attempt-logs/`:
  1. **`attempt-NN-short-description.md`**: Structured analysis (hypothesis, investigation, fix, outcome)
  2. **`attempt-NN-short-description-thinking.md`**: Raw thinking stream dump — write out the FULL internal reasoning as-is, including dead ends, reconsiderations, calculations, and self-corrections. This should be a faithful reproduction of the thinking process, not a cleaned-up summary.
- Include attempt number, date, files modified, and outcome (updated after user feedback)
- The thinking dump should be written BEFORE implementing the fix (captures the reasoning that led to it)
- Both files are mandatory for every attempt — do not skip either one

## STRICT POLICY: Sync MAME Driver Copy
- Every time files under `mame_driver/` are changed, resync the shared copy:
  `cp -rf /home/fsanches/devel/kn5000-roms-disasm/mame_driver/* /mnt/shared/mame_driver/`

## STRICT POLICY: Original Firmware is Source of Truth
- The **original KN5000 program ROM** is the mandatory compatibility target for ALL MAME driver changes
- The AW VM is **NOT a source of truth** — it can be adapted to match MAME driver updates
- When there's a conflict between AW VM behavior and original firmware behavior, always prioritize the original firmware
- Any input code changes require verifying the full signal chain: CPU SC1BUF → SCLK → cpanel RX → process → cpanel TX → CPU RX
- Always verify against both MAME driver source AND original firmware cpanel_routines.asm

## Architecture
- **ASL assembler** (`cpu 96c141`): TLCS-900/H target
- **Bytecode is big-endian** (Amiga/68k origin), TLCS-900 is little-endian → use `EX W, A` to byte-swap after `LD WA, (XIX)` for fetch_word
- **LDIRW** uses XHL=src, XDE=dst, XBC=word_count (not XIX/XIY!)
- `AND (XIY), WA` assembles as 16-bit AND (ASL determines size from register)
- `ADDW`/`SUBW` for explicit word-size memory operations

## VM Execution Model
- `_end_of_EXECUTE_INSTRUCTION`: computes VM_PC from XIX offset → XIX must point to bytecode
- `_after_PC_update`: skips VM_PC recomputation → use when VM_PC was already set (JMP, CALL, RET, NEXT_THREAD)
- **Critical**: opcodes that replace XIX with non-bytecode pointers (0x80, 0x40 video) must save VM_PC BEFORE the replacement and use `_after_PC_update`
- Same issue for pauseThread: after NEXT_THREAD sets VM_PC, must use `_after_PC_update`

## Helper Functions
- `_read_vm_var`: Input A=index, Output DE=value, Clobbers XIY/XWA
- `_write_vm_var`: Input A=index DE=value, Clobbers XIY/XWA

## Current Goal
**Fix both the VM and the MAME KN5000 driver for a fully playable game. All MAME driver changes must stay compatible with the original KN5000 firmware.**
- MAME driver files: `../../kn5000-roms-disasm/mame_driver/` (editable, manually copied to MAME tree)
- Key files: `tmp94c241_serial.cpp`, `kn5000_cpanel.cpp`, `kn5000.cpp`

## Implementation Status (2026-02-11)
- All opcodes 0x00-0x1A implemented (sound 0x18/0x1A are consuming stubs)
- Opcode 0x40/0x80 (video) fully implemented with proper CUR_VIDEO_DATA reset
- Part switching: resources decompressed correctly (ByteKiller fix), initForPart loads from PART_RESOURCE_TABLE
- Copy protection bypass: var[0xDC]=0x21, var[0xBC]=0x0010, var[0xF2]=0x0FA0 set in GAME_RESET
- VM hacks: var 0x54=0x81 (Interplay logo), blit hack checks GAME_PART_PROTECTION (was wrongly INTRO)
- FREEZE persists: CHECK_THREAD_REQUESTS applies `state = requested_state` every frame without clearing (reference behavior)
- Input implemented: SC1 serial reads CPR_SEG4 (directions) + CPL_SEG4 (action), writes 6 VM vars
- VM variable EQUs fixed to match reference HLE (0xDA, 0xE5, 0xFA-0xFE)

## Current Status (2026-02-15)
- **Left panel header encoding fix** (attempt 43): ROM lookup table at 0xEDA03C maps bits 7:6=00 → right panel (indices 0x0B-0x15), bits 7:6=11 → left panel (indices 0x00-0x0A). Old encoding (0x40=bits 7:6=01) fell in dead zone → left panel events bypassed LED dispatch. Fix: left=0xC0|segment, right=segment (unchanged).
- **Ghost toggle fix** (attempt 43): Per-segment confirmation filters MAME input port glitches (single-scan non-zero reads that revert immediately).
- **Remaining issue**: Pending user test after rebuild with header encoding fix.
- Original firmware boots fully: NVRAM valid → Sub-CPU payload → LED init → GUI display

## Previous Status (2026-02-12)
- Intro + splash screens play correctly with polygon rendering, palette, and timer-based frame timing
- Part switching works (copy protection bypass + FREEZE fix)
- Death handler → password display: thread 0 unfreezes after one frame, shows password strings
- Parts 2 (Water), 4 (Citadel), 8-9 (Password) have protection checks — all bypassed
- Timer-based PAUSE reads var[0xFF] for 20ms slices, polls SYSTEM_TICKS with DJNZ fallback
- Input via SC1 serial implemented; requires 3 MAME serial bug fixes to work in emulation
- MAME serial bugs fixed locally (timer_callback, cpanel queue, delay loop) — pending user testing
- **VM starts on Part 1 (Intro)** — skips Part 0 code wheel entirely (GAME_PART_FIRST=GAME_PART_INTRO)
- **Code wheel investigation paused**: branch `codewheel-investigation`, see `memory/codewheel-investigation.md`
- **INTA mechanism added to cpanel HLE** (2026-02-12): enables original firmware button handling
  - Cpanel SCLK output now connected to CPU serial[1] sioclk
  - INTA callback connected to PE.5 and TLCS900_INTA interrupt
  - Idle detect timer (250µs): if CPU stops driving SCLK, cpanel self-clocks response
  - Compatible with both AW VM (dummy-byte) and original firmware (INTA/slave mode)

## MAME Driver Bugs (found and fixed)
- **Serial timer stops early**: `timer_callback` only checks `m_tx_clock_count > 0`, stops before 8th rising edge for RX. Fix: add `m_rx_clock_count != 8` condition.
- **Cpanel queue overwrites TXD**: When loading next byte from queue, pre-outputs bit 0 overwriting bit 7 of previous byte. Fix: `tx_clock_count = 8`, no pre-output, handle in falling edge handler.
- **Rising-edge race condition**: CPU's `sioclk()` forwards clock to cpanel via `m_sclk_out_cb` BEFORE sampling `m_rxd`. If cpanel completes RX and calls `send_byte()` (pre-outputting bit 0), `m_rxd` is corrupted. Fix: capture `m_rxd` before forwarding clock.
- **Baud rate half speed**: Timer fires at `m_hz` but toggles → effective SCLK is `m_hz/2`. Not fixed; VM compensates with longer delay (0xFF iterations).
- **MAME DEC flag bug is 16-bit only**: `DEC 1, A; JR NZ` works correctly for 8-bit (DECBIR calls sub8 with proper flags). Only 16-bit DECWIR is broken (bare subtraction, no flags).
- **Missing INTA mechanism** (2026-02-12): Cpanel had no INTA output; SCLK output was disconnected. Original firmware uses bidirectional serial (CPU master for TX, panel master for RX via INTA). Fix: added INTA output, idle-detect timer (250µs), self-clocking. AW VM unaffected (dummy-byte approach still works).
- **Wrong command responses** (2026-02-12): Commands 0x25, 0xE2, 0xE3 returned sync instead of button data. Fix: dispatch like 0x20/0xE0 with param-based segment queries. Params > 0x0A default to sync.
- **TO2_trigger checks wrong bit for IOC** (2026-02-12): `BIT(m_serial_control, 1)` checked SCLKS instead of IOC (bit 0). TO2 kept driving SCLK in slave mode, conflicting with cpanel self-clock. Fix: `BIT(m_serial_control, 0)`.
- **sioclk() forwards SCLK ignoring PFFC** (2026-02-12): In master mode, clock edges forwarded to cpanel even when PFFC disabled the SCLK pin. Firmware clears PFFC during TX init phases — phantom bytes corrupted cpanel command parser → spurious LEDs. Fix: gate sclk_out_cb with `ioc || pffc_enabled`.
- **timer_callback: SC1MOD check kills firmware serial** (2026-02-13): Firmware sets SC1MOD=0 (TO2 trigger) but writes BR1CR for specific baud rates (250kHz/62.5kHz/31.25kHz). The baud rate timer provides the primary 250kHz SCLK. TO2 from Timer 1 cascade only fires at ~12.5kHz (too slow). Gating timer_callback on SC1MOD!=1 disables the 250kHz clock → "Error in CPU data transmission". Must gate on `(SC1MOD & 3)==0 && IOC==1` instead (only stop in TO2 slave mode).
- **TO2 activity gate needed**: Without gating TO2_trigger on TX/RX activity, TO2 fires continuously at Timer 1 rate (~12.5kHz), preventing cpanel idle detection (250µs timeout) → INTA never asserted → firmware never receives responses.
- **Wrong button packet header encoding** (2026-02-15): HLE used 0x40|segment for left panel (bits 7:6=01) → dead zone in ROM lookup table at 0xEDA03C → index 0x1F → bypassed LED dispatch. Fix: left=0xC0|segment (bits 7:6=11 → valid indices 0x00-0x0A), right=segment unchanged (bits 7:6=00 → valid indices 0x0B-0x15).
- **Ghost button toggles** (2026-02-15): MAME input ports momentarily return single-bit non-zero values that revert within one scan interval (7ms). Global 100ms debounce converted each glitch into a full press-release cycle, flooding the event queue. Fix: per-segment confirmation requires state to be stable for 2 consecutive scans (14ms).
- See `docs/serial-cpanel-compatibility-2026-02-11.md` for full analysis.

## VM Design Notes
- **INPUT_UPDATE_PLAYER must be once-per-frame**: Called inside end-of-frame section (after `CURRENT_THREAD=0`, before `CHECK_THREAD_REQUESTS`), matching reference HLE. NOT on every thread switch — that causes excessive serial traffic.
- **ASL `cpu 96c141` SFR addresses are wrong for TMP94C241**: ASL defines SC1BUF=0x54, but TMP94C241 has SC1BUF=0xD4 (0x80 offset). The `sfr_tmp94c241.asm` include overrides correctly — verified in listing output.

## Common Pitfalls
- `LD BC, WA` clobbers B — save B (or derived value) to stack first if needed later
- `POP WA` restores both W and A — don't follow with `LD A, W` (overwrites the restored A)
- After NEXT_THREAD or any XIX replacement, must use `_after_PC_update` not `_end_of_EXECUTE_INSTRUCTION`
- setPalette was missing `INC 2, XIX` — always verify bytecode pointer advances match consumed bytes
- **TLCS-900 INC only supports 1,2,4,8** — use ADD for other values (INC 3/5/6/7 are undefined on real hardware, though MAME treats them as literal values)
- **MN89304 DAC is 4-bit** (0-15), NOT 6-bit like standard VGA. Values > 15 wrap (only lower 4 bits used). AW 4-bit palette values map directly — do NOT scale with SLA 2.
- **AW palette format**: 2 bytes/color 0x0RGB → byte0 low nibble=R, byte1 high nibble=G, byte1 low nibble=B
- **Subroutine at 0xE7 DOES return** (RET at 0xF5) — don't confuse display loop (0xD2-0xE6) with subroutine (0xE7-0xF5)
- **TLCS-900 SLA only supports shift counts 1,2,4,8** — same 2-bit encoding as INC. Use SLA 1 + SLA 4 for ×32.
- **QWA is the previous register bank's WA** — `LD QWA, WA` does NOT modify XWA's upper bits. Don't use it for 32-bit address computation.
- **GET_PAGE_PTR must return full 32-bit address** — use `LD XWA, PAGE_BITMAP_x` not arithmetic with undefined upper bits
- **AW setPalette word**: palette index is in the upper byte (`fetchWord() >> 8`), lower byte is unused
- **NEXT_THREAD thread scan assumes W=0**: The `SLA 1, WA`/`EXTZ XWA` pattern for computing thread array indices requires W=0. Any code added to end-of-frame (between CHECK_THREAD_REQUESTS and `LD A, 0`) must not leave garbage in W. `LD XWA, (mem)` clobbers W — use `LD WA, 0` (not `LD A, 0`) afterward.
- **Timer frame timing**: T0/T1 cascade at 12500 Hz (80µs/tick) with INTT1 ISR incrementing SYSTEM_TICKS. INTT1 vector at offset 0x54 (entry 21). PAUSE reads var[0xFF] for 20ms slices (TICKS_PER_SLICE=250) with DJNZ fallback counter.
- **KN5000 CPU clock is 16 MHz** (2 × 8 MHz XTAL). All timer calculations must use 16 MHz.
- **Prescaler requires T16RUN bit 7** (PRRUN) to be set. T8RUN only controls timer run bits (0-3). Without `LD (T16RUN), 080h`, prescaler never runs and timers never count.
- **MAME prescaler divisions differ from datasheet**: T1=÷8, T4=÷32, T16=÷128, T256=÷2048 (datasheet says ÷4, ÷16, ÷64, ÷1024). T01MOD bits 1:0 select T0 clock in MAME (not bits 2:1 as SFR doc says).
- **MAME T01MOD register layout differs from SFR doc**: MAME uses bits[1:0]=T0CLK, bits[3:2]=T1CLK, bits[7:6]=operating mode. SFR doc says bit0=PRRUN, bits[2:1]=T0CLK. Use MAME's interpretation since we test there.
- **MAME bug: `DEC 1, rr; JP NZ` doesn't work** — MAME's TLCS-900 DEC instruction may not set flags correctly. Use `DJNZ rr, label` instead, which does decrement-and-branch-if-not-zero without relying on flags. Confirmed: `DEC 1, DE; JP NZ` causes black screen, `DJNZ DE` works identically.
- **Zoom must be 16-bit**: Reference uses `uint16_t zoom` throughout. Storing zoom in an 8-bit register (C) truncates values ≥ 256, causing characters to shrink/disappear at close zoom. Use `CUR_ZOOM` (DW) memory variable and `LD DE, (CUR_ZOOM)` for MUL operations in readVertices/readAndDrawPolygonHierarchy.
- **Opcode 0x40 zoom case 2**: The fetched byte IS the zoom value — don't just consume and discard it.
- **Opcode 0x40 zoom case 3**: Sets CUR_VIDEO_DATA to VIDEO_2 but must NOT clobber XIX before VM_PC is computed. Use PUSH/POP XIX around the CUR_VIDEO_DATA update.
- **FREEZE persists until changed**: Reference applies `thread->state = thread->requested_state` every frame without clearing. REQUESTED_STATE initialized to NOT_FROZEN. RESET_THREAD type 0 = unfreeze, type 1 = freeze (was previously swapped — caused threads to stay visible during cutscenes).
- **RLC vs RL**: `RLC` = circular rotate (bit 7 → bit 0, ignores carry). `RL` = rotate through carry (carry → bit 0, bit 7 → carry). LOAD_SCREEN's bitplane extraction uses `SLA` (MSB → carry) then must use `RL` to shift that carry into the pixel accumulator. Using `RLC` produces all-zero pixels.

## Floppy Disc Research (2026-02-12)
- See `memory/floppy-disc-research.md` for full details
- Boot sector never read; `EB FE` = `SLL A, XHL` on TLCS-900 (not x86 infinite loop)
- 8 update disc types, all write to flash, no code execution from floppy
- SSF XML presentation system in ROM (EXEC, SHOW, IMG, SONG tags) but no floppy loading path
- `make disc` creates type 7 update disc images; `tools/make_update_disc.py`

## Resources Available
- Bytecode: resource-0x18 (intro), also 0x14, 0x1d, 0x20, 0x23, 0x26, 0x29 (other parts)
- Palettes: resource-0x17 (intro)
- Video: resource-0x19 (video1), resource-0x1a (video2)
- Screens: resource-0x49, resource-0x53
- Other parts' resources need extraction for full game
