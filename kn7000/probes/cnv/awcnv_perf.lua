-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_perf.lua -- where do the KN7APP.BIN build's memory accesses go, frame by frame? (probes/cnv/README.md,
-- "Speed"). MAME has no wait states, so it cannot show the instrument's slowness; it can count what the
-- game reads and writes in each region, which is what the wait states multiply.
--
-- Starts the game as a player does (DISK MENU, STYLE CONVERT, OK on KN7LOAD.CNV), with the intro at tick 0
-- (NO_SPLASH, as awcnv_cksum.lua), and from tick AWP_FROM to AWP_MAX counts, per VM tick (between two writes
-- of FRAME_NO), every access the game's code makes (PC in KN7APP.BIN's image 0x502BA000-0x502BFFFF):
--   lcd_w16 / lcd_w32 / lcd_w8   stores into the LCD frame 0x9CE00000-0x9CE4AFFF, by size
--   lcd_r                        loads from it
--   page_r / page_w              loads / stores in the four VM pages and what follows them (the blit's
--                                shadow): 0x50320000-0x5036FFFF
--   data_r / data_w              loads / stores in the rest of the game's RAM 0x502C8000-0x5031AFFF (VM
--                                state, help buffer, the part's bytecode and polygons)
-- and, from any other PC, fw_lcd_w: the firmware's (or the loader's) stores into the LCD frame, with the
-- PCs and the rectangle they covered (perf_fw.txt). Also per tick: the emulated time it took (dt_ms) and
-- the converter calls the firmware made meanwhile.
-- Output in AWP_OUT: perf.tsv (one line per tick), perf_fw.txt; and the means over the ticks printed as
-- "awperf: ..." lines.
--   probes/cnv/run_perf.sh OUT probes/cnv/awcnv_perf.lua      (env AWP_FROM, default 1; AWP_MAX, default 400)
-- Addresses: src/platformcnv.inc, src/vm.inc, src/cnv_main.s.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local OUT = os.getenv("AWP_OUT") or "."
local FROM = tonumber(os.getenv("AWP_FROM") or "1")
local MAXTICK = tonumber(os.getenv("AWP_MAX") or "400")
local CV = 0x502DF000
local FRAME_NO, NO_SPLASH = 0x502E3000 + 0x7C, 0x502E3000 + 0x58
local CODE_LO, CODE_HI = 0x502BA000, 0x502C8000
local FB, FB_END = 0x9CE00000, 0x9CE00000 + 640 * 240 * 2
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = {
  { 30, "CPR_SEG1", 0x04, "DISK MENU" },
  { 36, "CPL_SEG0", 0x20, "STYLE CONVERT" },
  { 44, "CPR_SEG6", 0x01, "OK (KN7LOAD.CNV)" },
}
local COLS = { "lcd_w16", "lcd_w32", "lcd_w8", "lcd_r", "page_r", "page_w", "data_r", "data_w", "fw_lcd_w", "calls", "dt_ms" }
local C = {}
local function zero() for _, k in ipairs(COLS) do C[k] = 0 end end
zero()
local SUM, MAX, N = {}, {}, 0
for _, k in ipairs(COLS) do SUM[k] = 0; MAX[k] = 0 end
local FWPC = {}
local on, finish, nosplash = false, false, false
local function pc() return cpu.state["PC"].value end
local function game() local p = pc(); return p >= CODE_LO and p < CODE_HI end

AWP_TAPS = {
  sp:install_write_tap(FB, FB_END - 1, "awp_lcdw", function(offset, data, mask)
    if not on then return end
    local p = pc()
    if p >= CODE_LO and p < CODE_HI then
      if mask == 0xffffffff then C.lcd_w32 = C.lcd_w32 + 1
      elseif mask == 0xffff or mask == 0xffff0000 then C.lcd_w16 = C.lcd_w16 + 1
      else C.lcd_w8 = C.lcd_w8 + 1 end
    else
      C.fw_lcd_w = C.fw_lcd_w + 1
      local px = (offset - FB) // 2
      local x, y = px % 640, px // 640
      local r = FWPC[p]
      if not r then r = { n = 0, x0 = x, x1 = x, y0 = y, y1 = y }; FWPC[p] = r end
      r.n = r.n + 1
      if x < r.x0 then r.x0 = x end; if x > r.x1 then r.x1 = x end
      if y < r.y0 then r.y0 = y end; if y > r.y1 then r.y1 = y end
    end
  end),
  sp:install_read_tap(FB, FB_END - 1, "awp_lcdr", function(offset, data, mask)
    if on and game() then C.lcd_r = C.lcd_r + 1 end
  end),
  sp:install_read_tap(0x50320000, 0x5036FFFF, "awp_pager", function(offset, data, mask)
    if on and game() then C.page_r = C.page_r + 1 end
  end),
  sp:install_write_tap(0x50320000, 0x5036FFFF, "awp_pagew", function(offset, data, mask)
    if on and game() then C.page_w = C.page_w + 1 end
  end),
  sp:install_read_tap(0x502C8000, 0x5031AFFF, "awp_datar", function(offset, data, mask)
    if on and game() then C.data_r = C.data_r + 1 end
  end),
  sp:install_write_tap(0x502C8000, 0x5031AFFF, "awp_dataw", function(offset, data, mask)
    if on and game() then C.data_w = C.data_w + 1 end
  end),
}

local tsv = io.open(OUT .. "/perf.tsv", "w")
tsv:write("tick\tt\t" .. table.concat(COLS, "\t") .. "\n")
local t_last, calls_last = nil, 0
AWP_FRAME = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awp_frame", function(offset, data, mask)
  if finish or offset ~= FRAME_NO then return end
  local v = data & 0xffff
  if v == 0 then return end
  local tick = v - 1                  -- the tick that has just ended
  local t = M.time:as_double()
  local calls = sp:read_u32(CV + 0x10)
  if on and t_last then
    C.dt_ms = (t - t_last) * 1000
    C.calls = calls - calls_last
    local row = { tostring(tick), string.format("%.4f", t) }
    for _, k in ipairs(COLS) do
      row[#row + 1] = k == "dt_ms" and string.format("%.2f", C.dt_ms) or tostring(C[k])
      SUM[k] = SUM[k] + C[k]; if C[k] > MAX[k] then MAX[k] = C[k] end
    end
    N = N + 1
    tsv:write(table.concat(row, "\t") .. "\n")
  end
  zero()
  t_last, calls_last = t, calls
  on = tick + 1 >= FROM
  if tick >= MAXTICK then
    finish = true
    tsv:close()
    local f = io.open(OUT .. "/perf_fw.txt", "w")
    f:write("# pc writes x0 x1 y0 y1 (stores into the LCD frame from outside KN7APP.BIN, ticks " .. FROM .. "-" .. MAXTICK .. ")\n")
    local ks = {}
    for k in pairs(FWPC) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do local r = FWPC[k]; f:write(string.format("%08X %d %d %d %d %d\n", k, r.n, r.x0, r.x1, r.y0, r.y1)) end
    f:close()
    print(string.format("awperf: KN7APP.BIN %s; ticks %d-%d (%d frames), emulated %.1f s", os.getenv("AWP_TAG") or "", FROM, tick, N, t))
    local mean, mx = {}, {}
    for _, k in ipairs(COLS) do
      mean[#mean + 1] = string.format("%s %.1f", k, SUM[k] / math.max(N, 1))
      mx[#mx + 1] = string.format("%s %s", k, k == "dt_ms" and string.format("%.1f", MAX[k]) or tostring(MAX[k]))
    end
    print("awperf: mean per tick: " .. table.concat(mean, ", "))
    print("awperf: max per tick:  " .. table.concat(mx, ", "))
  end
end)

local step = 1
AWP_TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then press(s[2], s[3], 0); print("awperf: pressed " .. s[4]); step = step + 1 end
  if not nosplash and sp:read_u32(CV) >= 2 then sp:write_u32(NO_SPLASH, 0x5EED0FF0); nosplash = true end
  if finish then M:exit() end
end)
