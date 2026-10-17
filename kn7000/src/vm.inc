# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World VM state for the KN7000 port. The VM's working variables live in a
# small block of the 0x44 scratch window (CPU-writable; not used by the firmware).
# Field names and sizes mirror the KN5000 TLCS-900 source so the two stay readable
# side by side.

.equ VM_STATE,        0x44050000

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
# Arrays first, then scalars. All in the 0x44 scratch window.
.equ VM_VARIABLES,    0x44070000      # 256 x s16   (var[0..255])
.equ THREADS_DATA,    0x44070400      # 64 x {u16 pc @+0, u16 requested_pc @+2}
.equ VM_CHAN_STATE,   0x44070600      # 64 x {u8 state @+0, u8 requested_state @+1}
.equ VM_STACK,        0x44070800      # 256 x u16   (VM call stack)

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
.equ CURRENT_THREAD,  0x44071000      # u8
.equ VM_PC,           0x44071002      # u16
.equ VM_SP_PTR,       0x44071004      # u32  (points into VM_STACK)
.equ CUR_PAGE_1,      0x44071008      # u32  draw target page
.equ CUR_PAGE_2,      0x4407100C      # u32  display page
.equ CUR_PAGE_3,      0x44071010      # u32  work/back page
.equ CUR_VIDEO_DATA,  0x44071014      # u32  active polygon source
.equ CUR_VIDEO_1,     0x44071018      # u32  cinematic polygon source
.equ CUR_VIDEO_2,     0x4407101C      # u32  secondary polygon source
.equ CUR_BYTECODE,    0x44071020      # u32
.equ CUR_PALETTES,    0x44071024      # u32
.equ CUR_ZOOM,        0x44071028      # u16
.equ CURRENT_PART_ID, 0x4407102A      # u16
.equ REQ_NEXT_PART,   0x4407102C      # u16

# Game resources are loaded from the SD card as four separate files (the firmware's
# fread_api has a 16-bit count and no working sequential reads, so each resource is one
# fopen+fread+fclose, and each must be <= 65535 bytes -- all four are). Fixed load
# addresses in the 0x44 scratch window, clear of the pages and the VM state. Sizes are
# the intro resources' exact byte lengths; keep them in step with the SD files.
.equ AW_BYTECODE,     0x44400000     # resource 0x18, 9871 bytes
.equ AW_VIDEO1,       0x44420000     # resource 0x19, 65230 bytes
.equ AW_VIDEO2,       0x44440000     # resource 0x11, 25108 bytes
.equ AW_PALETTES,     0x44460000     # resource 0x17, 2048 bytes
.equ AW_FONT,         0x44480000     # anotherworld_chargen.rom, 768 bytes (8x8, chars 0x20+)
.equ AW_STRIDX,       0x44490000     # str_index.rom, 2048 bytes (LE u16 offset per string id)
.equ AW_STRDAT,       0x444A0000     # str_data.rom, 4096 bytes (NUL-terminated strings)
.equ AW_BYTECODE_SZ,  9871
.equ AW_VIDEO1_SZ,    65230
.equ AW_VIDEO2_SZ,    25108
.equ AW_PALETTES_SZ,  2048
.equ AW_FONT_SZ,      768
.equ AW_STRIDX_SZ,    2048
.equ AW_STRDAT_SZ,    4096

# Part 0x3E82 (water -- first playable) resources, preloaded at startup into their
# own RAM region just past the intro's. video2 (0x11) is shared with the intro.
.equ AW2_BYTECODE,    0x444B0000     # resource 0x1B, 20810 bytes
.equ AW2_VIDEO1,      0x444C0000     # resource 0x1C, 57510 bytes
.equ AW2_PALETTES,    0x444D0000     # resource 0x1A, 2048 bytes
.equ AW2_BYTECODE_SZ, 20810
.equ AW2_VIDEO1_SZ,   57510
.equ AW2_PALETTES_SZ, 2048
.equ AW_LOADED_FLAG,  0x44080020     # set to 0x600D once all four are loaded

.equ DRAW_BUDGET,     0x44080070     # per-VIDEO-op polygon budget (anti-hang guard)
.equ DRAW_BUDGET_MAX, 4000
.equ DRAW_DEPTH,      0x44080074     # polygon-hierarchy recursion depth (stack guard)
.equ DRAW_DEPTH_MAX,  12             # AW hierarchies are shallow; cap to protect the stack

# Frame pacing, the Another World way: a frame lasts var[0xFF] (PAUSE_SLICES) * SLICE_MS,
# the bytecode setting var[0xFF] each frame. We sleep only the remainder after the frame's
# work (measured via the firmware's 1 kHz counter), with a floor so the firmware keeps
# getting time for the keybed/panel. SLICE_MS = 20 is authentic AW; lower it to run faster.
.equ KERNEL_MS,       0x500D3C68     # firmware 1 kHz millisecond counter (u32)
.equ FRAME_START_MS,  0x44080044     # u32 scratch: KERNEL_MS at the start of this frame

# Last-applied direction bits per axis, for the sticky opposing-key rule. When both keys of an
# axis are held at once (ambiguous -- and the voice ring's order does NOT reliably say which was
# pressed last, so newest-wins mis-picks ~15% of the time, awringorder.lua), we keep whichever
# direction was already applied until that key is released. 0 = none, LR: 1 right/2 left, UD: 4
# down/8 up. Deterministic and brush-proof, unlike the ring-order newest-wins it replaces.
.equ PREV_LR_BITS,    0x44080048     # u16: last-applied L/R bit (0 / 1 / 2)
.equ PREV_UD_BITS,    0x4408004A     # u16: last-applied U/D bit (0 / 4 / 8)
.equ VAR_PAUSE_SLICES, 0xFF          # var index holding the per-frame slice count
.equ SLICE_MS,        20             # ms per slice (authentic AW)
.equ MIN_YIELD_MS,    8              # never yield less than this (firmware must run)
.equ MAX_YIELD_MS,    400            # safety cap on a single frame's sleep

# VM instruction trace (for diffing against the vm-gui reference). Each entry is 8
# bytes: frame(u16)@0, thread(u8)@2, opcode(u8)@3, pc(u16)@4. Dumped by probes/awtrace.lua.
.equ TRACE_COUNT,     0x44080078     # entries logged so far
.equ FRAME_NO,        0x4408007C     # current VM frame (tick) number
.equ TRACE_BUF,       0x44800000     # 8 bytes/entry (up to ~1.6 MB here, clear of all else)
.equ TRACE_MAX,       200000         # enough to hold the whole intro

# ================================================================================
# Player input (gameplay directional control for the water part, 0x3E82).
#
# The KN7000 firmware keeps a debounced control-panel button bitmap in work RAM: one
# byte per CP serial segment, one bit per switch line (bit = 1 << SWn), held 1 for as
# long as the physical button is down. The CPR half-panel's segments live at
# PANEL_CPR+seg, the CPL/CPC half at PANEL_CPL+seg. Decoded (byte+bit per button, and
# that it is level- not edge-held) by probes/awpanelmap.lua, which drives every cpanel
# ioport in MAME and diffs this region -- see probes/PANEL-INPUT.md. The keybed cannot
# serve here: its voice-event FIFO is drained by the firmware and the per-voice RAM
# holds free-running phase accumulators, not a stable held-note identity (three probes:
# probes/PANEL-INPUT.md). So gameplay directions come from five panel buttons instead.
.equ PANEL_CPR,       0x5006BE60     # CPR_SEGn button bitmap at PANEL_CPR + n
.equ PANEL_CPL,       0x5006BE90     # CPL_SEGn / CPC_SEGn button bitmap at PANEL_CPL + n

# The Another World D-pad + fire. Buttons chosen for mnemonic labels and for landing in
# distinct bytes, so any combination can be held and read at once.
.equ BTN_LEFT_ADDR,   PANEL_CPR+2    # PART SELECT LEFT     (CPR_SEG2 SW0)
.equ BTN_LEFT_BIT,    0x01
.equ BTN_RIGHT_ADDR,  PANEL_CPR+1    # PART SELECT RIGHT 1  (CPR_SEG1 SW1)
.equ BTN_RIGHT_BIT,   0x02
.equ BTN_UP_ADDR,     PANEL_CPR+6    # R1/R2 OCTAVE +       (CPR_SEG6 SW1)
.equ BTN_UP_BIT,      0x02
.equ BTN_DOWN_ADDR,   PANEL_CPR+7    # R1/R2 OCTAVE -       (CPR_SEG7 SW1)
.equ BTN_DOWN_BIT,    0x02
.equ BTN_FIRE_ADDR,   PANEL_CPR+5    # SUSTAIN              (CPR_SEG5 SW3)
.equ BTN_FIRE_BIT,    0x08

# Another World hero-control variables (same indices as the DOS game). The mask bits and
# signed values match rustyworld's update_player (our checksum oracle): RIGHT {1,+1},
# LEFT {2,-1}, DOWN {4,+1}, UP {8,-1}, BUTTON {0x80,+1}; RIGHT beats LEFT, DOWN beats UP.
.equ VAR_HERO_LR,       0xFC         # left/right position delta  (s16)
.equ VAR_HERO_UD,       0xE5         # up/down position delta     (s16)
.equ VAR_HERO_JUMP,     0xFB         # jump/down = copy of UD
.equ VAR_HERO_POS_MASK, 0xFD         # OR of all held inputs' masks
.equ VAR_HERO_ACTION,   0xFA         # fire button down -> 1
.equ VAR_HERO_ACT_MASK, 0xFE         # POS_MASK (the button mask is already in it)

# Keybed gameplay mapping (polyphonic held-note read; probes/PLUGIN-INPUT-INTERFACES.md).
# The TG voice allocator keeps a 128-bit held-slot bitmap and, per slot, the MIDI note.
# Verified in-game (probes/awkeyread.lua). Read each frame and OR'd into the panel mask,
# so keyboard and panel both work and either source can supply diagonals / move+fire.
.equ TG_HELD_MASK,    0x500D288C     # 16 bytes: bit per voice slot, set while its key is held
.equ TG_NODE_BASE,    0x500D1278     # voice node array; MIDI note at +0x0C, stride 0x2C
.equ TG_NODE_STRIDE,  0x2C
.equ TG_NODE_NOTE,    0x0C
# Active-voice ring (the FAST, symmetric key signal). Head cell holds a pointer to the
# first node's link field (node+0x10); from a link L the note is at (L-4)=node+0x0C and
# the next link at (L). A released note leaves the ring in ~17 ms -- symmetric with
# key-on, unlike the sustain mask's ~50 ms key-off (that asymmetry was the "extra kick").
# Walk guarded by bounds + a node cap so a bad pointer can't hang the VM.
.equ TG_RING_HEAD,    0x500D1050     # u32: head link of the class-0 active-voice ring (0=empty)
.equ TG_RING_LO,      0x500D1000     # sane address bounds for a ring link
.equ TG_RING_HI,      0x500D3000
.equ TG_RING_CAP,     64             # max nodes to walk
# Note numbers (C4 = 60). Any note <= C4 is ACTION -- the whole bass/left-hand range plus
# C4 itself. The right-hand cluster is the D-pad; Ab5 and Bb5 both map to UP.
.equ KBD_ACTION_MAX,  60             # <= 60 (bass range + C4) -> action
.equ KBD_LEFT_NOTE,   77             # F5
# UP was Ab5(80)/Bb5(82), but both GHOST against the run/direction keys in the keybed scan
# matrix (awrun_diag.lua/awupnote.lua: Ab5/Bb5/Db6/Eb6 vanish from the firmware held mask
# whenever another key is held, so run-right-and-jump was impossible). B5 and D6 survive the
# action+direction combos cleanly, so UP uses those.
.equ KBD_UP_NOTE_A,   83             # B5  (ghost-free with action + left/right)
.equ KBD_UP_NOTE_B,   86             # D6  (ghost-free alternate)
.equ KBD_DOWN_NOTE,   81             # A5
.equ KBD_RIGHT_NOTE,  84             # C6
