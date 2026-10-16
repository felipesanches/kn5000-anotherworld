-- Clean re-test: does the firmware register TWO panel buttons at once? Hold RIGHT+FIRE
-- steadily (set once, no per-frame churn) and sample the whole switch-shadow region.
-- Panel shadow is firmware-global, so no game load needed.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local RIGHT=F(":cpanel:CPR_SEG1","PART SELECT RIGHT 1 (SW1)")  -- seg 0x0d, 0x5006BE61 b1
local FIRE =F(":cpanel:CPR_SEG5","SUSTAIN (SW3)")              -- seg 0x11, 0x5006BE65 b3
local LEFT =F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)")     -- 0x5006BE62 b0
local function hx(a,n) local t={} for i=0,n-1 do t[#t+1]=string.format("%02x",sp:read_u8(a+i)) end return table.concat(t," ") end
local phase=0
emu.register_periodic(function()
 local t=M.time:as_double()
 if phase==0 and t>14 then
   RIGHT:set_value(1); FIRE:set_value(1)   -- hold BOTH, once
   print("holding RIGHT(BE61.b1) + FIRE(BE65.b3)"); phase=1; p1=t
 end
 if phase==1 and t>p1 and (math.floor((t-p1)*5)~=last) then
   last=math.floor((t-p1)*5)
   print(string.format("t+%.1f  edgeShadow[BE50..57]=%s  lvlShadow[BE60..69]=%s  R=%d F=%d",
     t-p1, hx(0x5006BE50,8), hx(0x5006BE60,10),
     (sp:read_u8(0x5006BE61)&2)~=0 and 1 or 0, (sp:read_u8(0x5006BE65)&8)~=0 and 1 or 0))
   if t-p1>1.5 then
     -- now add LEFT too (three held) to be thorough
     if phase==1 then LEFT:set_value(1); print("added LEFT(BE62.b0)"); phase=2; p2=t end
   end
 end
 if phase==2 and t>p2+1.0 then
   print(string.format("THREE held: lvlShadow[BE60..69]=%s  R=%d L=%d F=%d", hx(0x5006BE60,10),
     (sp:read_u8(0x5006BE61)&2)~=0 and 1 or 0,(sp:read_u8(0x5006BE62)&1)~=0 and 1 or 0,(sp:read_u8(0x5006BE65)&8)~=0 and 1 or 0))
   M:exit()
 end
end)
