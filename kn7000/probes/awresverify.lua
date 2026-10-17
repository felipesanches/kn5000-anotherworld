-- awresverify.lua -- is every Another World resource resident, byte-exact, where the tables say?
--
-- Presses SD CARD LOAD, times the load (SD CARD LOAD press -> AW_LOADED_FLAG = 0x600D written),
-- then reads the module's own ResAddr/ResSize tables (addresses from build/another.map) and dumps
-- every resource's bytes from emulated RAM to AWRV_OUT/resource-0xNN.bin, plus a table
-- AWRV_OUT/resident.tsv (id, address, size). probes/awresverify.py compares them with the
-- unpacked originals in build/res/.
--   AWRV_OUT=~/compartilhado/tmp/awrv ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets \
--     -skip_gameinfo -window kn7000 -bios sp7001 -harddisk build/another_sd.img \
--     -autoboot_script probes/awresverify.lua -str 60
--   python3 -I probes/awresverify.py ~/compartilhado/tmp/awrv build/res
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local OUT=os.getenv("AWRV_OUT"); local MAP=os.getenv("AWRV_MAP") or "build/another.map"
local sym={}
for l in io.lines(MAP) do local a,n=l:match("^0x(%x+)%s+(%S+)"); if a then sym[n]=tonumber(a,16) end end
local RES_ADDR, RES_SIZE = sym["ResAddr"], sym["ResSize"]
local FLAG=0x44080020
local tPress, tLoaded
AWRV_FLAG = sp:install_write_tap(FLAG, FLAG+3, "awrv_flag", function(o,d,m)
  if d == 0x600D and not tLoaded then tLoaded = M.time:as_double() end end)
local SD; do local p=M.ioport.ports[":cpanel:CPR_SEG1"]; for _,f in pairs(p.fields) do if f.name=="SD CARD LOAD (SW7)" then SD=f end end end
local done=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not tPress and t>11 then SD:set_value(1); tPress=t end
  if tPress and t>tPress+0.4 then SD:set_value(0) end
  if tLoaded and not done and t>tLoaded+0.5 then done=true
    local idx=io.open(OUT.."/resident.tsv","w"); local n,bytes=0,0
    for id=0,145 do
      local a=sp:read_u32(RES_ADDR+4*id); local sz=sp:read_u16(RES_SIZE+2*id)
      idx:write(string.format("0x%02X\t%08X\t%d\n",id,a,sz))
      local f=io.open(string.format("%s/resource-0x%02x.bin",OUT,id),"wb")
      if sz>0 then f:write(sp:read_range(a,a+sz-1,8)); n=n+1; bytes=bytes+sz end
      f:close()
    end
    idx:close()
    print(string.format("awresverify: load took %.2f s (SD CARD LOAD at %.2f, loaded at %.2f); dumped %d resources, %d bytes",
      tLoaded-tPress, tPress, tLoaded, n, bytes))
    M:exit()
  end
  if t>90 and not done then print("awresverify: TIMEOUT, flag never set"); M:exit() end
end)
