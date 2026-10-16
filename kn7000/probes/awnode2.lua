-- The sustain mask 0x500D288C gives held voice SLOTS. Dump each held slot's full node
-- record (0x500D1278 + slot*0x2C, 0x2C bytes) to locate the NOTE field. Hold C4(0x3C)
-- then E4(0x40) so two distinct notes disambiguate which byte is the note.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local C4=F(":KEYS1","C4"); local E4=F(":KEYS1","E4")
local BASE=0x500D1278; local MASK=0x500D288C
local function heldslots() local r={} for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do if (v&(1<<bit))~=0 then r[#r+1]=byte*8+bit end end end return r end
local function dumpnode(s)
  local b=BASE+s*0x2C; local h={}
  for i=0,0x2B do h[#h+1]=string.format("%02x",sp:read_u8(b+i)) end
  print(string.format("  slot %3d @0x%08X: %s", s, b, table.concat(h," ")))
end
local function scan(tag)
  local hs=heldslots()
  print(string.format("[%s] held slots: %s", tag, #hs>0 and table.concat(hs,",") or "(none)"))
  for _,s in ipairs(hs) do dumpnode(s) end
end
local ph=0
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph==0 and t>13 then C4:set_value(1); ph=1; p=t end
 if ph==1 and t>p+0.4 then scan("C4=0x3C held"); E4:set_value(1); ph=2; p=t end
 if ph==2 and t>p+0.4 then scan("C4=0x3C + E4=0x40 held"); C4:set_value(0); E4:set_value(0); ph=3; p=t end
 if ph==3 and t>p+0.5 then M:exit() end
end)
