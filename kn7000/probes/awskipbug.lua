-- Why does the intro skip with no key? Log the OLD skip signal (0x50149690) vs the
-- held-slot bitmap (0x500D288C, any bit) and the part id, with NO key pressed.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local CURPART=0x4407102A; local FRAME_NO=0x4408007C; local MASK=0x500D288C
local function masknz() for b=0,15 do if sp:read_u8(MASK+b)~=0 then return 1 end end return 0 end
local ph="sd"; local lf=-1; local printed=0
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="run" end
 elseif ph=="run" then
   local fn=sp:read_u16(FRAME_NO)
   if fn~=lf then lf=fn
     if printed<30 then printed=printed+1
       print(string.format("frame %d: part=%04x  0x50149690=%04x  heldmask_nz=%d",
         fn, sp:read_u16(CURPART), sp:read_u16(0x50149690), masknz()))
     end
   end
   if t>45 then M:exit() end
 end
end)
