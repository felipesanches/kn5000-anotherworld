-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_noteoff.lua -- are the note-offs the game puts into the MIDI IN 1 receive ring (src/audio.s)
-- honoured as those that come in on the MIDI IN port are? In MAME some notes ring on after their
-- note-off whatever their source (the overlay's tone generator releases some voice classes only on
-- a keybed key-up: kn7000_mame notes/tg-envelope-implementation-plan.md), so the same notes go both
-- ways and are compared. The game runs (-bios v13) with its own sound turned off (AU_ENABLED = 0 once
-- AudioInit has run); this script writes into the ring as audio.s's MidiMsg does, on channel 4:
--   emu 70.0 bank 121/0 + program 80, 70.2-71.2 C4; emu 73.0 bank 121/0 + program 0, 73.2-74.2 E4;
-- and gen_noteoff_mid.py's SMF, given to -midiin1, sends the same on channel 5 through the serial port:
--   emu 77.0 program 80, 77.2-78.2 G4; emu 80.0 program 0, 80.2-81.2 A4.
-- Record with -wavwrite; noteoff_levels.py prints each note's level while held and after its note-off.
--   env: AWN_OUT (log), AWN_RING (MIDI IN 1 header: 893 0x5001F020, 941 0x5001F050)
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local log = io.open(os.getenv("AWN_OUT") or "awcnv_noteoff.log", "w")
local function P(...) local s = string.format(...); print(s); log:write(s, "\n"); log:flush() end
local RING = tonumber(os.getenv("AWN_RING") or "0x5001F020")
local CV, AU = 0x502C0000, 0x502DA000
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = { { 30, "CPR_SEG1", 0x04, "DISK MENU" }, { 36, "CPL_SEG0", 0x20, "STYLE CONVERT" },
                { 44, "CPR_SEG6", 0x01, "OK (KN7LOAD.CNV)" } }
local function put(bytes)                    -- audio.s MidiMsg, with the emulated CPU stopped between frames
  local st, last, wr, free = sp:read_u32(RING), sp:read_u32(RING + 4), sp:read_u32(RING + 12), sp:read_u16(RING + 16)
  if free < #bytes then P("ring full"); return end
  for _, b in ipairs(bytes) do sp:write_u8(wr, b); if wr == last then wr = st else wr = wr + 1 end end
  sp:write_u16(RING + 16, free - #bytes); sp:write_u32(RING + 12, wr)
end
local sched = { { 70.0, { 0xB3, 0, 121 } }, { 70.0, { 0xB3, 32, 0 } }, { 70.0, { 0xC3, 80 } }, { 70.2, { 0x93, 60, 100 } },
                { 71.2, { 0x83, 60, 64 } }, { 73.0, { 0xB3, 0, 121 } }, { 73.0, { 0xB3, 32, 0 } }, { 73.0, { 0xC3, 0 } },
                { 73.2, { 0x93, 64, 100 } }, { 74.2, { 0x83, 64, 64 } } }
local step, si, muted = 1, 1, false
TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then press(s[2], s[3], 0); P("t=%.1f pressed %s", t, s[4]); step = step + 1 end
  if not muted and sp:read_u32(AU + 0x3C) == 1 then sp:write_u32(AU, 0); muted = true; P("t=%.2f the game's sound off (AU_ENABLED 0)", t) end
  while si <= #sched and t >= sched[si][1] do
    put(sched[si][2]); P("t=%.3f ring <- %s", t, table.concat((function() local o = {} for _, b in ipairs(sched[si][2]) do o[#o + 1] = string.format("%02X", b) end return o end)(), " "))
    si = si + 1
  end
  if t > 84 then P("t=%.1f done; game sent %d messages; ring rd %08X wr %08X", t, sp:read_u32(AU + 0x2C), sp:read_u32(RING + 8), sp:read_u32(RING + 12)); log:close(); M:exit() end
end)
