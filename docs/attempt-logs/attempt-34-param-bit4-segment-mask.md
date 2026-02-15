# Attempt 34: Extract Segment from Param Low Nibble (2026-02-14)

## Hypothesis
The firmware's cpanel polling loop sends commands with param values that have bit 4
set (0x10, 0x11, 0x13). The cpanel HLE treats these as out-of-range (> 0x0B) and
returns sync packets instead of button data. The firmware expects button segment
responses for these params, where the segment index is in the low nibble (param & 0x0F).

The repeating `E0 13` command (right panel, param 0x13 = segment 3 with bit 4 flag)
gets a sync response instead of segment 3 button data, causing the firmware to loop
forever without processing button state changes.

## Evidence

### Log analysis (71,948 lines)
- 0 garbled commands (orphan edge fix from attempt 33 is working)
- rx_count always 8 at tx_start (byte boundaries aligned)
- 34 total commands decoded correctly
- After initialization + GUI loading, firmware enters polling loop
- Polling loop stuck on `E0 13` (11 consecutive occurrences until end of log)

### Firmware disassembly analysis
Three firmware functions use params with bit 4 set:
1. **CPanel_ReadAllButtons**: `25 01`, `E2 04`, `20 10`, `E2 11`
2. **CPanel_InitButtonState**: `2B 00`, `EB 00`, `20 10`, `E3 10`
3. **CPanel_InterruptPoll_MainLoop**: `E0 13` (every 42 iterations)

Param values with bit 4:
- 0x10 = segment 0 in scan mode
- 0x11 = segment 1 in scan mode
- 0x13 = segment 3 in scan mode

The response header uses only bits 6 (panel) and 3-0 (segment), confirmed by
firmware's `AND W, 0x4F` mask in `CPanel_RX_ButtonPacket`.

## Fix
In `process_command()`, extract segment from `param & 0x0F` instead of using param
directly as the segment index. Only param == 0x00 is a sync/ping; everything else
with a valid low nibble (0-11) returns button data.

```cpp
int segment = param & 0x0f;
if (param == 0x00)
    send_sync_packet();
else if (segment <= 0x0b)
    send_button_packet(segment, ...);
else
    send_sync_packet();
```

## Files Modified
- `kn5000_cpanel.cpp`: Both left panel (0x20/0x25) and right panel (0xE0/0xE2/0xE3)
  query handlers now extract segment from `param & 0x0F`

## Expected Outcome
- `E0 13` → button packet for right panel segment 3 (instead of sync)
- `20 10` → button packet for left panel segment 0 (instead of sync)
- `E2 11` → button packet for right panel segment 1 (instead of sync)
- `E3 10` → button packet for right panel segment 0 (instead of sync)
- Firmware's polling loop progresses through segments instead of getting stuck
- Button presses should be detected and reflected in the GUI

## Risk
- LOW: Only changes how params > 0x0A are interpreted. Params 0x00-0x0B
  behave identically (segment == param when bit 4 is 0). The change only
  affects the `else` branch that previously returned sync for all out-of-range
  params.
- AW VM unaffected (uses its own serial protocol, not these commands)
