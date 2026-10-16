-- Hold C4 (gm60=0x3C,idx0x18) then G4 (gm67=0x43,idx0x1F); capture firmware RAM each
-- time so we can diff for a held-note store that the AW module could map to directions.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local C4=field(":KEYS1","C4")
local G4=field(":KEYS1","G4")
local FRAME_NO=0x4408007C
local LO,HI=0x50148000,0x5014B000
local pressed=false; local phase=0
local function grab(fn) local s=sp:read_range(LO,HI-1,8); local f=io.open(fn,"wb"); f:write(s); f:close() end
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not pressed then return end
  local f=sp:read_u16(FRAME_NO)
  if phase==0 and f>=20 then C4:set_value(1); phase=1; print("C4 held") end
  if phase==1 and f>=40 then grab("/home/fsanches/compartilhado/tmp/kn7000-aw-reference/ram_c4.bin"); C4:set_value(0); phase=2; print("captured C4") end
  if phase==2 and f>=60 then G4:set_value(1); phase=3; print("G4 held") end
  if phase==3 and f>=80 then grab("/home/fsanches/compartilhado/tmp/kn7000-aw-reference/ram_g4.bin"); G4:set_value(0); phase=4; print("captured G4") end
  if phase==4 and f>=90 then M:exit() end
end)
