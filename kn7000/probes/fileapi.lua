-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Validate the framework-object file-method offsets against a running firmware.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("FILEAPI_LOG") or "build/fileapi.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local pressed=false; local done=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not done and t>24 then done=true
    local fw=sp:read_u32(0x50299298); L(string.format("framework *(0x50299298) = 0x%08X", fw))
    local so=sp:read_u32(fw+0x2E1C);  L(string.format("subobj  *(fw+0x2E1C)     = 0x%08X", so))
    for _,off in ipairs({0x2D0,0x2D8,0x2DC}) do
      L(string.format("  subobj+0x%03X = 0x%08X", off, sp:read_u32(so+off)))
    end
    -- which task is the current running one?
    L(string.format("running task 0x5038002C = 0x%08X ; disk worker is task 8", sp:read_u32(0x5038002C)))
    M:exit()
  end
end)
