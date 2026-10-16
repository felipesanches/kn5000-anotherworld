-- Confirm polyphonic held-note readout works DURING the water part. Held-slot bitmap
-- 0x500D288C -> slots; note = (0x500D1278 + slot*0x2C + 0x0C). Reach water, hold C4+G4.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local C4=F(":KEYS1","C4"); local G4=F(":KEYS1","G4"); local C5=F(":KEYS2","C5")
local BASE=0x500D1278; local MASK=0x500D288C
local CURPART=0x4407102A; local REQPART=0x4407102C
local function heldnotes()
  local n={}
  for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do
    if (v&(1<<bit))~=0 then local s=byte*8+bit; n[#n+1]=string.format("s%d=0x%02X",s,sp:read_u8(BASE+s*0x2C+0x0C)) end end end
  return #n>0 and table.concat(n," ") or "(none)"
end
local ph="sd"
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="intro" end
 elseif ph=="intro" then if sp:read_u16(CURPART)==0x3E81 then ph="water" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="water" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then print(string.format("water @t=%.1f",t)); ph="t"; p=t end
   if t>130 then print("TIMEOUT water"); M:exit() end
 elseif ph=="t" then
   local dt=t-p
   if dt>0.1 and dt<0.15 then C4:set_value(1) end
   if dt>0.5 and dt<0.55 then G4:set_value(1) end
   if dt>0.9 and dt<0.95 then C5:set_value(1) end
   if math.floor(dt*2)~=last then last=math.floor(dt*2); print(string.format("  t+%.1f heldnotes: %s",dt,heldnotes())) end
   if dt>2.0 then M:exit() end
 end
end)
