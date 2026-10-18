# ram44.cmd -- a tools/rigs/remote.lua command file (kn7000_mame); run with run_probe.sh (README.md)
lua _G.W={} _G.W.b={} local sp=manager.machine.devices[":maincpu"].spaces["program"] local function tap(base) return sp:install_write_tap(base, base+0xFFFFFF, "w44"..base, function(o,d,m) local k=(o & 0xFFFFFF) >> 16 _G.W.b[k]=(_G.W.b[k] or 0)+1 return d end) end _G.W.t1=tap(0x44000000) _G.W.t2=tap(0x84000000)
lua _G.WD=function(tag) local ks={} for k,v in pairs(_G.W.b) do ks[#ks+1]=k end table.sort(ks) local s={} for _,k in ipairs(ks) do s[#s+1]=string.format("%02X:%d",k,_G.W.b[k]) end emu.print_error("W44 "..tag.." "..table.concat(s," ")) end
wait 40
lua _G.WD("boot")
snap
press CPR_SEG1 04
wait 4
snap
press CPL_SEG0 20
wait 6
snap
press CPR_SEG6 01
wait 6
snap
lua _G.WD("after-style-convert")
