-- On release, does the GONE mask (0x500D287C) set FASTER than the SUSTAIN mask
-- (0x500D288C) clears? If so, "sustain AND NOT gone" gives a ~fast release -> fixes the
-- lingering extra kick. Press F5, release, time sustain-clear vs gone-set for its slot.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local F5=Fany("F5")
local BASE=0x500D1278; local SUS=0x500D288C; local GONE=0x500D287C
local CURPART=0x4407102A; local REQPART=0x4407102C
local function slot77() for byte=0,15 do local v=sp:read_u8(SUS+byte); for bit=0,7 do
    if (v&(1<<bit))~=0 and sp:read_u8(BASE+(byte*8+bit)*0x2C+0x0C)==77 then return byte*8+bit end end end return -1 end
local function bit(addr,s) if s<0 then return 0 end return (sp:read_u8(addr+(s>>3))&(1<<(s&7)))~=0 and 1 or 0 end
local ph="sd"; local tw; local trial=0; local st="press"; local t0; local slot; local trel; local sawS,sawG
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then tw=t; ph="t"; st="press"; t0=t+0.3 end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   if st=="press" then if t>=t0 then F5:set_value(1); st="hold"; t0=t+0.3 end
   elseif st=="hold" then if t>=t0 then slot=slot77(); if slot>=0 then F5:set_value(0); trel=t; sawS=nil; sawG=nil; st="watch" end end
   elseif st=="watch" then
     if not sawS and bit(SUS,slot)==0 then sawS=(t-trel)*1000 end
     if not sawG and bit(GONE,slot)==1 then sawG=(t-trel)*1000 end
     if (sawS and sawG) or (t-trel)>0.3 then
       print(string.format("trial %d slot%d: sustain-clear=%s ms  gone-set=%s ms", trial, slot,
         sawS and string.format("%.1f",sawS) or ">300", sawG and string.format("%.1f",sawG) or ">300(never)"))
       trial=trial+1; st="press"; t0=t+0.3
     end
   end
   if trial>=4 then M:exit() end
 end
end)
