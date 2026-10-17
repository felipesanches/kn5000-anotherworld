-- What controls the pace? Measure, in the water part: (a) emulated time per VM frame
-- (FRAME_NO delta) = total frame time incl. our 30ms DLY_TSK; (b) var[0xFF] PAUSE_SLICES
-- the bytecode requests (authentic AW delay would be that * 20ms). Compares CPU/render
-- cost vs the fixed delay.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local FRAME_NO=0x4408007C; local CURPART=0x4407102A; local REQPART=0x4407102C
local VARFF=0x44070000+0xFF*2
local ph="sd"; local lf=-1; local lt=nil; local n=0; local sumdt=0; local mindt=99; local maxdt=0
local ffseen={}
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then ph="t" end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local fn=sp:read_u16(FRAME_NO)
   if fn~=lf then
     local ff=sp:read_u16(VARFF)
     ffseen[ff]=(ffseen[ff] or 0)+1
     if lt then local dt=(t-lt)*1000; n=n+1; sumdt=sumdt+dt; if dt<mindt then mindt=dt end; if dt>maxdt then maxdt=dt end
       if n<=12 then print(string.format("frame %d: dt=%.1f ms  var[0xFF]=%d", fn, dt, ff)) end end
     lt=t; lf=fn
   end
   if n>=60 then
     print(string.format("---- avg frame %.1f ms (min %.1f max %.1f); our fixed DLY=30ms ----", sumdt/n, mindt, maxdt))
     local keys={}; for k,_ in pairs(ffseen) do keys[#keys+1]=k end; table.sort(keys)
     local s=""; for _,k in ipairs(keys) do s=s..string.format("%d(x%d) ",k,ffseen[k]) end
     print("var[0xFF] PAUSE_SLICES values seen: "..s.."  (authentic delay = value * 20ms)")
     M:exit()
   end
 end
end)
