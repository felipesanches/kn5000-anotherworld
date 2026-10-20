# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# Another World on the Technics SX-KN7000 with no SP7001: the game is KN7APP.BIN, an application of
# the generic SD loader KN7LOAD.CNV (technics-roms-disasm kn7000/tools/cnv_romdump; kn7cnv.inc is the
# contract). DISK MENU > STYLE CONVERT runs KN7LOAD.CNV from the floppy; the loader reads this file
# from the SD card's root folder to APP_BASE (0x502BA000), checks its header and CRC-32, and calls
# its entry (AH_ENTRY = CnvEntry) on every converter call, on the firmware's main task
# (platformcnv.inc says how the firmware drives a converter). Any program build: 893 (v1.3), 935,
# 941 (v1.6), 942. The game's files are beside KN7APP.BIN in the card's root folder (README-CNV.md).
#
# Each call does one step and returns; every call but the last answers request 5 (a short text),
# which parks the firmware on the converter while the game task runs:
#   * the first FW_STEPS calls find the firmware's routines and RAM (fwfind.s), and check the
#     loader's service table, whose SD file routines the game reads its files with;
#   * the next ones read the font, the strings and the shared polygons from the SD card, one file
#     per call (GlobalList), then start the game task (display.s GameTask runs the VM);
#   * from then on, whenever the game task asks for a part (EnsurePart, at a part switch), each call
#     reads one of that part's files and unpacks it in place (LoadStep), until the part is resident.
# Holding EXIT for QUIT_HOLD_MS asks the game task to end itself at its next yield (DLY_TSK below);
# the following call answers 0xFE, which hands the instrument back: the firmware shows a message
# (EXIT), then "Continue Next?". YES makes the loader read KN7APP.BIN afresh (zeroing APP_BASE..
# CNV_END first) and call it, which starts a new game from the firmware search on; NO leaves.
#
# Memory: platformcnv.inc. The game writes nothing outside [AW_LO, AW_HI) but the mailbox and the LCD:
# not CS1 (IC23, the panel memories), not the user-memory pools, not the loader's resident area
# below APP_BASE, whose service table it only reads (tools/ic23_guard.py --loader checks every
# address named here; GuardRange checks every computed load destination at run time).

.include "kn7cnv.inc"               # the loader's contract (technics-roms-disasm cnv_romdump)
.include "platformcnv.inc"
.include "vm.inc"
.include "awpart.inc"               # generated: RES_COUNT, PART_LISTS, LR_* (tools/aw_extract.py --parts)
.mnbase APP_BASE                    # where KN7LOAD.CNV loads KN7APP.BIN
.equ ResAddr,      RES_TAB          # interp.s ResPtr: the table the part loader fills

# ---- the application header (kn7cnv.inc AH_*); mkapp.py fills in the size and the CRC-32 ----
AppHeader:
    .ascii  "KN7A"                  # AH_MAGIC
    .long   LOADER_ABI              # AH_ABI
    .long   0                       # AH_SIZE (mkapp.py)
    .long   CnvEntry                # AH_ENTRY: called on every converter call
    .long   0                       # AH_CRC (mkapp.py)
    .long   APP_BASE                # AH_BASE
    .long   0, 0
AppName:                            # AH_NAME: 32 bytes, NUL-padded
    .ascii  "ANOTHER WORLD"
    .space  AppHeader + 0x40 - .

# ---- our variables (CNV_VARS, zeroed by the loader with the whole application area on each load) ----
.equ CV_STATE,     CNV_VARS + 0x00  # 0 first call, 1 searching, 2 global files, 3 running, 4 failed
.equ CV_QUIT_REQ,  CNV_VARS + 0x04  # set by the entry when EXIT has been held long enough
.equ CV_TASK_DONE, CNV_VARS + 0x08  # set when no game task runs (ended, or never started)
.equ CV_EXIT_T0,   CNV_VARS + 0x0C  # the ms counter when EXIT went down (0 = up)
.equ CV_CALLS,     CNV_VARS + 0x10  # entry calls so far
.equ CV_FAIL,      CNV_VARS + 0x14  # why the game cannot start: 0x100 + search step, 0x200 file, 0x300 task
.equ CV_STEP,      CNV_VARS + 0x18  # the firmware search's next step
.equ CV_TASK_ID,   CNV_VARS + 0x1C  # the game task's id (0 = none)
.equ CV_FAILCALLS, CNV_VARS + 0x20  # calls since failing, when EXIT cannot be read
.equ CV_ENDED,     CNV_VARS + 0x30  # we answered 0xFE: the next call is "Continue Next?" -> YES
.equ CV_REPORT,    CNV_VARS + 0x34  # AWPERF.TXT at quit: 0 not yet, 1 written, 2 not written (none or failed)
.equ CV_REPORT_N,  CNV_VARS + 0x38  # what the last file call of the report returned (bytes, or < 0)
.equ CV_REPORT_K,  CNV_VARS + 0x3C  # the report's file: AWPERFk.TXT (0-9), or 10 when all ten exist
.equ CV_NAME,      CNV_VARS + 0x180 # 16 bytes: that name
.equ LD_REQ,       CNV_VARS + 0x40  # the part id the game task waits for (written by the game task)
.equ LD_CUR,       CNV_VARS + 0x44  # the part id whose files are resident (0 while one loads)
.equ LD_PART,      CNV_VARS + 0x48  # the part id being loaded
.equ LD_REC,       CNV_VARS + 0x4C  # the next record of the list being loaded (0 = no load running)
.equ LD_DONE,      CNV_VARS + 0x50  # records loaded of this list
.equ LD_TOTAL,     CNV_VARS + 0x54  # records in this list
.equ LD_FAILED,    CNV_VARS + 0x58  # a file of the list could not be loaded: the game stops
.equ LD_IN_READ,   CNV_VARS + 0x5C  # 1 while fmmread fills a destination for us (the probes' taps)
.equ LD_T0,        CNV_VARS + 0x60  # the ms counter when this list started
.equ LD_MS,        CNV_VARS + 0x64  # how long the last list took
.equ LD_LISTS,     CNV_VARS + 0x68  # lists loaded so far (the global one, then each part)
.equ LD_BAD_ID,    CNV_VARS + 0x6C  # the resource id (or 0xFFFF) of the file that failed
.equ LD_ERRORS,    CNV_VARS + 0x70  # files that failed so far
.equ LD_HELD,      CNV_VARS + 0x74  # calls a new list has waited for the panel to be let go
.equ LD_TRIES,     CNV_VARS + 0x78  # failed attempts at the current record
.equ LD_RETRIED,   CNV_VARS + 0x7C  # files that loaded at a second or third attempt, so far
.equ FILE_TRIES,   3                # attempts per file before the list fails
.equ HELD_CALLS,   100              # at most about 5 s: then it loads anyway
.equ BK_CRC,       CNV_VARS + 0x80  # unpacker state
.equ BK_LEFT,      CNV_VARS + 0x84
.equ BK_N,         CNV_VARS + 0x88
.equ BK_ACC,       CNV_VARS + 0x8C
.equ BK_D1,        CNV_VARS + 0x90
.equ BK_D2,        CNV_VARS + 0x94
.equ CV_ERRLOG,    CNV_VARS + 0x100 # u32 per failed file, the first 32: (kind << 24) | (id << 8)
.equ FAIL_CALLS,   200              # about 10 s of calls: end a failed run when EXIT cannot be read

# =================================================================================
# The entry: called by the loader with `calls (a0)` on every converter call, on the firmware's main task.
CnvEntry:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (CV_CALLS), d0
    inc     d0
    mov     d0, (CV_CALLS)
    mov     (CV_STATE), d0
    cmp     0, d0
    beq     ce_first
    cmp     1, d0
    beq     ce_search
    cmp     2, d0
    beq     ce_global
    cmp     3, d0
    beq     ce_run
    bra     ce_failed

ce_first:                           # a fresh load: everything here is zero
    mov     1, d0
    mov     d0, (CV_STATE)
ce_search:                          # one step of the firmware search per call
    mov     (CV_STEP), d0
    call    FwStep, 0, 0
    cmp     0, d0
    bne     ce_search_fail
    mov     (CV_STEP), d0
    inc     d0
    mov     d0, (CV_STEP)
    mov     FW_STEPS, d1
    call    Progress, 0, 0
    mov     (CV_STEP), d0
    cmp     FW_STEPS, d0
    blt     ce_park
    mov     2, d0                   # all found: the global files next
    mov     d0, (CV_STATE)
    mov     GlobalList, a0
    call    ListStart, 0, 0
    bra     ce_park
ce_search_fail:
    mov     (CV_STEP), d0
    add     0x100, d0
    bra     ce_fail_now

ce_global:                          # one global file per call, then the game task
    call    LoadStep, 0, 0
    cmp     0, d0
    beq     ce_park
    cmp     1, d0
    bne     ce_global_fail
    call    ListEnd, 0, 0
    mov     3, d0
    mov     d0, (CV_STATE)
    call    StartTask, 0, 0
    bra     ce_poll_exit
ce_global_fail:
    mov     0x200, d0
ce_fail_now:
    mov     d0, (CV_FAIL)
    mov     4, d0
    mov     d0, (CV_STATE)
    mov     1, d0
    mov     d0, (CV_TASK_DONE)
    bra     ce_failed

ce_run:
    # A call after we answered 0xFE would be the firmware's "Continue Next?" answered YES: play
    # again. (With the loader it never comes: YES makes the loader load KN7APP.BIN afresh, which
    # starts at ce_first. Kept for a loader that calls the application again without reloading.)
    # NO leaves STYLE CONVERT without calling us.
    mov     (CV_ENDED), d0
    cmp     0, d0
    beq     ce_load
    clr     d0
    mov     d0, (CV_ENDED)
    mov     d0, (CV_QUIT_REQ)
    mov     d0, (CV_TASK_DONE)
    mov     d0, (CV_EXIT_T0)
    mov     d0, (LD_FAILED)
    mov     d0, (CV_REPORT)
    call    StartTask, 0, 0
ce_load:                            # a part the game task waits for: one of its files per call
    mov     (LD_REC), d0
    cmp     0, d0
    bne     ce_load_step
    mov     (LD_REQ), d0
    cmp     0, d0
    beq     ce_poll_exit
    mov     (LD_CUR), d1
    cmp     d1, d0
    beq     ce_poll_exit
    call    PanelIdle, 0, 0         # not while a panel button is down: a list keeps the main task
    cmp     0, d0                   # busy for a file per call, and the button's release must not
    bne     ce_held                 # be the panel event it misses (probes/cnv/README.md)
    clr     d0
    mov     d0, (LD_HELD)
    mov     (LD_REQ), d0
    mov     d0, (LD_PART)           # a new part: forget the old one's files, start its list
    clr     d1
    mov     d1, (LD_CUR)
    call    PartListStart, 0, 0
    bra     ce_poll_exit
ce_held:
    mov     (LD_HELD), d0
    inc     d0
    mov     d0, (LD_HELD)
    cmp     HELD_CALLS, d0
    blt     ce_poll_exit
    clr     d0                      # held too long (or stuck): load anyway
    mov     d0, (LD_HELD)
    mov     (LD_REQ), d0
    mov     d0, (LD_PART)
    clr     d1
    mov     d1, (LD_CUR)
    call    PartListStart, 0, 0
    bra     ce_poll_exit
ce_load_step:
    call    LoadStep, 0, 0
    cmp     0, d0
    beq     ce_poll_exit
    cmp     1, d0
    bne     ce_load_fail
    call    ListEnd, 0, 0
    mov     (LD_PART), d0           # resident: the game task goes on
    mov     d0, (LD_CUR)
    bra     ce_poll_exit
ce_load_fail:
    mov     1, d0                   # the game task stops (EnsurePart) and shows why; the list is
    mov     d0, (LD_FAILED)         # dropped, so the file is not tried again on every call, and
    clr     d0                      # YES starts afresh
    mov     d0, (LD_REC)
    mov     d0, (LD_CUR)

ce_poll_exit:
    # EXIT held for QUIT_HOLD_MS -> quit request (the firmware ignores EXIT while we answer 5)
    mov     (FWV_PANEL), a0
    movbu   (EXIT_OFS, a0), d0
    btst    EXIT_BIT, d0
    beq     ce_exit_up
    mov     (CV_EXIT_T0), d1
    cmp     0, d1
    bne     ce_exit_held
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d1
    or      1, d1
    mov     d1, (CV_EXIT_T0)
    bra     ce_answer
ce_exit_held:
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    sub     d1, d0
    cmp     QUIT_HOLD_MS, d0
    blt     ce_answer
    mov     1, d0
    mov     d0, (CV_QUIT_REQ)
    bra     ce_answer
ce_exit_up:
    clr     d0
    mov     d0, (CV_EXIT_T0)
    bra     ce_answer

ce_failed:                          # the game cannot start: say why; EXIT (or time) ends it
    mov     (FWV_PANEL), a0
    cmp     0, a0
    beq     ce_failed_count         # the panel was not found: no EXIT to read
    movbu   (EXIT_OFS, a0), d0
    btst    EXIT_BIT, d0
    beq     ce_answer
    bra     ce_failed_quit
ce_failed_count:
    mov     (CV_FAILCALLS), d0
    inc     d0
    mov     d0, (CV_FAILCALLS)
    cmp     FAIL_CALLS, d0
    blt     ce_answer
ce_failed_quit:
    mov     1, d0
    mov     d0, (CV_QUIT_REQ)

ce_answer:
    mov     MAILBOX, a0
    mov     (CV_QUIT_REQ), d0
    cmp     0, d0
    beq     ce_park
    mov     (CV_TASK_DONE), d0
    cmp     0, d0
    beq     ce_park                 # wait for the game task to leave first
    mov     (CV_REPORT), d0         # the speed report, once, before the end (perf.s ReportBuild)
    cmp     0, d0
    bne     ce_end
    mov     2, d0
    mov     d0, (CV_REPORT)
    mov     (CV_TASK_ID), d0        # (not when the game never ran)
    cmp     0, d0
    beq     ce_end
    call    ReportWrite, 0, 0
    bra     ce_park                 # one call more: the next one ends
ce_end:
    mov     MAILBOX, a0
    mov     0xFE, d0                # done: hand the instrument back
    movbu   d0, (a0)
    mov     1, d0
    mov     d0, (CV_ENDED)
    bra     ce_ret
ce_park:
    mov     MAILBOX, a0
    mov     5, d0                   # request 5: show our text, call us again
    movbu   d0, (a0)
    call    AnswerText, 0, 0        # a1 = the text
    inc     a0
ce_cpy:
    movbu   (a1), d0
    movbu   d0, (a0)
    inc     a0
    inc     a1
    cmp     0, d0
    bne     ce_cpy
ce_ret:
    ret     [d2,d3,a2,a3], 0x30

# AnswerText -> a1 = the text request 5 shows: what is going on, or why the game cannot start
# (CV_FAIL; "STEP n" names the firmware search step that failed, fwfind.s). Keeps a0. Leaf.
AnswerText:
    mov     (CV_STATE), d0
    cmp     3, d0
    beq     at_play
    cmp     4, d0
    beq     at_fail
    mov     msg_load, a1
    rets
at_play:
    mov     msg_play, a1
    mov     (LD_FAILED), d0
    cmp     0, d0
    beq     at_ret
    mov     msg_file, a1
at_ret:
    rets
at_fail:
    mov     (CV_FAIL), d0
    cmp     0x200, d0
    beq     at_file
    mov     msg_task, a1
    cmp     0x300, d0
    beq     at_ret
    and     15, d0                  # 0x100 + step: "AW: UNKNOWN FIRMWARE, STEP n"
    add     0x30, d0
    movbu   d0, (msg_fw_n)
    mov     msg_fw, a1
    rets
at_file:
    mov     msg_file, a1
    rets

# Create and start the game task, trying slot 10 then 9.
StartTask:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     TASK_ID_FIRST, d2
st_try:
    mov     d2, d0
    mov     game_ctsk, a0
    mov     (FW_CRE), a1
    calls   (a1)
    cmp     0, d0                    # E_OK
    beq     st_start
    add     -1, d2
    cmp     TASK_ID_LAST, d2
    bge     st_try
    mov     1, d0                    # no free slot: nothing runs, so EXIT can end at once
    mov     d0, (CV_TASK_DONE)
    mov     0x300, d0
    mov     d0, (CV_FAIL)
    mov     4, d0
    mov     d0, (CV_STATE)
    bra     st_done
st_start:
    mov     d2, (CV_TASK_ID)
    mov     d2, d0
    clr     d1
    mov     (FW_STA), a1
    calls   (a1)
st_done:
    ret     [d2,d3,a2,a3], 0x30

# =================================================================================
# DLY_TSK(d0 = ms): every yield of the VM and the help screen comes through here (display.s,
# interp.s, help.s call DLY_TSK). If the entry has asked us to quit, end the task here, between
# frames; otherwise it is the firmware's yield.
DLY_TSK:
    mov     (CV_QUIT_REQ), d1
    cmp     0, d1
    bne     dq_quit
    mov     (FW_DLY), a0
    jmp     (a0)                    # tail call: it returns to our caller
dq_quit:
    add     -0x10, sp               # (a frame: it never returns)
    call    PerfWindowEnd, 0, 0     # the figures so far, into the game's (AWPERF.TXT)
    mov     1, d1
    mov     d1, (CV_TASK_DONE)
    mov     (FW_EXD), a0
    calls   (a0)                    # exit and delete this task; does not return
dq_hang:
    bra     dq_hang

# =================================================================================
# The game task's side of part loading (interp.s InitForPart calls these).
#
# EnsurePart(d0 = part id 0x3E80..0x3E89): return once that part's files are resident. Unless they
# already are, ask the converter for them (LD_REQ) and yield until it has loaded them, a file per
# converter call. The VM does not run meanwhile. If a file cannot be loaded, the game stops.
EnsurePart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2
    mov     (LD_CUR), d1
    cmp     d2, d1
    beq     ep_ret
    mov     d2, (LD_REQ)
    mov     PH_LOAD, d0             # not part of any frame (perf.s)
    call    PerfPhase, 0, 0
    mov     d0, (0x10, sp)
ep_wait:
    mov     20, d0
    mov     DLY_TSK, a1
    calls   (a1)
    mov     (LD_FAILED), d0
    cmp     0, d0
    bne     ep_fail
    mov     (LD_CUR), d1
    cmp     d2, d1
    bne     ep_wait
    mov     POSTLOAD_FRAMES, d0     # the firmware repaints its own screen around a load: repaint
    mov     d0, (PF_POSTLOAD)       # everything a few frames on (perf.s), besides the load bar's
    mov     (0x10, sp), d0
    call    PerfPhase, 0, 0
ep_ret:
    ret     [d2,d3,a2,a3], 0x30
ep_fail:
    mov     (GUARD_WHAT), d0        # GuardRange refused the destination: keep that reason
    cmp     0, d0
    bne     ep_stop
    mov     GUARD_FILE, d0          # otherwise the file itself: missing, short or not intact
    mov     (LD_BAD_ID), d1
    call    GuardTrip, 0, 0
ep_stop:
    call    StopGame, 0, 0          # does not return

# BitmapData(d0 = resource id) -> a0 = the bitmap's 32,000 bytes of planes, or 0. A packed bitmap
# (ResPacked != 0) is unpacked into BITMAP_BUF. A bitmap that is not resident stops the game: the
# part lists hold every bitmap each part's bytecode LOADs (tools/aw_extract.py --parts).
# BkUnpack's state is shared with LoadStep; they never run at once: LoadStep runs on the main task
# only while the game task waits in EnsurePart (or before it exists), and a task of priority 3 is
# never preempted by another of the same priority.
BitmapData:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    and     0xff, d0
    mov     d0, d2
    cmp     RES_COUNT, d2
    bcc     bd_missing
    mov     d2, d0
    asl     2, d0
    mov     RES_TAB, a0
    add     d0, a0
    mov     (a0), a0
    cmp     0, a0
    beq     bd_missing
    mov     d2, d0
    asl     2, d0
    mov     ResPacked, a1
    add     d0, a1
    mov     (a1), d0                # packed size, or 0: stored as is
    cmp     0, d0
    beq     bd_ret
    mov     BITMAP_BUF, a1
    mov     PAGE_SIZE / 2, d1       # 32,000 bytes of planes
    call    BkUnpack, 0, 0          # d0 = 0 when intact
    cmp     0, d0
    bne     bd_bad
    mov     BITMAP_BUF, a0
bd_ret:
    ret     [d2,d3,a2,a3], 0x30
bd_missing:
    mov     GUARD_BITMAP, d0
    mov     d2, d1
    call    GuardTrip, 0, 0
    mov     0, a0
    bra     bd_ret
bd_bad:
    mov     GUARD_FILE, d0
    mov     d2, d1
    call    GuardTrip, 0, 0
    mov     0, a0
    bra     bd_ret

# TraceInsn(d1 = opcode): no instruction trace in this build. Leaf.
TraceInsn:
    rets

# =================================================================================
# The converter's side: lists of files (GlobalList, PartList0..8 in awpart_tab.s; 20-byte records,
# awpart.inc LR_*), loaded one record per call.

# ListStart(a0 = list): count its records, start the clock and the bar. Leaf.
ListStart:
    mov     a0, (LD_REC)
    clr     d0
    mov     d0, (LD_DONE)
ls_count:
    mov     (LR_NAME, a0), d1
    cmp     0, d1
    beq     ls_counted
    inc     d0
    add     LR_LEN, a0
    bra     ls_count
ls_counted:
    mov     d0, (LD_TOTAL)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (LD_T0)
    rets

# ListEnd: the list is loaded. Leaf.
ListEnd:
    clr     d0
    mov     d0, (LD_REC)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     (LD_T0), d1
    sub     d1, d0
    mov     d0, (LD_MS)
    mov     (LD_LISTS), d0
    inc     d0
    mov     d0, (LD_LISTS)
    rets

# PartListStart: LD_PART's list; every resource of the part before it is gone (RES_TAB entries
# cleared, but the shared polygons'), as its space is reused.
PartListStart:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     RES_TAB, a0
    mov     RES_COUNT, d1
    clr     d0
pl_clear:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     pl_clear
    mov     VIDEO2_AT, d0
    mov     d0, (RES_TAB + 4 * RES_VIDEO2)
    mov     (LD_PART), d0           # PartLists[part - 0x3E80]
    add     -PART_FIRST, d0
    asl     2, d0
    mov     PartLists, a0
    add     d0, a0
    mov     (a0), a0
    call    ListStart, 0, 0
    ret     [d2,d3,a2,a3], 0x30

# LoadStep: load the record at LD_REC -- check its destination, open its file in the SD card's root
# folder (the loader empties the current folder around each call), read it there in FILE_PIECE
# pieces as the loader reads KN7APP.BIN, close it, unpack it in place if it is packed -- and move on.
# The loader's routines (FW_OPEN.., from its service table) are called as the loader calls them:
# the drive switch to the SD card first and back after (a no-op when they are the SD backends). A
# file that fails (open, short read, not intact) is logged and tried again on the next call, up to
# FILE_TRIES attempts; a destination the guard refuses is not.
#   -> d0 = 0 more to come, 1 the list is done, 2 the file failed for good (LD_BAD_ID)
# The firmware's routines store their arguments in the caller's frame at sp+4..sp+0x10, so nothing
# of ours lives there; they keep d2, d3, a2, a3.
LoadStep:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (LD_REC), a2
    mov     (LR_NAME, a2), d0
    cmp     0, d0
    bne     lst_go
    mov     1, d0
    bra     lst_ret
lst_go:
    movhu   (LR_ID, a2), d0
    mov     d0, (LD_BAD_ID)         # (named if it fails)
    mov     (LR_DEST, a2), a0       # the destination must lie in the game's RAM, clear of the
    mov     (LR_READ, a2), d0       # mailbox page: as long as the file, or as the unpacked
    movbu   (LR_FLAGS, a2), d1      # resource when it is unpacked there (a bitmap kept packed
    btst    LR_INPLACE, d1          # takes only its packed bytes)
    beq     lst_len
    mov     (LR_SIZE, a2), d1
    cmp     d0, d1
    bls     lst_len
    mov     d1, d0
lst_len:
    call    GuardRange, 0, 0
    cmp     0, d0
    bne     lst_guard
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    mov     (LD_REC), a2
    mov     (LR_NAME, a2), a0
    mov     mode_rb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    blt     lst_open_back
    mov     1, d0
    mov     d0, (LD_IN_READ)
    mov     (LD_REC), a2
    mov     (LR_DEST, a2), a3       # a3: where the next piece goes
    mov     (LR_READ, a2), d2       # d2: bytes still to read
    clr     d3                      # d3: bytes read
lst_piece:
    cmp     0, d2
    beq     lst_read_end
    mov     d2, d0
    mov     FILE_PIECE, d1
    cmp     d1, d0
    bls     lst_ask
    mov     d1, d0
lst_ask:
    mov     d0, (0x14, sp)          # asked for
    mov     a3, a0
    mov     (FW_READ), a1
    calls   (a1)                    # d0 = bytes read
    mov     (0x14, sp), d1
    cmp     d1, d0
    bne     lst_read_end            # short, or an error: the count below tells
    add     d0, d3
    add     d0, a3
    sub     d0, d2
    bra     lst_piece
lst_read_end:
    clr     d0
    mov     d0, (LD_IN_READ)
    mov     (FW_CLOSE), a3
    calls   (a3)
    mov     (FW_RESETEXT), a3       # the file layer back, as the firmware expects between calls
    calls   (a3)
    mov     (LD_REC), a2
    mov     (LR_READ, a2), d1
    cmp     d1, d3
    bne     lst_short
    movbu   (LR_FLAGS, a2), d0
    btst    LR_INPLACE, d0
    beq     lst_place
    mov     (LR_DEST, a2), a0       # BkUnpack(a0 = packed, d0 = packed size, a1 = dst, d1 = size)
    mov     a0, a1
    mov     (LR_READ, a2), d0
    mov     (LR_SIZE, a2), d1
    call    BkUnpack, 0, 0
    cmp     0, d0
    bne     lst_crc
lst_place:
    mov     (LD_TRIES), d0          # count a file that needed more than one attempt
    cmp     0, d0
    beq     lst_first
    mov     (LD_RETRIED), d0
    inc     d0
    mov     d0, (LD_RETRIED)
    clr     d0
    mov     d0, (LD_TRIES)
lst_first:
    mov     (LD_REC), a2
    movhu   (LR_ID, a2), d0
    cmp     RES_COUNT, d0
    bcc     lst_next                # not a resource (the font, the strings)
    asl     2, d0
    mov     RES_TAB, a0
    add     d0, a0
    mov     (LR_DEST, a2), d1
    mov     d1, (a0)
lst_next:
    add     LR_LEN, a2
    mov     a2, (LD_REC)
    mov     (LD_DONE), d0
    inc     d0
    mov     d0, (LD_DONE)
    mov     (LD_TOTAL), d1
    call    Progress, 0, 0
    clr     d0
lst_ret:
    ret     [d2,d3,a2,a3], 0x30
lst_guard:
    mov     0x04000000, d0          # kind 4: a destination outside the game's RAM
    bra     lst_fail
lst_open_back:
    mov     (FW_RESETEXT), a3
    calls   (a3)
lst_open_fail:
    mov     0x01000000, d0          # kind 1: the open failed
    bra     lst_fail
lst_short:
    mov     0x03000000, d0          # kind 3: a short read
    bra     lst_fail
lst_crc:
    mov     0x02000000, d0          # kind 2: the unpacked data is not intact
lst_fail:
    mov     (LD_BAD_ID), d1
    asl     8, d1
    or      d1, d0
    mov     (LD_TRIES), d1          # the attempt number in the low byte
    or      d1, d0
    call    LogError, 0, 0
    mov     (GUARD_WHAT), d0        # a refused destination is not tried again
    cmp     0, d0
    bne     lst_give_up
    mov     (LD_TRIES), d0          # a read can fail now and work next time: the same record
    inc     d0                      # again on the next call
    mov     d0, (LD_TRIES)
    cmp     FILE_TRIES, d0
    bcc     lst_give_up
    clr     d0
    bra     lst_ret
lst_give_up:
    clr     d0
    mov     d0, (LD_TRIES)
    mov     2, d0
    bra     lst_ret

# GuardRange(a0 = start, d0 = length) -> d0 = 0 when [start, start + length) lies inside
# [AW_LO, AW_HI) and clear of the mailbox page; else 1, recorded as GUARD_LOAD. Leaf.
GuardRange:
    mov     a0, d1
    cmp     AW_LO, d1
    bcs     grg_bad
    add     d0, d1                  # d1 = end
    bcs     grg_bad
    cmp     AW_HI, d1
    bhi     grg_bad
    cmp     MAILBOX_PAGE, d1        # ends at or before the mailbox page
    bls     grg_ok
    mov     a0, d1
    cmp     MAILBOX_PAGE_END, d1    # or starts at or after its end
    bcc     grg_ok
grg_bad:
    mov     GUARD_LOAD, d0
    mov     a0, d1
    jmp     GuardTrip               # a leaf: it returns to our caller with d0 = 1
grg_ok:
    clr     d0
    rets

# PanelIdle -> d0 = 0 when no panel button is down: the firmware's switch bitmaps (16 CPR segments
# at FWV_PANEL, 16 CPL/CPC segments at FWV_PANEL + 0x30) are all zero; else 1. Leaf.
PanelIdle:
    mov     (FWV_PANEL), a0
    mov     16, d1
pi_seg:
    movbu   (a0), d0
    cmp     0, d0
    bne     pi_held
    movbu   (PANEL_CPL_OFS, a0), d0
    cmp     0, d0
    bne     pi_held
    inc     a0
    add     -1, d1
    bne     pi_seg
    clr     d0
    rets
pi_held:
    mov     1, d0
    rets

# LogError(d0 = (kind << 24) | detail): count it and keep the first 32. Leaf.
LogError:
    mov     (LD_ERRORS), d1
    cmp     32, d1
    bcc     le_count
    asl     2, d1
    mov     CV_ERRLOG, a0
    add     d1, a0
    mov     d0, (a0)
le_count:
    mov     (LD_ERRORS), d1
    inc     d1
    mov     d1, (LD_ERRORS)
    rets

# Progress(d0 = done, d1 = total): a white bar along the LCD's bottom rows, 600 * done / total
# pixels (the black border; the game's next blit repaints it: PF_DAMAGE).
Progress:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (PF_DAMAGE), d2
    or      PFD_BAR, d2
    mov     d2, (PF_DAMAGE)
    cmp     0, d1
    beq     pg_done
    mov     d1, d2
    mov     600, d1
    mulu    d0, d1
    clr     d3
    mov     d3, mdr
    divu    d2, d1
    cmp     0, d1
    beq     pg_done
    mov     FB + 228*FB_STRIDE + 20*2, a1
    mov     6, d3                   # rows
pg_row:
    mov     a1, a0
    mov     d1, d2
pg_px:
    mov     0xFFFF, d0
    movhu   d0, (a0)
    add     2, a0
    add     -1, d2
    bne     pg_px
    add     FB_STRIDE, a1
    add     -1, d3
    bne     pg_row
pg_done:
    ret     [d2,d3,a2,a3], 0x20

# ReportWrite: the speed figures (perf.s ReportBuild) into a new file in the SD card's root folder,
# AWPERF0.TXT .. AWPERF9.TXT, the first of those names that does not exist yet (it never writes over a
# file: each one is tried with an "rb" open first, which fails for a missing file, as a missing game
# file's does), the way the ROM dumper writes its files on the owner's unit (technics-roms-disasm
# cnv_romdump: DUMPLIST.TXT): the drive switch to the card, open "wb" (an 8.3 name, relative to C:\
# around every converter call), one write, close, the drive switch back. Only when the loader found a
# write routine (FW_WRITE); on the main task, once per quit, after the game task has ended. When all
# ten names exist it writes nothing. CV_REPORT, CV_REPORT_N and CV_REPORT_K say how it went.
ReportWrite:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     (FW_WRITE), d0
    cmp     0, d0
    beq     rw_ret
    call    ReportBuild, 0, 0       # d0 = its length, in REPORT_BUF
    mov     d0, d2
    cmp     REPORT_MAX, d0
    bhi     rw_ret
    mov     1, d0                   # the file layer to the SD card
    mov     (FW_SETEXT), a3
    calls   (a3)
    clr     d3                      # AWPERFk.TXT, k = d3
rw_name:
    mov     d3, (CV_REPORT_K)
    cmp     10, d3
    bcc     rw_back                 # all ten exist: nothing written
    mov     report_name, a1     # the name, k in it
    mov     CV_NAME, a0
    call    StrPut, 0, 0
    clr     d0
    movbu   d0, (a0)
    mov     d3, d0
    add     0x30, d0
    movbu   d0, (CV_NAME + 6)
    mov     CV_NAME, a0             # does it exist?
    mov     mode_rb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    cmp     0, d0
    blt     rw_new
    mov     (FW_CLOSE), a3          # it does: the next name
    calls   (a3)
    inc     d3
    bra     rw_name
rw_new:
    mov     CV_NAME, a0
    mov     mode_wb, a1
    mov     (FW_OPEN), a3
    calls   (a3)
    exth    d0
    mov     d0, (CV_REPORT_N)
    cmp     0, d0
    blt     rw_back
    mov     REPORT_BUF, a0
    mov     d2, d0
    mov     (FW_WRITE), a3
    calls   (a3)                    # d0 = bytes written
    mov     d0, (CV_REPORT_N)
    mov     d0, d3
    mov     (FW_CLOSE), a3
    calls   (a3)
    cmp     d2, d3
    bne     rw_back
    mov     1, d0
    mov     d0, (CV_REPORT)
rw_back:
    mov     (FW_RESETEXT), a3       # the file layer back, as the firmware expects between calls
    calls   (a3)
rw_ret:
    ret     [d2,d3,a2,a3], 0x30

# =================================================================================
# BkUnpack(a0 = packed data, d0 = packed size, a1 = destination, d1 = unpacked size) -> d0 = crc
# (0 = intact). ByteKiller, as tools/aw_extract.py unpack(): 32-bit big-endian words are read from
# the END of the packed data (unpacked size, crc, then the first bit-buffer word); the output is
# written backwards from its last byte. a2 = next word to read, d3 = bit buffer, a3 = output. Works
# in place (packed data at the start of the destination), as the original engine unpacks: the
# build checks every resource that is unpacked so (aw_extract.py unpack_in_place).
BkUnpack:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d1, (BK_LEFT)
    mov     a1, a3
    add     d1, a3
    add     -1, a3                  # last output byte
    add     d0, a0
    add     -8, a0
    mov     a0, a2
    call    ReadBE, 0, 0            # d3 = crc word
    mov     d3, (BK_CRC)
    add     -4, a2
    call    ReadBE, 0, 0            # d3 = first bit-buffer word
    add     -4, a2
    mov     (BK_CRC), d0
    xor     d3, d0
    mov     d0, (BK_CRC)
bk_loop:
    mov     (BK_LEFT), d0
    cmp     0, d0
    ble     bk_done
    mov     1, d0
    call    GetBits, 0, 0
    cmp     0, d0
    bne     bk_1
    mov     1, d0
    call    GetBits, 0, 0
    cmp     0, d0
    bne     bk_01
    mov     3, d0                   # 00: literal run of 1..8 bytes
    call    GetBits, 0, 0
    add     1, d0
    mov     d0, d1
    bra     bk_literal
bk_01:                              # 01: copy 2 bytes from an 8-bit offset
    mov     8, d0
    call    GetBits, 0, 0
    mov     d0, d2
    mov     2, d1
    bra     bk_copy
bk_1:
    mov     2, d0
    call    GetBits, 0, 0
    cmp     3, d0
    bne     bk_1x
    mov     8, d0                   # 11: literal run of 9..264 bytes
    call    GetBits, 0, 0
    add     9, d0
    mov     d0, d1
    bra     bk_literal
bk_1x:
    cmp     2, d0
    bne     bk_1y
    mov     8, d0                   # 10: copy 1..256 bytes from a 12-bit offset
    call    GetBits, 0, 0
    add     1, d0
    mov     d0, d1
    mov     12, d0
    call    GetBits, 0, 0
    mov     d0, d2
    bra     bk_copy
bk_1y:
    cmp     1, d0
    bne     bk_1z
    mov     10, d0                  # 01 after 1: copy 4 bytes from a 10-bit offset
    call    GetBits, 0, 0
    mov     d0, d2
    mov     4, d1
    bra     bk_copy
bk_1z:
    mov     9, d0                   # 00 after 1: copy 3 bytes from a 9-bit offset
    call    GetBits, 0, 0
    mov     d0, d2
    mov     3, d1
bk_copy:                            # d1 bytes from d2 above the output pointer
    call    Clamp, 0, 0
bk_copy_b:
    cmp     0, d1
    beq     bk_loop
    mov     a3, a0
    add     d2, a0
    movbu   (a0), d0
    movbu   d0, (a3)
    add     -1, a3
    add     -1, d1
    bra     bk_copy_b
bk_literal:                         # d1 bytes, 8 bits each
    call    Clamp, 0, 0
bk_lit_b:
    cmp     0, d1
    beq     bk_loop
    mov     8, d0
    call    GetBits, 0, 0
    movbu   d0, (a3)
    add     -1, a3
    add     -1, d1
    bra     bk_lit_b
bk_done:
    mov     (BK_CRC), d0
    cmp     0, d0                   # also fail if the stream ran past the expected size
    bne     bk_ret
    mov     (BK_LEFT), d0
bk_ret:
    ret     [d2,d3,a2,a3], 0x20

# Clamp: BK_LEFT -= d1, never writing past the start of the output (corrupt data). Leaf.
Clamp:
    mov     (BK_LEFT), d0
    cmp     d1, d0
    bcc     cp_ok
    mov     d0, d1                  # only what is left
cp_ok:
    sub     d1, d0
    mov     d0, (BK_LEFT)
    rets

# ReadBE: d3 = the big-endian 32-bit word at a2. Leaf; uses d0.
ReadBE:
    movbu   (a2), d3
    asl     8, d3
    movbu   (1, a2), d0
    or      d0, d3
    asl     8, d3
    movbu   (2, a2), d0
    or      d0, d3
    asl     8, d3
    movbu   (3, a2), d0
    or      d0, d3
    rets

# GetBits(d0 = n): d0 = the next n bits, first bit most significant. Keeps d1, d2 (saved in RAM);
# advances the bit buffer d3 and the word pointer a2, folding each new word into BK_CRC.
GetBits:
    mov     d1, (BK_D1)
    mov     d2, (BK_D2)
    mov     d0, d2                  # bits still to take
    clr     d1                      # value
gb_bit:
    mov     d3, d0
    and     1, d0
    lsr     1, d3
    cmp     0, d3
    bne     gb_have
    movbu   (a2), d3                # refill: d3 = the next big-endian word (inline: a leaf
    asl     8, d3                   # entered with `call x, 0, 0` must not call -- the nested
    movbu   (1, a2), d0             # call would overwrite its return address at (sp))
    or      d0, d3
    asl     8, d3
    movbu   (2, a2), d0
    or      d0, d3
    asl     8, d3
    movbu   (3, a2), d0
    or      d0, d3
    add     -4, a2
    mov     (BK_CRC), d0
    xor     d3, d0
    mov     d0, (BK_CRC)
    mov     d3, d0
    and     1, d0
    lsr     1, d3
    or      0x80000000, d3
gb_have:
    asl     1, d1
    or      d0, d1
    add     -1, d2
    bne     gb_bit
    mov     d1, d0
    mov     (BK_D1), d1
    mov     (BK_D2), d2
    rets

# =================================================================================
.include "display.s"
    .align  2
mode_rb:
    .asciz  "rb"
mode_wb:
    .asciz  "wb"
report_name:
    .asciz  "AWPERF0.TXT"           # ReportWrite's names: the digit is k
msg_play:
    .asciz  "HOLD EXIT TO QUIT"
msg_load:
    .asciz  "LOADING ANOTHER WORLD"
msg_file:
    .asciz  "AW: A GAME FILE IS MISSING OR BAD"
msg_task:
    .asciz  "AW: NO TASK SLOT FREE"
msg_fw:
    .ascii  "AW: UNKNOWN FIRMWARE, STEP "
msg_fw_n:
    .asciz  "0"
    .align  4
.include "fwfind.s"
.include "vm.s"
.include "interp.s"
.include "help.s"
.include "perf.s"
.include "awpart_tab.s"             # generated: PartLists, GlobalList, ResPacked, ResType, file names
cnv_image_end:                      # tools/cnv_layout.py: must lie below IMAGE_END_MAX
