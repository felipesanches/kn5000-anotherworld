# Attempt 29 - Thinking Dump (2026-02-14)

## Starting Point

Attempts 27-28 modified cpanel PROTOCOL (what we respond) with zero effect on LEDs:
- Attempt 27: Removed spurious sync for unknown commands → same 2 LED commands
- Attempt 28: Extended button packets for params > 0x0A → same 2 LED commands

Key finding: LED decisions are DETERMINISTIC — firmware sends same C2 01 and C0 42
regardless of cpanel response content. Protocol-level changes cannot affect LEDs.

## Shift in Approach: TIMING Instead of CONTENT

If WHAT we respond doesn't matter, maybe WHEN we respond does. The firmware's
initialization is a sequential state machine — timing of response delivery affects
how far each processing step gets before the next one runs.

## Deep Dive: CPanel_InitButtonState Timing

The firmware's CPanel_InitButtonState (cpanel_routines.asm line 528) does:
```
1. Send 0x2B 0x00 (left panel all buttons)
2. Wait 3×DELAY_6_TICKS (~1.44ms)
3. Call CPanel_RX_ProcessWithFlag (processes available data, sets flag bit 2)
4. Send 0xEB 0x00 (right panel all buttons)
5. Wait 3×DELAY_6_TICKS
6. Call CPanel_RX_ProcessWithFlag
7. Send 0x20 0x10
8. Wait 2×DELAY_6_TICKS
9. Call CPanel_RX_ProcessWithFlag
10. Send 0xE3 0x10
11. Wait 2×DELAY_6_TICKS
12. Call CPanel_RX_ProcessWithFlag
```

CPanel_RX_ProcessWithFlag differs from CPanel_RX_Process by setting bit 2 of
CPANEL_TX_RX_FLAGS. The flag is marked "UNUSED?" in our disassembly, but it IS
checked by setting it, and its presence in ProcessWithFlag vs Process is intentional.

## The Timing Problem

Our self-clocking delivers 22 bytes (11 two-byte packets) with a 200µs gap between
packets. Total delivery time: ~3.1ms.

The firmware waits only 1.44ms before CPanel_RX_ProcessWithFlag.

At the 1.44ms mark, only ~5 of 11 packets have been delivered. CPanel_RX_ProcessWithFlag
processes those 5 segments WITH flag bit 2 set, then returns. The remaining 6 segments'
bytes arrive later and sit in the RX ring buffer until the next CPanel_RX_Process call
(from the main poll loop), which processes them WITHOUT flag bit 2.

On real hardware, the panel MCU delivers all 22 bytes in ~704µs (continuous at 250kHz).
All 11 segments are processed by CPanel_RX_ProcessWithFlag WITH the flag set.

## Why This Could Affect LEDs

CPanel_RX_ButtonPacket does three things:
1. Stores button data at STATE_OF_CPANEL_BUTTONS[offset]
2. Adds 3 event entries to CPANEL_RX_EVENT_QUEUE
3. Decrements event slot counter by 3

The event queue is processed by application code, which may use it to determine initial
LED states. If only 5 of 11 segments' events are in the queue when the application
processes them (with the flag set), the application makes decisions based on incomplete
data.

The flag itself might control how events are dispatched — e.g., whether they trigger
immediate LED updates or are deferred.

## Why The User Saw Correct LEDs Before

This is speculative, but: an earlier version might have had different timing that
accidentally delivered all data before processing. Alternatively, pre-INTA versions
(where no responses were delivered at all) might have caused the firmware to take an
entirely different code path (error/timeout recovery) that happened to set LEDs correctly.

## The Fix

Reduce inter-packet gap from 200µs to 20µs:
- 20µs = 320 CPU cycles at 16MHz — plenty for the INTA ISR (~10 instructions)
- Total delivery: ~1.17ms — fits within the 1.44ms window
- All 11 segments processed by CPanel_RX_ProcessWithFlag WITH flag bit 2

The 200µs gap was originally added for safety — to give the firmware time to process
each 2-byte packet (write SC1CR, re-enable RX). But 20µs is more than sufficient for
this. The INTA ISR is just: save registers, write SC1CR (one instruction), restore, RETI.

## Risk Assessment

LOW. This change:
- Only affects timing, not protocol content
- 20µs is still a generous gap for ISR processing
- AW VM is unaffected (uses dummy bytes, not self-clocking)
- If it breaks anything, the symptom would be garbled serial data (easily detected)

## If This Doesn't Work

Next steps:
1. Try completely eliminating the gap (continuous clocking without pause)
2. Also reduce the initial idle_detect timeout from 50µs to 20µs
3. Investigate NVRAM initialization — is the firmware correctly loading factory defaults?
4. Add MAME debugger breakpoints on Set_LEDs (FC71B2) to trace what determines the
   pattern byte for each LED row
