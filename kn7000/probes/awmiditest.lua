-- Verify that MIDI-IN notes reach the TG voice allocator (same held-note state the game
-- reads), by watching the held mask while a SMF on -midiin1 plays note-ons at ~t=22s.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local BASE=0x500D1278; local MASK=0x500D288C
local CURPART=0x4407102A; local REQPART=0x4407102C
local function heldnotes()
  local n={}
  for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do
    if (v&(1<<bit))~=0 then local s=byte*8+bit; n[#n+1]=string.format("s%d=0x%02X",s,sp:read_u8(BASE+s*0x2C+0x0C)) end end end
  return #n>0 and table.concat(n," ") or "(none)"
end
local ph="sd"; local last=-1
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then print(string.format("water @t=%.1f (SMF note-ons due ~22s)",t)); ph="t" end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   if math.floor(t)~=last then last=math.floor(t)
     if t>=18 then print(string.format("  t=%ds heldnotes: %s", math.floor(t), heldnotes())) end
   end
   if t>34 then M:exit() end
 end
end)
