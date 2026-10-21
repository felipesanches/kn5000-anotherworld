-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_speed.lua -- the run the owner makes on the instrument (README-CNV.md, "Speed"), in MAME: what do
-- the overlay, the speed page and AWPERF0.TXT show, and what does the game measure in MAME's own time?
--
-- Starts the game as a player does (DISK MENU, STYLE CONVERT, OK on KN7LOAD.CNV), lets the splash and the
-- intro play with no input, and then, with the intro at frame AWS_AT (default 300):
--   PAGE UP (the overlay on), AWS_HOLD seconds (default 12), a snapshot;
--   PAGE DOWN (the old blit), AWS_HOLD seconds, a snapshot; PAGE DOWN (the new blit again), AWS_HOLD seconds;
--   HELP, PAGE DOWN three times (the speed page), a snapshot, EXIT;
--   hold EXIT 2 s (quit: the game writes AWPERF0.TXT), EXIT, NO (right button 4), and the end.
-- Prints "awspeed: ..." lines: the overlay's figures each time (read from RAM: vm.inc PF_SHOW), the
-- benchmark, the bus registers, and how the report went. run_perf.sh copies AWPERF*.TXT off the card.
--   probes/cnv/run_perf.sh OUT probes/cnv/awcnv_speed.lua
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("AWS_AT") or "300")
local HOLD = tonumber(os.getenv("AWS_HOLD") or "12")
local CV = 0x502DF000
local PART, FRAME_NO = 0x502E1000 + 0x102A, 0x502E3000 + 0x7C
local PERF = 0x502E6000
local PF_MODE, PF_SHOW, PF_BENCH, PF_REGS = PERF + 0x80, PERF + 0xC0, PERF + 0x100, PERF + 0x140
local function now() return M.time:as_double() end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(c, s) local t = now() + s; while now() < t do if c() then return true end; coroutine.yield() end; return c() end
local function press(tag, mask, hold) local f = field(tag, mask); f:set_value(1); wait(hold or 0.4); f:set_value(0) end
local function frame() return sp:read_u32(FRAME_NO) & 0xffff end
local function show(what)
  local v = {}
  for i = 0, 13 do v[i] = sp:read_u32(PF_SHOW + 4 * i) end
  print(string.format("awspeed: %s (blit mode %d): fps %.1f, frame %.1f ms, longest %.1f, LCD pixels %d, yield asked %.1f; ms per frame: VM %.1f, polygons %.1f, page ops %.1f, blit %.1f, border %.1f, yield %.1f; load %.1f, pause %.1f ms in the window",
    what, sp:read_u32(PF_MODE), v[0] / 10, v[1] / 10, v[2] / 10, v[3], v[4] / 10, v[5] / 10, v[6] / 10, v[7] / 10, v[8] / 10, v[9] / 10, v[10] / 10, v[11] / 10, v[12] / 10))
end
local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)    -- DISK MENU
  press("CPL_SEG0", 0x20); wait(8)    -- STYLE CONVERT
  for i = 1, 6 do                     -- OK, until the loader runs
    press("CPR_SEG6", 0x01)
    if wait_until(function() return sp:read_u32(CV) >= 1 end, 6) then break end
  end
  wait_until(function() return sp:read_u16(PART) == 0x3E81 and frame() >= AT end, 600)
  local bn = {}
  for i = 0, 8 do bn[#bn + 1] = string.format("%.1f", sp:read_u32(PF_BENCH + 4 * i) / 10) end
  print("awspeed: benchmark, ns per access (ALU LCDw16 LCDw32 LCDr16 RAMw8 RAMw32 RAMr8 RAMr32 UNCr32): " .. table.concat(bn, " "))
  local rg = {}
  for i = 0, 13 do rg[#rg + 1] = string.format("%X", sp:read_u32(PF_REGS + 4 * i)) end
  print("awspeed: registers (MEMCTR0-7, 40, 42, CHCTR, TM4MD, TM4BR, build): " .. table.concat(rg, " "))
  press("CPC_SEG11", 0x10); wait(HOLD); show("new blit, overlay on"); M.video:snapshot()
  press("CPC_SEG11", 0x20); wait(HOLD); show("old blit"); M.video:snapshot()
  press("CPC_SEG11", 0x20); wait(HOLD); show("new blit again")
  press("CPC_SEG5", 0x02); wait(2)                                   -- HELP
  for i = 1, 3 do press("CPC_SEG11", 0x20); wait(1.5) end           -- the speed page
  M.video:snapshot()
  press("CPC_SEG11", 0x80); wait(3)                                  -- EXIT
  press("CPC_SEG11", 0x80, 2.0)                                      -- quit
  wait_until(function() return sp:read_u32(CV + 0x30) == 1 end, 20)  -- CV_ENDED: the report is written
  print(string.format("awspeed: report: state %d (1 written), AWPERF%d.TXT, %d bytes", sp:read_u32(CV + 0x34),
    sp:read_u32(CV + 0x3C), sp:read_u32(CV + 0x38)))
  wait(4); press("CPC_SEG11", 0x80); wait(4)                         -- EXIT: Continue Next?
  press("CPR_SEG6", 0x01); wait(4)                                   -- NO
  M:exit()
  while true do coroutine.yield() end
end)
AWS_FRAME = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("awspeed: ERROR " .. tostring(err)); M:exit() end
  end
end)
