-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("RENDER_LOG") or "build/render.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function s16(a) local v=sp:read_u16(a); if v>=0x8000 then v=v-0x10000 end return v end
local pressed=false; local done=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not done and t>34 then done=true
    local S=0x44050000
    L(string.format("DrawSpanN calls=%d  STEP1=%d STEP2=%d POLY_H(final)=%d",
      sp:read_u32(0x44060000), sp:read_u32(S+0x2C), sp:read_u32(S+0x30), (function() local v=sp:read_u16(S+0x1A); if v>=0x8000 then v=v-0x10000 end return v end)()))
    L(string.format("VM: NUM=%d XMIN=%d XMAX=%d YMIN=%d YMAX=%d HLINEY=%d",
      sp:read_u8(S), s16(S+6),s16(S+8),s16(S+0xA),s16(S+0xC),s16(S+0xE)))
    L(string.format("points = (%d,%d)(%d,%d)(%d,%d)(%d,%d)  X1init region: see STEP",
      sp:read_u16(S+0x40),sp:read_u16(S+0x42),sp:read_u16(S+0x44),sp:read_u16(S+0x46),
      sp:read_u16(S+0x48),sp:read_u16(S+0x4A),sp:read_u16(S+0x4C),sp:read_u16(S+0x4E)))
    local nz=0; for i=0,63999 do if sp:read_u8(0x44100000+i)~=0 then nz=nz+1 end end
    L("page-0 non-zero bytes: "..nz)
    for y=0,199,8 do
      local line={}
      for x=0,319,8 do local c=sp:read_u8(0x44100000 + y*320 + x); line[#line+1]= (c==0) and "." or string.format("%X",c&15) end
      L(table.concat(line))
    end
    M.video:snapshot()
    M:exit()
  end
end)
