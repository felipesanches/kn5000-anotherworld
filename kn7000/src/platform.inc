# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# KN7000 / SP7001 platform definitions for the Another World port.
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

# ---- RAM for the game ----------------------------------------------------------
# Work RAM 0x50000000-0x503FFFFF is real but heavily used by the firmware, and is
# the only region the SD read can DMA into. The 0x44000000 window (16 MB) is CPU-
# writable scratch the firmware does not use, but the SD read cannot target it --
# so the loader reads into a work-RAM staging buffer and copies to 0x44.
.equ STAGING,         0x50300000    # work-RAM staging buffer for SD reads
.equ STAGING_BIG,     0x50200000    # work-RAM buffer large enough for the whole AWDATA
.equ GAME_RAM,        0x44000000    # the game image + page buffers live here
.equ PAGE_BITMAP_0,   0x44100000    # four 320x200 pages, one per 0x10000
.equ PAGE_BITMAP_1,   0x44110000
.equ PAGE_BITMAP_2,   0x44120000
.equ PAGE_BITMAP_3,   0x44130000
.equ PAGE_SIZE,       AW_W*AW_H     # 64000 bytes, one colour index per pixel

# ---- RAM the VM reads (program 942; build 941 has each 0x10 lower: platform941.inc) ----
.equ KERNEL_MS,       0x500D3C68     # firmware 1 kHz millisecond counter (u32)
.equ PANEL_CPR,       0x5006BE60     # CPR_SEGn button bitmap at PANEL_CPR + n
.equ PANEL_CPL,       0x5006BE90     # CPL_SEGn / CPC_SEGn button bitmap at PANEL_CPL + n
.equ MIDIIN1_RXQ,     0x5001F060     # MIDI IN 1 receive ring header (1024 bytes)
.equ MIDIOUT1_TXQ,    0x5001F874     # MIDI OUT 1 transmit ring header (2048 bytes): the keybed
