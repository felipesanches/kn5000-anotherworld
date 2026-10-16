-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Press SD CARD to load, then read back the fopen/fread results the add-on stored.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("SDREAD_LOG") or "build/sdread.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local pressed=false; local done=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not done and t>30 then done=true
    L(string.format("FILE* = 0x%08X", sp:read_u32(0x44100000)))
    L(string.format("bytes read = %d", sp:read_u32(0x44100004)))
    L(string.format("done marker = 0x%04X (0xCAFE if task finished)", sp:read_u32(0x44100008)&0xffff))
    local b={} for i=0,23 do b[#b+1]=string.format("%02x",sp:read_u8(0x50200000+i)) end
    L("buffer[0..23] = "..table.concat(b))
    L("expected      = 000000000101000000000005000000015b42434000010000")
    M:exit()
  end
end)
