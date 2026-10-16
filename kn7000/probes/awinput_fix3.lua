-- Many tight single-key presses; count PRESS-context wrong-direction glitches (a mask bit
-- that the currently-held key does NOT map to) for raw vs per-slot debounce, at VM-frame
-- cadence. Press-glitches = the "same key, different effect" bug.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local function Fp(tag,name) local p=M.ioport.ports[tag]; for _,f in pairs(p.fields) do if f.name==name then return f end end end
local SD=Fp(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local K={F5=Fany("F5"), C6=Fany("C6")}; local WANT={F5=2,C6=1}
local BASE=0x500D1278; local MASK=0x500D288C; local FRAME_NO=0x4408007C
local CURPART=0x4407102A; local REQPART=0x4407102C
local function classify(note)
  if note==0 then return 0 end
  if note<=60 then return 0x80 elseif note==77 then return 2 elseif note==80 or note==82 then return 8
  elseif note==81 then return 4 elseif note==84 then return 1 else return 0 end
end
local prev={}; for i=0,15 do prev[i]=0 end
local function masks()
  local raw,deb=0,0
  for byte=0,15 do local cur=sp:read_u8(MASK+byte); local st=cur&prev[byte]; prev[byte]=cur
    for bit=0,7 do local s=byte*8+bit
      if (cur&(1<<bit))~=0 then raw=raw|classify(sp:read_u8(BASE+s*0x2C+0x0C)) end
      if (st &(1<<bit))~=0 then deb=deb|classify(sp:read_u8(BASE+s*0x2C+0x0C)) end end end
  return raw,deb
end
-- build 25 tight presses each of F5 then C6 (0.15 on, 0.12 off)
local SCH={}; local tt=0.3
for _,kk in ipairs({"F5","C6"}) do for i=1,25 do SCH[#SCH+1]={tt,kk,true}; SCH[#SCH+1]={tt+0.15,kk,false}; tt=tt+0.27 end end
local tend=tt+0.3
local ph="sd"; local tw; local si=1; local down={}; local lf=-1
local rawP,debP,rawR,debR=0,0,0,0
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then tw=t; ph="t"; print("water; begin") end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local rel=t-tw
   while si<=#SCH and rel>=SCH[si][1] do local e=SCH[si]; if K[e[2]] then K[e[2]]:set_value(e[3] and 1 or 0) end; down[e[2]]=e[3]; si=si+1 end
   local fn=sp:read_u16(FRAME_NO)
   if fn~=lf then lf=fn
     local raw,deb=masks()
     local exp=0; local anydown=false; for k,v in pairs(down) do if v then exp=exp|WANT[k]; anydown=true end end
     if anydown then   -- press/hold context: any bit beyond exp = wrong-direction glitch
       if (raw & ~exp)~=0 then rawP=rawP+1 end
       if (deb & ~exp)~=0 then debP=debP+1 end
     else              -- release context: leftover bits = release lag
       if raw~=0 then rawR=rawR+1 end
       if deb~=0 then debR=debR+1 end
     end
   end
   if rel>tend then print(string.format("---- PRESS-glitches raw=%d deb=%d | RELEASE-lag raw=%d deb=%d ----",rawP,debP,rawR,debR)); M:exit() end
 end
end)
