-- awloadtime.lua -- where does the startup load time go: per-file overhead or data rate?
--
-- Logs the emulated time at which each fread starts landing data in the staging buffer
-- (the first write to STAGING_BIG, 0x50200000, after the previous file), from SD CARD LOAD (11 s) until
-- AW_LOADED_FLAG is set. LoadGameData reads, in order: the font (768 B), the string index
-- (2048 B), the string data (4096 B), then the packs AWP00..AWPxx. awloadtime_fit.py fits
-- seconds-per-file = overhead + bytes / rate; the three small files pin the overhead.
--   LT_OUT=~/compartilhado/tmp/loadtime.txt ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets \
--     -skip_gameinfo -window kn7000 -bios sp7001 -harddisk build/another_sd.img \
--     -autoboot_script probes/awloadtime.lua -str 90
--   python3 -I probes/awloadtime_fit.py ~/compartilhado/tmp/loadtime.txt build/res
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local OUT=io.open(os.getenv("LT_OUT"),"w")
local STAGING=0x50200000
local last=-1
AWLT_TAP=sp:install_write_tap(STAGING,STAGING+3,"awlt",function(o,d,m)
  local t=M.time:as_double()
  if t<11 then return end            -- the firmware's own boot-time use of that RAM
  if t-last>0.002 then OUT:write(string.format("%.6f\n",t)) end   -- one line per fread
  last=t end)
local SD; do local p=M.ioport.ports[":cpanel:CPR_SEG1"]; for _,f in pairs(p.fields) do if f.name=="SD CARD LOAD (SW7)" then SD=f end end end
local tflag=nil
emu.register_periodic(function() local t=M.time:as_double(); SD:set_value((t>11 and t<11.4) and 1 or 0)
  if not tflag and sp:read_u32(0x44080020)==0x600D then tflag=t; OUT:write(string.format("%.6f done\n",t)) end
  if (tflag and t>tflag+0.2) or t>80 then OUT:close(); M:exit() end end)
