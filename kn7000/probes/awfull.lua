-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Run the WHOLE intro: snapshot periodically (for the rendering inspection) and dump
-- the full VM instruction trace, stopping as soon as the bytecode requests the next
-- stage (REQ_NEXT_PART at 0x4407102C becomes non-zero -- a LOAD of a part id 0x3E8x),
-- which is the natural end of the intro. Falls back to a time limit.
-- Run via mame-pr/kn7000 (unpatched) with -str to clear the warning screen.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function u8(a) return sp:read_u8(a) end
local function u16(a) return sp:read_u16(a) end
local function u32(a) return sp:read_u32(a) end
local TRACE_BUF=0x44800000
local TRACE_COUNT=0x44080078
local REQ_NEXT_PART=0x4407102C
local FRAME_NO=0x4408007C
local FALLBACK = tonumber(os.getenv("FALLBACK") or "280")
local pressed=false; local done=false
local nextshot=16; local shotstep=12
local function dump(reason)
  local n = u32(TRACE_COUNT)
  local out=io.open(os.getenv("TRACE_OUT") or "build/kn7000_trace.txt","w")
  for i=0,n-1 do
    local base=TRACE_BUF + i*8
    -- entry: frame u16 @0, thread u8 @2, opcode u8 @3, pc u16 @4
    out:write(string.format("%d %d %d %02x\n", u16(base), u8(base+2), u16(base+4), u8(base+3)))
  end
  out:close()
  local log=io.open(os.getenv("RENDER_LOG") or "build/awfull.log","w")
  log:write(string.format("%s: traced %d instructions, last frame %d, REQ_NEXT_PART=0x%04X\n",
    reason, n, u16(FRAME_NO), u16(REQ_NEXT_PART)))
  log:close()
  M.video:snapshot()
end
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if done then return end
  if t>14 and t>nextshot then M.video:snapshot(); nextshot=nextshot+shotstep end
  if t>13 and u16(REQ_NEXT_PART)~=0 then
    done=true; dump("part-switch requested"); M:exit()
  elseif t>FALLBACK then
    done=true; dump("time fallback"); M:exit()
  end
end)
