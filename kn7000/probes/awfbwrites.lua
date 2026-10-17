-- awfbwrites.lua -- who writes the LCD frame (0x9CE00000, 640x240 RGB565) while the game runs?
-- Counts writes per 2 s window, split into module (0x502B4D80..0x502C0000) vs firmware, with the
-- firmware writes' bounding box and top PCs. Presses PART SELECT LEFT, R1/R2 OCTAVE + and SUSTAIN
-- at 40..46 s. Answer (2026-10-17): during play the firmware writes nothing, except one full-frame
-- repaint (PC 0x48414FD4, 305,920 writes, x 0..638 y 1..239) when OCTAVE + was pressed -- hence
-- FillBorder on every blit (main.s). It also shows the module blitting ~33 times a second.
--   ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets -skip_gameinfo -window \
--     kn7000 -bios sp7001 -harddisk build/another_sd.img -autoboot_script probes/awfbwrites.lua -str 60
local M=manager.machine; local cpu=M.devices[":maincpu"]; local sp=cpu.spaces["program"]
local FB=0x9CE00000; local FBEND=FB+640*240*2-1
local mod,fw=0,0; local bx0,by0,bx1,by1=9999,9999,-1,-1; local pcs={}
FBT=sp:install_write_tap(FB,FBEND,"fb",function(o,d,m)
  if M.time:as_double()<20 then return end
  local pc=cpu.state["PC"].value
  if pc>=0x502B4D80 and pc<0x502C0000 then mod=mod+1 else fw=fw+1
    local px=(o-FB)//2; local x,y=px%640,px//640
    if x<bx0 then bx0=x end; if x>bx1 then bx1=x end; if y<by0 then by0=y end; if y>by1 then by1=y end
    pcs[pc]=(pcs[pc] or 0)+1 end end)
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local BTN={F(":cpanel:CPR_SEG2","PART SELECT LEFT (SW0)") or false, F(":cpanel:CPR_SEG6","R1/R2 OCTAVE + (SW1)") or false, F(":cpanel:CPR_SEG5","SUSTAIN (SW3)") or false}
local nxt=22
emu.register_periodic(function() local t=M.time:as_double(); SD:set_value((t>11 and t<11.4) and 1 or 0)
  for k,b in ipairs(BTN) do if b then b:set_value((t>38+2*k and t<39+2*k) and 1 or 0) end end
  if t>nxt then
    local top={} for pc,n in pairs(pcs) do top[#top+1]={pc,n} end; table.sort(top,function(a,b) return a[2]>b[2] end)
    local s="" for i=1,math.min(3,#top) do s=s..string.format(" %08X:%d",top[i][1],top[i][2]) end
    print(string.format("t=%.0f module=%d firmware=%d fwbox=x%d..%d y%d..%d%s",t,mod,fw,bx0,bx1,by0,by1,s))
    mod,fw=0,0; bx0,by0,bx1,by1=9999,9999,-1,-1; pcs={}; nxt=nxt+2 end
  if t>50 then M:exit() end end)
