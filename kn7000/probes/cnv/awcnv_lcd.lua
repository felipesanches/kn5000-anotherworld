-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_lcd.lua -- does the LCD show exactly what it showed before the blit wrote only what changed?
-- (probes/cnv/README.md, "Speed"). awcnv_cksum.lua checks the VM's pages; this checks the LCD frame itself.
--
-- Starts the game as a player does (DISK MENU, STYLE CONVERT, OK on KN7LOAD.CNV), with the intro at tick 0
-- (NO_SPLASH), and lets it run with no input: the intro, then (it loads the lake by itself) the lake. At
-- every VM tick, when FRAME_NO is written (NextThread, just after the end-of-frame blit of the front page),
-- it reads the whole LCD frame (640x240 RGB565 at 0x9CE00000) and checks it against what the old blit made
-- of the same VM state: the 20-row bands and 160-pixel strips black, and every pixel of the window
-- palette[page[y * 320 + x] & 15] with page = CUR_PAGE_2 and palette the game's 16 RGB565 entries (the
-- `palette` label of the build, AWL_PAL from its map). At the ticks in AWL_SNAPS (default every 100th,
-- and the last) it also writes the frame to AWL_OUT/lcd_TTTT.bin, for a byte comparison between two
-- builds (cmp). Prints "awlcd: ..." lines: the ticks checked, the ticks and pixels that differ (and the
-- first few), and the snapshots written.
--   AWL_PAL=0x$(grep ' palette$' build/kn7app.map | cut -c3-10) probes/cnv/run_perf.sh OUT probes/cnv/awcnv_lcd.lua
-- env: AWL_PAL (required), AWL_MAX (last tick, default 3600), AWL_SNAPS ("all", "none" or the step, default 100),
-- AWL_TRACE ("FIRST-LAST": for those ticks, a line each with the firmware's LCD stores since the last tick,
-- the full repaints, the sentinel repaints and PF_DAMAGE so far (vm.inc VM_PERF_BASE; the new build only)
-- and the part resident; and for every tick, a line whenever the firmware stored into the LCD frame).
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local OUT = os.getenv("AWL_OUT") or "."
local PAL = tonumber(os.getenv("AWL_PAL") or "")
local MAXTICK = tonumber(os.getenv("AWL_MAX") or "3600")
local SNAPS = os.getenv("AWL_SNAPS") or "100"
local CV = 0x502C0000
local CUR_PAGE_2, FRAME_NO, NO_SPLASH, PART = 0x502C2000 + 0x100C, 0x502C4000 + 0x7C, 0x502C4000 + 0x58, 0x502C2000 + 0x102A
local FB, W, H, X0, Y0 = 0x9CE00000, 640, 240, 160, 20
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = {
  { 30, "CPR_SEG1", 0x04, "DISK MENU" },
  { 36, "CPL_SEG0", 0x20, "STYLE CONVERT" },
  { 44, "CPR_SEG6", 0x01, "OK (KN7LOAD.CNV)" },
}
if not PAL then print("awlcd: AWL_PAL (the build's palette label) is required"); M:exit() end
local ZROW = string.rep("\0", W * 2)
local ZSTRIP = string.rep("\0", X0 * 2)
local checked, badticks, badpx, firstbad, snaps, finish, nosplash = 0, 0, 0, {}, 0, false, false
local TR = os.getenv("AWL_TRACE")
local TR0, TR1 = 1, 0
if TR then TR0, TR1 = TR:match("(%d+)-(%d+)"); TR0, TR1 = tonumber(TR0), tonumber(TR1) end
local fwst, fwpc = 0, {}
local cpu = M.devices[":maincpu"]
AWL_FW = sp:install_write_tap(FB, FB + W * H * 2 - 1, "awl_fw", function(offset, data, mask)
  local p = cpu.state["PC"].value
  if p < 0x502BA000 or p >= 0x502C0000 then fwst = fwst + 1; fwpc[p] = true end
end)
local PERF = 0x502C7000
local parts = {}
local function check(tick)
  local pal = {}
  for i = 0, 15 do
    local v = sp:read_u16(PAL + 2 * i)
    pal[i] = string.char(v & 0xff, v >> 8)
  end
  local page = sp:read_u32(CUR_PAGE_2)
  local lcd = sp:read_range(FB, FB + W * H * 2 - 1, 8)
  local pix = sp:read_range(page, page + 320 * 200 - 1, 8)
  local bad = 0
  for y = 0, H - 1 do
    local row = lcd:sub(y * W * 2 + 1, (y + 1) * W * 2)
    local want
    if y < Y0 or y >= Y0 + 200 then
      want = ZROW
    else
      local t = { ZSTRIP }
      local base = (y - Y0) * 320
      for x = 1, 320 do t[#t + 1] = pal[pix:byte(base + x) & 15] end
      t[#t + 1] = ZSTRIP
      want = table.concat(t)
    end
    if row ~= want then
      for x = 0, W - 1 do
        if row:sub(2 * x + 1, 2 * x + 2) ~= want:sub(2 * x + 1, 2 * x + 2) then
          bad = bad + 1
          if #firstbad < 8 then firstbad[#firstbad + 1] = string.format("tick %d (%d,%d)", tick, x, y) end
        end
      end
    end
  end
  checked = checked + 1
  if bad > 0 then badticks = badticks + 1; badpx = badpx + bad end
  local snap = SNAPS == "all" or (SNAPS ~= "none" and tick % tonumber(SNAPS) == 0) or tick == MAXTICK
  if snap then
    local f = io.open(string.format("%s/lcd_%04d.bin", OUT, tick), "wb"); f:write(lcd); f:close()
    snaps = snaps + 1
  end
end

AWL_TAP = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awl_frame", function(offset, data, mask)
  if finish or offset ~= FRAME_NO then return end
  local v = data & 0xffff
  if v == 0 then return end
  local tick = v - 1
  parts[sp:read_u16(PART)] = true
  local bad0 = badpx
  check(tick)
  if (tick >= TR0 and tick <= TR1) or fwst > 0 then
    local pcs = {}
    for k in pairs(fwpc) do pcs[#pcs + 1] = string.format("%08X", k) end
    print(string.format("awlcd: tick %d: firmware LCD stores %d (%s), repaints %d, sentinel %d, damage %X, resident %04X, bad pixels %d",
      tick, fwst, table.concat(pcs, " "), sp:read_u32(PERF + 0x30), sp:read_u32(PERF + 0x34), sp:read_u32(PERF + 0x20),
      sp:read_u32(CV + 0x44), badpx - bad0))
  end
  fwst, fwpc = 0, {}
  if tick >= MAXTICK then
    finish = true
    local pl = {}
    for p in pairs(parts) do pl[#pl + 1] = string.format("%04X", p) end
    table.sort(pl)
    print(string.format("awlcd: ticks 0-%d: %d checked, %d differ from the old blit's picture (%d pixels)%s; parts %s; %d snapshots in %s",
      tick, checked, badticks, badpx, #firstbad > 0 and (": " .. table.concat(firstbad, ", ")) or "", table.concat(pl, " "), snaps, OUT))
  end
end)

local step = 1
AWL_TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then press(s[2], s[3], 0); print("awlcd: pressed " .. s[4]); step = step + 1 end
  if not nosplash and sp:read_u32(CV) >= 2 then sp:write_u32(NO_SPLASH, 0x5EED0FF0); nosplash = true end
  if finish then M:exit() end
end)
