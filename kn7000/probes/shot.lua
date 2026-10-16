-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Boot the game card, press SD CARD to load the .XAP, snapshot a few times.
local M=manager.machine
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local pressed=false; local shots={16,24,32}; local i=1
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if i<=#shots and t>shots[i] then i=i+1; M.video:snapshot(); if i>#shots then M:exit() end end
end)
