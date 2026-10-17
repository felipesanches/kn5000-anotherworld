-- awfeatures.lua -- show the port's own screens: splash, black border, help pages, code screen.
--
-- Presses SD CARD LOAD and takes MAME snapshots (into -snapshot_directory) along a script:
-- the splash (logo / credits), the intro (action skips the splash), the lake, the help
-- pages (HELP, PAGE DOWN twice, PAGE UP), back to the game (EXIT), then the level-code screen
-- (OTHER PART & FR). Also prints the colour of a few border pixels at each snapshot, which must
-- be 0 (black). Times are emulated seconds after the game task starts (FRAME_NO first > 0).
--   ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets -skip_gameinfo -window \
--     kn7000 -bios sp7001 -harddisk build/another_sd.img -snapshot_directory build/snap \
--     -autoboot_script probes/awfeatures.lua -str 200
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local HELP=F(":cpanel:CPC_SEG5","HELP (SW1)"); local CODES=F(":cpanel:CPC_SEG5","OTHER PART & FR (SW0)")
local PGUP=F(":cpanel:CPC_SEG11","PAGE UP (SW4)"); local PGDN=F(":cpanel:CPC_SEG11","PAGE DOWN (SW5)")
local EXIT=F(":cpanel:CPC_SEG11","EXIT (SW7)"); local FIRE=F(":cpanel:CPR_SEG5","SUSTAIN (SW3)")
local FB=0x9CE00000
local function border() local s={}
  for _,xy in ipairs({{0,0},{639,0},{5,120},{630,120},{320,5},{320,235}}) do s[#s+1]=string.format("%04X",sp:read_u16(FB+(xy[2]*640+xy[1])*2)) end
  return table.concat(s," ") end
-- {seconds after the game starts, action}
local STEPS={
  {3,"snap","splash1"},{8,"snap","splash2"},{14,"snap","splash3"},
  {15,"press",FIRE},{15.4,"release",FIRE},{20,"snap","intro"},
  {21,"part",0x3E82},{30,"snap","lake"},
  {31,"press",HELP},{31.4,"release",HELP},{33,"snap","help1"},
  {34,"press",PGDN},{34.3,"release",PGDN},{35.5,"snap","help2"},
  {36,"press",PGDN},{36.3,"release",PGDN},{37.5,"snap","help3"},
  {38,"press",PGUP},{38.3,"release",PGUP},{39.5,"snap","help2b"},
  {40,"press",EXIT},{40.3,"release",EXIT},{42,"snap","lake_back"},
  {43,"press",CODES},{43.3,"release",CODES},{48,"snap","codes"},
  {49,"end"}}
local t0=nil; local i=1
emu.register_periodic(function()
  local t=M.time:as_double(); SD:set_value((t>11 and t<11.4) and 1 or 0)
  if not t0 and sp:read_u16(0x4408007C)>0 then t0=t; print(string.format("awfeatures: game task running at %.2f s", t)) end
  if not t0 then return end
  local s=STEPS[i]; if not s or t-t0<s[1] then return end
  if s[2]=="snap" then M.video:snapshot()
    print(string.format("snap %-10s t+%5.1f part=%04X frame=%d border=%s", s[3], t-t0, sp:read_u16(0x4407102A), sp:read_u16(0x4408007C), border()))
  elseif s[2]=="press" then s[3]:set_value(1)
  elseif s[2]=="release" then s[3]:set_value(0)
  elseif s[2]=="part" then sp:write_u16(0x4407102C, s[3])
  elseif s[2]=="end" then M:exit() end
  i=i+1
end)
