-- Verify the keybed agent's finding: the TG voice-allocator node array at
-- 0x500D1278 + slot*0x2C holds STABLE held-note state (+0x26 bit7 = held, +0x28 = note,
-- +0x29 = hw slot). Hold C4 (0x3C) + G4 (0x43) staggered, scan all 128 nodes.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local C4=F(":KEYS1","C4")
local G4=F(":KEYS1","G4")
local E4=F(":KEYS1","E4")
local BASE=0x500D1278
local LASTKEY=0x501496B2
local SUSTMASK=0x500D288C
local function scan(tag)
  local held={}
  for s=0,127 do
    local b=BASE+s*0x2C
    local fl=sp:read_u16(b+0x26)
    if (fl&0x80)~=0 then held[#held+1]=string.format("slot%d note=0x%02X(%d) hw=0x%02X fl=0x%04X",s,sp:read_u8(b+0x28),sp:read_u8(b+0x28),sp:read_u8(b+0x29),fl) end
  end
  local sm={} for i=0,15 do sm[#sm+1]=string.format("%02x",sp:read_u8(SUSTMASK+i)) end
  print(string.format("[%s] lastkey@6B2=0x%02X  sustmask=%s", tag, sp:read_u8(LASTKEY), table.concat(sm,"")))
  print(string.format("   held voices (%d): %s", #held, #held>0 and table.concat(held," | ") or "(none)"))
end
local ph=0
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph==0 and t>13 then scan("idle, no keys"); ph=1; p=t end
 if ph==1 and t>13.3 then C4:set_value(1); ph=2; p=t end         -- press C4
 if ph==2 and t>p+0.4 then scan("C4 held"); E4:set_value(1); ph=3; p=t end   -- add E4 (staggered)
 if ph==3 and t>p+0.4 then scan("C4+E4 held"); G4:set_value(1); ph=4; p=t end -- add G4
 if ph==4 and t>p+0.4 then scan("C4+E4+G4 held (chord)"); C4:set_value(0); ph=5; p=t end -- release C4
 if ph==5 and t>p+0.5 then scan("released C4 (E4+G4 still held)"); E4:set_value(0); G4:set_value(0); ph=6; p=t end
 if ph==6 and t>p+0.6 then scan("all released"); M:exit() end
end)
