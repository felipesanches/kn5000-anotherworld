-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_panelsettings.lua -- which panel buttons change the instrument's live settings while AW.CNV
-- parks the firmware? (probes/cnv/README.md)
--
-- Question: the acceptance session found one byte of IC23's header (the live panel settings,
-- 0x84000000-0x840007A3) changed by the game's panel controls (header offset 0xCE, bit 0x08), so the
-- POWER OFF that followed saved it. Which button does it, and which buttons are free of that? Runs
-- AW.CNV (DISK MENU > STYLE CONVERT > OK, pressed again until the converter loads), waits for the
-- game, then presses each button below once (0.4 s, then 2 s), and prints the header bytes each
-- press changed: "PRESS <name>: n bytes  off:old->new ...". Nothing is saved: it exits without
-- POWER OFF.
--   kn7000 kn7000 -bios v13 -flop build/another_floppy.img -harddisk SD.img -nvram_directory NV \
--     -autoboot_script probes/cnv/awcnv_panelsettings.lua -window -nothrottle
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local CV, MISC = 0x502C0000, 0x502C4000
local BUTTONS = {   -- name, port, mask: the game's five, twice each, then candidates for a free fire
  { "PART SELECT RIGHT 1 (game RIGHT)", "CPR_SEG1", 0x02 }, { "PART SELECT LEFT (game LEFT)", "CPR_SEG2", 0x01 },
  { "R1/R2 OCTAVE + (game UP)", "CPR_SEG6", 0x02 }, { "R1/R2 OCTAVE - (game DOWN)", "CPR_SEG7", 0x02 },
  { "SUSTAIN (game FIRE)", "CPR_SEG5", 0x08 }, { "SUSTAIN (game FIRE), again", "CPR_SEG5", 0x08 },
  { "PART SELECT RIGHT 1, again", "CPR_SEG1", 0x02 }, { "PART SELECT LEFT, again", "CPR_SEG2", 0x01 },
  { "R1/R2 OCTAVE +, again", "CPR_SEG6", 0x02 }, { "R1/R2 OCTAVE -, again", "CPR_SEG7", 0x02 },
  { "PART SELECT RIGHT 2", "CPR_SEG2", 0x02 }, { "PART SELECT RIGHT 2, again", "CPR_SEG2", 0x02 },
  { "DISPLAY HOLD", "CPC_SEG11", 0x40 }, { "DISPLAY HOLD, again", "CPC_SEG11", 0x40 },
}
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local function now() return M.time:as_double() end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local function header() return sp:read_range(0x84000000, 0x840007A3, 8) end
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)
  press("CPL_SEG0", 0x20); wait(8)
  for _ = 1, 8 do
    press("CPR_SEG6", 0x01)
    if wait_until(function() return sp:read_u32(CV + 0x10) > 0 end, 6) then break end
  end
  local ok = wait_until(function() return sp:read_u32(CV) == 3 and (sp:read_u32(MISC + 0x7C) & 0xffff) > 60 end, 180)
  print(string.format("PANELSET game running: %s (t=%.0f s)", tostring(ok), now()))
  for _, b in ipairs(BUTTONS) do
    local h0 = header()
    press(b[2], b[3]); wait(2)
    local h1, d = header(), {}
    for i = 1, #h0 do
      if h0:byte(i) ~= h1:byte(i) then d[#d + 1] = string.format("%03X:%02X->%02X", i - 1, h0:byte(i), h1:byte(i)) end
    end
    print(string.format("PRESS %-34s %d bytes  %s", b[1] .. ":", #d, table.concat(d, " ")))
  end
  M.video:snapshot()
  M:exit()
end)
PANELSET = emu.register_periodic(function() if coroutine.status(co) ~= "dead" then
  local okc, err = coroutine.resume(co); if not okc then print("PANELSET ERROR " .. tostring(err)); M:exit() end end end)
