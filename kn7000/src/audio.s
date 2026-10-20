# (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
# Licensed under the terms of the GNU General Public License v3 or later
#
# audio.s -- Another World's sound effects and music on the KN7000's own tone generator (KN7APP.BIN
# build only; main.s, the SP7001 build, takes audio_stub.s). No sample is output: the game becomes a
# MIDI source, and the firmware plays the notes by its normal path.
#
# HOW: as if the bytes came in on MIDI IN 1. The firmware's MIDI 1 receive ISR (941 0x484B1E86)
# reads each byte from the serial port and enqueues it into a byte ring in work RAM (lib 0x4C0249C5
# -> the enqueue 0x4C024CBC: byte at wr, wr+1 wrapping at last, free-1; it refuses a byte when free
# is 0); a firmware task dequeues the bytes and parses them as MIDI, and the MIDI receive parts play
# the tone generator. The game writes whole messages into that ring the same way (MidiMsg), with
# interrupts masked (PSW IE off) so the ISR cannot enqueue in the middle and no task switch can
# happen. It never touches the read pointer: the firmware stays the only consumer. The ring's header
# is fwfind.s's FWV_MIDIIN1, the one the game already reads for MIDI IN input (interp.s NotePoll).
# In MAME (program 893), bytes put there while the game runs parked on STYLE CONVERT are consumed and
# sound: probes/cnv/README.md, "Sound".
#
# WHERE: the KN7000's MIDI receive routing, as initialised (owner's manual p.190): channels 1-3 are
# RIGHT 1, RIGHT 2 and LEFT (the panel's voices), channels 4-16 are PART 4-16, the parts "for SMF
# playback or MIDI receive". The game uses only PART 4-14, never the panel's parts:
#   channels 4-7    the sound effects, one per AW mixer channel 0-3 (program per sound)
#   channel 10      the drums (music and sound effects): GM2 drum set (bank 120/0, program 0)
#   channels 11-14  the music, one per module channel 0-3 (program per instrument)
# Melodic programs are GM, sent as GM2 bank 121/0 + program change (in MAME, program 893: program
# 80 turned PART 4 into a square wave, 48 into strings, with or without the bank select).
#
# WHAT: tools/aw_sound_map.py gives every sound resource a GM program and the note it sounds at
# 8363 Hz, or a GM drum key (SndTab: the file AWSND.AW, made at build time, loaded with the font). PLAY_SOUND (0x18) plays it at its frequency index
# (semitones) and volume (velocity), for the sample's length at that rate, or held while it loops;
# volume 0 stops the channel. PLAY_MUSIC (0x1A) starts, retimes or stops the module player (rawgl
# SfxPlayer): every row, each of the four channels may play a note (an Amiga period: the nearest
# semitone), stop, change volume, or set the sync mark var 0xF4, which the intro reads to time its
# scenes. The marks are written as the original does, whether the sound is on or off.
#
# WHEN: AudioPoll runs at every thread switch (interp.s NextThread) and between short slices of
# every yield (cnv_main.s DLY_TSK): it plays the rows that are due (the kernel's 1 ms counter) and
# ends the notes whose time is up. A part switch and LOAD 0 stop everything, as rawgl's restartAt and
# stopAll do; the help screen silences and freezes the music; quitting sends all notes off and all
# sound off on every channel the game uses. PART SELECT RIGHT 2 turns the sound off and on.

.equ AU_ENABLED,   AUDIO_VARS + 0x00    # u32: 1 = send MIDI (PART SELECT RIGHT 2 toggles)
.equ AU_PAUSED,    AUDIO_VARS + 0x04    # u32: 1 = the help screen is up: the music is frozen
.equ AU_BTN,       AUDIO_VARS + 0x08    # u32: the toggle button as it was at the last poll
.equ AU_MOD,       AUDIO_VARS + 0x0C    # u32: the module playing (0 = none)
.equ AU_ORDER,     AUDIO_VARS + 0x10    # u32: its order index
.equ AU_NORD,      AUDIO_VARS + 0x14    # u32: orders in the module
.equ AU_POS,       AUDIO_VARS + 0x18    # u32: the row's offset in the pattern, 0..1008 in 16s
.equ AU_NEXT,      AUDIO_VARS + 0x1C    # u32: the kernel ms counter when the next row is due
.equ AU_FRAC,      AUDIO_VARS + 0x20    # u32: ... and 1/256 ms
.equ AU_PER,       AUDIO_VARS + 0x24    # u32: a row's time, 1/256 ms
.equ AU_DROPS,     AUDIO_VARS + 0x28    # u32: MIDI bytes dropped because the ring was full
.equ AU_SENT,      AUDIO_VARS + 0x2C    # u32: MIDI messages put into the ring
.equ AU_ROWS,      AUDIO_VARS + 0x30    # u32: module rows played
.equ AU_SOUNDS,    AUDIO_VARS + 0x34    # u32: PLAY_SOUNDs that sounded
.equ AU_MARK,      AUDIO_VARS + 0x38    # u32: the last sync mark written to var 0xF4
.equ AU_READY,     AUDIO_VARS + 0x3C    # u32: 1 once AudioInit has run (the task's first 2.5 s yield polls)
.equ AU_PROG,      AUDIO_VARS + 0x40    # 16 x u8: the program last sent per MIDI channel (0xFF = none)
.equ AU_SLOTS,     AUDIO_VARS + 0x80    # AU_NSLOTS x SL_LEN: the notes sounding
.equ SL_CH,        0                    #   u8: MIDI channel 0-15 (0xFF = no note)
.equ SL_NOTE,      1                    #   u8: the note
.equ SL_OFF,       4                    #   u32: the ms counter when it ends (0 = held until stopped)
.equ SL_LEN,       8
.equ AU_NSLOTS,    8                    # 0-3: the module's channels, 4-7: PLAY_SOUND's channels
.equ AU_SLOT_SFX,  4
.equ SndTab,       SND_TAB              # AWSND.AW, loaded with the font (tools/aw_sound_map.py)
.equ AU_CH_SFX,    3                    # MIDI channel 4 (0-based 3): AW mixer channel 0's effects
.equ AU_CH_DRUM,   9                    # MIDI channel 10
.equ AU_CH_MUS,    10                   # MIDI channel 11: module channel 0
.equ AU_VOLUME,    100                  # CC 7 on every channel the game uses
.equ AU_DRUM_MS,   150                  # a drum note's note-off after this
.equ AU_MIN_MS,    30                   # the shortest note
.equ AU_MAX_ROWS,  4                    # rows played at most per poll (then the player resyncs)
.equ AU_BTN_OFS,   2                    # PART SELECT RIGHT 2 (CPR_SEG2 SW1; probes/cnv/README.md)
.equ AU_BTN_BIT,   0x02
.equ AU_MARK_VAR,  0xF4                 # the music's sync mark (rawgl VAR_MUSIC_SYNC)

# ================================================================================
# MidiMsg(d0 = status | data1 << 8 | data2 << 16): one channel message (program change and channel
# pressure take one data byte, the others two) into the MIDI IN 1 receive ring, whole or not at all
# (not when the sound is off, nor when the ring lacks room: AU_DROPS counts those bytes).
MidiMsg:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (AU_ENABLED), d1
    cmp     0, d1
    beq     mm_ret
    mov     (FWV_MIDIIN1), a0       # the ring's header
    cmp     0, a0
    beq     mm_ret
    mov     3, d2                   # d2 = bytes
    mov     d0, d1
    and     0xE0, d1
    cmp     0xC0, d1                # 0xCn program change, 0xDn channel pressure
    bne     mm_len
    mov     2, d2
mm_len:
    mov     psw, d1                 # interrupts off, as in the ISR's own enqueue
    mov     d1, (0, sp)
    and     0xF7FF, psw
    nop
    nop
    movhu   (QH_FREE, a0), d1
    cmp     d2, d1
    bcs     mm_full                 # free < bytes
    sub     d2, d1
    movhu   d1, (QH_FREE, a0)
    mov     (QH_WR, a0), a1         # a1 = where the next byte goes
    mov     (QH_LAST, a0), d3
mm_byte:
    movbu   d0, (a1)
    lsr     8, d0
    mov     a1, d1
    cmp     d3, d1
    bne     mm_inc
    mov     (QH_START, a0), a1      # past the last byte: wrap
    bra     mm_next
mm_inc:
    inc     a1
mm_next:
    add     -1, d2
    bne     mm_byte
    mov     a1, (QH_WR, a0)         # published last: the consumer stops at wr
    mov     (AU_SENT), d1
    inc     d1
    mov     d1, (AU_SENT)
    bra     mm_unmask
mm_full:
    mov     (AU_DROPS), d1
    add     d2, d1
    mov     d1, (AU_DROPS)
mm_unmask:
    mov     (0, sp), d1
    mov     d1, psw
    nop
mm_ret:
    ret     [d2,d3,a2,a3], 0x20

# MidiCC(d0 = channel, d1 = controller, a0 = value)
MidiCC:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    or      0xB0, d0
    asl     8, d1
    or      d1, d0
    mov     a0, d1
    asl     16, d1
    or      d1, d0
    call    MidiMsg, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# SetProg(d0 = channel, d1 = program): bank select and program change, unless that channel has it.
# Channel 10 takes the GM2 drum bank (120), the others the GM2 melodic bank (121).
SetProg:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     d1, d3
    mov     AU_PROG, a2
    add     d2, a2
    movbu   (a2), d0
    cmp     d3, d0
    beq     spg_ret
    movbu   d3, (a2)
    mov     d2, d0                  # CC 0: bank MSB
    clr     d1
    mov     121, a0
    cmp     AU_CH_DRUM, d2
    bne     spg_msb
    mov     120, a0
spg_msb:
    call    MidiCC, 0, 0
    mov     d2, d0                  # CC 32: bank LSB 0
    mov     32, d1
    mov     0, a0
    call    MidiCC, 0, 0
    mov     d3, d0                  # program change
    asl     8, d0
    or      0xC0, d0
    or      d2, d0
    call    MidiMsg, 0, 0
spg_ret:
    ret     [d2,d3,a2,a3], 0x20

# SlotOff(d0 = slot): end the slot's note, if it has one.
SlotOff:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    asl     3, d0
    mov     AU_SLOTS, a2
    add     d0, a2
    movbu   (SL_CH, a2), d0
    cmp     0xFF, d0
    beq     so_ret
    or      0x80, d0                # note-off, release velocity 64
    movbu   (SL_NOTE, a2), d1
    asl     8, d1
    or      d1, d0
    mov     0x400000, d1
    or      d1, d0
    call    MidiMsg, 0, 0
    mov     0xFF, d0
    movbu   d0, (SL_CH, a2)
    clr     d0
    mov     d0, (SL_OFF, a2)
so_ret:
    ret     [d2,d3,a2,a3], 0x20

# SlotOn(d0 = slot, d1 = channel | note << 8 | velocity << 16, a0 = ms it lasts, 0 = held): the
# slot's note ends, this one starts.
SlotOn:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d2
    mov     d1, d3
    mov     a0, (4, sp)             # ((0, sp) is where a call puts its return address)
    call    SlotOff, 0, 0           # d0 = slot
    mov     d3, d0
    or      0x90, d0                # note-on
    call    MidiMsg, 0, 0
    mov     d2, d0
    asl     3, d0
    mov     AU_SLOTS, a2
    add     d0, a2
    movbu   d3, (SL_CH, a2)
    mov     d3, d0
    lsr     8, d0
    movbu   d0, (SL_NOTE, a2)
    mov     (4, sp), d0
    cmp     0, d0
    beq     son_held
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d1
    add     d1, d0
    cmp     0, d0
    bne     son_held
    inc     d0                      # (0 means held)
son_held:
    mov     d0, (SL_OFF, a2)
    ret     [d2,d3,a2,a3], 0x20

# AllOff(d0 = 1: also all sound off and reset controllers): end every slot's note, then all notes
# off on every channel the game uses.
AllOff:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     d0, d3
    mov     (AU_READY), d0          # nothing set up yet: nothing to end
    cmp     0, d0
    beq     ao_ret
    clr     d2
ao_slot:
    mov     d2, d0
    call    SlotOff, 0, 0
    inc     d2
    cmp     AU_NSLOTS, d2
    bne     ao_slot
    mov     au_channels, a2
ao_ch:
    movbu   (a2), d2
    cmp     0xFF, d2
    beq     ao_ret
    mov     d2, d0
    mov     123, d1                 # all notes off
    mov     0, a0
    call    MidiCC, 0, 0
    cmp     0, d3
    beq     ao_next
    mov     d2, d0
    mov     120, d1                 # all sound off
    mov     0, a0
    call    MidiCC, 0, 0
    mov     d2, d0
    mov     121, d1                 # reset all controllers
    mov     0, a0
    call    MidiCC, 0, 0
ao_next:
    inc     a2
    bra     ao_ch
ao_ret:
    ret     [d2,d3,a2,a3], 0x20

# AudioSetup: the channels the game uses: controllers reset, volume, no program known (the next
# note sends its own), the drum set on channel 10.
AudioSetup:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     AU_PROG, a0
    mov     16, d1
    mov     0xFF, d0
as_prog:
    movbu   d0, (a0)
    inc     a0
    add     -1, d1
    bne     as_prog
    mov     au_channels, a2
as_ch:
    movbu   (a2), d2
    cmp     0xFF, d2
    beq     as_drums
    mov     d2, d0
    mov     121, d1                 # reset all controllers
    mov     0, a0
    call    MidiCC, 0, 0
    mov     d2, d0
    mov     7, d1                   # volume
    mov     AU_VOLUME, a0
    call    MidiCC, 0, 0
    inc     a2
    bra     as_ch
as_drums:
    mov     AU_CH_DRUM, d0
    clr     d1
    call    SetProg, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# AudioInit: a new game (GameReset). Sound on, nothing playing, the channels set up.
AudioInit:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     AUDIO_VARS, a0
    mov     0x200 / 4, d1
    clr     d0
ai_zero:
    mov     d0, (a0)
    add     4, a0
    add     -1, d1
    bne     ai_zero
    mov     AU_SLOTS, a0
    mov     AU_NSLOTS, d1
    mov     0xFF, d0
ai_slot:
    movbu   d0, (SL_CH, a0)
    add     SL_LEN, a0
    add     -1, d1
    bne     ai_slot
    mov     1, d0
    mov     d0, (AU_ENABLED)
    mov     d0, (AU_READY)
    mov     (FWV_PANEL), a0         # the toggle as it is now: a button held at the start is no press
    movbu   (AU_BTN_OFS, a0), d0
    and     AU_BTN_BIT, d0
    mov     d0, (AU_BTN)
    call    AudioSetup, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# AudioStopAll: no module, no note (a part switch, LOAD 0, the stop screen).
AudioStopAll:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (AU_MOD)
    call    AllOff, 0, 0            # d0 = 0: notes off only
    ret     [d2,d3,a2,a3], 0x20

# AudioEnd: the game is quitting: nothing may hang when the menu comes back.
AudioEnd:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (AU_MOD)
    mov     1, d0
    call    AllOff, 0, 0
    ret     [d2,d3,a2,a3], 0x20

# AudioPause / AudioResume: the help screen. Silence, freeze the music; on the way out the music
# goes on from the row it was at.
AudioPause:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     1, d0
    mov     d0, (AU_PAUSED)
    call    AllOff, 0, 0            # d0 = 1: and all sound off
    ret     [d2,d3,a2,a3], 0x20

AudioResume:
    clr     d0
    mov     d0, (AU_PAUSED)
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d0
    mov     d0, (AU_NEXT)
    clr     d0
    mov     d0, (AU_FRAC)
    rets

# AudioSound(a0 = PLAY_SOUND's operands: resource u16 BE, frequency index, volume, channel)
AudioSound:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    movbu   (4, a0), d2
    and     3, d2
    add     AU_SLOT_SFX, d2         # d2 = slot
    movbu   (3, a0), d0
    cmp     0, d0
    beq     as_stop                 # volume 0: stop the channel
    cmp     63, d0
    bls     as_vol
    mov     63, d0
as_vol:
    asl     1, d0
    inc     d0
    mov     d0, (0x10, sp)          # velocity
    movbu   (2, a0), d0
    cmp     39, d0
    bls     as_freq
    mov     39, d0
as_freq:
    mov     d0, (0x14, sp)          # frequency index
    movbu   (a0), d0
    movbu   (1, a0), d1
    asl     8, d0
    or      d1, d0
    cmp     RES_COUNT, d0
    bcc     as_ret
    asl     2, d0
    mov     SndTab, a2
    add     d0, a2                  # a2 = the sound's entry
    movbu   (a2), d3                # program, 0x80 drum, 0xFF none
    cmp     0xFF, d3
    beq     as_stop
    cmp     0x80, d3
    bne     as_melodic
    movbu   (1, a2), d1             # drum: its key on channel 10
    asl     8, d1
    or      AU_CH_DRUM, d1
    mov     AU_DRUM_MS, a0
    bra     as_play
as_melodic:
    mov     d2, d0                  # the slot's channel: 4..7
    add     AU_CH_SFX - AU_SLOT_SFX, d0
    mov     d0, (0x18, sp)
    mov     d3, d1
    call    SetProg, 0, 0
    movbu   (1, a2), d0             # note = the note at 8363 Hz + f - 16
    mov     (0x14, sp), d1
    add     d1, d0
    add     -16, d0
    call    ClampNote, 0, 0
    asl     8, d0
    mov     (0x18, sp), d1
    or      d0, d1                  # d1 = channel | note << 8
    mov     d1, (0x18, sp)
    movhu   (2, a2), d0             # ms at 8363 Hz (0xFFFF: loops, held)
    cmp     0xFFFF, d0
    beq     as_held
    mov     8363, d1                # at this frequency: ms * 8363 / rate
    mulu    d1, d0
    mov     (0x14, sp), d1
    asl     1, d1
    mov     au_freq, a1
    add     d1, a1
    movhu   (a1), d1
    clr     d3
    mov     d3, mdr
    divu    d1, d0
    cmp     AU_MIN_MS, d0
    bcc     as_dur
    mov     AU_MIN_MS, d0
as_dur:
    mov     d0, a0
    bra     as_ms
as_held:
    mov     0, a0
as_ms:
    mov     (0x18, sp), d1
as_play:
    mov     (0x10, sp), d0          # velocity
    asl     16, d0
    or      d0, d1
    mov     d2, d0
    call    SlotOn, 0, 0
    mov     (AU_SOUNDS), d0
    inc     d0
    mov     d0, (AU_SOUNDS)
    bra     as_ret
as_stop:
    mov     d2, d0
    call    SlotOff, 0, 0
as_ret:
    ret     [d2,d3,a2,a3], 0x30

# ClampNote(d0 = note, signed) -> d0 in 0..127. Leaf.
ClampNote:
    cmp     0, d0
    bge     cn_lo
    clr     d0
cn_lo:
    cmp     127, d0
    ble     cn_hi
    mov     127, d0
cn_hi:
    rets

# AudioMusic(a0 = PLAY_MUSIC's operands: resource u16 BE, delay u16 BE, order u8): a resource
# starts its module at that order (with the module's own delay when 0); resource 0 with a delay
# retimes the module playing; both 0 stop it (rawgl snd_playMusic).
AudioMusic:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     a0, a2
    movbu   (a2), d0
    movbu   (1, a2), d1
    asl     8, d0
    or      d1, d0                  # d0 = resource
    movbu   (2, a2), d2
    movbu   (3, a2), d1
    asl     8, d2
    or      d1, d2                  # d2 = delay
    cmp     0, d0
    bne     amu_start
    cmp     0, d2
    beq     amu_stop
    mov     d2, d0
    call    MusicPeriod, 0, 0
    bra     amu_ret
amu_stop:
    call    MusicStop, 0, 0
    bra     amu_ret
amu_start:
    mov     d0, d3
    call    MusicStop, 0, 0
    cmp     RES_COUNT, d3
    bcc     amu_ret
    mov     d3, d0
    call    ResPtr, 0, 0            # a0 = the module, if the part's list loaded it
    cmp     0, a0
    beq     amu_ret
    movbu   (4, a2), d0
    mov     d0, (AU_ORDER)
    movbu   (0x3E, a0), d0
    movbu   (0x3F, a0), d1
    asl     8, d0
    or      d1, d0
    mov     d0, (AU_NORD)
    clr     d0
    mov     d0, (AU_POS)
    mov     d0, (AU_FRAC)
    cmp     0, d2
    bne     amu_delay
    movbu   (a0), d2                # the module's own delay
    movbu   (1, a0), d1
    asl     8, d2
    or      d1, d2
amu_delay:
    mov     a0, (AU_MOD)
    mov     d2, d0
    call    MusicPeriod, 0, 0
    mov     (FWV_KERNEL_MS), a0     # the first row now
    mov     (a0), d0
    mov     d0, (AU_NEXT)
amu_ret:
    ret     [d2,d3,a2,a3], 0x20

# MusicPeriod(d0 = delay): a row lasts delay * 60000 / 7159092 ms (rawgl SfxPlayer: the Paula
# clock); AU_PER in 1/256 ms = delay * 2146 / 1000. Leaf.
MusicPeriod:
    and     0xFFFF, d0
    mov     2146, d1
    mulu    d1, d0
    clr     d1
    mov     d1, mdr
    mov     1000, d1
    divu    d1, d0
    mov     d0, (AU_PER)
    rets

# MusicStop: no module; its notes end.
MusicStop:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    clr     d0
    mov     d0, (AU_MOD)
    clr     d2
mst_slot:
    mov     d2, d0
    call    SlotOff, 0, 0
    inc     d2
    cmp     AU_SLOT_SFX, d2
    bne     mst_slot
    ret     [d2,d3,a2,a3], 0x20

# MusicRow: the four channels' events of the current row, then the next row (rawgl handleEvents).
MusicRow:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (AU_ROWS), d0
    inc     d0
    mov     d0, (AU_ROWS)
    mov     (AU_MOD), a3
    mov     (AU_ORDER), d0
    cmp     0x80, d0
    bcc     mr_end
    mov     a3, a0
    add     d0, a0
    movbu   (0x40, a0), d0          # the pattern
    asl     10, d0                  # 1024 bytes each
    mov     (AU_POS), d1
    add     d1, d0
    add     0xC0, d0
    mov     a3, a2
    add     d0, a2                  # a2 = this row's four events
    clr     d2
mr_ch:
    mov     d2, d0
    mov     a2, a0
    call    MusicEvent, 0, 0
    mov     (AU_MOD), d0            # (a mark could not stop it, but stay safe)
    cmp     0, d0
    beq     mr_ret
    add     4, a2
    inc     d2
    cmp     4, d2
    bne     mr_ch
    mov     (AU_POS), d0
    add     16, d0
    cmp     1024, d0
    bcs     mr_pos
    mov     (AU_ORDER), d1
    inc     d1
    mov     d1, (AU_ORDER)
    mov     (AU_NORD), d0
    cmp     d0, d1
    bcc     mr_end                  # past the last order: the module ends
    clr     d0
mr_pos:
    mov     d0, (AU_POS)
    bra     mr_ret
mr_end:
    call    MusicStop, 0, 0
mr_ret:
    ret     [d2,d3,a2,a3], 0x20

# MusicEvent(d0 = channel 0..3, a0 = its event: u16 note (an Amiga period, or 0xFFFD the sync mark,
# 0xFFFE stop), u16 instrument << 12 | effect << 8 | value) -- rawgl SfxPlayer::handlePattern.
MusicEvent:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x20, sp
    mov     d0, d2                  # d2 = channel = slot
    movbu   (a0), d3
    movbu   (1, a0), d1
    asl     8, d3
    or      d1, d3                  # d3 = note
    movbu   (2, a0), d0
    movbu   (3, a0), d1
    asl     8, d0
    or      d1, d0
    mov     d0, (0x10, sp)          # (0x10) = instrument / effect / value
    cmp     0xFFFD, d3
    bne     me_notmark
    mov     d0, d1                  # the sync mark: var 0xF4 = value
    mov     d1, (AU_MARK)
    mov     AU_MARK_VAR, d0
    call    WriteVar, 0, 0
    bra     me_ret
me_notmark:
    cmp     0xFFFE, d3
    bne     me_notstop
    mov     d2, d0
    call    SlotOff, 0, 0
    bra     me_ret
me_notstop:
    lsr     12, d0                  # instrument 1..15 (0: none)
    cmp     0, d0
    beq     me_ret
    add     -1, d0
    asl     2, d0
    mov     (AU_MOD), a2
    add     d0, a2                  # instrument at module + 2 + 4 * (n - 1)
    movbu   (2, a2), d0
    movbu   (3, a2), d1
    asl     8, d0
    or      d1, d0                  # resource
    cmp     0, d0
    beq     me_ret
    cmp     RES_COUNT, d0
    bcc     me_ret
    asl     2, d0
    mov     SndTab, a3
    add     d0, a3                  # a3 = its SndTab entry
    movbu   (4, a2), d0
    movbu   (5, a2), d1
    asl     8, d0
    or      d1, d0                  # volume
    mov     (0x10, sp), d1
    lsr     8, d1
    and     15, d1                  # effect: 5 volume up, 6 volume down
    cmp     5, d1
    bne     me_not5
    mov     (0x10, sp), d1          # volume up
    and     0xFF, d1
    add     d1, d0
    cmp     63, d0
    ble     me_vol
    mov     63, d0
    bra     me_vol
me_not5:
    cmp     6, d1
    bne     me_vol
    mov     (0x10, sp), d1          # volume down
    and     0xFF, d1
    sub     d1, d0
    bge     me_vol
    clr     d0
me_vol:
    cmp     0, d3
    beq     me_ret                  # no note: a volume change, nothing to send
    cmp     0, d0
    bne     me_audible
    mov     d2, d0                  # volume 0: silent
    call    SlotOff, 0, 0
    bra     me_ret
me_audible:
    asl     1, d0
    inc     d0
    asl     16, d0
    mov     d0, (0x14, sp)          # velocity << 16
    movbu   (a3), d1                # program, 0x80 drum, 0xFF none
    cmp     0xFF, d1
    beq     me_ret
    cmp     0x80, d1
    bne     me_melodic
    movbu   (1, a3), d1             # drum key on channel 10
    asl     8, d1
    or      AU_CH_DRUM, d1
    mov     AU_DRUM_MS, a0
    bra     me_play
me_melodic:
    mov     d2, d0
    add     AU_CH_MUS, d0
    mov     d0, (0x18, sp)
    call    SetProg, 0, 0           # d0 = channel, d1 = program
    mov     d3, d0
    call    PeriodSemis, 0, 0       # semitones from period 428
    movbu   (1, a3), d1
    add     d1, d0
    call    ClampNote, 0, 0
    asl     8, d0
    mov     (0x18, sp), d1
    or      d0, d1
    mov     d1, (0x18, sp)
    movhu   (2, a3), d0             # ms at period 428 (0xFFFF: loops, held)
    mov     0, a0
    cmp     0xFFFF, d0
    beq     me_ms
    mulu    d3, d0                  # at period p: ms * p / 428
    clr     d1
    mov     d1, mdr
    mov     428, d1
    divu    d1, d0
    cmp     AU_MIN_MS, d0
    bcc     me_dur
    mov     AU_MIN_MS, d0
me_dur:
    mov     d0, a0
me_ms:
    mov     (0x18, sp), d1
me_play:
    mov     (0x14, sp), d0
    or      d0, d1
    mov     d2, d0
    call    SlotOn, 0, 0
me_ret:
    ret     [d2,d3,a2,a3], 0x30

# PeriodSemis(d0 = Amiga period) -> d0 = semitones above period 428 (C-3): the nearest note of the
# ProTracker period table, 856 (-12) .. 113 (+23). Leaf.
PeriodSemis:
    mov     au_period_mid, a0
    mov     -12, a1                 # a1 = the note's semitones
ps_loop:
    movhu   (a0), d1
    cmp     0, d1
    beq     ps_done
    cmp     d1, d0                  # period >= the midpoint below this note: found
    bcc     ps_found
    add     2, a0
    inc     a1
    bra     ps_loop
ps_found:
    mov     a1, d0
    rets
ps_done:
    mov     23, d0
    rets

# AudioPoll: the PART SELECT RIGHT 2 toggle, the rows that are due, the notes whose time is up.
AudioPoll:
    movm    [d2,d3,a2,a3], (sp)
    add     -0x10, sp
    mov     (AU_READY), d0
    cmp     0, d0
    beq     apl_ret
    mov     (FWV_PANEL), a0
    cmp     0, a0
    beq     ap_time
    movbu   (AU_BTN_OFS, a0), d0
    and     AU_BTN_BIT, d0
    mov     (AU_BTN), d1
    mov     d0, (AU_BTN)
    cmp     0, d0
    beq     ap_time
    cmp     0, d1
    bne     ap_time                 # still held
    mov     (AU_ENABLED), d0        # pressed: sound off / on
    cmp     0, d0
    beq     ap_on
    mov     1, d0
    call    AllOff, 0, 0            # (sent while still enabled)
    clr     d0
    mov     d0, (AU_ENABLED)
    bra     ap_time
ap_on:
    mov     1, d0
    mov     d0, (AU_ENABLED)
    call    AudioSetup, 0, 0
ap_time:
    mov     (FWV_KERNEL_MS), a0
    mov     (a0), d2                # d2 = now
    mov     (AU_PAUSED), d0
    cmp     0, d0
    bne     ap_slots
    mov     AU_MAX_ROWS, d3
ap_row:
    mov     (AU_MOD), d0
    cmp     0, d0
    beq     ap_slots
    mov     d2, d0
    mov     (AU_NEXT), d1
    sub     d1, d0
    blt     ap_slots                # not due yet
    call    MusicRow, 0, 0
    mov     (AU_FRAC), d0           # the next row: AU_NEXT.AU_FRAC += AU_PER (1/256 ms)
    mov     (AU_PER), d1
    add     d1, d0
    mov     d0, d1
    and     0xFF, d1
    mov     d1, (AU_FRAC)
    lsr     8, d0
    mov     (AU_NEXT), d1
    add     d0, d1
    mov     d1, (AU_NEXT)
    add     -1, d3
    bne     ap_row
    mov     d2, (AU_NEXT)           # too far behind: from now on
ap_slots:
    mov     AU_SLOTS, a2
    clr     d3
ap_slot:
    mov     (SL_OFF, a2), d0
    cmp     0, d0
    beq     ap_slot_next
    mov     d2, d1
    sub     d0, d1
    blt     ap_slot_next            # not yet
    mov     d3, d0
    call    SlotOff, 0, 0
ap_slot_next:
    add     SL_LEN, a2
    inc     d3
    cmp     AU_NSLOTS, d3
    bne     ap_slot
apl_ret:
    ret     [d2,d3,a2,a3], 0x20

# ---- tables -------------------------------------------------------------------------------------
au_channels:    # every MIDI channel the game sends on (0-based): 4-7, 10, 11-14
    .byte   3, 4, 5, 6, 9, 10, 11, 12, 13, 0xFF
    .align  2
au_freq:        # PLAY_SOUND's 40 frequencies, Hz (rawgl freqTable): a semitone apart
    .word   0x0CFF, 0x0DC3, 0x0E91, 0x0F6F, 0x1056, 0x114E, 0x1259, 0x136C
    .word   0x149F, 0x15D9, 0x1726, 0x1888, 0x19FD, 0x1B86, 0x1D21, 0x1EDE
    .word   0x20AB, 0x229C, 0x24B3, 0x26D7, 0x293F, 0x2BB2, 0x2E4C, 0x3110
    .word   0x33FB, 0x370D, 0x3A43, 0x3DDF, 0x4157, 0x4538, 0x4998, 0x4DE5
    .word   0x5240, 0x5764, 0x5C9A, 0x61C8, 0x6793, 0x6E19, 0x7485, 0x7BBD
au_period_mid:  # the midpoints between the ProTracker periods 856, 808 .. 120, 113: a period at or
                # above entry k is note k (k - 12 semitones from 428); 0 ends the table
    .word   832, 785, 741, 699, 659, 622, 587, 554, 523, 494, 467, 441
    .word   416, 393, 371, 350, 330, 311, 294, 277, 262, 247, 233, 220
    .word   208, 196, 185, 175, 165, 156, 147, 139, 131, 124, 117, 0
    .align  4
