-- Find the "physically held" indicator (clears immediately on key-up, unlike the sounding
-- mask 0x500D288C which lingers through the release envelope). Hold C4, then release and
-- sample the node record + both masks every frame; see what flips AT release vs later.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local function Fp(tag,name) local p=M.ioport.ports[tag]; for _,f in pairs(p.fields) do if f.name==name then return f end end end
local SD=Fp(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local C4=Fany("C4")
local BASE=0x500D1278; local SMASK=0x500D288C; local GMASK=0x500D287C
local function heldslot() for byte=0,15 do local v=sp:read_u8(SMASK+byte); for bit=0,7 do if (v&(1<<bit))~=0 then return byte*8+bit end end end return -1 end
local function nodehex(s) local b=BASE+s*0x2C; local h={} for i=0,0x2B do h[#h+1]=string.format("%02x",sp:read_u8(b+i)) end return table.concat(h,"") end
local function maskbit(addr,s) return (sp:read_u8(addr+(s>>3))&(1<<(s&7)))~=0 and 1 or 0 end
local ph="sd"; local slot=-1; local relT=nil; local lasthex=nil; local lastframe=-1
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="hold" end
 elseif ph=="hold" then
   if t>14 then C4:set_value(1); ph="wait"; p=t end
 elseif ph=="wait" then
   if t>p+0.6 then slot=heldslot(); print(string.format("C4 held on slot %d: node=%s S=%d G=%d",slot,nodehex(slot),maskbit(SMASK,slot),maskbit(GMASK,slot)))
     C4:set_value(0); relT=t; ph="rel" end
 elseif ph=="rel" then
   local dt=t-relT
   local hx=nodehex(slot)
   local line=string.format("rel+%.3f node=%s S=%d G=%d", dt, hx, maskbit(SMASK,slot), maskbit(GMASK,slot))
   if hx~=lasthex then lasthex=hx; print("  "..line) end
   if dt>0.4 then M:exit() end
 end
end)
