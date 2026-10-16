-- Does ONE physical key sound more than one voice/note (arranger chord/harmony/layer)?
-- In the water part, press each key alone and dump ALL held voices: note (+0x0C) and
-- candidate part/flag bytes (+0x00,+0x08,+0x0A). Extra notes => the input contamination.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
  print("MISSING",name) end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local BASE=0x500D1278; local MASK=0x500D288C
local CURPART=0x4407102A; local REQPART=0x4407102C
local TESTS={"C2","C3","C4","F5","A5","C6"}
local K={}; for _,n in ipairs(TESTS) do K[n]=Fany(n) end
local function dump(tag)
  local out={}
  for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do
    if (v&(1<<bit))~=0 then local s=byte*8+bit; local b=BASE+s*0x2C
      out[#out+1]=string.format("s%d[note=%d p0=%02x p8=%02x pA=%02x]",s,sp:read_u8(b+0x0C),sp:read_u8(b),sp:read_u8(b+8),sp:read_u8(b+0x0A)) end end end
  print(string.format("  %-4s held(%d): %s", tag, #out, table.concat(out," ")))
end
local ph="sd"; local ti=1; local tp=0; local cur
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then ph="t"; tp=t; print("water") end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local n=TESTS[ti]
   if n==nil then M:exit(); return end
   if cur==nil then cur=n; if K[n] then K[n]:set_value(1) end; tp=t end
   if t>=tp+0.8 then dump(cur); if K[cur] then K[cur]:set_value(0) end; cur=nil; ti=ti+1; tp=t+0.3 end
 end
end)
