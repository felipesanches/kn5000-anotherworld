-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_midiprog.lua -- the experiment src/audio.s was built on (2026-10-20, -bios v13 = program 893,
-- KN7APP.BIN e3ee3a40..., the build before sound). While the game runs parked on STYLE CONVERT, the
-- script itself becomes a producer of the firmware's MIDI IN 1 receive ring, as the RX ISR is (byte at
-- wr, wr+1 wrapping at last, free-1), and asks: (1) does the firmware consume the bytes (its rd follows
-- wr) and play them? (2) does a received program change change the sound of PART 4, with and without a
-- GM2 bank select (121/0)? (3) is PART 10 a drum part, and does the GM2 drum bank (120/0) keep it one?
-- Schedule (s after the game task starts): A 4.0 note C4 on channel 4 as PART 4 is; B 6.0 program 80
-- alone, C4; C 8.0 bank 121/0 + program 80, C4; D 10.0 bank 0/0 + program 0, C4; E 12.0 channel 10
-- keys 42, 38, 36; F 14.0 bank 120/0 + program 0 on channel 10, the same keys; G 16.0 bank 121/0 +
-- program 48, C4; 18.0 all notes off on both. Record with -wavwrite; midiprog_spectra.py reads it.
-- Answers seen (README.md, "Sound"): every byte consumed; B and C a square wave (odd harmonics only,
-- GM 80 Square Lead), D piano-like, G sawtooth-like strings (GM 48); E and F a 57 Hz thump on key 36
-- and a 216 Hz one on 38 (drums both times). In MAME no note ever stops: the overlay's tone generator
-- releases MIDI-received notes of some voice classes only on a keybed key-up
-- (kn7000_mame notes/tg-envelope-implementation-plan.md, GATE_FOLLOW), so the A note rings throughout.
--   env: RING (the MIDI IN 1 header: 893 0x5001F020, 941 0x5001F050), OUT (log)
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local RING = tonumber(os.getenv("RING") or "0x5001F020")
local log = io.open(os.getenv("OUT") or "midiinject.log", "w")
local function P(...) local s = string.format(...); print(s); log:write(s, "\n"); log:flush() end
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = { { 30, "CPR_SEG1", 0x04, "DISK MENU" }, { 36, "CPL_SEG0", 0x20, "STYLE CONVERT" },
                { 44, "CPR_SEG6", 0x01, "OK (KN7LOAD.CNV)" } }
local CV = 0x502C0000
local function put(b)
  local st, last, wr, free = sp:read_u32(RING), sp:read_u32(RING + 4), sp:read_u32(RING + 12), sp:read_u16(RING + 16)
  if free == 0 then P("ring full"); return end
  sp:write_u8(wr, b)
  if wr == last then wr = st else wr = wr + 1 end
  sp:write_u32(RING + 12, wr); sp:write_u16(RING + 16, free - 1)
end
local readers = {}
TAP = nil and sp:install_read_tap(RING + 8, RING + 11, "rdtap", function(off, data, mask)
  local pc = cpu.state["PC"].value
  if not readers[pc] then readers[pc] = true; P("rd read by pc %08X at t=%.2f", pc, M.time:as_double()) end
end)
local step, t3, k, sched = 1, nil, 0, {}
-- program/bank test: does a received program change / bank select change PART 4's and PART 10's sound?
local function at(t, bytes) sched[#sched + 1] = { t, bytes } end
local function note(t, ch, n, d) at(t, { 0x90 + ch, n, 100 }); at(t + d, { 0x80 + ch, n, 64 }) end
note(4.0, 3, 60, 1.0)                                        -- A: PART 4 as it is
at(6.0, { 0xC3, 80 }); note(6.2, 3, 60, 1.0)                 -- B: PC 80 alone
at(8.0, { 0xB3, 0, 121 }); at(8.0, { 0xB3, 32, 0 }); at(8.0, { 0xC3, 80 }); note(8.2, 3, 60, 1.0)   -- C: GM2 121/0/80
at(10.0, { 0xB3, 0, 0 }); at(10.0, { 0xB3, 32, 0 }); at(10.0, { 0xC3, 0 }); note(10.2, 3, 60, 1.0)  -- D: 0/0/0
note(12.0, 9, 42, 0.1); note(12.5, 9, 38, 0.1); note(13.0, 9, 36, 0.1)                            -- E: PART 10 as it is
at(14.0, { 0xB9, 0, 120 }); at(14.0, { 0xB9, 32, 0 }); at(14.0, { 0xC9, 0 })                      -- F: GM2 drums 120/0/0
note(14.2, 9, 42, 0.1); note(14.7, 9, 38, 0.1); note(15.2, 9, 36, 0.1)
at(16.0, { 0xB3, 0, 121 }); at(16.0, { 0xB3, 32, 0 }); at(16.0, { 0xC3, 48 }); note(16.2, 3, 60, 1.0)  -- G: GM2 strings
at(18.0, { 0xB3, 123, 0 }); at(18.0, { 0xB9, 123, 0 })
table.sort(sched, function(a, b) return a[1] < b[1] end)
local si = 1
TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then press(s[2], s[3], 0); P("pressed %s at %.1f", s[4], t); step = step + 1 end
  if not t3 and sp:read_u32(CV) == 3 then t3 = t; P("game running at t=%.1f; ring start %08X last %08X rd %08X wr %08X free %d", t,
    sp:read_u32(RING), sp:read_u32(RING + 4), sp:read_u32(RING + 8), sp:read_u32(RING + 12), sp:read_u16(RING + 16)) end
  if t3 then
    while si <= #sched and t - t3 >= sched[si][1] do
      for _, b in ipairs(sched[si][2]) do put(b) end
      P("t=%.3f (emu %.3f) sent %02X %02X %s", t - t3, t, sched[si][2][1], sched[si][2][2], tostring(sched[si][2][3]))
      si = si + 1
    end
    if t - t3 > 19.5 then P("done; rd %08X wr %08X free %d", sp:read_u32(RING + 8), sp:read_u32(RING + 12), sp:read_u16(RING + 16)); log:close(); M:exit() end
  end
end)
