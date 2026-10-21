# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# KN7000 KN7APP.BIN build (cnv_main.s): the platform definitions. The game is an application of the
# generic SD loader KN7LOAD.CNV (technics-roms-disasm kn7000/tools/cnv_romdump: loader.s, and
# kn7cnv.inc, the contract between the two, which cnv_main.s includes before this file). No firmware
# address is built in: the loader finds the SD file routines and hands them over in its service
# table; fwfind.s finds the task services, the millisecond counter, the panel bitmaps and the MIDI
# rings by their code, so one KN7APP.BIN runs on program 893 (v1.3), 935, 941 (v1.6) and 942
# (tools/aw_find_fw.py runs the same searches over each).
#
# DISK MENU > STYLE CONVERT lists the floppy's *.CNV files, reads the chosen one (KN7LOAD.CNV) whole
# to 0x502B8000 (after zeroing 0x30000 bytes there) and calls its first byte with `calls (a0)` on the
# firmware's main task (941 0x48479929, 893 0x48479766). On its first call the loader finds the
# firmware's file routines, zeroes APP_BASE..CNV_END, reads C:\KN7APP.BIN to APP_BASE, checks its
# header and CRC-32, and from then on calls the application's entry (AH_ENTRY) on every converter
# call, with the SD card's current folder emptied around it (file names are relative to C:\). Each
# time it returns, the firmware reads a request from the mailbox at 0x5031BC00, serves it, writes
# 0xFF there and calls again. Request 5 shows the NUL-terminated text that follows it in the mailbox
# on title 0x4A (_TT_STYLCNVTXT); the firmware then keeps calling (about 20 times a second), so
# answering 5 every time parks the UI on the converter while our own task runs. Request 0xFE ends
# the conversion (title 0x4C, then EXIT goes back to DISK MENU); "Continue Next?" YES then makes the
# loader read KN7APP.BIN afresh. See technics-roms-disasm kn7000/notes/style-converter.md, the
# loader's README.md ("How it stays out of the firmware's way") and README-CNV.md here.

# ---- display: LCD frame, 640x240 RGB565, 1280 bytes/row (FB, FB_STRIDE: kn7cnv.inc) -----
.equ FB_W,            640
.equ FB_H,            240
.equ AW_W,            320
.equ AW_H,            200
.equ AW_X0,           160           # (640-320)/2
.equ AW_Y0,           20            # (240-200)/2

# ---- the converter area, the loader and the mailbox -------------------------------------
# kn7cnv.inc: CNV_BASE 0x502B8000 (where the firmware loads KN7LOAD.CNV), CNV_END 0x502E8000 (end of
# the 0x30000 bytes the firmware zeroes, and of what the loader zeroes before each application
# load), SVC 0x502B9E00 (the loader's service table), APP_BASE 0x502BA000 (where KN7APP.BIN is
# loaded: this module's .mnbase), MAILBOX 0x5031BC00 (byte 0: our request; request 5's text follows).
# The loader stays resident below APP_BASE -- its code, line buffer, variables and service table,
# 0x502B8000-0x502B9FFF -- and runs on every converter call: the game never writes there, and reads
# only the service table (tools/ic23_guard.py --loader checks both, tools/cnv_layout.py the map).
.equ LOADER_LO,       CNV_BASE      # the loader's resident area: never written by the game
.equ LOADER_HI,       APP_BASE
.equ LOADER_CODE_HI,  LOADER_VARS-0x100  # the loader's image ends below its line buffer (its Makefile: < 0x1C00)
.equ MAILBOX_PAGE,    0x5031B000    # the firmware writes 0x5031BC00.. and 0x5031BFFC: never ours
.equ MAILBOX_PAGE_END, 0x5031C000

# ---- where the game lives (README-CNV.md, "Memory") ------------------------------------
# All of it in the work RAM STYLE CONVERT leaves to a converter, measured on program 893 in MAME
# (research-scratch aw-memory-plan: taps893_ranges.out): 0x502B8000-0x50379FFF stays untouched by
# the firmware through boot, idle, DISK MENU and a converter run, except the mailbox page (and the
# acceptance tests measure it again with the loader and the SD card: probes/cnv/README.md); less the
# loader's resident area below APP_BASE. Nothing
# of the game is in CS1 (0x44000000-0x47FFFFFF and its view 0x84000000-0x87FFFFFF: IC23, the
# battery-backed SRAM with the panel settings and the PANEL MEMORY records, repeating every 256 KB
# through the whole chip select) nor in the user-memory pools 0x50180000-0x50297FFF (COMPOSER
# styles, pads; kept across power-off). tools/ic23_guard.py checks every address this build
# names; tools/cnv_layout.py checks the regions below; the run-time guard (cnv_main.s GuardRange,
# vm.s GuardPage) refuses a computed one outside [AW_LO, AW_HI) or on the mailbox page.
.equ AW_LO,           APP_BASE      # every byte the game writes is in [AW_LO, AW_HI) ...
.equ AW_HI,           0x5037A000    # ... (0x5037A000 on holds boot data) minus the mailbox page
.equ IMAGE_END_MAX,   0x502C8000    # KN7APP.BIN itself (header, code, tables) must end before this
.equ HELP_BUF,        0x502C8000    # 64,000 bytes: help pages, the stop screen, and the buffer a
.equ BITMAP_BUF,      HELP_BUF      #   packed bitmap is unpacked into before LoadBitmap draws it
.equ AW_FONT,         0x502D8000    # anotherworld_chargen.rom, 768 bytes
.equ AW_STRIDX,       0x502D8300    # str_index.rom, 2048 bytes
.equ AW_STRDAT,       0x502D8B00    # str_data.rom, 4096 bytes, to 0x502D9AFF
.equ AUDIO_VARS,      0x502DA000    # audio.s: the MIDI producer, the music player, the note slots, 0x200 bytes
.equ SND_TAB,         0x502DA200    # AWSND.AW: each sound's program, note and length (tools/aw_sound_map.py)
.equ SND_TAB_MAX,     0x400
.equ DSP_HOST,        0x502DA600    # dsp.s: the effects DSP's routines, state, command records, readback, 0x400 bytes
.equ MUSIC_BUF,       0x502DB000    # the current part's music module (0x07 intro, 0x8A final), unpacked in
.equ MUSIC_MAX,       0x4000        #   place (aw_extract.py --parts puts it in the part's list), to 0x502DEFFF
# The variables, 0x502DF000-0x502E6FFF. Until the DSP build (2026-10-21) they were 0x1F000 lower, at
# 0x502C0000-0x502C7FFF, right after the image; they moved up as one block, with the same layout, to give the
# image 32 KB more (probes/cnv/*.lua follow the new addresses).
.equ CNV_VARS,        0x502DF000    # the application's entry and part loader's variables (cnv_main.s)
.equ FW_VARS,         0x502DF400    # what fwfind.s found (below), then its scratch from +0x40
.equ AW_PATHS,        0x502DF800    # the game's folder and the name being opened (cnv_main.s AppPath):
.equ AW_PREFIX,       AW_PATHS      #   16 bytes: "AW\" from the program menu's launch block, "" in the root
.equ AW_PATHBUF,      AW_PATHS+0x10 #   32 bytes: AW_PREFIX and a file name
.equ AW_PATHNAME,     AW_PATHS+0x30 #   the name AppPath was given
.equ AW_PATHS_LEN,    0x40
.equ VM_POLY_BASE,    0x502E0000    # vm.inc: rasterizer scratch, 0x200 bytes
.equ VM_INTERP_BASE,  0x502E1000    # vm.inc: the interpreter, 0x1100 bytes
.equ VM_MISC_BASE,    0x502E3000    # vm.inc: the rest, 0x1400 bytes
.equ RES_TAB,         0x502E5000    # u32 per resource id: where it is resident now (0 = not)
.equ VM_PERF_BASE,    0x502E6000    # vm.inc: the speed measurement and the blit's tables, 0x1000 bytes
.equ DSP_BANKTAB,     0x502E7000    # AWBANK.AW: where each sound of the DSP's sample bank goes (aw_extract.py)
.equ DSP_BANKTAB_MAX, 0xF00         #   to 0x502E7EFF, below the program menu's launch block (LB_ADDR)
.equ VIDEO2_AT,       0x502E8000    # the shared polygons (resource 0x11, 25,108 bytes), loaded once
.equ PART_AREA,       0x502EE400    # the current part's palette, bytecode, polygons, bitmaps (and, before the
.equ PART_END,        0x5031B000    #   first part, the sample bank's coded files, dsp.s BankRead) (largest part,
                                    #   the city: 164,407 bytes; aw_extract.py --parts)
.equ PAGE_BITMAP_0,   0x50320000    # four 320x200 pages, one per 0x10000 (interp.s GetPagePtr)
.equ PAGE_BITMAP_1,   0x50330000
.equ PAGE_BITMAP_2,   0x50340000
.equ PAGE_BITMAP_3,   0x50350000    # to 0x5035F9FF
.equ SHADOW,          0x50360000    # 64,000 bytes: the page as the LCD shows it now (display.s BlitPage)
.equ REPORT_BUF,      0x50370000    # 8 KB: the text of AWPERF.TXT, written to the SD card at quit (cnv_main.s)
.equ REPORT_MAX,      0x2000
.equ PAGE_SIZE,       AW_W*AW_H

# ---- MIDI IN as game input ----------------------------------------------------------
# The game's own sound goes into the MIDI IN 1 receive ring on channels 4-16 (audio.s), so the note
# trackers count only channels 1-3 there (interp.s NotesAnyHeld): play the game over MIDI IN on 1-3.
.equ MIDI_IN_CHANNELS, 0x0007
.equ YIELD_SLICE,     4             # cnv_main.s DLY_TSK yields in slices of at most this many ms (audio.s)

# ---- task ------------------------------------------------------------------------
# Every firmware task runs at priority 3 and micro-ITRON does not time-slice, so ours runs at 3
# too and yields every frame (DLY_TSK). Slots 10, then 9, are free. The kernel allocates the
# task's stack itself (cre_tsk) and frees it at exd_tsk.
.equ TASK_ID_FIRST,   10
.equ TASK_ID_LAST,    9
.equ TASK_PRI,        3
.equ TASK_STACK,      0x2000         # room for the VM's polygon-hierarchy recursion

# ---- quitting ----------------------------------------------------------------------
.equ EXIT_OFS,        0x30+11       # EXIT = CPC_SEG11 SW7: PANEL_CPL + 11 (vm.inc FWV_PANEL)
.equ EXIT_BIT,        0x80
.equ QUIT_HOLD_MS,    1500          # hold EXIT this long to leave the game

# ---- what fwfind.s finds (FwStep), in FW_VARS ----------------------------------------
.equ FW_STEPS,        8             # 0-5 must find what they look for; 6-7 (the effects DSP) may not
# FW_OPEN .. FW_CLOSE and FW_SETEXT, FW_RESETEXT are the SD file routines the loader found and put in
# its service table (SV_OPEN, SV_READ, SV_CLOSE, SV_SETEXT, SV_RESETEXT), copied by step 2 after it
# has checked the table: either the SD backends themselves (FOUND_TABLES; the drive switch is then the
# loader's no-op) or the fmm dispatchers with the drive switch (FOUND_FILESIG).
.equ FW_OPEN,         FW_VARS + 0x00   # open(a0 = name, a1 = mode "rb") -> d0 (16-bit, < 0 = error)
.equ FW_READ,         FW_VARS + 0x04   # read(a0 = buffer, d0 = bytes) -> d0 = bytes read
.equ FW_CLOSE,        FW_VARS + 0x08   # close(): the one open file
.equ FW_CRE,          FW_VARS + 0x0C   # ER cre_tsk(d0 = id, a0 = &T_CTSK)
.equ FW_STA,          FW_VARS + 0x10   # ER sta_tsk(d0 = id, d1 = start code)
.equ FW_DLY,          FW_VARS + 0x14   # the firmware's yield: d0 = ms (adds to the ms counter, rotates the ready queue)
.equ FW_EXD,          FW_VARS + 0x18   # exd_tsk(): exit and delete the calling task
.equ FW_SETEXT,       FW_VARS + 0x1C   # SetExtMode(d0 = 1): the file layer to the SD card (or a no-op)
.equ FW_RESETEXT,     FW_VARS + 0x20   # ResetExtMode: back to the floppy, as the firmware expects (or a no-op)
.equ FW_WRITE,        FW_VARS + 0x24   # write(a0 = buffer, d0 = bytes) -> d0 = bytes written (0: none; AWPERF.TXT only)
.equ FILE_PIECE,      0x4000           # a file is read in pieces of this size, as the loader reads KN7APP.BIN
# The RAM addresses the shared VM reads (the ms counter, the panel bitmaps, the MIDI rings) go to
# vm.inc's FWV_* variables.
