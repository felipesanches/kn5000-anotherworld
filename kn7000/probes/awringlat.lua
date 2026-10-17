-- Fine set/release latency of the voice ring (head *(0x500D1050)) for note 60 (C4),
-- in-game, vs the sustain mask. 4 trials.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)"); local C4=Fany("C4")
local CURPART=0x4407102A; local REQPART=0x4407102C; local SMASK=0x500D288C
local function ringHas(nn) local L=sp:read_u32(0x500D1050); local s={}; local n=0
  while L~=0 and not s[L] and n<40 do s[L]=true; if sp:read_u8(L-4)==nn then return true end; L=sp:read_u32(L); n=n+1 end; return false end
local function susHas() for b=0,15 do if sp:read_u8(SMASK+b)~=0 then return true end end return false end
local ph="sd"; local st="press"; local t0; local trial=0; local tp
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82); if sp:read_u16(CURPART)==0x3E82 then ph="run"; t0=t+0.3 end
   if t>120 then print("TIMEOUT w"); M:exit() end
 elseif ph=="run" then
   if st=="press" then if t>=t0 then C4:set_value(1); st="son"; tp=t end
   elseif st=="son" then if ringHas(60) then rs=(t-tp)*1000; st="smon"; tp2=t end; if t-tp>0.4 then rs=-1; st="smon"; tp2=t end
   elseif st=="smon" then local sm=susHas() and (t-tp2)*1000 or nil
     -- wait for both set, then hold
     if (t-tp2)>0.3 then st="rel"; t0=t+0.3 end
   elseif st=="rel" then if t>=t0 then C4:set_value(0); st="roff"; tr=t end
   elseif st=="roff" then
     local ringOff = not ringHas(60); local susOff = not susHas()
     if ringOff and (rr==nil) then rr=(t-tr)*1000 end
     if susOff and (sr==nil) then sr=(t-tr)*1000 end
     if (rr and sr) or (t-tr)>0.4 then
       print(string.format("trial %d: ring set=%.0fms  ring release=%s  sustain release=%s",
         trial, rs, rr and string.format("%.0fms",rr) or ">400", sr and string.format("%.0fms",sr) or ">400"))
       trial=trial+1; rr=nil; sr=nil; st="press"; t0=t+0.3
     end
   end
   if trial>=4 then M:exit() end
 end
end)
