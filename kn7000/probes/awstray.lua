local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local UP=Fany("G5#"); local LEFT=Fany("F5")
local CURPART=0x4407102A; local REQPART=0x4407102C; local FRAME_NO=0x4408007C
local ph="sd"; local tw; local lf=-1; local stray=0; local frames=0
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82); if sp:read_u16(CURPART)==0x3E82 then tw=t; ph="t" end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local rel=t-tw
   local upnow=(math.floor(rel/0.5)%2==0)
   if UP then UP:set_value(upnow and 1 or 0) end
   if LEFT then LEFT:set_value(upnow and 0 or 1) end
   local fn=sp:read_u16(FRAME_NO)
   if fn~=lf then lf=fn; frames=frames+1
     local m=sp:read_u8(0x44080068)
     if upnow then if (m&2)~=0 then stray=stray+1 end else if (m&8)~=0 then stray=stray+1 end end
   end
   if rel>8 then print(string.format("STRAY applied-mask opposite-direction frames = %d / %d", stray, frames)); M:exit() end
 end
end)
