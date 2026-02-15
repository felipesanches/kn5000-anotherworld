# Attempt 43: Ghost Toggle Fix + Left Panel Header Encoding (2026-02-15)

## Two bugs found and fixed in this attempt.

---

## Bug 1: Ghost Button Toggles (per-segment confirmation)

### Root Cause

The cpanel HLE's `button_scan_callback` (7ms periodic) reads MAME input ports
that **momentarily return non-zero values** even when no keyboard keys are pressed.
These single-scan glitches ("ghost toggles") produce a systematic pattern:

1. Port reads 0xNN (single bit set) → cpanel reports button press via INTA
2. 100ms debounce expires → port reads 0x00 → cpanel reports button release via INTA

Every ghost toggle generates 2 INTA sessions (press + release) that deliver
phantom button events to the firmware.

### Evidence from Log (131,525 lines)

- **110 left panel events**: ALL ghost toggles (55 press-release pairs), ZERO real presses
- **50 right panel events**: ALL ghost toggles (25 pairs)
- Every non-zero value is a single bit (0x01, 0x02, ..., 0x80)
- All pairs have exactly 137-line gaps (the 100ms debounce window)
- Affected ports include buttons WITHOUT any PORT_CODE mapping (e.g., CPL_SEG0
  rhythm group buttons) — confirming the glitch is internal, not from user input

### Fix: Per-Segment Confirmation

Replaced the global 100ms debounce with per-segment confirmation:

- Added `m_pending_button_state[22]` array (mirrors `m_last_button_state`)
- A state change must appear in **2 consecutive scans** (14ms) before being reported
- First scan: state differs from confirmed → record as pending
- Second scan: state still matches pending → CONFIRMED, report via INTA
- If state reverts before confirmation: pending is reset, no report

Additionally removed `queue_button_changes()` calls from command handlers (E0/20
query path) to prevent bypassing the confirmation logic.

---

## Bug 2: Left Panel Header Encoding (THE ROOT CAUSE)

### Root Cause

**The button packet header encoding was wrong for the left panel.** The real
panel MCUs encode the panel identity in bits 7:6 of the response header:

| Panel | Bits 7:6 | Header format | Example (seg 3) |
|-------|----------|---------------|------------------|
| Left  | 00       | `segment`     | 0x03             |
| Right | 11       | `0xC0 \| seg` | 0xC3             |

Our HLE was using `bit 6 = 1` for left panel (header = `0x40 | segment`),
which was **wrong**.

### Why This Matters

The firmware's event dispatcher at `LABEL_FC6A12` translates raw header bytes
through a ROM lookup table at address `0xEDA03C`. The translation index is
computed as `(header & 0xC0) >> 1 | (header & 0x1F)`:

| Header encoding   | Lookup index | Table value | Result |
|-------------------|-------------|-------------|--------|
| Left (00): 0x03   | 0x03        | 0x0E        | Valid index 14 → LED dispatch ✓ |
| Right (C0): 0xC3  | 0x63        | 0x03        | Valid index 3 → LED dispatch ✓ |
| **Old left (40): 0x43** | **0x23** | **0x1F** | **Index 31 → DEAD ZONE** ✗ |

The lookup table contents (verified from ROM at offset 0xDA03C):
```
[0x00-0x0A]: 0B 0C 0D 0E 0F 10 11 12 13 14 15   ← left panel → indices 11-21
[0x0B-0x5F]: all 1F                                ← dead zone (index 31)
[0x60-0x6A]: 00 01 02 03 04 05 06 07 08 09 0A     ← right panel → indices 0-10
```

With the old encoding (0x40), left panel events got index 0x1F. In the
dispatcher, indices > 0x15 (21) bypass the LED dispatch path — so the firmware
**never sent LED commands or processed button handlers for left panel events**.

### Fix

Changed `send_button_packet` header encoding:
```cpp
// OLD (wrong):
if (is_left_panel) header |= 0x40;

// NEW (correct):
if (!is_left_panel) header |= 0xC0;
```

Left panel headers are now plain segment numbers (0x00-0x0A), and right panel
headers use 0xC0 | segment (0xC0-0xCA), matching the real panel MCU encoding.

### Verification via CPanel_RX_ButtonPacket

The firmware's `AND W, 04Fh; BIT 006h, W` correctly handles both encodings:
- Left (0x03): AND 0x4F = 0x03, bit 6 = 0 → indices 0-10 in STATE array
- Right (0xC3): AND 0x4F = 0x43, bit 6 = 1 → SUB 0x30 → indices 16-26

The firmware's internal naming of the code paths is reversed from our physical
panel naming, but the data flow is correct with this encoding.

---

## Files Modified

- `kn5000_cpanel.h`: Added `m_pending_button_state[22]` member
- `kn5000_cpanel.cpp`:
  - Constructor/device_reset: Initialize `m_pending_button_state` to all zeros
  - device_start: Added `save_item(NAME(m_pending_button_state))`
  - `send_button_packet`: Fixed header encoding (left=segment, right=0xC0|segment)
    and also updates `m_pending_button_state[state_idx]`
  - `button_scan_callback`: Rewritten with per-segment confirmation logic
  - `queue_button_changes`: Emptied (no longer called from command handlers)
  - Query command handlers (0x20/0x25/0xe0/0xe2/0xe3): Removed `queue_button_changes()` calls
  - Protocol documentation: Updated header format comment

## Expected Outcome

- **Left panel buttons should now work**: Correct header encoding means the
  firmware's event dispatcher finds valid lookup table entries → LED dispatch
  executes → visible reactions to button presses
- **Zero ghost toggle INTAs**: Per-segment confirmation filters single-scan glitches
- **Both panels fully functional**: Left via INTA proactive notifications,
  right via E0 13 polling + INTA

## Compatibility

- **Original firmware**: Header encoding now matches real panel MCU behavior.
  Per-segment confirmation adds 7ms latency — imperceptible to humans.
- **AW VM**: Uses separate input mechanism (SC1 serial reads CPR_SEG4/CPL_SEG4),
  not affected by cpanel changes.

## Risk

- LOW: Header encoding fix is verified against ROM lookup table data
- LOW: Per-segment confirmation is conservative (14ms vs 50ms+ real press time)
- The firmware's internal "left/right" naming in CPanel_RX_ButtonPacket code
  paths is reversed from physical panel naming — this is by design in the
  original firmware, not a bug in our fix.
