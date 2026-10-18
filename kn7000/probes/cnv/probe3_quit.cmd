# probe3_quit.cmd -- a tools/rigs/remote.lua command file (kn7000_mame); run with run_probe.sh (README.md)
wait 30
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
lua _G.RD=function(tag) local sp=manager.machine.devices[":maincpu"].spaces["program"] local m={} for i=0,15 do m[#m+1]=string.format("%08X",sp:read_u32(0x502E0300+4*i)) end emu.print_error(string.format("PROBE %s hb=%d entries=%d quit=%d title=%08X/%08X mb=%s", tag, sp:read_u32(0x502E0000), sp:read_u32(0x502E0020), sp:read_u32(0x502E0030), sp:read_u32(0x502E0014), sp:read_u32(0x502E001C), table.concat(m," "))) end
lua _G.RD("running")
press CPC_SEG11 80 0.5
wait 2
lua _G.RD("after-EXIT")
snap
wait 3
lua _G.RD("after-EXIT+3s")
snap
press CPC_SEG11 80 0.5
wait 3
snap
press CPC_SEG11 80 0.5
wait 3
snap
