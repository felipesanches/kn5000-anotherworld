-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
-- Licensed under the terms of the GNU General Public License v3 or later
--
-- How much memory can a KN7000 SP7001 app get from the firmware heap (malloc_X)?
-- Read-only: after boot, and again after the SD CARD button opens the SD screen,
-- log the heap break 0x500006E8, the bytes left to grow 0x500006EC, and the free
-- list at 0x500006F0 (each block: +0 next, +4 size). Program 942 (-bios sp7001).
-- Output: $HEAP_PROBE_LOG (default heap_probe.log).
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("HEAP_PROBE_LOG") or "heap_probe.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function dump(label)
  local brk, left = sp:read_u32(0x500006E8), sp:read_u32(0x500006EC)
  local n, total, maxb, node = 0, 0, 0, sp:read_u32(0x500006F0)
  while node ~= 0 and n < 10000 do
    local size = sp:read_u32(node+4); n=n+1; total=total+size; if size>maxb then maxb=size end
    node = sp:read_u32(node)
  end
  L(string.format("%s: break 0x%08X, %d bytes left to grow (%.1f KB); free list %d blocks, %d bytes, largest %d",
    label, brk, left, left/1024, n, total, maxb))
end
local stage=0
emu.register_periodic(function()
  local t=M.time:as_double()
  if stage==0 and t>10 then dump("after boot"); stage=1 end
  if stage==1 and t>11 then SD:set_value(1); stage=2 end
  if stage==2 and t>11.4 then SD:set_value(0); stage=3 end
  if stage==3 and t>22 then dump("SD screen open"); M:exit() end
end)
