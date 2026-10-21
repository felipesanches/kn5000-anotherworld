-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_fwlcd.lua -- while the game runs, when and where does the firmware draw on the LCD? (probes/cnv/
-- README.md, "Speed"). The game paints the black border around its window on every blit because the
-- firmware "repaints the frame now and then"; a blit that writes only what changed needs to know what the
-- firmware draws, after which events, and where, to find out when the picture has been damaged.
--
-- Starts the game as a player does (DISK MENU, STYLE CONVERT, OK on KN7LOAD.CNV), with the intro at tick 0
-- (NO_SPLASH). From the first VM frame on, a write tap over the LCD frame 0x9CE00000-0x9CE4AFFF counts every
-- store from outside KN7APP.BIN's image (the firmware, the loader), per window: 10 s with no input, then
-- each panel button below pressed once (0.4 s) and the 4 s after it, a keybed key, 10 s with no input, and
-- last DISPLAY HOLD (twice) and EXIT (twice). AWL_INTRO=1 instead lets the intro run with no input into the
-- lake, one window per 200 VM ticks to tick 2800 (the intro ends at tick 2612 and loads the lake). For each window:
-- the stores, the rectangle they covered, the converter calls meanwhile and the PCs that stored; a
-- snapshot 1 s after each press. Printed as "awlcd: ..." lines and written to AWL_OUT/fwlcd.txt.
--   probes/cnv/run_perf.sh OUT probes/cnv/awcnv_fwlcd.lua
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local OUT = os.getenv("AWL_OUT") or "."
local CV = 0x502DF000
local FRAME_NO, NO_SPLASH = 0x502E3000 + 0x7C, 0x502E3000 + 0x58
local CODE_LO, CODE_HI = 0x502BA000, 0x502C8000
local FB, FB_END = 0x9CE00000, 0x9CE00000 + 640 * 240 * 2
local function now() return M.time:as_double() end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEY = {}
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do KEY[f.name] = f end end
end
local W = nil                         -- the current window's record
local function newwin(name)
  W = { name = name, n = 0, pcs = {}, x0 = 9999, x1 = -1, y0 = 9999, y1 = -1, calls0 = sp:read_u32(CV + 0x10), t0 = now() }
end
AWL_TAP = sp:install_write_tap(FB, FB_END - 1, "awl_lcdw", function(offset, data, mask)
  if not W then return end
  local p = cpu.state["PC"].value
  if p >= CODE_LO and p < CODE_HI then return end
  W.n = W.n + 1
  W.pcs[p] = (W.pcs[p] or 0) + 1
  local px = (offset - FB) // 2
  local x, y = px % 640, px // 640
  if x < W.x0 then W.x0 = x end; if x + 1 > W.x1 then W.x1 = x + 1 end
  if y < W.y0 then W.y0 = y end; if y > W.y1 then W.y1 = y end
end)
local outf = io.open(OUT .. "/fwlcd.txt", "w")
local function endwin()
  local pcs = {}
  for p, c in pairs(W.pcs) do pcs[#pcs + 1] = { p, c } end
  table.sort(pcs, function(a, b) return a[2] > b[2] end)
  local top = {}
  for i = 1, math.min(6, #pcs) do top[#top + 1] = string.format("%08X:%d", pcs[i][1], pcs[i][2]) end
  local s = string.format("%-28s %5.1f s: %7d firmware stores, x %d-%d y %d-%d, converter calls %d; pcs %s", W.name,
    now() - W.t0, W.n, W.n > 0 and W.x0 or 0, W.n > 0 and W.x1 or 0, W.n > 0 and W.y0 or 0, W.n > 0 and W.y1 or 0,
    sp:read_u32(CV + 0x10) - W.calls0, table.concat(top, " "))
  print("awlcd: " .. s); outf:write(s .. "\n"); outf:flush()
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local PRESSES = {
  { "R1/R2 OCTAVE +", "CPR_SEG6", 0x02 }, { "R1/R2 OCTAVE -", "CPR_SEG7", 0x02 },
  { "SUSTAIN", "CPR_SEG5", 0x08 }, { "SUSTAIN again", "CPR_SEG5", 0x08 },
  { "PART SELECT RIGHT 1", "CPR_SEG1", 0x02 }, { "PART SELECT LEFT", "CPR_SEG2", 0x01 },
  { "PAGE UP", "CPC_SEG11", 0x10 }, { "PAGE UP again", "CPC_SEG11", 0x10 }, { "PAGE DOWN", "CPC_SEG11", 0x20 },
  { "HELP", "CPC_SEG5", 0x02 }, { "EXIT (leaves the help)", "CPC_SEG11", 0x80 },
  { "OTHER PART & FR", "CPC_SEG5", 0x01 },
}
-- last: DISPLAY HOLD, which in the first run (2026-10-20) made the firmware repaint the whole screen and stop
-- calling the converter; then whether a second press or EXIT brings the calls back. AWL_HOLD_EARLY=1 presses
-- it where that first run did, right after PART SELECT LEFT (in the intro).
local LAST = {
  { "DISPLAY HOLD", "CPC_SEG11", 0x40 }, { "DISPLAY HOLD again", "CPC_SEG11", 0x40 },
  { "EXIT", "CPC_SEG11", 0x80 }, { "EXIT again", "CPC_SEG11", 0x80 },
}
if os.getenv("AWL_HOLD_EARLY") then
  table.insert(PRESSES, 7, LAST[2]); table.insert(PRESSES, 7, LAST[1])
end
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  press("CPR_SEG6", 0x01)             -- OK
  wait_until(function() return sp:read_u32(CV) >= 2 end, 60)
  sp:write_u32(NO_SPLASH, 0x5EED0FF0)
  newwin("loader to first frame")
  wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > 0 end, 120)
  endwin()
  if os.getenv("AWL_INTRO") then
    for t = 200, 2800, 200 do
      newwin(string.format("ticks to %d", t))
      wait_until(function() return (sp:read_u32(FRAME_NO) & 0xffff) > t end, 600)
      endwin()
    end
    outf:close()
    M:exit()
    while true do coroutine.yield() end
  end
  newwin("first 5 s of the intro"); wait(5); endwin()
  newwin("10 s, no input"); wait(10); endwin()
  for _, b in ipairs(PRESSES) do
    newwin(b[1])
    press(b[2], b[3]); wait(1); M.video:snapshot(); wait(3)
    endwin()
  end
  newwin("keybed C6"); local f = KEY["C6"]; f:set_value(1); wait(0.4); f:set_value(0); wait(4); endwin()
  newwin("10 s, no input"); wait(10); endwin()
  for _, b in ipairs(LAST) do
    newwin(b[1])
    press(b[2], b[3]); wait(1); M.video:snapshot(); wait(3)
    endwin()
  end
  outf:close()
  M:exit()
  while true do coroutine.yield() end
end)
AWL_FRAME = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awlcd: ERROR " .. tostring(err)); M:exit() end
  end
end)
