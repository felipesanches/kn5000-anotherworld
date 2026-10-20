# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World VM state for the KN7000 port, shared by both builds. Where it lives is the
# platform's choice: three bases, VM_POLY_BASE (rasterizer scratch, 0x200 bytes),
# VM_INTERP_BASE (the interpreter, 0x1100 bytes) and VM_MISC_BASE (everything else, 0x1400
# bytes), come from platform.inc (the SP7001 build: the 0x44000000 window, MAME ONLY -- on a real
# KN7000 that window is IC23, the battery-backed SRAM with the panel memories) or platformcnv.inc
# (the STYLE CONVERT build: the converter area of work RAM). Field names and sizes mirror the
# KN5000 TLCS-900 source so the two stay readable side by side.

.equ VM_STATE,        VM_POLY_BASE  # per platform (platform.inc / platformcnv.inc)

.equ POLY_NUM_POINTS, VM_STATE + 0x00   # byte
.equ POLY_BBOX_W,     VM_STATE + 0x02   # u16
.equ POLY_BBOX_H,     VM_STATE + 0x04   # u16
.equ POLY_XMIN,       VM_STATE + 0x06   # s16
.equ POLY_XMAX,       VM_STATE + 0x08   # s16
.equ POLY_YMIN,       VM_STATE + 0x0A   # s16
.equ POLY_YMAX,       VM_STATE + 0x0C   # s16
.equ HLINEY,          VM_STATE + 0x0E   # s16
.equ X1,              VM_STATE + 0x10   # s16
.equ X2,              VM_STATE + 0x12   # s16
.equ DX,              VM_STATE + 0x14   # s16
.equ LINE_XMIN,       VM_STATE + 0x16   # s16
.equ LINE_XMAX,       VM_STATE + 0x18   # s16
.equ POLY_H,          VM_STATE + 0x1A   # s16 (dy / remaining scanlines)
.equ STEP_V,          VM_STATE + 0x1C   # s16 scratch for calcStep
.equ CUR_LINE,        VM_STATE + 0x20   # u32 pointer into the page
.equ CPT1,            VM_STATE + 0x24   # u32 fixed-point edge x (left)
.equ CPT2,            VM_STATE + 0x28   # u32 fixed-point edge x (right)
.equ STEP1,           VM_STATE + 0x2C   # s32 per-scanline delta for CPT1
.equ STEP2,           VM_STATE + 0x30   # s32 per-scanline delta for CPT2
.equ CUR_PAGE,        VM_STATE + 0x34   # u32 base of the page being drawn
.equ DRAW_COLOR,      VM_STATE + 0x38   # byte
.equ DRAW_FUNC,       VM_STATE + 0x39   # byte: 0 = flat (N), 1 = copy page0 (P), 2 = blend

# POLY_POINTS: up to 50 (x,y) pairs, u16 each, interleaved. Kept last.
# Spans VM_STATE+0x40 .. +0x108 (200 bytes). The interpreter state below starts a
# long way clear of it.
.equ POLY_POINTS,     VM_STATE + 0x40

# ================================================================================
# Interpreter state (the VM proper), ported from the KN5000 main.asm declarations.
# Arrays first, then scalars. All from VM_INTERP_BASE.
.equ VM_VARIABLES,    VM_INTERP_BASE + 0x0000      # 256 x s16   (var[0..255])
.equ THREADS_DATA,    VM_INTERP_BASE + 0x0400      # 64 x {u16 pc @+0, u16 requested_pc @+2}
.equ VM_CHAN_STATE,   VM_INTERP_BASE + 0x0600      # 64 x {u8 state @+0, u8 requested_state @+1}
.equ VM_STACK,        VM_INTERP_BASE + 0x0800      # 256 x u16   (VM call stack)

.equ PC_OFFSET,         0             # within a THREADS_DATA entry
.equ REQ_PC_OFFSET,     2
.equ CUR_STATE,         0             # within a VM_CHAN_STATE entry
.equ REQ_STATE,         1

.equ INACTIVE_THREAD,   0xFFFF
.equ DELETE_THREAD,     0xFFFE
.equ NO_REQUEST,        0xFFFF
.equ ST_FROZEN,         0
.equ ST_NOT_FROZEN,     1

# scalars
.equ CURRENT_THREAD,  VM_INTERP_BASE + 0x1000      # u8
.equ VM_PC,           VM_INTERP_BASE + 0x1002      # u16
.equ VM_SP_PTR,       VM_INTERP_BASE + 0x1004      # u32  (points into VM_STACK)
.equ CUR_PAGE_1,      VM_INTERP_BASE + 0x1008      # u32  draw target page
.equ CUR_PAGE_2,      VM_INTERP_BASE + 0x100C      # u32  display page
.equ CUR_PAGE_3,      VM_INTERP_BASE + 0x1010      # u32  work/back page
.equ CUR_VIDEO_DATA,  VM_INTERP_BASE + 0x1014      # u32  active polygon source
.equ CUR_VIDEO_1,     VM_INTERP_BASE + 0x1018      # u32  cinematic polygon source
.equ CUR_VIDEO_2,     VM_INTERP_BASE + 0x101C      # u32  secondary polygon source
.equ CUR_BYTECODE,    VM_INTERP_BASE + 0x1020      # u32
.equ CUR_PALETTES,    VM_INTERP_BASE + 0x1024      # u32
.equ CUR_ZOOM,        VM_INTERP_BASE + 0x1028      # u16
.equ CURRENT_PART_ID, VM_INTERP_BASE + 0x102A      # u16
.equ REQ_NEXT_PART,   VM_INTERP_BASE + 0x102C      # u16

# SP7001 build: every Another World resource (all 146 MEMLIST entries: sounds, music, bitmaps,
# palettes, bytecode, polygons) is resident, loaded at startup by LoadGameData (main.s). They
# are laid out from RES_BASE (4-byte aligned, id order) and the card carries that image cut into
# pack files of <= 65535 bytes (C:\TECHNICS\DATA\AWPxx.AW): the firmware's fread_api has a
# 16-bit count and no working sequential reads, so each pack is one fopen + fread + fclose.
# Where each resource lands, its size and type, and each pack's base and length are the
# generated tables ResAddr/ResSize/ResType/PackAddr/PackSize (build/res/awres_tab.s, from
# tools/aw_extract.py).
.equ RES_TYPE_BITMAP, 2              # MEMLIST type of a 320x200 4-plane screen bitmap
.equ RES_VIDEO2,      0x11           # the shared polygon resource (video2)
.equ PART_FIRST,      0x3E80         # part ids 0x3E80..0x3E89 (PartTable in interp.s)
.equ PART_LAST,       0x3E89
# The STYLE CONVERT build keeps one part's resources at a time and loads the next part's from the
# floppy at the part switch (cnv_main.s, EnsurePart). Both builds find a resource through ResPtr
# (interp.s): the u32 at ResAddr + 4 * id (a table in the module for SP7001, a table in RAM that the
# part loader fills for STYLE CONVERT).
# AW_FONT (anotherworld_chargen.rom, 8x8, chars 0x20+), AW_STRIDX (str_index.rom, LE u16 offset per
# string id), AW_STRDAT (str_data.rom, NUL-terminated strings): per platform.
.equ AW_FONT_SZ,      768
.equ AW_STRIDX_SZ,    2048
.equ AW_STRDAT_SZ,    4096
.equ AW_LOADED_FLAG,  VM_MISC_BASE + 0x0020     # set to 0x600D once everything is loaded
.equ LOAD_PACK,       VM_MISC_BASE + 0x0050     # u32: LoadGameData's pack loop index
.equ LOAD_FILE,       VM_MISC_BASE + 0x0054     # u32: LoadGameData's open FILE*

.equ DRAW_BUDGET,     VM_MISC_BASE + 0x0070     # per-VIDEO-op polygon budget (anti-hang guard)
.equ DRAW_BUDGET_MAX, 4000
.equ DRAW_DEPTH,      VM_MISC_BASE + 0x0074     # polygon-hierarchy recursion depth (stack guard)
.equ DRAW_DEPTH_MAX,  12             # AW hierarchies are shallow; cap to protect the stack

# Frame pacing, the Another World way: a frame lasts var[0xFF] (PAUSE_SLICES) * SLICE_MS,
# the bytecode setting var[0xFF] each frame. We sleep only the remainder after the frame's
# work (measured via the firmware's 1 kHz counter), with a floor so the firmware keeps
# getting time for the keybed/panel. SLICE_MS = 20 is authentic AW; lower it to run faster.
# The counter's address is in FWV_KERNEL_MS (below).
.equ FRAME_START_MS,  VM_MISC_BASE + 0x0044     # u32 scratch: the counter at the start of this frame

# Last-applied direction bits per axis, for the sticky opposing-key rule. When both keys of an
# axis are held at once (ambiguous), we keep whichever direction was already applied until that
# key is released. 0 = none, LR: 1 right/2 left, UD: 4 down/8 up. Deterministic and brush-proof.
.equ PREV_LR_BITS,    VM_MISC_BASE + 0x0048     # u16: last-applied L/R bit (0 / 1 / 2)
.equ PREV_UD_BITS,    VM_MISC_BASE + 0x004A     # u16: last-applied U/D bit (0 / 4 / 8)
.equ VAR_PAUSE_SLICES, 0xFF          # var index holding the per-frame slice count
.equ SLICE_MS,        20             # ms per slice (authentic AW)
.equ MIN_YIELD_MS,    8              # never yield less than this (firmware must run)
.equ MAX_YIELD_MS,    400            # safety cap on a single frame's sleep

# VM instruction trace (for diffing against the vm-gui reference): ExecuteInstruction calls the
# platform's TraceInsn. The SP7001 build (MAME only) logs 8-byte entries, frame(u16)@0,
# thread(u8)@2, opcode(u8)@3, pc(u16)@4, to its TRACE_BUF (main.s; dumped by probes/awtrace.lua);
# the STYLE CONVERT build logs nothing. FRAME_NO also tells the probes the VM is running.
.equ TRACE_COUNT,     VM_MISC_BASE + 0x0078     # entries logged so far
.equ FRAME_NO,        VM_MISC_BASE + 0x007C     # current VM frame (tick) number

# ================================================================================
# Player input (gameplay directional control for every part after the intro).
#
# The KN7000 firmware keeps a debounced control-panel button bitmap in work RAM: one
# byte per CP serial segment, one bit per switch line (bit = 1 << SWn), held 1 for as
# long as the physical button is down. The CPR half-panel's segments live at
# PANEL_CPR+seg, the CPL/CPC half at PANEL_CPL+seg = PANEL_CPR+0x30+seg in every program
# build (fwfind.s checks it). Decoded (byte+bit per button, and that it is level- not
# edge-held) by probes/awpanelmap.lua, which drives every cpanel ioport in MAME and diffs
# this region -- see probes/PANEL-INPUT.md. Five panel buttons form a D-pad + fire; the
# keybed and MIDI IN drive the same inputs (NOTES_* below).
#
# Where the firmware keeps things differs between program builds, so the shared code reads
# them through these variables, which the platform fills before the game task starts:
# platform.inc's 942 constants (main.s Hook), or what fwfind.s found (cnv_main.s).
.equ FWV_KERNEL_MS,   VM_MISC_BASE + 0x0200     # u32: address of the kernel's 1 kHz ms counter
.equ FWV_PANEL,       VM_MISC_BASE + 0x0204     # u32: PANEL_CPR, the switch bitmaps' base
.equ FWV_MIDIIN1,     VM_MISC_BASE + 0x0208     # u32: MIDI IN 1 receive ring header
.equ FWV_MIDIOUT1,    VM_MISC_BASE + 0x020C     # u32: MIDI OUT 1 transmit ring header (the keybed)
.equ PANEL_CPL_OFS,   0x30           # PANEL_CPL - PANEL_CPR

# The Another World D-pad + fire, as offsets from FWV_PANEL. Buttons chosen for mnemonic labels
# and for landing in distinct bytes, so any combination can be held and read at once.
.equ BTN_LEFT_OFS,    2              # PART SELECT LEFT     (CPR_SEG2 SW0)
.equ BTN_LEFT_BIT,    0x01
.equ BTN_RIGHT_OFS,   1              # PART SELECT RIGHT 1  (CPR_SEG1 SW1)
.equ BTN_RIGHT_BIT,   0x02
.equ BTN_UP_OFS,      6              # R1/R2 OCTAVE +       (CPR_SEG6 SW1)
.equ BTN_UP_BIT,      0x02
.equ BTN_DOWN_OFS,    7              # R1/R2 OCTAVE -       (CPR_SEG7 SW1)
.equ BTN_DOWN_BIT,    0x02
.equ BTN_FIRE_OFS,    5              # SUSTAIN              (CPR_SEG5 SW3)
.equ BTN_FIRE_BIT,    0x08

# The port's own buttons (measured with probes/awbtnmap5.lua, as above): HELP shows the help
# screens, OTHER PART & FR opens the password (level code) screen, PAGE UP/DOWN and EXIT drive
# the help screens.
.equ BTN_HELP_OFS,    PANEL_CPL_OFS+5   # HELP                 (CPC_SEG5 SW1)
.equ BTN_HELP_BIT,    0x02
.equ BTN_CODES_OFS,   PANEL_CPL_OFS+5   # OTHER PART & FR      (CPC_SEG5 SW0)
.equ BTN_CODES_BIT,   0x01
.equ BTN_PAGE_OFS,    PANEL_CPL_OFS+11  # PAGE UP / PAGE DOWN / EXIT (CPC_SEG11 SW4 / SW5 / SW7)
.equ BTN_PAGEUP_BIT,  0x10
.equ BTN_PAGEDN_BIT,  0x20
.equ BTN_EXIT_BIT,    0x80
.equ PART_PASSWORD,   0x3E88         # the level-code screen (rawgl kPartPassword)
.equ PART_PROTECTION, 0x3E80         # the copy-protection part, whose start is the splash

# Help screen state. The pages are drawn into their own 320x200 buffer (HELP_BUF, per platform),
# clear of the four VM pages, and shown through their own 4-colour palette; the game's palette is
# saved and put back.
.equ HELP_PAGE_NO,    VM_MISC_BASE + 0x005C     # u32: the help page shown (0..HELP_PAGES-1)
.equ HELP_PAL_SAVE,   VM_MISC_BASE + 0x0100     # 32 bytes: the game's palette while the help is up
.equ HELP_PAGES,      3
.equ HELP_TICK,       VM_MISC_BASE + 0x0120     # u32: help polls since the page was last shown
.equ HELP_REFRESH,    16             # re-show the page every 16 polls (~0.5 s)

# Splash: by default the game starts like the KN5000 port, at the copy-protection part's logo and
# credits sequence (bytecode 0x007B), which then loads the intro. A probe that needs the old start
# (the intro at tick 0, as every recorded fixture assumes) writes NO_SPLASH_MAGIC to NO_SPLASH
# before the game task starts; a random power-on value will not match it.
.equ NO_SPLASH,       VM_MISC_BASE + 0x0058     # u32
.equ NO_SPLASH_MAGIC, 0x5EED0FF0
.equ SPLASH_PC,       0x007B         # part 0x3E80: the logo / credits sequence (thread 0)
.equ SPLASH_LOOP_PC,  0x10A3         # part 0x3E80: its display loop (thread 60), as 0x0000 sets up

# Another World hero-control variables (same indices as the DOS game). The mask bits and
# signed values match rustyworld's update_player (our checksum oracle): RIGHT {1,+1},
# LEFT {2,-1}, DOWN {4,+1}, UP {8,-1}, BUTTON {0x80,+1}; RIGHT beats LEFT, DOWN beats UP.
.equ VAR_HERO_LR,       0xFC         # left/right position delta  (s16)
.equ VAR_HERO_UD,       0xE5         # up/down position delta     (s16)
.equ VAR_HERO_JUMP,     0xFB         # jump/down = copy of UD
.equ VAR_HERO_POS_MASK, 0xFD         # OR of all held inputs' masks
.equ VAR_HERO_ACTION,   0xFA         # fire button down -> 1
.equ VAR_HERO_ACT_MASK, 0xFE         # POS_MASK (the button mask is already in it)

# Keybed + MIDI gameplay mapping: exact held-note state from the firmware's MIDI byte streams.
# The firmware's lib keeps byte rings {start @+0, last @+4, rd @+8, wr @+0xC, free u16 @+0x10}
# (enqueue lib 0x4C024D16). Two carry every note event a player makes:
#   * MIDI IN 1 receive ring -- filled byte by byte by the SIO1 RX ISR (Midi1RxIsr 0x484B1E75);
#   * MIDI OUT 1 transmit ring -- the firmware sends every keybed note-on/off here as MIDI
#     (running status, velocity-0 note-off), drained by the SIO1 TX ISR at MIDI baud.
# The module never consumes from them: each tracker keeps its own read pointer and parses the
# new bytes every ReadInput into per-note channel masks. (The TG voice ring this replaces held
# STALE note bytes in reused voice nodes and dropped still-held voices, for keybed and MIDI
# alike -- probes/INPUT-PRECISION.md.) Found on 942 by probes/awmidiq.lua; each build has them
# elsewhere, so the code reads FWV_MIDIIN1 / FWV_MIDIOUT1 (above). Keybed notes reach the TX ring
# while the keybed part transmits on MIDI OUT (the default).
.equ QH_START,        0x00           # u32: first byte of the ring buffer
.equ QH_LAST,         0x04           # u32: last byte of the ring buffer
.equ QH_WR,           0x0C           # u32: next byte the producer writes
.equ NOTES_MIDI,      VM_MISC_BASE + 0x1000     # note tracker for MIDI IN 1
.equ NOTES_KBD,       VM_MISC_BASE + 0x1200     # note tracker for the keybed (the MIDI OUT 1 stream)
.equ NS_HDR,          0x00           # u32: ring header address
.equ NS_RP,           0x04           # u32: private read pointer (0 = resync on the next poll)
.equ NS_STATUS,       0x08           # u8: running status (0 = none)
.equ NS_D1,           0x09           # u8: first data byte of the message being collected
.equ NS_CNT,          0x0A           # u8: data bytes collected so far (0/1)
.equ NS_MASK,         0x10           # u16[128]: bit c set while MIDI channel c holds note n
# Note numbers (C4 = 60). Any note <= C4 is ACTION -- the whole bass/left-hand range plus
# C4 itself. The right-hand cluster is the D-pad; two notes map to UP.
.equ KBD_ACTION_MAX,  60             # <= 60 (bass range + C4) -> action
.equ KBD_LEFT_NOTE,   77             # F5
# UP: Bb5 is Felipe's chosen note and works for everything up to TWO keys (the water swim is
# action+up, and up+a single direction) -- two keys never ghost. BUT Bb5 GHOSTS in the THREE-key
# run+jump combo (action + a direction + Bb5 vanishes from the firmware held mask -- keybed scan
# matrix, awrun_diag.lua/awupnote.lua: Ab5/Bb5/Db6/Eb6 all do this). B5 survives that combo, so it
# is kept as the second UP note specifically for run-and-jump. Use Bb5 normally; use B5 when
# holding action + direction + up at once.
.equ KBD_UP_NOTE_A,   82             # Bb5 (A#5) -- primary up (fine for swim / up+one direction)
.equ KBD_UP_NOTE_B,   83             # B5  -- ghost-free up for the 3-key run+jump combo
.equ KBD_DOWN_NOTE,   81             # A5
.equ KBD_RIGHT_NOTE,  84             # C6

# ================================================================================
# The run-time guard (interp.s GuardTrip): a write the VM is about to make through a pointer it
# computed (a page, the VM stack) that is not where it must be is skipped, recorded here, and the
# platform stops the game at its next yield (cnv_main.s: DLY_TSK shows a message and parks the
# task). 0 = never tripped.
.equ GUARD_WHAT,      VM_MISC_BASE + 0x0210     # u32: which check (GUARD_* below)
.equ GUARD_ADDR,      VM_MISC_BASE + 0x0214     # u32: the pointer it refused
.equ GUARD_COUNT,     VM_MISC_BASE + 0x0218     # u32: refusals so far
.equ GUARD_TEXT,      VM_MISC_BASE + 0x0220     # 16 bytes: StopGame's "AT 0x12345678"
.equ GUARD_PAGE,      1              # a page pointer that is none of the four pages
.equ GUARD_VMSTACK,   2              # the VM call stack ran over or under
.equ GUARD_LOAD,      3              # a load destination outside the game's RAM (cnv_main.s)
.equ GUARD_BITMAP,    4              # a LOAD of a bitmap that is not resident (cnv_main.s)
.equ GUARD_FILE,      5              # a game file could not be opened, read or unpacked (cnv_main.s)
.equ VM_STACK_SIZE,   0x200          # 256 x u16 at VM_STACK
