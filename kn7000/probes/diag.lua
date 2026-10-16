-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- After the SD button loads our .XAP, check whether our task ran: page 0 plaid at
-- 0x44000000, task slot 10, our palette, and a frame pixel in a corner the init box
-- does not cover (top-left of the AW area).
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("DIAG_LOG") or "build/diag.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local pressed=false; local done=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not done and t>26 then done=true
    L(string.format("XapEntry byte0 at 0x5029B000 = 0x%02X (0xcf if our .XAP is loaded)", sp:read_u8(0x5029B000)))
    L(string.format("page0 0x44000000 first row: %02X %02X %02X %02X %02X %02X %02X %02X",
      sp:read_u8(0x44000000),sp:read_u8(0x44000001),sp:read_u8(0x44000002),sp:read_u8(0x44000003),
      sp:read_u8(0x44000100),sp:read_u8(0x44000101),sp:read_u8(0x44000102),sp:read_u8(0x44000103)))
    L(string.format("task slot 10 (0x50380028) = 0x%08X", sp:read_u32(0x50380028)))
    L(string.format("palette[0..3] = %04X %04X %04X %04X", sp:read_u16(0x5029B394),sp:read_u16(0x5029B396),sp:read_u16(0x5029B398),sp:read_u16(0x5029B39A)))
    -- a frame pixel at the AW top-left (160,20)
    local fx=0x9CE00000 + 20*1280 + 160*2
    L(string.format("frame pixel (160,20) = 0x%04X ; (200,60) = 0x%04X", sp:read_u16(fx), sp:read_u16(0x9CE00000+60*1280+200*2)))
    M:exit()
  end
end)
