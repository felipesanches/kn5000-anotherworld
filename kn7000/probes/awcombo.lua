-- Does the firmware register two simultaneous panel buttons? Reach the water part, then
-- press combos and read the raw switch-shadow bits (not the VM vars, which the bytecode
-- also writes). Shows exactly what the firmware debounce reports.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local BTN={RIGHT=F(":cpanel:CPR_SEG1","PART SELECT RIGHT 1 (SW1)"),
           LEFT =F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)"),
           UP   =F(":cpanel:CPR_SEG6","R1/R2 OCTAVE + (SW1)"),
           DOWN =F(":cpanel:CPR_SEG7","R1/R2 OCTAVE - (SW1)"),
           FIRE =F(":cpanel:CPR_SEG5","SUSTAIN (SW3)")}
-- shadow (addr,bit) per button
local SH={RIGHT={0x5006BE61,0x02},LEFT={0x5006BE62,0x01},UP={0x5006BE66,0x02},
          DOWN={0x5006BE67,0x02},FIRE={0x5006BE65,0x08}}
local function shadow() local s={} for _,n in ipairs({"RIGHT","LEFT","UP","DOWN","FIRE"}) do
    local d=SH[n]; s[#s+1]=n:sub(1,1)..((sp:read_u8(d[1])&d[2])~=0 and "1" or "0") end return table.concat(s," ") end
local CURPART=0x4407102A; local REQPART=0x4407102C
local COMBOS={{"RIGHT","FIRE"},{"UP","LEFT"},{"DOWN","RIGHT"},{"UP","LEFT","FIRE"},{"RIGHT"},{"UP"}}
local st="sd"; local ci=1; local pt=0
local function clearall() for _,f in pairs(BTN) do f:set_value(0) end end
emu.register_periodic(function()
 local t=M.time:as_double()
 if st=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); st="intro" end
 elseif st=="intro" then if sp:read_u16(CURPART)==0x3E81 then st="toWater" end; if t>90 then print("TIMEOUT intro"); M:exit() end
 elseif st=="toWater" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then print(string.format("water @t=%.1f",t)); st="test"; pt=t end
   if t>130 then print("TIMEOUT water"); M:exit() end
 elseif st=="test" then
   local c=COMBOS[ci]
   if c==nil then M:exit(); return end
   if t<pt+0.05 then clearall(); for _,b in ipairs(c) do BTN[b]:set_value(1) end
   elseif t>=pt+0.5 then
     print(string.format("press {%-20s} shadow-> %s", table.concat(c,","), shadow()))
     clearall(); ci=ci+1; pt=t+0.2
   end
 end
end)
