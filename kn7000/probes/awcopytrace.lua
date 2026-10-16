-- Verify bug-2 fix: trace CopyPage (srcId, resolved src ptr, vscroll) from 0x44080050.
-- Reach water, hold A5 (down) to make Lester swim / scroll, and print unique traces.
-- src=0x83 must resolve to page 3 (0x44130000), not page 0 (0x44100000), and carry vscroll.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local function Fany(name) for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do
    local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local A5=Fany("A5"); local C6=Fany("C6"); local F5=Fany("F5")
local CURPART=0x4407102A; local REQPART=0x4407102C
local seen={}
local function trace()
  local src=sp:read_u32(0x44080050); local ptr=sp:read_u32(0x44080054); local vs=sp:read_u32(0x44080058)
  local key=string.format("%08x_%08x_%08x",src,ptr,vs)
  if not seen[key] then seen[key]=true
    local vss= vs>=0x8000 and (vs-0x100000000) or vs   -- not needed; vs is 32-bit signed-ish
    print(string.format("CopyPage src=0x%X -> srcPtr=0x%08X vscroll=%d (page %d)", src&0xff, ptr, (vs<0x80000000 and vs or vs-0x100000000), (ptr-0x44100000)//0x10000))
  end
end
local ph="sd"; local tw
emu.register_periodic(function()
 local t=M.time:as_double()
 if ph=="sd" then if t>11 then SD:set_value(1) end; if t>11.4 then SD:set_value(0); ph="i" end
 elseif ph=="i" then if sp:read_u16(CURPART)==0x3E81 then ph="w" end; if t>90 then print("TIMEOUT"); M:exit() end
 elseif ph=="w" then sp:write_u16(REQPART,0x3E82)
   if sp:read_u16(CURPART)==0x3E82 then tw=t; ph="t"; print("water") end
   if t>130 then print("TIMEOUT w"); M:exit() end
 elseif ph=="t" then
   local rel=t-tw
   if rel>0.3 and rel<6 then if A5 then A5:set_value(1) end end       -- swim down to scroll
   if rel>6 then if A5 then A5:set_value(0) end; if C6 then C6:set_value(1) end end
   trace()
   if rel>9 then M:exit() end
 end
end)
