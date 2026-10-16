-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Clean diagnostic: VM state (0x44050000), page-0 non-zero count, page ASCII art.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("DUMP_LOG") or "build/dump.log","w")
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
    L(string.format("markers hook=%02X task=%02X GameInit=%02X palDone=%02X fillDone=%02X postFill=%02X",
      sp:read_u8(0x44200020),sp:read_u8(0x44200024),sp:read_u8(0x44200000),sp:read_u8(0x4420002C),sp:read_u8(0x44200030),sp:read_u8(0x44200008)))
    L(string.format("hloopHit=%02X spanHit=%02X preFill=%02X", sp:read_u8(0x4420000C), sp:read_u8(0x44200010), sp:read_u8(0x44200004)))
    L(string.format("FillPage: entered=%02X exited=%02X", sp:read_u8(0x44200034), sp:read_u8(0x44200038)))
    L(string.format("VM: NUM=%d BBOX=%dx%d XMIN=%d XMAX=%d YMIN=%d YMAX=%d HLINEY=%d",
      sp:read_u8(S+0), s16(S+2),s16(S+4), s16(S+6),s16(S+8),s16(S+0xA),s16(S+0xC),s16(S+0xE)))
    L(string.format("    X1=%d X2=%d POLY_H=%d CUR_PAGE=0x%08X CUR_LINE=0x%08X STEP1=%d STEP2=%d",
      s16(S+0x10),s16(S+0x12),s16(S+0x1A), sp:read_u32(S+0x34), sp:read_u32(S+0x20), sp:read_u32(S+0x2C), sp:read_u32(S+0x30)))
    L(string.format("    points[0..3] = (%d,%d)(%d,%d)(%d,%d)(%d,%d)",
      sp:read_u16(S+0x40),sp:read_u16(S+0x42),sp:read_u16(S+0x44),sp:read_u16(S+0x46),
      sp:read_u16(S+0x48),sp:read_u16(S+0x4A),sp:read_u16(S+0x4C),sp:read_u16(S+0x4E)))
    local nz=0; for i=0,63999 do if sp:read_u8(0x44100000+i)~=0 then nz=nz+1 end end
    L("page-0 non-zero bytes: "..nz)
    M:exit()
  end
end)
