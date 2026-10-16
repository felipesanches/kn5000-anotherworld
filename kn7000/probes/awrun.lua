-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Single-dump bring-up probe: press SD CARD LOAD to launch the plug-in (and our
-- ride-along hook), let the VM run, then dump the loaded resource pointers, the VM
-- scalars, each page's fill and an ASCII view of the displayed page, and a snapshot.
-- Run through mame-pr/kn7000 (unpatched) with -str to clear the warning screen.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("RENDER_LOG") or "build/awrun.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function u8(a) return sp:read_u8(a) end
local function u16(a) return sp:read_u16(a) end
local function u32(a) return sp:read_u32(a) end
local pressed=false; local done=false
local DUMP_AT = tonumber(os.getenv("DUMP_AT") or "30")
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not done and t>DUMP_AT then done=true
    L(string.format("bytecode[0..3] @44400000 = %02X %02X %02X %02X   video1[0..3] @44420000 = %02X %02X %02X %02X",
      u8(0x44400000),u8(0x44400001),u8(0x44400002),u8(0x44400003),
      u8(0x44420000),u8(0x44420001),u8(0x44420002),u8(0x44420003)))
    L(string.format("CUR_BYTECODE=%08X VIDEO1=%08X VIDEO2=%08X PAL=%08X",
      u32(0x44071020),u32(0x44071018),u32(0x4407101C),u32(0x44071024)))
    L(string.format("CURRENT_THREAD=%d VM_PC=%d CUR_ZOOM=%d PART=%04X",
      u8(0x44071000),u16(0x44071002),u16(0x44071028),u16(0x4407102A)))
    local act=0; for th=0,63 do if u16(0x44070400+th*4)~=0xFFFF then act=act+1 end end
    L(string.format("active threads=%d", act))
    for pg=0,3 do
      local base=0x44100000+pg*0x10000
      local nz=0; for i=0,63999,7 do if u8(base+i)~=0 then nz=nz+1 end end
      L(string.format("PAGE_%d (%08X) non-zero (1/7 sampled)=%d", pg, base, nz))
    end
    local disp=u32(0x4407100C)
    if disp>=0x44100000 and disp<0x44200000 then
      L("displayed page ASCII:")
      for y=0,199,10 do
        local line={}
        for x=0,319,8 do local c=u8(disp + y*320 + x); line[#line+1]=(c==0) and "." or string.format("%X",c&15) end
        L(table.concat(line))
      end
    end
    M.video:snapshot()
    M:exit()
  end
end)
