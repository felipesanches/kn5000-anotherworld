# Attempt 23: Keep INTA Asserted During Multi-Packet Gaps (2026-02-14)

## Hypothesis
During `send_all_button_states` (0x2B/0xEB), cpanel queues 22 bytes delivered in 11 INTA cycles with 200us gaps. Previously, INTA was deasserted during each gap, allowing firmware's WaitTXReady to pass (PE.5=LOW) and start the next command before all packets were delivered. This would corrupt the response stream.

## Investigation
- Analyzed firmware WaitTXReady: checks PE.5 (INTA), TX_RX_FLAGS bits 0&1, PF.6
- Traced multi-packet delivery timing: 11 packets x (148us + 200us) = 3.83ms total
- Firmware delay between command and ProcessWithFlag is only 1.44ms
- During 200us gap, all WaitTXReady conditions pass -> firmware sends next command
- Verified execute_set_input for INTA: level-triggered via update_int_reg lambda
- Confirmed atomic pulse (deassert+reassert in same callback) works: CPU never executes between calls

## Fix
Two changes in `kn5000_cpanel.cpp`:
1. `self_clock_callback` packet-pause: removed INTA deassert, keeps PE.5 HIGH during gaps
2. `idle_detect_callback`: when INTA already asserted (re-trigger case), does atomic pulse `m_inta_cb(0); m_inta_cb(1)` to re-trigger interrupt without CPU observing PE.5=LOW

## Files Modified
- `kn5000_cpanel.cpp`: self_clock_callback (removed deassert), idle_detect_callback (added atomic pulse branch)

## Outcome
**No change** — exact same result as attempt 22. The INTA gap was not the cause of remaining LED issues.

## Commit
`1786458`
