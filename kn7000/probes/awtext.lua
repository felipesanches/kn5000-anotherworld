-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Capture the computer-terminal / text scene of the Another World intro, to verify
-- DRAW_STRING (op 0x12) now renders glyphs. The reference (vm-gui) trace shows
-- DRAW_STRING executing on VM frames 1120..1897; we snapshot the MAME LCD at a set of
-- target frames in that window (first time FRAME_NO reaches each), log which snapshot
-- index maps to which frame, then exit.
-- Run via mame-pr/kn7000 (unpatched) with -str to clear the warning screen.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function u16(a) return sp:read_u16(a) end
local function u32(a) return sp:read_u32(a) end
local FRAME_NO=0x4408007C
local AW_LOADED_FLAG=0x44080020
local FALLBACK=tonumber(os.getenv("FALLBACK") or "300")
-- target VM frames across the DRAW_STRING window (1120..1897); 1100 is a just-before baseline.
local targets={1100,1130,1160,1200,1260,1340,1460,1600,1740,1880}
local ti=1
local seq=0
local pressed=false
local dumped=false
local function u8(a) return sp:read_u8(a) end
local function hexbytes(base,n) local s="" for i=0,n-1 do s=s..string.format("%02X ",u8(base+i)) end return s end
local log=io.open(os.getenv("TEXT_LOG") or "build/awtext.log","w")
log:write(string.format("loaded_flag(start)=0x%04X\n", u16(AW_LOADED_FLAG)))
log:flush()
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if not pressed then return end
  -- once resources are loaded, dump the first bytes of the three new blobs to prove
  -- the SD files landed (the loaded flag alone is set even if an fopen failed).
  if not dumped and u16(AW_LOADED_FLAG)==0x600D then
    dumped=true
    log:write(string.format("AW_FONT[0..15]  = %s\n", hexbytes(0x44480000,16)))
    log:write(string.format("AW_STRIDX[0..15]= %s\n", hexbytes(0x44490000,16)))
    log:write(string.format("AW_STRDAT[0..31]= %s\n", hexbytes(0x444A0000,32)))
    log:flush()
  end
  local f=u16(FRAME_NO)
  if ti<=#targets and f>=targets[ti] then
    M.video:snapshot()
    -- Also dump the raw 320x200 AW canvas straight from the LCD framebuffer (RGB565),
    -- so the text can be read pixel-perfect without the panel bezel / scaling.
    -- FB=0x9CE00000, stride 1280 B/row, canvas placed at (AW_X0=160, AW_Y0=20).
    local FB=0x9CE00000
    local fn=string.format("build/canvas_%04d.bin", seq)
    local fh=io.open(fn,"wb")
    for yy=0,199 do
      local rowbase=FB + (20+yy)*1280 + 160*2
      local parts={}
      for xx=0,319 do
        local v=u16(rowbase + xx*2)
        parts[xx+1]=string.char(v & 0xFF, (v>>8) & 0xFF)
      end
      fh:write(table.concat(parts))
    end
    fh:close()
    log:write(string.format("snapshot %04d  VM frame=%d  (target %d)  loaded=0x%04X  canvas=%s\n",
      seq, f, targets[ti], u16(AW_LOADED_FLAG), fn))
    log:flush()
    seq=seq+1
    ti=ti+1
  end
  if ti>#targets or t>FALLBACK then
    log:write(string.format("done: last VM frame=%d, snapshots=%d\n", f, seq))
    log:close()
    M:exit()
  end
end)
