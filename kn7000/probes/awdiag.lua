-- Thorough steady-hold test: do momentary panel buttons coexist (diagonals)? and which
-- button works as a plain-momentary FIRE (SUSTAIN appears to be latched/special)?
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end
  print("MISSING",tag,name) end
local B={
 UP ={F(":cpanel:CPR_SEG6","R1/R2 OCTAVE + (SW1)"),0x5006BE66,0x02},
 DOWN={F(":cpanel:CPR_SEG7","R1/R2 OCTAVE - (SW1)"),0x5006BE67,0x02},
 LEFT={F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)"),0x5006BE62,0x01},
 RIGHT={F(":cpanel:CPR_SEG1","PART SELECT RIGHT 1 (SW1)"),0x5006BE61,0x02},
 SUST={F(":cpanel:CPR_SEG5","SUSTAIN (SW3)"),0x5006BE65,0x08},
 SOLO={F(":cpanel:CPR_SEG0","SOLO (SW0)"),0x5006BE60,0x01},
 CHOR={F(":cpanel:CPR_SEG5","CHORUS (SW2)"),0x5006BE65,0x04},
 DEFF={F(":cpanel:CPR_SEG4","DIGITAL EFFECT (SW3)"),0x5006BE64,0x08},
}
local function st(n) local b=B[n]; return (sp:read_u8(b[2])&b[3])~=0 and 1 or 0 end
local TESTS={
 {"UP"},{"DOWN"},{"LEFT"},{"RIGHT"},{"SUST"},{"SOLO"},{"CHOR"},{"DEFF"},
 {"UP","LEFT"},{"UP","RIGHT"},{"DOWN","LEFT"},{"DOWN","RIGHT"},
 {"RIGHT","SOLO"},{"RIGHT","CHOR"},{"RIGHT","DEFF"},{"UP","RIGHT","SOLO"},
}
local ph="boot"; local ti=1; local tp=0
local function clr() for _,b in pairs(B) do if b[1] then b[1]:set_value(0) end end end
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="boot" then if t>14 then ph="test"; tp=t end; return end
 local tc=TESTS[ti]
 if tc==nil then M:exit(); return end
 if t<tp+0.05 then clr(); for _,n in ipairs(tc) do if B[n][1] then B[n][1]:set_value(1) end end
 elseif t>=tp+0.6 then
   local o={} for _,n in ipairs({"UP","DOWN","LEFT","RIGHT","SUST","SOLO","CHOR","DEFF"}) do o[#o+1]=n..st(n) end
   print(string.format("held {%-22s} -> %s", table.concat(tc,"+"), table.concat(o," ")))
   clr(); ti=ti+1; tp=t+0.2
 end
end)
