-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_cksum.lua -- the STYLE CONVERT (.CNV) build's per-frame front pages, for the same
-- pixel-exact comparison against rustyworld as ../awcksum.lua (which starts the SP7001 build).
--
-- Starts the game the way a player does on a stock KN7000 (program 941): DISK MENU, STYLE CONVERT,
-- OK on AW.CNV (the floppy in the drive from boot). Then, exactly like awcksum.lua, a write tap on
-- FRAME_NO (0x4408007C) captures the displayed page (CUR_PAGE_2) at every VM tick into AWCK_BIN,
-- with "tick frontaddr" lines in AWCK_IDX; probes/cksum_pages.py and probes/compare_frames.py turn
-- them into the comparison. The splash is skipped (NO_SPLASH) as the reference logs start at the
-- intro. Also prints the loader's result (errors, load time, task id) when the first frame comes.
--
--   kn7000 kn7000 -rompath ROMS -flop build/another_floppy.img -harddisk SD.img \
--     -autoboot_script probes/cnv/awcnv_cksum.lua -window -nothrottle
-- env: AWCK_BIN, AWCK_IDX, AWCK_MAX (last tick, default 2612)
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = {                     -- {time, port, mask, what}
  { 30, "CPR_SEG1", 0x04, "DISK MENU" },
  { 36, "CPL_SEG0", 0x20, "STYLE CONVERT" },
  { 44, "CPR_SEG6", 0x01, "OK (AW.CNV)" },
}
local CUR_PAGE_2, FRAME_NO = 0x4407100C, 0x4408007C
local OUTBIN = os.getenv("AWCK_BIN") or "build/cnv_pages.bin"
local OUTIDX = os.getenv("AWCK_IDX") or "build/cnv_pages.idx"
local MAXTICK = tonumber(os.getenv("AWCK_MAX") or "2612")
local binf, idxf = io.open(OUTBIN, "wb"), io.open(OUTIDX, "w")
local captured, finish, told = 0, false, false
sp:write_u32(0x44080058, 0x5EED0FF0)   -- NO_SPLASH: start at the intro, like the reference

AWCNV_TAP = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awframe", function(offset, data, mask)
  if finish or offset ~= FRAME_NO then return end
  local v = data & 0xffff
  if v == 0 then return end
  local tick = v - 1
  if not told then
    told = true
    print(string.format("awcnv: first frame at t=%.1f s; loader errors=%d load=%d ms task=%d",
      M.time:as_double(), sp:read_u32(0x502E0014), sp:read_u32(0x502E0018), sp:read_u32(0x502E001C)))
  end
  local front = sp:read_u32(CUR_PAGE_2)
  binf:write(sp:read_range(front, front + 63999, 8))
  idxf:write(string.format("%d %08X\n", tick, front))
  captured = captured + 1
  if tick >= MAXTICK then
    finish = true
    binf:close(); idxf:close()
    print(string.format("awcnv: captured %d frames (last tick %d); exiting", captured, tick))
  end
end)

local step = 1
AWCNV_TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then press(s[2], s[3], 0); print("awcnv: pressed " .. s[4]); step = step + 1 end
  if finish then M:exit() end
end)
