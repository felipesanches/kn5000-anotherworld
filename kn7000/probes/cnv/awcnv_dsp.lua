-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_dsp.lua -- the DSP sound build (README-CNV.md, "Sound"; src/dsp.s, tools/dsp_mixer.py) in one MAME session
-- through the program menu, as Felipe runs it: the owner's loader floppy, the menu as the card's root KN7APP.BIN, the
-- game in AW\ (run_dsp.sh builds the card). The light check of iteration 2 (dsp_report.py reads what this writes):
--   * the game loads the mixer and the sample bank (the bar), hooks units 0 and 9, and the intro's music and sound
--     effects play from the DSP: its voices, its mix, unit 0's and unit 9's returns; nothing goes out as MIDI;
--   * PART SELECT RIGHT 2 at intro + 25 s (TONE GENERATOR: the firmware's slots back, MIDI notes), + 35 s (OFF),
--     + 45 s (DSP again: hooked again);
--   * EXIT held 2 s at intro + 60 s: the slots back as found, read back, the message registers 0, the reverb running;
--     EXIT, "Continue Next?" YES: the menu, the game again: the bank must still be in SDRAM (not sent again);
--     EXIT held, EXIT, NO; a C4 on the keybed (the firmware's reverb, in the recording).
-- The firmware's "DSP dead" flag is read all along.
-- Writes $AWD_OUT/tap.txt (every 0.25 s of emulated time: the state below), $AWD_OUT/events.txt (what was pressed and
-- seen, with times) and snapshots. Env: AWD_OUT, AWD_DEAD (893: 0x500066D8), AWD_PANEL (893: 0x5006BE4C).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local dsp = M.devices[":dsp"]
local dm, pm = dsp.spaces["data"], dsp.spaces["program"]
local OUT = assert(os.getenv("AWD_OUT"), "set AWD_OUT")
local DEAD = tonumber(os.getenv("AWD_DEAD") or "0x500066D8")
local PANEL = tonumber(os.getenv("AWD_PANEL") or "0x5006BE4C")
-- the game's addresses (src/platformcnv.inc, src/vm.inc, src/cnv_main.s, src/dsp.inc)
local CV, INTERP, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_STATE, CV_DONE, CV_CALLS, CV_TASK = CV, CV + 8, CV + 0x10, CV + 0x1C
local PART, FRAME_NO, NO_SPLASH = INTERP + 0x102A, MISC + 0x7C, MISC + 0x58
local AU = 0x502DA000                               -- audio.s AU_*: +0x2C MIDI messages sent, +0x34 PLAY_SOUNDs, +0x30 rows
local DH = 0x502DA600                               -- dsp.inc DV_*
local DV_STATE, DV_FAIL, DV_HOOKED, DV_MODE, DV_READY = DH, DH + 4, DH + 0x54, DH + 0x60, DH + 0x64
local DV_BK_DONE, DV_BK_SENT, DV_FLUSHES, DV_BUSY, DV_FOUND = DH + 0x74, DH + 0x7C, DH + 0x90, DH + 0x8C, DH + 0x28
local BANKTAB = 0x502E7000                          -- AWBANK.AW: +0x0C words in all
local MV, V_NPROG, ORDER, PR_NAME = 0x502C0000, 0x502C0034, 0x502C3800, 0x40   -- the menu's (kn7menu menu.inc)
local LB = 0x502E7F00
-- the DSP's (tools/dsp_mixer.py)
local VOICES, MIX, HB9 = 0x9D20, 0x9D13, 0x9D16

local function now() return M.time:as_double() end
local ev = assert(io.open(OUT .. "/events.txt", "w"))
local function E(...) local s = string.format("%8.2f ", now()) .. string.format(...); print("awcnv_dsp: " .. s); ev:write(s, "\n"); ev:flush() end
local function cstr(a, n)
  local s = ""
  for i = 0, (n or 64) - 1 do local c = sp:read_u8(a + i); if c == 0 then break end; s = s .. string.char(c) end
  return s
end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEYC4
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do if f.name == "C4" then KEYC4 = f end end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(cond, s) local t = now() + s; while now() < t do if cond() then return true end; coroutine.yield() end; return cond() end
-- a panel press, seen in the firmware's own switch bitmap (the emulated panel sometimes loses one: then again)
local function press(tag, mask, hold)
  local f = field(tag, mask)
  local seg = tonumber(tag:match("SEG(%d+)"))
  local byte = PANEL + seg + (tag:sub(1, 3) == "CPR" and 0 or 0x30)
  for try = 1, 6 do
    f:set_value(1)
    local seen = wait_until(function() return (sp:read_u8(byte) & mask) ~= 0 end, 1.0)
    if seen then wait(hold or 0.4); f:set_value(0); return true end
    f:set_value(0); E("press %s %02X not seen (try %d): again", tag, mask, try); wait(1.5)
  end
  return false
end
local function slot(a) return pm:read_u64(a) & 0xFFFFFFFFFFFF end
local function voices()               -- bit v: voice v sounds (POS < END)
  local m = 0
  for v = 0, 7 do
    local b = VOICES + 8 * v
    if dm:read_u32(b) < dm:read_u32(b + 4) then m = m | (1 << v) end
  end
  return m
end

-- ---- the tap: every 0.25 s ------------------------------------------------------------------------
local tap = assert(io.open(OUT .. "/tap.txt", "w"))
tap:write("t cv part frame dvstate fail hooked mode ready bkdone bksent slot0 slot9 m4 m5 m6 m7 hb9 vmask mixmax out0max out9max " ..
          "c003 dead sent sounds rows flushes busy f4\n")
local T = { next = 0, mixmax = 0, o0 = 0, o9 = 0, vseen = 0 }
local function sx24(v) v = v & 0xFFFFFF; if v >= 0x800000 then v = v - 0x1000000 end; return v end
local function s32(v) if v >= 0x80000000 then v = v - 0x100000000 end; return v end
local function sample()
  local m = math.abs(s32(dm:read_u32(MIX)))
  if m > T.mixmax then T.mixmax = m end
  local a = math.abs(sx24(dm:read_u32(0xC342))); if a > T.o0 then T.o0 = a end
  local b = math.abs(sx24(dm:read_u32(0xC356))); if b > T.o9 then T.o9 = b end
  T.vseen = T.vseen | voices()
  local t = now()
  if t < T.next then return end
  T.next = t + 0.25
  tap:write(string.format("%.2f %d %04X %d %d %d %d %d %d %d %d %012X %012X %X %X %X %d %d %02X %d %d %d %08X %d %d %d %d %d %d %d\n",
    t, sp:read_u32(CV_STATE), sp:read_u16(PART), sp:read_u16(FRAME_NO), sp:read_u32(DV_STATE), sp:read_u32(DV_FAIL),
    sp:read_u32(DV_HOOKED), sp:read_u32(DV_MODE), sp:read_u32(DV_READY), sp:read_u32(DV_BK_DONE), sp:read_u32(DV_BK_SENT),
    slot(0x8080), slot(0x80A0), dm:read_u32(0x0C), dm:read_u32(0x0D), dm:read_u32(0x0E), dm:read_u32(0x0F),
    dm:read_u32(HB9), T.vseen, T.mixmax, T.o0, T.o9, dm:read_u32(0xC003), sp:read_u8(DEAD),
    sp:read_u32(AU + 0x2C), sp:read_u32(AU + 0x34), sp:read_u32(AU + 0x30), sp:read_u32(DV_FLUSHES), sp:read_u32(DV_BUSY),
    sp:read_u16(INTERP + 2 * 0xF4)))
  tap:flush()
  T.mixmax, T.o0, T.o9, T.vseen = 0, 0, 0, 0
end

-- ---- the session --------------------------------------------------------------------------------
local function to_converter()         -- DISK MENU, STYLE CONVERT (left 3), OK (right 4) until the loader runs
  press("CPR_SEG1", 0x04); wait(6)
  press("CPL_SEG0", 0x20); wait(8)
  for i = 1, 8 do
    press("CPR_SEG6", 0x01)
    if wait_until(function() return sp:read_u32(0x502B9E00) == 0x53374E4B end, 20) then break end
    E("OK %d not taken; again", i)
  end
end
local function run_aw()               -- the menu's list: "Another World", its row's left button, RUN (right 5)
  local ok = wait_until(function() return sp:read_u32(MV) == 4 and cstr(0x502BA020, 32) ~= "ANOTHER WORLD" end, 150)
  local n, idx = sp:read_u32(V_NPROG), nil
  for i = 0, n - 1 do if cstr(sp:read_u32(ORDER + 4 * i) + PR_NAME) == "Another World" then idx = idx or i end end
  E("menu: %s, %d programs, Another World at %s", ok and "up" or "NOT UP", n, tostring(idx))
  if not idx then return false end
  for _ = 1, idx // 5 do press("CPR_SEG5", 0x20); wait(1) end
  press("CPL_SEG0", ({ 0x02, 0x08, 0x20, 0x01, 0x04 })[idx % 5 + 1]); wait(1)
  press("CPR_SEG5", 0x01)
  ok = wait_until(function() return cstr(0x502BA020, 32) == "ANOTHER WORLD" end, 30)
  E("RUN: %q at APP_BASE, launch folder %q", cstr(0x502BA020, 32), cstr(LB + 0x10, 16))
  return ok
end
local nosplash = false
local function game(label)
  local t0 = now()
  wait_until(function() return sp:read_u32(CV_STATE) >= 2 end, 120)
  if not nosplash or label == "again" then sp:write_u32(NO_SPLASH, 0x5EED0FF0); nosplash = true end
  E("%s: firmware search done (DSP routines found %02X), global files loading", label, sp:read_u32(DV_FOUND))
  wait_until(function() return sp:read_u32(CV_STATE) == 5 end, 60)
  local tb = now()
  wait_until(function() return sp:read_u32(CV_STATE) == 3 end, 400)
  E("%s: the game task starts after %.1f s of DSP setup: DSP state %d, fail %d, hooked %d, mode %d, bank sent %d (%d of %d words), slots %012X %012X",
    label, now() - tb, sp:read_u32(DV_STATE), sp:read_u32(DV_FAIL), sp:read_u32(DV_HOOKED), sp:read_u32(DV_MODE),
    sp:read_u32(DV_BK_SENT), sp:read_u32(DV_BK_DONE), sp:read_u32(BANKTAB + 0x0C), slot(0x8080), slot(0x80A0))
  M.video:snapshot()
end
local function quit(label)
  press("CPC_SEG11", 0x80, 2.0)                         -- EXIT held 2 s
  local ok = wait_until(function() return sp:read_u32(CV_DONE) == 1 and sp:read_u32(DV_STATE) == 3 end, 20)
  wait(1)
  E("%s quit: task done %d, DSP state %d, hooked %d, slots %012X %012X, MSGR4-7 %X %X %X %X", label,
    sp:read_u32(CV_DONE), sp:read_u32(DV_STATE), sp:read_u32(DV_HOOKED), slot(0x8080), slot(0x80A0),
    dm:read_u32(0x0C), dm:read_u32(0x0D), dm:read_u32(0x0E), dm:read_u32(0x0F))
  M.video:snapshot()
  -- EXIT while the firmware's message shows: "Continue Next?" (it comes by itself a few seconds later, and an
  -- EXIT then would cancel it: RUNNING-THE-BUILDS.md)
  press("CPC_SEG11", 0x80); wait(4)
  return ok
end

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  E("boot: slots %012X %012X, dead %d", slot(0x8080), slot(0x80A0), sp:read_u8(DEAD))
  to_converter()
  run_aw()
  game("first")
  wait_until(function() return sp:read_u16(PART) == 0x3E81 end, 60)
  local ti = now()
  E("the intro starts")
  wait(25); E("RIGHT 2: -> tone generator"); press("CPR_SEG2", 0x02, 0.3); wait(1)
  E("mode %d hooked %d slots %012X %012X", sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED), slot(0x8080), slot(0x80A0))
  wait(9); E("RIGHT 2: -> off"); press("CPR_SEG2", 0x02, 0.3); wait(1)
  E("mode %d hooked %d", sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED))
  wait(9); E("RIGHT 2: -> DSP"); press("CPR_SEG2", 0x02, 0.3); wait(1)
  E("mode %d hooked %d slots %012X %012X", sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED), slot(0x8080), slot(0x80A0))
  wait_until(function() return now() > ti + 60 end, 60)
  quit("first")
  press("CPR_SEG7", 0x01)                               -- YES (right 3): the loader loads the menu again
  run_aw()
  game("again")
  wait(15)
  quit("again")
  press("CPR_SEG6", 0x01); wait(6)                      -- NO (right 4): the main screen
  E("left STYLE CONVERT; slots %012X %012X; a C4 on the keybed", slot(0x8080), slot(0x80A0))
  M.video:snapshot()
  KEYC4:set_value(1); wait(1.0); KEYC4:set_value(0); wait(5)
  E("end")
  tap:close(); ev:close()
  M:exit()
end)
AWD_TICK = emu.add_machine_frame_notifier(function()
  sample()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then E("ERROR %s", tostring(err)); tap:close(); ev:close(); M:exit() end
  end
end)
E("installed; dead flag at 0x%08X", DEAD)
