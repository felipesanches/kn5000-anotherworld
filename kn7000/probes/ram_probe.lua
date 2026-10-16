-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>
-- Licensed under the terms of the GNU General Public License v3 or later
--
-- Which large RAM windows can an SP7001 app actually use on the KN7000?
-- Write a marker to several candidate addresses and read it back (MAME maps the
-- real decoded windows; an unmapped write reads back 0). Read/write only.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("RAM_PROBE_LOG") or "ram_probe.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local tests={0x44000000,0x44800000,0x44FF0000,0x4C800000,0x4CF00000,0x50300000,0x503F0000,
             0x9CE00000,0x9CE80000,0x9CF00000,0x56000000,0x96800000,0x45000000,0x48000000}
local done=false
emu.register_periodic(function()
  if done or M.time:as_double()<8 then return end
  done=true
  for _,a in ipairs(tests) do
    local ok=pcall(function() sp:write_u32(a,0xA5A5F00F) end)
    local rb = ok and sp:read_u32(a) or -1
    L(string.format("0x%08X : write %s, read 0x%08X %s", a, tostring(ok), rb&0xffffffff,
      (rb&0xffffffff)==0xA5A5F00F and "RAM" or "not writable"))
  end
  M:exit()
end)
