local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local C4=Fany("C4"); local CURPART=0x4407102A
local st="sd"; local t0
emu.register_periodic(function()
 local t=M.time:as_double()
 if st=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); st="nokey" end
 elseif st=="nokey" then
   if sp:read_u16(CURPART)==0x3E81 and not t0 then t0=t; print(string.format("intro @t=%.1f; 6s no-key watch...",t)) end
   if t0 and sp:read_u16(CURPART)~=0x3E81 then print(string.format("FAIL premature skip @t=%.1f (%.1fs no key) part=%04x",t,t-t0,sp:read_u16(CURPART))); M:exit() end
   if t0 and t>t0+6 then print(string.format("PASS no-key: still intro after 6s. pressing C4...")); C4:set_value(1); st="keyed"; t0=t end
   if t>95 then print("TIMEOUT"); M:exit() end
 elseif st=="keyed" then
   if sp:read_u16(CURPART)==0x3E82 then print(string.format("PASS skip: C4 -> water (0x3E82) in %.2fs",t-t0)); M:exit() end
   if t>t0+6 then print("FAIL: key did not skip"); M:exit() end
 end
end)
