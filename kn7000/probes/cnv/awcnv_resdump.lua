-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_resdump.lua -- what did AW.CNV's loader leave in RAM? Starts the game through DISK MENU >
-- STYLE CONVERT > OK, waits for AW_LOADED_FLAG (0x44080020 = 0x600D), prints the loader's
-- counters, dumps the resource region (RES_BASE 0x44200000, RES_LEN bytes) and the font and string
-- tables into AWDUMP_DIR, then exits. resverify.py compares the dumps with the SD build's files.
--
--   AWDUMP_DIR=DIR RES_LEN=0x1A6748 kn7000 kn7000 -rompath ROMS -flop build/another_floppy.img \
--     -harddisk SD.img -autoboot_script probes/cnv/awcnv_resdump.lua -window -nothrottle
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local DIR = os.getenv("AWDUMP_DIR") or "build"
local RES_LEN = tonumber(os.getenv("RES_LEN") or "0x1A6748")
local function set(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = { { 30, "CPR_SEG1", 0x04 }, { 36, "CPL_SEG0", 0x20 }, { 44, "CPR_SEG6", 0x01 } }
local function dump(name, a, n)
  local f, t = io.open(DIR .. "/" .. name, "wb"), {}
  for i = 0, n - 1, 4 do
    t[#t + 1] = string.pack("<I4", sp:read_u32(a + i))
    if #t == 4096 then f:write(table.concat(t)); t = {} end
  end
  f:write(table.concat(t)); f:close()
end
local step, done = 1, false
AWCNV_DUMP = emu.register_periodic(function()
  local t, s = M.time:as_double(), STEPS[step]
  if s and t > s[1] then set(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + 0.4 then set(s[2], s[3], 0); step = step + 1 end
  if not done and sp:read_u32(0x44080020) == 0x600D then
    done = true
    print(string.format("awcnv_resdump: loaded at t=%.1f s; errors=%d load=%d ms", t,
      sp:read_u32(0x502E0014), sp:read_u32(0x502E0018)))
    dump("ram_res.bin", 0x44200000, RES_LEN)
    dump("ram_font.bin", 0x44480000, 768)
    dump("ram_stridx.bin", 0x44490000, 2048)
    dump("ram_strdat.bin", 0x444A0000, 4096)
    print("awcnv_resdump: dumped to " .. DIR); M:exit()
  end
  if t > 400 then print("awcnv_resdump: not loaded by t=400 s"); M:exit() end
end)
