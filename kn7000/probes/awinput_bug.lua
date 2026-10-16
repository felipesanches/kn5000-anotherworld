-- Hunt the input mix-up: in the water part, press/release single keys repeatedly and
-- with overlap, logging each frame the held-notes (slot:note), the mask ReadInput would
-- compute, and the panel button bits -- to catch wrong/lingering/phantom inputs.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local K={F5=Fany("F5"), C6=Fany("C6"), A5=Fany("A5"), Ab5=Fany("G5#")}
local BASE=0x500D1278; local MASK=0x500D288C
local PANEL={{0x5006BE61,0x02,"R"},{0x5006BE62,0x01,"L"},{0x5006BE66,0x02,"U"},{0x5006BE67,0x02,"D"},{0x5006BE65,0x08,"F"}}
local CURPART=0x4407102A; local REQPART=0x4407102C
local function classify(note)
  if note<=60 then return 0x80 elseif note==77 then return 2 elseif note==80 or note==82 then return 8
  elseif note==81 then return 4 elseif note==84 then return 1 else return 0 end
end
local function sample()
  local notes={}; local mask=0
  for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do
    if (v&(1<<bit))~=0 then local s=byte*8+bit; local n=sp:read_u8(BASE+s*0x2C+0x0C)
      notes[#notes+1]=string.format("%d:%d",s,n); mask=mask|classify(n) end end end
  local pan={}; for _,p in ipairs(PANEL) do if (sp:read_u8(p[1])&p[2])~=0 then pan[#pan+1]=p[3]; 
    mask=mask|(p[3]=="R" and 1 or p[3]=="L" and 2 or p[3]=="D" and 4 or p[3]=="U" and 8 or 0x80) end end
  return notes, mask, pan
end
-- schedule: list of {t_rel, key_or_nil_to_press, down(bool)}
local SCH={}
local tt=0.3
for i=1,6 do SCH[#SCH+1]={tt,"F5",true}; SCH[#SCH+1]={tt+0.25,"F5",false}; tt=tt+0.45 end  -- same key repeat
for i=1,3 do SCH[#SCH+1]={tt,"C6",true}; SCH[#SCH+1]={tt+0.25,"C6",false}; tt=tt+0.45 end
-- overlap: F5 down, C6 down while F5 still down, release F5, release C6
SCH[#SCH+1]={tt,"F5",true}; SCH[#SCH+1]={tt+0.15,"C6",true}; SCH[#SCH+1]={tt+0.3,"F5",false}; SCH[#SCH+1]={tt+0.5,"C6",false}; tt=tt+0.8
local tend=tt+0.3
local ph="sd"; local tw=nil; local si=1; local down={}; local lastline=nil
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then tw=t; print("water; begin input schedule"); ph="t" end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local rel=t-tw
   while si<=#SCH and rel>=SCH[si][1] do local e=SCH[si]; if K[e[2]] then K[e[2]]:set_value(e[3] and 1 or 0) end
     down[e[2]]=e[3]; si=si+1 end
   local dn={}; for k,v in pairs(down) do if v then dn[#dn+1]=k end end; table.sort(dn)
   local notes,mask,pan=sample()
   local line=string.format("down={%s} held={%s} mask=%02x panel={%s}", table.concat(dn,","), table.concat(notes," "), mask, table.concat(pan,""))
   if line~=lastline then lastline=line; print(string.format("  t+%.2f %s", rel, line)) end
   if rel>tend then M:exit() end
 end
end)
