-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Diagnostic: at a target VM frame, dump all four AW pages (as colour indices), the
-- three page pointers (draw/display/back), and the RGB565 palette. Used to find out why
-- a DRAW_STRING that the reference draws every frame is not visible on the LCD: is the
-- text on the draw page but not the displayed one, or drawn in a colour equal to the bg?
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function u8(a) return sp:read_u8(a) end
local function u16(a) return sp:read_u16(a) end
local function u32(a) return sp:read_u32(a) end
local FRAME_NO=0x4408007C
local CUR_PAGE_1=0x44071008
local CUR_PAGE_2=0x4407100C
local CUR_PAGE_3=0x44071010
local PAGES={0x44100000,0x44110000,0x44120000,0x44130000}
local PALETTE=tonumber(os.getenv("PALETTE_ADDR") or "0")  -- optional absolute palette addr
local TARGET=tonumber(os.getenv("TARGET") or "1130")
local pressed=false; local done=false
local log=io.open("build/awpagedump.log","w")
local function dumppage(base, fn)
  local fh=io.open(fn,"wb")
  for off=0,320*200-1,320 do
    local parts={}
    for x=0,319 do parts[x+1]=string.char(u8(base+off+x)) end
    fh:write(table.concat(parts))
  end
  fh:close()
end
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not pressed or done then return end
  local f=u16(FRAME_NO)
  if f>=TARGET then
    done=true
    local p1,p2,p3=u32(CUR_PAGE_1),u32(CUR_PAGE_2),u32(CUR_PAGE_3)
    local pcur=u32(0x44050034)  -- CUR_PAGE (polygon pipeline's resolved page)
    log:write(string.format("frame=%d CUR_PAGE_1(draw)=0x%08X CUR_PAGE_2(disp)=0x%08X CUR_PAGE_3(back)=0x%08X CUR_PAGE(poly)=0x%08X\n", f,p1,p2,p3,pcur))
    for i,base in ipairs(PAGES) do
      log:write(string.format("PAGE_%d = 0x%08X%s\n", i-1, base,
        (base==p1 and "  <=DRAW" or "")..(base==p2 and "  <=DISPLAY" or "")..(base==p3 and "  <=BACK" or "")))
      dumppage(base, string.format("build/page%d_f%d.bin", i-1, TARGET))
    end
    if PALETTE~=0 then
      local s=""
      for i=0,15 do s=s..string.format("%04X ", u16(PALETTE+i*2)) end
      log:write("palette RGB565: "..s.."\n")
    end
    log:close()
    M:exit()
  end
end)
