-- awricost.lua -- how many instructions does one ReadInput call execute?
--
-- Runs the keybed re-performance (awkbreplay.lua, so keys are being parsed) and has the MAME
-- debugger trace ReadInput from its entry breakpoint to its final ret in VM frames F0..F0+2 of the
-- water part. Each hit reopens the trace file, so it holds the frame F0+2 call; the entry
-- instruction itself (the movm the breakpoint sits on) is not in it. Count lines in the module
-- range 0x502B6000.. . Addresses: grep -E ' (ReadInput|ri_ret)$' build/another.map
--   AW_RI=502B7017 AW_RIRET=502B71A3 AW_TRACE=$HOME/compartilhado/tmp/ri.tr AW_F0=300 \
--   AW_KBEVENTS=probes/sessions/2026-10-17-fsanches-misinput1-events.csv AW_SESSION=ricost \
--   ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets -skip_gameinfo -window \
--     kn7000 -bios sp7001 -harddisk build/another_sd.img -autoboot_script probes/awricost.lua \
--     -debug -debugger none -str 120
-- 2026-10-17, frame 302: voice-ring build 127 instructions; MIDI-ring build 805 (NotePoll 75,
-- NotesAnyHeld 583 -- the 61-note action range, both trackers).
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
dofile(here .. "awkbreplay.lua")
local M=manager.machine; local dbg=M.debugger
local ri=os.getenv("AW_RI"); local rr=os.getenv("AW_RIRET"); local f0=tonumber(os.getenv("AW_F0") or "300")
local cond=string.format("(w@4408007C>=%X)&&(w@4408007C<=%X)", f0, f0+2)
dbg:command(string.format("bpset %s,%s,{trace %s,maincpu,noloop;g}", ri, cond, os.getenv("AW_TRACE")))
dbg:command(string.format("bpset %s,%s,{trace off;g}", rr, cond))
dbg:command("go")
emu.register_periodic(function() if manager.machine.devices[":maincpu"].spaces["program"]:read_u16(0x4408007C) > f0+4 then M:exit() end end)
