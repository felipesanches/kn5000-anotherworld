-- Functional proof that panel input drives the game: reach the water part, optionally
-- hold a direction (AWHOLD=up|left|...), and log a checksum of the DISPLAYED page at
-- several water-frames. Divergence between held and not-held runs => input moves Lester.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local BTN={right=F(":cpanel:CPR_SEG1","PART SELECT RIGHT 1 (SW1)"),
           left =F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)"),
           up   =F(":cpanel:CPR_SEG6","R1/R2 OCTAVE + (SW1)"),
           down =F(":cpanel:CPR_SEG7","R1/R2 OCTAVE - (SW1)")}
local HOLD=os.getenv("AWHOLD")
local CURPART=0x4407102A; local REQPART=0x4407102C; local FRAME_NO=0x4408007C
local function pagesum() local base=sp:read_u32(0x4407100C); if base<0x44100000 or base>=0x44200000 then return -1 end
  local s=0; local str=sp:read_range(base,base+63999,8); for i=1,#str,7 do s=(s+str:byte(i))&0xFFFFFF end; return s end
local st="sd"; local f0=nil
emu.register_periodic(function()
 local t=M.time:as_double()
 if st=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); st="intro" end
 elseif st=="intro" then if sp:read_u16(CURPART)==0x3E81 then st="toWater" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif st=="toWater" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then f0=sp:read_u16(FRAME_NO); if HOLD and BTN[HOLD] then BTN[HOLD]:set_value(1) end
     print(string.format("water @t=%.1f f0=%d hold=%s",t,f0,HOLD or "none")); st="run" end
   if t>130 then print("TIMEOUT water"); M:exit() end
 elseif st=="run" then
   local df=sp:read_u16(FRAME_NO)-f0
   if df==10 or df==20 or df==30 or df==40 then
     print(string.format("waterframe %2d  pagesum=%06x",df,pagesum()))
   end
   if df>=42 then M:exit() end
 end
end)
