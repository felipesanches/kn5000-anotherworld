# Gameplay input: how the KN7000 controls reach the Another World VM

The water part (`0x3E82`) is playable: five control-panel buttons drive a D-pad + fire,
feeding the Another World hero-control variables. This note records how the input source
was chosen and decoded, and the one measurement that limits it. Every number below has a
script here that reproduces it; run each through the unpatched `mame-pr/kn7000` with
`-str 60` (clears the warning screen so the autoboot script runs).

## Why the panel, not the keybed

Felipe asked to play from the keybed. Three probes show the firmware exposes no stable,
readable *held-note identity* to a ride-along module, so the keybed cannot drive
directions:

| probe             | question                                        | result |
|-------------------|-------------------------------------------------|--------|
| (earlier) FIFO    | is the keybed voice-event FIFO readable?        | drained by the firmware; 236 reads caught 0 events |
| `awnotediff.lua`  | does any RAM byte equal the held note / key idx?| 0 bytes correlate (C4→G4) across 12 KB of work RAM |
| `awkeycal.lua`    | what *does* move when a key is held?            | free-running phase/voice accumulators (`0x8901` one run, `0x0E79` another for the same region) — not a stable note |

The only clean keybed signal is "a voice is active" (bit 7 of `0x5014967C`: `0x89` held
vs `0x09` released), which is enough for the intro *skip* (any key = fire) but carries no
direction. Reliable directional input therefore comes from the panel.

## The firmware panel switch-shadow (decoded by `awpanelmap.lua`)

`awpanelmap.lua` drives every one of the 154 `:cpanel:*` button fields in turn and diffs
`0x5006BE40..0x5006BE9F` while each is held. Result: the firmware keeps a **debounced,
level-held button bitmap** — one byte per CP serial segment, one bit per switch line,
held `1` for as long as the button is physically down:

```
CPR_SEGn button bits at 0x5006BE60 + n   (segments 0..9)
CPL_SEGn / CPC_SEGn     at 0x5006BE90 + n (segments 0..7)
bit = 1 << SWn   (SW0->0x01, SW1->0x02, SW2->0x04, ... SW7->0x80)
```

verified across every segment (e.g. CPR_SEG0: SOLO/SW0→`0x01`, PANEL MEMORY 1/SW1→`0x02`,
PROGRAM MENUS/SW2→`0x04`, …, CUSTOMIZE/SW6→`0x40`). The churn in `+00..+1f` is the
transient CP-serial scan/LED buffer (marked `edge` by the probe) and is ignored.

The five buttons chosen (distinct bytes, so any combination is independently readable):

| direction | button               | segment  | shadow byte  | bit  |
|-----------|----------------------|----------|--------------|------|
| LEFT      | PART SELECT LEFT     | CPR_SEG2 | `0x5006BE62` | 0x01 |
| RIGHT     | PART SELECT RIGHT 1  | CPR_SEG1 | `0x5006BE61` | 0x02 |
| UP        | R1/R2 OCTAVE +       | CPR_SEG6 | `0x5006BE66` | 0x02 |
| DOWN      | R1/R2 OCTAVE -       | CPR_SEG7 | `0x5006BE67` | 0x02 |
| FIRE      | SUSTAIN              | CPR_SEG5 | `0x5006BE65` | 0x08 |

## The limit: one panel button at a time (`awcombo.lua`)

`awcombo.lua` presses two buttons at once and reads the shadow bits. The firmware reports
**only one** pressed button at a time — every combo collapses to a single bit
(RIGHT+FIRE→RIGHT only, UP+LEFT→LEFT only, DOWN+RIGHT→RIGHT only). The control panel is a
menu panel, not a rollover game matrix. Consequence: no diagonals and no move+fire from
the panel. The water part (swim up, then exit sideways; no gun yet) is playable with
single-axis input; this is a measured hardware constraint, not a code limit — `ReadInput`
ORs the mask bits and would pass a diagonal through if the firmware ever set two.

## Correctness: the hero variables match the oracle (`awinputverify.lua`)

`awinputverify.lua` forces the water part (pokes `REQ_NEXT_PART=0x3E82`), presses each
button, and reads back `var[0xFC,0xE5,0xFB,0xFD,0xFA,0xFE]`. All five single-button cases
match rustyworld's `update_player` exactly:

```
RIGHT -> FC=+1 E5=0 FB=0 FD=0x01 FA=0 FE=0x01
LEFT  -> FC=-1 E5=0 FB=0 FD=0x02 FA=0 FE=0x02
DOWN  -> FC=0 E5=+1 FB=+1 FD=0x04 FA=0 FE=0x04
UP    -> FC=0 E5=-1 FB=-1 FD=0x08 FA=0 FE=0x08
FIRE  -> FC=0 E5=0 FB=0 FD=0x80 FA=1 FE=0x80
```

(Combos read back "wrong" only because the running bytecode also writes these variables
as scratch within a frame; the raw-shadow probe above is the clean test, and it is the
firmware one-button limit, not `ReadInput`, that caps combos.)

## Functional: input moves Lester (`awmove.lua`)

`awmove.lua` reaches the water part and logs a checksum of the displayed page at
water-frames 10/20/30/40, with and without a direction held. The output diverges by
input — at frame 40: none=`004f7e/004f5d`, UP=`004f87/004f69`, LEFT=`004f8b/004f66` (all
three distinct). Holding a direction changes the rendered state, and different directions
produce different states.
