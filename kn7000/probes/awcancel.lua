-- Verify: diagonal (non-opposing) survives; opposing pair cancels to neutral.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local K={F5=Fany("F5"),C6=Fany("C6"),A5=Fany("A5"),Ab5=Fany("G5#")}
local VARS=0x44070000
local function v(i) return sp:read_u16(VARS+2*i) end
local CURPART=0x4407102A; local REQPART=0x4407102C
-- staggered-press tests: {label, first, second, expect FC, E5, FD}
local T={
 {"F5+A5 (diag L+D)", "F5","A5", 0xFFFF,0x0001,0x06},
 {"F5+C6 (opp L+R)",  "F5","C6", 0x0000,0x0000,0x00},
 {"Ab5+A5 (opp U+D)", "Ab5","A5",0x0000,0x0000,0x00},
}
local ph="sd"; local ti=1; local tp=0; local sub=0
local function clr() for _,f in pairs(K) do if f then f:set_value(0) end end end
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then ph="t"; tp=t; print("water") end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local tc=T[ti]
   if tc==nil then M:exit(); return end
   local dt=t-tp
   if sub==0 and dt>0.05 then clr(); K[tc[2]]:set_value(1); sub=1 end
   if sub==1 and dt>0.35 then K[tc[3]]:set_value(1); sub=2 end
   if sub==2 and dt>0.8 then
     local fc,e5,fd=v(0xFC),v(0xE5),v(0xFD)
     local ok=(fc==tc[4] and e5==tc[5] and fd==tc[6])
     print(string.format("%-18s %s FC=%04x E5=%04x FD=%02x (exp FC=%04x E5=%04x FD=%02x)",tc[1], ok and "OK " or "DIFF", fc,e5,fd, tc[4],tc[5],tc[6]))
     clr(); ti=ti+1; tp=t+0.25; sub=0
   end
 end
end)
