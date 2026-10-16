-- Hypothesis: two switch-changes in the SAME scan collapse to one, but STAGGERED presses
-- coexist (as a human plays). Press button1, wait, press button2 (both held), read both.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name)
  local p=M.ioport.ports[tag]
  if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end
end
local B={
 UP   ={F(":cpanel:CPR_SEG6","R1/R2 OCTAVE + (SW1)"),0x5006BE66,0x02},
 DOWN ={F(":cpanel:CPR_SEG7","R1/R2 OCTAVE - (SW1)"),0x5006BE67,0x02},
 LEFT ={F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)"),0x5006BE62,0x01},
 RIGHT={F(":cpanel:CPR_SEG1","PART SELECT RIGHT 1 (SW1)"),0x5006BE61,0x02},
 SUST ={F(":cpanel:CPR_SEG5","SUSTAIN (SW3)"),0x5006BE65,0x08},
}
local function stt(n) local b=B[n]; if (sp:read_u8(b[2])&b[3])~=0 then return 1 else return 0 end end
local TESTS={{"UP","RIGHT"},{"UP","LEFT"},{"DOWN","RIGHT"},{"DOWN","LEFT"},{"RIGHT","SUST"},{"LEFT","UP"}}
local ph="boot"; local ti=1; local tp=0; local sub=0
local function clr() for _,b in pairs(B) do if b[1] then b[1]:set_value(0) end end end
emu.register_periodic(function()
  local t=M.time:as_double()
  if ph=="boot" then
    if t>14 then ph="t"; tp=t; sub=0 end
    return
  end
  local tc=TESTS[ti]
  if tc==nil then M:exit(); return end
  local dt=t-tp
  if sub==0 and dt>0.02 then clr(); B[tc[1]][1]:set_value(1); sub=1 end
  if sub==1 and dt>0.35 then B[tc[2]][1]:set_value(1); sub=2 end
  if sub==2 and dt>0.75 then
    print(string.format("stagger {%s then %s} -> %s=%d %s=%d",
      tc[1],tc[2],tc[1],stt(tc[1]),tc[2],stt(tc[2])))
    clr(); ti=ti+1; tp=t+0.25; sub=0
  end
end)
