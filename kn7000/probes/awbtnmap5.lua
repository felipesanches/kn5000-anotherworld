-- awbtnmap5.lua -- where do HELP, OTHER PART & FR, PAGE UP, PAGE DOWN and EXIT show in the
-- firmware's debounced button bitmap? Holds each for 0.6 s (after SD CARD LOAD, game running) and
-- diffs 0x5006BE40..BF. Answer (2026-10-17): HELP 0x5006BE95 bit 0x02, OTHER PART & FR 0x5006BE95
-- bit 0x01, PAGE UP / PAGE DOWN / EXIT 0x5006BE9B bits 0x10 / 0x20 / 0x80 (vm.inc BTN_*).
--   ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets -skip_gameinfo -window \
--     kn7000 -bios sp7001 -harddisk build/another_sd.img -autoboot_script probes/awbtnmap5.lua -str 60
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local function F(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=F(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local B={{"HELP",F(":cpanel:CPC_SEG5","HELP (SW1)")},{"OTHER PART",F(":cpanel:CPC_SEG5","OTHER PART & FR (SW0)")},
         {"PAGE UP",F(":cpanel:CPC_SEG11","PAGE UP (SW4)")},{"PAGE DOWN",F(":cpanel:CPC_SEG11","PAGE DOWN (SW5)")},{"EXIT",F(":cpanel:CPC_SEG11","EXIT (SW7)")}}
local function snap() local t={} for a=0x5006BE40,0x5006BEBF do t[a]=sp:read_u8(a) end return t end
local base; local i=1; local t0=30
emu.register_periodic(function() local t=M.time:as_double(); SD:set_value((t>11 and t<11.4) and 1 or 0)
  if t<t0 then return end
  local b=B[i]; if not b then M:exit(); return end
  local ph=t-t0-(i-1)*1.5
  if ph<0.1 then base=base or snap() elseif ph<0.7 then b[2]:set_value(1)
    if ph>0.6 and not b.done then b.done=true; local s=snap(); local out={}
      for a=0x5006BE60,0x5006BEBF do if s[a]~=base[a] then out[#out+1]=string.format("%08X:%02X->%02X",a,base[a],s[a]) end end
      print(b[1].." -> "..table.concat(out," ")) end
  elseif ph<1.5 then b[2]:set_value(0) else i=i+1; base=nil end end)
