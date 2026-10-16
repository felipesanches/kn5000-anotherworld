# Other ways for an SP7001 plug-in to read the keybed and the control panel

Investigation (2026-10-16): does the SD plug-in interface expose helper methods for
reading the keybed or the control panel, beyond the raw RAM reads the port currently
uses? Short answer: **the formal plug-in export API exposes no keybed/panel *read*
helper, but the firmware keeps stable RAM structures a plug-in can poll — and the keybed
one gives full polyphonic, note-numbered held-key readout, which earlier work had wrongly
concluded was impossible.** Addresses are for SP7001 program build 942 (disassembly in
`kn7000_disassembly`).

## The plug-in interface itself

The firmware hands a loaded `.XAP` a **framework object** (`KssFrameworkObj`,
`*0x50299298`) and calls into the plug-in through header slots:

- `XapSlot08` (0x483E88E4) — called once at probe with `a0 = framework object`.
- `XapSlot0C` (0x483E88FE) — **called every pass of the library main loop** (the natural
  per-frame polling hook; our ride-along instead hooks the loading task).
- `XapSlot10` (0x483E8303) — `d0/d1` in, result out.

A plug-in calls the firmware only through the framework object's method tables
(`obj+0x1C` and `obj+0x2E1C`; the file API we use lives in the `+0x2E1C` table). The
authoritative list of blessed services is the **237-entry export table**
(`kn7000_disassembly/kn7000_sp7001_exports.sym`, code array 0x487B1BB8 / names 0x487B1F5C).
It exports file/media, the sequencer, RTOS (tasks/semaphores/flags), compression, the
**M3 message bus**, **MIDI**, and **panel LEDs** — but **no "read keybed" or "read panel
buttons" function**. A native plug-in can also *call any firmware address* (as we already
do for `fopen_api`), so "not exported" only means "not blessed," not "unreachable."

## Keybed — the working read path (polyphonic, stable, note-numbered)

The physical keybed is **scanned by the two TG LSIs in hardware**, not by this CPU. Key
events arrive in a hardware voice-event FIFO at `0x98040004` (main TG) / `0x98050004`
(sub TG), which the firmware's keybed task drains every loop — so a plug-in must **not**
poll the FIFO (it would steal events and cause stuck notes). The M3 bus
(`GetM3Em` 0x4C01499D / `GetM3EmVal` 0x4C014A51) does carry note-numbered polyphonic MIDI
events, but (a) the physical keybed is not published to it, and (b) `GetM3Em` is a
*consuming* dequeue shared with the firmware's pump — also unsafe to tap.

**The safe, working path is to read the TG voice-allocator state in work RAM:**

| what | where | format |
|------|-------|--------|
| held-voice bitmap | `0x500D288C` | 128 bits, one per voice slot; bit set while the slot's key is held, cleared on release |
| per-slot note number | `0x500D1278 + slot*0x2C + 0x0C` | u8 MIDI note |
| last-key part (filter) | `0x500D2878` | u8; the part the last key went to |

Algorithm: for each set bit in `0x500D288C`, `slot = byte*8 + bit`, then read the note at
`0x500D1278 + slot*0x2C + 0x0C`. Verified in MAME **during the water part**
(`awkeyread.lua`): holding C4, then G4, then C5 reads back `0x3C`, `0x43`, `0x48`
simultaneously — three distinct held notes with correct note numbers. `awnode2.lua`
located the note field at record offset `+0x0C` (C4→`0x3C` on slot 65, E4→`0x40` on slot
67). This is plain memory reads, read-only, no race with the firmware.

Caveats:
- **Slot-indexed, not key-indexed.** One keybed note can light several slots (melodic
  element voices + any layers), and the bitmap reflects *all* sounding voices — keybed +
  auto-accompaniment + sequencer + MIDI-in. During Another World nothing else sounds, so
  the held slots are exactly the keybed. To isolate the keybed in general, part-filter via
  `0x500D2878` / the known keyboard part numbers.
- The 128-bit mask is the reliable "held" signal. (The voice node's own `+0x26` bit7
  "held" flag did not light in practice; the mask did.)

**Why the earlier probes failed:** `awnotediff.lua`/`awkeycal.lua` scanned `0x50148000..`,
which holds free-running phase/pitch caches (`0x500CA0B0`/`0x500AF940` region), not the
allocator bookkeeping. The stable held-note state is at `0x500D1278`/`0x500D288C`, far
below that window. So **polyphonic keybed input IS achievable** — the port's earlier
"keybed can't give directions" was a probe-placement error, not a hardware limit.

## Control panel — the readable structures

No exported panel-read helper either, but the firmware maintains several readable RAM
structures (decoder `PanelFrameDecode` 0x484AD100):

- **Per-segment level bitmap** — `0x5006BE60 + seg` (CPR) / `0x5006BE90 + seg` (CPL/CPC),
  one bit per switch line, held while down. This is what the shipped port reads; it holds
  multiple buttons at once (see [PANEL-INPUT.md](PANEL-INPUT.md)).
- **XOR-edge shadows** — `0x5006BE50` / `0x5006BE80` (the decoder's previous-state
  reference).
- **Cooked switch-event FIFO** — functions `PanelEventFifoPop` (0x484AD529) /
  `PanelEventFifoPush` / `PanelEventFifoFree`, ring at `0x5006BCF8`; each momentary-switch
  change is a `[normSeg, DATA, CHANGED]` triplet.
- **Harvested change records** — `PanelSwEventHarvest` (0x484AD869) drains the FIFO into
  up to 7 `[normSeg, DATA, CHANGED]` records at `0x5006BEB4` (count `0x5006BEF0`).
- **App event system** — `PanelEventPost` (0x484AE16C) → the app queue → `ApPostEvent` /
  `GetEvent` (0x484293D2) / `MainGetEvent` (0x48429824): panel buttons dispatched as
  `(event, param)` pairs through the same system a module reads UI events from.

For this port the level bitmap is the simplest and is sufficient. The event/FIFO paths
would matter only if we needed press/release *edges* rather than held *level*.

## Bonus: LED output

The firmware exports/holds panel-LED writers — `SetHoldLed` (0x48416512), `SetDialLed`
(0x48416563), `SetModeLed` (0x48416590), `SetOtherPartLed`, and the LED-register path
`panel_led_frame` (MAME `kn_cpanel.cpp`). A plug-in could light panel LEDs for game
feedback.

## Bottom line for the port

- **Keybed gameplay is implemented** (ReadInput, part 0x3E82): held notes are read from
  `0x500D288C` + `0x500D1278+slot*0x2C+0x0C` each frame and OR'd into the same mask the
  panel feeds. Mapping: any note **<= 60** (C4 and the whole bass/left-hand range) =
  action; **F5** left, **A5** down, **C6** right, **Ab5 or Bb5** up. Polyphonic, so
  diagonals and move+fire work (verified in-game, `awkbdmap.lua`). The keybed also handles
  same-instant presses better than the panel (the TG allocates both voices at once).
- **Panel** already works and supports multiple buttons; no API change needed.
- Neither needs a new exported helper; both are plain work-RAM polls a plug-in can do
  each `XapSlot0C` pass (or, as now, from the ride-along hook).

### Probes
`awnodes.lua` (node-array/sustain-mask scan), `awnode2.lua` (locate the note field at
`+0x0C`), `awkeyread.lua` (polyphonic held-note read verified in the water part). Firmware
addresses from `kn7000_disassembly/kn7000_sp7001_exports.sym`,
`kn7000_sp7001_manual.sym`, `kn7000_manual.sym`, and
`kn7000_mame/notes/keybed-fifo-makebreak.md` / `sound-hw-architecture.md`.
