-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Dump the KN7000 VM instruction trace (TRACE_BUF, 8 bytes/entry: frame u16, thread
-- u8, opcode u8, pc u16) to a text file, one line per instruction in the format
--   <frame> <thread> <pc> <op_hex2>
-- matching the vm-gui reference trace, so the two can be diffed.
-- Run via mame-pr/kn7000 (unpatched) with -str to clear the warning screen.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function u8(a) return sp:read_u8(a) end
local function u16(a) return sp:read_u16(a) end
local function u32(a) return sp:read_u32(a) end
local TRACE_BUF=0x44800000
local TRACE_COUNT=0x44080078
local DUMP_AT = tonumber(os.getenv("DUMP_AT") or "40")
local pressed=false; local done=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not done and t>DUMP_AT then done=true
    local n = u32(TRACE_COUNT)
    local out=io.open(os.getenv("TRACE_OUT") or "build/kn7000_trace.txt","w")
    for i=0,n-1 do
      local base=TRACE_BUF + i*8
      local frame=u16(base)
      local thr=u8(base+2)
      local op=u8(base+3)
      local pc=u16(base+4)
      out:write(string.format("%d %d %d %02x\n", frame, thr, pc, op))
    end
    out:close()
    local log=io.open(os.getenv("RENDER_LOG") or "build/awtrace.log","w")
    log:write(string.format("traced %d instructions, last frame %d\n", n, u16(0x4408007C)))
    log:close()
    M:exit()
  end
end)
