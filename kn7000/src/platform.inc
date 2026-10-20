# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# KN7000 / SP7001 platform definitions for the Another World port.
#
# *** MAME ONLY. NOT FOR A REAL INSTRUMENT. *** This build keeps the game in the 0x44000000 window.
# MAME's upstream driver maps 16 MB of plain RAM there as a placeholder; on a real KN7000 the
# window is chip select CS1, which is IC23 alone: the 256 KB battery-backed SRAM holding the panel
# settings and the 104 PANEL MEMORY records, repeating every 256 KB through the whole window
# (confirmed on Felipe's unit, 2026-10-20). Every game write would land on the stored settings, and
# the firmware's power-off stamps the damage valid (kn7000_mame notes/ic23-nvram-2026-10-20). Its
# loader also uses STAGING_BIG in the user-memory pool (the TPAD pads). The STYLE CONVERT build
# (platformcnv.inc) is the one that stays out of both; this one cannot follow it there, because
# the plug-in's file API works only during the plug-in load, so it cannot load per part (README.md).
# The Makefile runs tools/ic23_guard.py on it and refuses to build it without MAME_ONLY=1.
#
# The game rides along with the SP7001 base plug-in BASEEXT.XAP: tools/xap_addon.py
# (in kn7000_disassembly) places this module in the plug-in's unused tail and
# redirects XapEntry's first instruction to our hook. The hook runs on the
# firmware's loading task, where the file API works; it loads the game from the SD
# card into RAM and starts a task that renders to the LCD. BASEEXT keeps working,
# so the firmware reaches its static SP7001 screen -- on which a full-frame blit
# persists (the firmware only repaints what changes). See kn7000/README.md and the
# probes/ for how each fact below was established.

# ---- where the plug-in runs ----------------------------------------------------
.equ XAP_RESUME,      0x5029B005    # BASEEXT's XapEntry, after its first two instructions

# ---- plug-in API (program 942 export table / framework file methods) -----------
.equ CRE_TSK_X,       0x48585D42    # ER cre_tsk_X(d0 = id, a0 = &T_CTSK)
.equ STA_TSK,         0x4C03DCD3    # ER sta_tsk(d0 = id, d1 = start code)
.equ DLY_TSK,         0x4C03E295    # ER dly_tsk(d0 = milliseconds)
.equ SYS_MS,          0x500D3C68    # kernel 1 kHz tick (ms since power-on)
# File API -- call ONLY from the hook (firmware task context), buffers in WORK RAM.
.equ FOPEN,           0x48585E2A    # FILE* fopen_api(a0 = path, a1 = mode)   e.g. "rb"
.equ FREAD,           0x48585E50    # n    fread_api(a0 = buf, a1 = FILE, d0 = size, d1 = count)
.equ FCLOSE,          0x48585E65    #      fclose_api(a0 = FILE)

# ---- task ----------------------------------------------------------------------
# micro-ITRON is priority-preemptive: a task below the firmware's priority 3 is never
# scheduled while the firmware's (always-ready) tasks exist, so we MUST run at 3 and
# round-robin with them -- the per-frame dly_tsk is what keeps the firmware alive.
# Slots 10 then 9 are free; 11 would overrun the TCB table.
.equ TASK_ID_FIRST,   10
.equ TASK_ID_LAST,    9
.equ TASK_PRI,        3
.equ TASK_STACK,      0x2000         # room for the VM's polygon-hierarchy recursion

# ---- display: LCD frame, 640x240 RGB565, 1280 bytes/row ------------------------
.equ FB,              0x9CE00000
.equ FB_W,            640
.equ FB_H,            240
.equ FB_STRIDE,       1280
# Another World is 320x200; draw it centred.
.equ AW_W,            320
.equ AW_H,            200
.equ AW_X0,           160           # (640-320)/2
.equ AW_Y0,           20            # (240-200)/2

# ---- RAM for the game (MAME ONLY, see the top) ------------------------------------
# Work RAM 0x50000000-0x503FFFFF is real but heavily used by the firmware, and is
# the only region the SD read can DMA into. The 0x44000000 window is NOT free RAM on
# an instrument: it is CS1 = IC23, the battery-backed settings SRAM (above). In MAME's
# upstream driver it is a 16 MB placeholder, which is the only reason this build runs.
# The SD read cannot target it, so the loader reads into a work-RAM staging buffer
# and copies to 0x44.
.equ STAGING,         0x50300000    # work-RAM staging buffer for SD reads
.equ STAGING_BIG,     0x50200000    # work-RAM buffer large enough for the whole AWDATA (in the TPAD pool!)
.equ GAME_RAM,        0x44000000    # the game image + page buffers live here
.equ PAGE_BITMAP_0,   0x44100000    # four 320x200 pages, one per 0x10000
.equ PAGE_BITMAP_1,   0x44110000
.equ PAGE_BITMAP_2,   0x44120000
.equ PAGE_BITMAP_3,   0x44130000
.equ PAGE_SIZE,       AW_W*AW_H     # 64000 bytes, one colour index per pixel
.equ VM_POLY_BASE,    0x44050000    # vm.inc's three blocks
.equ VM_INTERP_BASE,  0x44070000
.equ VM_MISC_BASE,    0x44080000
.equ HELP_BUF,        0x44140000    # 64000 bytes (the pages end at 0x44140000)
.equ AW_FONT,         0x44480000    # anotherworld_chargen.rom, 768 bytes (8x8, chars 0x20+)
.equ AW_STRIDX,       0x44490000    # str_index.rom, 2048 bytes (LE u16 offset per string id)
.equ AW_STRDAT,       0x444A0000    # str_data.rom, 4096 bytes (NUL-terminated strings)
.equ TRACE_BUF,       0x44800000    # main.s TraceInsn: 8 bytes/entry
.equ TRACE_MAX,       200000        # enough to hold the whole intro

# ---- RAM the VM reads (program 942; main.s Hook copies them to vm.inc's FWV_* variables) ----
.equ KERNEL_MS,       0x500D3C68     # firmware 1 kHz millisecond counter (u32)
.equ PANEL_CPR,       0x5006BE60     # CPR_SEGn button bitmap at PANEL_CPR + n
.equ PANEL_CPL,       0x5006BE90     # CPL_SEGn / CPC_SEGn button bitmap at PANEL_CPL + n
.equ MIDIIN1_RXQ,     0x5001F060     # MIDI IN 1 receive ring header (1024 bytes)
.equ MIDIOUT1_TXQ,    0x5001F874     # MIDI OUT 1 transmit ring header (2048 bytes): the keybed
