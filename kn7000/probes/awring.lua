-- Walk the active-voice ring from head *(0x500D1050) (links at node+0x10, note at node+0x0C
-- = link-4). Does releasing ONE of two held notes remove it from the ring FAST (per-note),
-- faster than the 50ms sustain mask? That would be a usable fast per-note signal.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local C4=Fany("C4"); local G4=Fany("G4")
local CURPART=0x4407102A; local REQPART=0x4407102C
local function ringnotes()
  local head=sp:read_u32(0x500D1050); local out={}; local seen={}; local L=head; local n=0
  while L~=0 and not seen[L] and n<40 do seen[L]=true; out[#out+1]=sp:read_u8(L-4); L=sp:read_u32(L); n=n+1 end
  table.sort(out); return table.concat(out,",")
end
local ph="sd"; local t0; local last=-1
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82); if sp:read_u16(CURPART)==0x3E82 then ph="run"; t0=t; print("water") end
   if t>120 then print("TIMEOUT w"); M:exit() end
 elseif ph=="run" then
   local r=t-t0
   if r>0.3 and r<0.35 then C4:set_value(1); G4:set_value(1); print("+C4+G4 (60,67)") end
   if r>1.3 and r<1.35 then C4:set_value(0); print("release C4 only (keep G4)") end
   local l=math.floor(r*10)
   if l~=last and r>1.2 and r<1.8 then last=l; print(string.format("  r=%.2f ringnotes={%s}", r, ringnotes())) end
   if r>2.0 then M:exit() end
 end
end)
