-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_keymute.lua -- does a MIDI message put into the MIDI IN 1 receive ring, as the game's MidiMsg puts it (src/audio.s),
-- silence the keybed's own notes (program 893, the main screen; no game, no card)? Felipe's request of 2026-10-21: a
-- panel key that mutes the instrument's notes for the keys that steer the game. Three modes:
--   (default)  one keybed C4, and one C4 sent as MIDI IN on channel 1, before and after each of CC 11 = 0 on channel 1,
--              CC 11 = 0 on channels 1-3, CC 7 = 0 on channel 1 (and their undoing); round3_report.py prints the
--              recording's level in each "keys window". MAME's answer: no change at all, for any of them: the overlay's
--              tone generator does not model the voice level word (class 0x3000) the firmware sets (below).
--   AWK_DIFF=1 work RAM (0x50000000-0x5017FFFF) before CC 11 = 0 on channel 1, after it, after CC 11 = 127: the bytes
--              that went and came back (893: 0x5000B36B, 0x7F -> 0 -> 0x7F: the firmware took the message).
--   AWK_TG=1   the tone generators' register writes (address latch 0x98040000 / 0x98050000, data at +2) for one keybed
--              C4 with CC 11 at 127, at 0, at 127 again, into AWK_OUT/tg.txt (one column each). Masking the voice
--              number out of the address and dropping the 0xFCxx polling, the only difference is class 0x3000, the
--              voice's level word (kn7000_mame notes/tg-voice-allocator.md: TgVoiceLevelWordCalc): 0x0BE8 / 0x0BA4 for
--              the note's two layers at 127, 0x0000 at 0, the same as before at 127 again.
-- Env: AWK_OUT (events.txt, tg.txt), AWK_RING (893: 0x5001F020). Run (from the emulator's directory):
--   AWK_OUT=$O [AWK_DIFF=1 | AWK_TG=1] ./kn7000 kn7000 -bios v13 -rompath ./roms -pluginspath ./plugins -skip_gameinfo
--     -window -nothrottle [-wavwrite $O/run.wav] -nvram_directory $O/nv -cfg_directory $O/cfg \
--     -autoboot_script .../probes/cnv/awcnv_keymute.lua
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local OUT = assert(os.getenv("AWK_OUT"))
local RING = tonumber(os.getenv("AWK_RING") or "0x5001F020")
local function now() return M.time:as_double() end
local ev = assert(io.open(OUT .. "/events.txt", "w"))
local function E(...) local s = string.format("%8.2f ", now()) .. string.format(...); print("awk: " .. s); ev:write(s, "\n"); ev:flush() end
local KEY = {}
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do KEY[f.name] = f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function put(bytes)                 -- as audio.s MidiMsg: the bytes at wr, wr wrapping at last, free less
  local start, last, wr, free = sp:read_u32(RING), sp:read_u32(RING + 4), sp:read_u32(RING + 0xC), sp:read_u16(RING + 0x10)
  if free < #bytes then E("ring full"); return end
  for _, b in ipairs(bytes) do sp:write_u8(wr, b); if wr == last then wr = start else wr = wr + 1 end end
  sp:write_u16(RING + 0x10, free - #bytes); sp:write_u32(RING + 0xC, wr)
end
local function mwindow(label, ch)           -- the same C4, but as MIDI IN on channel ch (1-16)
  local t0 = now()
  put({ 0x8F + ch, 60, 100 }); wait(1.0); put({ 0x8F + ch, 60, 0 })
  E("keys window %s %.3f %.3f", label, t0 + 0.1, now()); wait(2.0)
end
local function window(label, name)
  local k = KEY[name or "C4"]; local t0 = now()
  k:set_value(1); wait(1.0); k:set_value(0)
  E("keys window %s %.3f %.3f", label, t0 + 0.1, now()); wait(2.0)
end
local TESTS = {
  { "cc11_ch1_0", { 0xB0, 11, 0 }, { 0xB0, 11, 127 } },
  { "cc11_ch123_0", { 0xB0, 11, 0, 0xB1, 11, 0, 0xB2, 11, 0 }, { 0xB0, 11, 127, 0xB1, 11, 127, 0xB2, 11, 127 } },
  { "cc7_ch1_0", { 0xB0, 7, 0 }, { 0xB0, 7, 100 } },
}
-- where the firmware keeps what CC 11 on channel 1 sets: work RAM read before, after CC 11 = 0 and after CC 11 = 127;
-- the bytes that went 0x7F -> 0 -> 0x7F (AWK_DIFF=1)
local function ram()
  local t = {}
  for a = 0x50000000, 0x5017FFFF, 4 do t[#t + 1] = sp:read_u32(a) end
  return t
end
local function diffscan()
  local r0 = ram(); put({ 0xB0, 11, 0 }); wait(0.5)
  local r1 = ram(); put({ 0xB0, 11, 127 }); wait(0.5)
  local r2 = ram()
  local n = 0
  for i = 1, #r0 do
    if r0[i] ~= r1[i] and r0[i] == r2[i] then
      for b = 0, 3 do
        local x0, x1 = (r0[i] >> (8 * b)) & 0xFF, (r1[i] >> (8 * b)) & 0xFF
        if x0 ~= x1 then
          E("ram %08X: %02X -> %02X -> back", 0x50000000 + 4 * (i - 1) + b, x0, x1); n = n + 1
          if n > 60 then return end
        end
      end
    end
  end
end
-- the tone generators' register writes for one keybed C4 (address latch 0x98040000 / 0x98050000, data at +2), with
-- CC 11 on channel 1 at 127 and at 0 (AWK_TG=1): the writes that differ say whether expression reaches the note
local TGLOG, tgaddr = nil, { 0, 0 }
AWK_TGT = {
  sp:install_write_tap(0x98040000, 0x98040003, "awk_tg0", function(o, d, m)
    if m & 0xFFFF ~= 0 then tgaddr[1] = d & 0xFFFF elseif TGLOG then TGLOG[#TGLOG + 1] = string.format("0:%04X=%04X", tgaddr[1], (d >> 16) & 0xFFFF) end
  end),
  sp:install_write_tap(0x98050000, 0x98050003, "awk_tg1", function(o, d, m)
    if m & 0xFFFF ~= 0 then tgaddr[2] = d & 0xFFFF elseif TGLOG then TGLOG[#TGLOG + 1] = string.format("1:%04X=%04X", tgaddr[2], (d >> 16) & 0xFFFF) end
  end),
}
local function tgnote()
  TGLOG = {}
  KEY["C4"]:set_value(1); wait(0.3); KEY["C4"]:set_value(0); wait(0.3)
  local l = TGLOG; TGLOG = nil; return l
end
local co = coroutine.create(function()
  wait(32)
  if os.getenv("AWK_TG") then
    local a = tgnote(); put({ 0xB0, 11, 0 }); wait(0.5)
    local b = tgnote(); put({ 0xB0, 11, 127 }); wait(0.5)
    local c = tgnote()
    E("TG writes: expression 127 %d, 0 %d, 127 again %d", #a, #b, #c)
    local f = assert(io.open(OUT .. "/tg.txt", "w"))
    for i = 1, math.max(#a, #b, #c) do f:write(string.format("%s %s %s\n", tostring(a[i]), tostring(b[i]), tostring(c[i]))) end
    f:close()
    E("end"); ev:close(); M:exit(); return
  end
  if os.getenv("AWK_DIFF") then diffscan(); E("end"); ev:close(); M:exit(); return end
  window("before"); mwindow("before_midi", 1)
  for _, t in ipairs(TESTS) do
    put(t[2]); wait(0.5); window(t[1]); mwindow(t[1] .. "_midi", 1)
    put(t[3]); wait(0.5); window(t[1] .. "_back"); mwindow(t[1] .. "_back_midi", 1)
  end
  E("end"); ev:close(); M:exit()
end)
AWK_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then E("ERROR %s", tostring(err)); ev:close(); M:exit() end
  end
end)
