-- Verify the panel D-pad feeds the AW hero variables exactly like rustyworld's
-- update_player. Gated on emulated time (the VM comes up ~t=30s after SD load). Launch,
-- wait for the intro, force the water part, then press each combo and read the vars.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end
  print("MISSING FIELD",tag,name); return nil end
local SD   =F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local BTN={RIGHT=F(":cpanel:CPR_SEG1","PART SELECT RIGHT 1 (SW1)"),
           LEFT =F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)"),
           UP   =F(":cpanel:CPR_SEG6","R1/R2 OCTAVE + (SW1)"),
           DOWN =F(":cpanel:CPR_SEG7","R1/R2 OCTAVE - (SW1)"),
           FIRE =F(":cpanel:CPR_SEG5","SUSTAIN (SW3)")}
local VARS=0x44070000
local function v(i) return sp:read_u16(VARS+2*i) end
local CURPART=0x4407102A
local REQPART=0x4407102C
local TESTS={
 {"RIGHT",     {"RIGHT"},        1,0,0,0x01,0,0x01},
 {"LEFT",      {"LEFT"},         0xFFFF,0,0,0x02,0,0x02},
 {"DOWN",      {"DOWN"},         0,1,1,0x04,0,0x04},
 {"UP",        {"UP"},           0,0xFFFF,0xFFFF,0x08,0,0x08},
 {"FIRE",      {"FIRE"},         0,0,0,0x80,1,0x80},
 {"RIGHT+FIRE",{"RIGHT","FIRE"}, 1,0,0,0x81,1,0x81},
 {"UP+LEFT",   {"UP","LEFT"},    0xFFFF,0xFFFF,0xFFFF,0x0A,0,0x0A},
 {"(none)",    {},               0,0,0,0,0,0},
}
local st="sd"; local ti=1; local pt=0; local pass=0; local fail=0
local function clearall() for _,f in pairs(BTN) do f:set_value(0) end end
emu.register_periodic(function()
 local t=M.time:as_double()
 if st=="sd" then
   if t>11 then SD:set_value(1) end
   if t>11.4 then SD:set_value(0); st="intro" end
 elseif st=="intro" then
   if sp:read_u16(CURPART)==0x3E81 then print(string.format("intro active @t=%.1f",t)); st="toWater" end
   if t>90 then print("TIMEOUT no intro; CURPART="..string.format("%04x",sp:read_u16(CURPART))); M:exit() end
 elseif st=="toWater" then
   sp:write_u16(REQPART,0x3E82)                       -- keep requesting until it takes
   if sp:read_u16(CURPART)==0x3E82 then print(string.format("water part active @t=%.1f",t)); st="test"; pt=t end
   if t>130 then print("TIMEOUT no water; CURPART="..string.format("%04x",sp:read_u16(CURPART))); M:exit() end
 elseif st=="test" then
   local tc=TESTS[ti]
   if tc==nil then print(string.format("---- input verify: %d passed, %d failed ----",pass,fail)); M:exit(); return end
   if t<pt+0.05 then clearall(); for _,b in ipairs(tc[2]) do if BTN[b] then BTN[b]:set_value(1) end end
   elseif t>=pt+0.6 then
     local got={v(0xFC),v(0xE5),v(0xFB),v(0xFD),v(0xFA),v(0xFE)}
     local exp={tc[3],tc[4],tc[5],tc[6],tc[7],tc[8]}
     local ok=true; for i=1,6 do if got[i]~=exp[i] then ok=false end end
     if ok then pass=pass+1 else fail=fail+1 end
     print(string.format("%-11s %s  got FC=%04x E5=%04x FB=%04x FD=%02x FA=%x FE=%02x | exp FC=%04x E5=%04x FB=%04x FD=%02x FA=%x FE=%02x",
       tc[1], ok and "OK  " or "FAIL", got[1],got[2],got[3],got[4],got[5],got[6], exp[1],exp[2],exp[3],exp[4],exp[5],exp[6]))
     clearall(); ti=ti+1; pt=t+0.15
   end
 end
end)
