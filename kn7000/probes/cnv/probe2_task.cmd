# probe2_task.cmd -- a tools/rigs/remote.lua command file (kn7000_mame); run with run_probe.sh (README.md)
wait 30
lua _G.RD=function(tag) local sp=manager.machine.devices[":maincpu"].spaces["program"] local s={} for i=0,0x7f do local b=sp:read_u8(0x502E0200+i) if b~=0 then s[#s+1]=string.format("%02X:%02X",0x40+i,b) end end emu.print_error(string.format("PROBE %s hb=%d entries=%d cre=%d id=%d sta=%d mout=%08X title=%08X/%08X ms=%d seen=%s", tag, sp:read_u32(0x502E0000), sp:read_u32(0x502E0020), sp:read_u32(0x502E0024), sp:read_u32(0x502E0028), sp:read_u32(0x502E002C), sp:read_u32(0x502E0010), sp:read_u32(0x502E0014), sp:read_u32(0x502E001C), sp:read_u32(0x502E0018), table.concat(s," "))) end
lua _G.KP=function(v) local pp=manager.machine.ioport.ports[":KEYS1"] for _,f in pairs(pp.fields) do if f.mask==0x0100 then f:set_value(v) end end end
snap
press CPR_SEG1 04
wait 4
snap
press CPL_SEG0 20
wait 6
snap
press CPR_SEG6 01
wait 4
snap
lua _G.RD("after-OK")
wait 2
lua _G.RD("later")
press CPR_SEG2 01 0.5
wait 1.5
lua _G.RD("after-PARTSELECT-LEFT")
lua _G.KP(1)
wait 1
lua _G.KP(0)
wait 1
lua _G.RD("after-key")
snap
press CPC_SEG11 80 0.5
wait 2
lua _G.RD("after-EXIT")
snap
wait 2
lua _G.RD("after-EXIT+2s")
