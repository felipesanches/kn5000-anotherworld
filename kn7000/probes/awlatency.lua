-- Measure raw latency from a key press (set_value) to the held mask showing its note,
-- and from release to the note clearing. Tells us if the ~1-frame lag is firmware
-- processing (big ms) or just frame quantization.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local F5=Fany("F5")
local BASE=0x500D1278; local MASK=0x500D288C
local CURPART=0x4407102A; local REQPART=0x4407102C
local function has77() for byte=0,15 do local v=sp:read_u8(MASK+byte); for bit=0,7 do
    if (v&(1<<bit))~=0 and sp:read_u8(BASE+(byte*8+bit)*0x2C+0x0C)==77 then return true end end end return false end
local ph="sd"; local tw; local trial=0; local st="idle"; local t0
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then tw=t; ph="t"; st="press"; t0=t+0.3 end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   if st=="press" then
     if t>=t0 then F5:set_value(1); st="waiton"; tpress=t end
   elseif st=="waiton" then
     if has77() then print(string.format("trial %d: press->mask ON  = %.1f ms", trial, (t-tpress)*1000)); st="holdrel"; t0=t+0.3 end
     if t-tpress>0.5 then print("ON timeout"); st="holdrel"; t0=t+0.3 end
   elseif st=="holdrel" then
     if t>=t0 then F5:set_value(0); st="waitoff"; trel=t end
   elseif st=="waitoff" then
     if not has77() then print(string.format("trial %d: release->mask OFF = %.1f ms", trial, (t-trel)*1000)); trial=trial+1; st="press"; t0=t+0.4 end
     if t-trel>0.5 then print("OFF timeout"); trial=trial+1; st="press"; t0=t+0.4 end
   end
   if trial>=5 then M:exit() end
 end
end)
