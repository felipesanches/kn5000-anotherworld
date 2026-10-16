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

The only clean keybed signal *in that RAM window* is "a voice is active" (bit 7 of
`0x5014967C`: `0x89` held vs `0x09` released), enough for the intro *skip* (any key =
fire). So the shipped gameplay input uses the panel.

**Correction (2026-10-16): the keybed *can* give directions — those three probes just
scanned the wrong region.** The stable, polyphonic held-note state is the TG voice
allocator's bookkeeping at `0x500D288C` (held-slot bitmap) + `0x500D1278 + slot*0x2C +
0x0C` (note per slot), far below the `0x50148000` window above. Verified reading three
simultaneous held notes in-game. See [PLUGIN-INPUT-INTERFACES.md](PLUGIN-INPUT-INTERFACES.md).
The panel remains what the port currently wires up; the keybed is now a viable alternative.

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

## Multiple buttons DO coexist — diagonals and move+fire work (`awcombo2.lua`, `awdiag.lua`, `awstagger.lua`)

An earlier reading (`awcombo.lua`) concluded "one button at a time, no diagonals." **That
was wrong — a test artifact.** `awcombo.lua` re-pressed the combo every frame
(`clearall()` then set), toggling each held button 0->1 many times per 4 ms panel scan;
that churn races the scan and only one change survives. Pressing cleanly tells a different
story:

- `awdiag.lua` (both buttons set in the *same* frame, held steady): still collapses to one
  — two switch-changes in a single 250 Hz scan cycle lose one.
- `awcombo2.lua` / `awstagger.lua` (buttons pressed a few frames **apart**, as a human
  does, then both held): **both bits set and persist.** All four diagonals register
  (UP+RIGHT, UP+LEFT, DOWN+RIGHT, DOWN+LEFT) and move+fire registers (RIGHT+SUSTAIN).

So the only thing that collapses is two presses landing in the *exact same* ~4 ms scan —
impossible for human fingers, and most likely a MAME scan/tx timing artifact rather than
real-hardware behaviour (MAME's `panel_scan` in `kn_cpanel.cpp` does emit a frame for
every changed segment and queues them all). **Diagonals and move+fire are available for
normal play**, and the shipped `ReadInput` already ORs the shadow bits, so no code change
is needed to use them.

(SUSTAIN registers fine as fire when pressed on its own or staggered; the single `F=0` in
`awcombo2.lua`'s first line was only because fire was pressed in the *same* frame as RIGHT.)

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
