-- Verify the keybed gameplay mapping: hold each mapped key in the water part and read
-- back the hero vars. action = bass/C4 (<=60); F5 left, A5 down, C6 right, B5/D6 up.
-- Also checks the run+jump combos (action+direction+up held at once) -- these need up on a
-- note that does not ghost against the other keys in the keybed scan matrix (see vm.inc).
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
  print("MISSING KEY",name); return nil end
local SD=Fany and nil
do local p=M.ioport.ports[":cpanel:CPR_SEG1"]; for _,f in pairs(p.fields) do if f.name=="SD CARD LOAD (SW7)" then SD=f end end end
local K={ F5=Fany("F5"), A5=Fany("A5"), C6=Fany("C6"), B5=Fany("B5"), D6=Fany("D6"),
          C4=Fany("C4"), C3=Fany("C3") }
local VARS=0x44070000
local function v(i) return sp:read_u16(VARS+2*i) end
local CURPART=0x4407102A; local REQPART=0x4407102C
-- (label, keys{}, expect FC,E5,FB,FD,FA,FE)
local T={
 {"F5=left",   {"F5"},        0xFFFF,0,0,0x02,0,0x02},
 {"C6=right",  {"C6"},        1,0,0,0x01,0,0x01},
 {"A5=down",   {"A5"},        0,1,1,0x04,0,0x04},
 {"B5=up",     {"B5"},        0,0xFFFF,0xFFFF,0x08,0,0x08},
 {"D6=up",     {"D6"},        0,0xFFFF,0xFFFF,0x08,0,0x08},
 {"C4=action", {"C4"},        0,0,0,0x80,1,0x80},
 {"C3=action", {"C3"},        0,0,0,0x80,1,0x80},
 {"C6+C3(R+fire)",{"C6","C3"},1,0,0,0x81,1,0x81},
 {"C3+C6+B5(run-R-jump)",{"C3","C6","B5"},1,0xFFFF,0xFFFF,0x89,1,0x89},
 {"C3+F5+B5(run-L-jump)",{"C3","F5","B5"},0xFFFF,0xFFFF,0xFFFF,0x8A,1,0x8A},
}
local ph="sd"; local ti=1; local tp=0
local function clr() for _,f in pairs(K) do if f then f:set_value(0) end end end
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then print(string.format("water @t=%.1f",t)); ph="t"; tp=t end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local tc=T[ti]
   if tc==nil then M:exit(); return end
   if t<tp+0.05 then clr(); for _,k in ipairs(tc[2]) do if K[k] then K[k]:set_value(1) end end
   elseif t>=tp+0.7 then
     local g={v(0xFC),v(0xE5),v(0xFB),v(0xFD),v(0xFA),v(0xFE)}
     local e={tc[3],tc[4],tc[5],tc[6],tc[7],tc[8]}
     local ok=true; for i=1,6 do if g[i]~=e[i] then ok=false end end
     print(string.format("%-14s %s FC=%04x E5=%04x FB=%04x FD=%02x FA=%x FE=%02x",tc[1],ok and "OK " or "DIFF",g[1],g[2],g[3],g[4],g[5],g[6]))
     clr(); ti=ti+1; tp=t+0.2
   end
 end
end)
