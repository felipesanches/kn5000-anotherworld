-- Capture a voice node at the first VM frame its held-bit appears vs the next frames, to
-- see if the note at +0x0C is stale/0 then, and whether another byte flips when it
-- becomes valid (a lag-free discriminator for the allocation transient).
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local F5=Fany("F5"); local C6=Fany("C6")
local BASE=0x500D1278; local MASK=0x500D288C; local FRAME_NO=0x4408007C
local CURPART=0x4407102A; local REQPART=0x4407102C
local function held() local h={} for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do if (v&(1<<bit))~=0 then h[byte*8+bit]=true end end end return h end
local function nhex(s) local b=BASE+s*0x2C; local t={} for i=0,15 do t[#t+1]=string.format("%02x",sp:read_u8(b+i)) end return table.concat(t," ") end
local prev={}; local track={}  -- slot -> frames remaining to log
local ph="sd"; local tw; local lf=-1; local tp
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then tw=t; ph="t"; tp=t end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local rel=t-tw
   -- tap F5 / C6 alternately to force slot reuse with stale notes
   local onF5 = (math.floor(rel/0.4)%2==0)
   if F5 then F5:set_value(onF5 and 1 or 0) end
   if C6 then C6:set_value(onF5 and 0 or 1) end
   local fn=sp:read_u16(FRAME_NO)
   if fn~=lf then lf=fn
     local h=held()
     for s,_ in pairs(h) do if not prev[s] then track[s]=4 end end  -- newly appeared
     for s,n in pairs(track) do if n>0 then
       print(string.format("f%d slot%d APPEAR+%d note=%d bytes=[%s]", fn, s, 4-n, sp:read_u8(BASE+s*0x2C+0x0C), nhex(s)))
       track[s]=n-1 end end
     prev=h
   end
   if rel>4 then M:exit() end
 end
end)
