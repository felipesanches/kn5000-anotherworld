# taskprobe.cmd -- a tools/rigs/remote.lua command file (kn7000_mame); run with run_probe.sh (README.md)
wait 30
lua local d=manager.machine.debugger; d:command('bp 48479929,1,{printf "CNVCALL tcb=%08X main=%08X t1=%08X t2=%08X",d@5038002c,d@50380004,d@50380008,d@5038000c; g}'); d:command('bp 484ad116,1,{printf "PANELDEC tcb=%08X",d@5038002c; g}'); d:command('g')
lua _G.PL={n=0}; _G.PL.h=emu.add_machine_frame_notifier(function() local log=manager.machine.debugger.consolelog; while _G.PL.n < #log do _G.PL.n=_G.PL.n+1; local l=log[_G.PL.n]; if l:match('^CNVCALL') or (l:match('^PANELDEC') and _G.PL.n < 400) then emu.print_error(l) end end end)
snap
press CPR_SEG1 04
wait 4
snap
press CPL_SEG0 20
wait 6
snap
press CPR_SEG6 01
wait 8
snap
lua manager.machine.debugger:command('wp 5001f870,4,w,1,{printf "MOUTWR tcb=%08X val=%08X",d@5038002c,wpdata; g}'); manager.machine.debugger:command('g'); _G.PL.n=#manager.machine.debugger.consolelog
lua _G.KP=function(v) local pp=manager.machine.ioport.ports[":KEYS1"]; for _,f in pairs(pp.fields) do if f.mask==0x0100 then f:set_value(v) end end end
lua _G.PL2=emu.add_machine_frame_notifier(function() local log=manager.machine.debugger.consolelog; while _G.PL.n < #log do _G.PL.n=_G.PL.n+1; local l=log[_G.PL.n]; if l:match('^MOUTWR') then emu.print_error(l) end end end)
press CPC_SEG11 80
wait 3
lua _G.KP(1)
wait 1
lua _G.KP(0)
wait 2
lua local sp=manager.machine.devices[":maincpu"].spaces["program"]; for _,a in ipairs({0x5001F050,0x5001F060,0x5001F864,0x5001F874}) do emu.print_error(string.format("HDR %08X: %08X %08X %08X %08X %04X", a, sp:read_u32(a), sp:read_u32(a+4), sp:read_u32(a+8), sp:read_u32(a+12), sp:read_u16(a+16))) end
snap
lua manager.machine.debugger:command('bp 4c024cbc,1,{printf "ENQ tcb=%08X a0=%08X d0=%02X",d@5038002c,a0,d0; g}'); manager.machine.debugger:command('g'); _G.PL.n=#manager.machine.debugger.consolelog
lua _G.PL3=emu.add_machine_frame_notifier(function() local log=manager.machine.debugger.consolelog; while _G.PL.n < #log do _G.PL.n=_G.PL.n+1; local l=log[_G.PL.n]; if l:match('^ENQ') then emu.print_error(l) end end end)
wait 1
lua _G.KP(1)
wait 1
lua _G.KP(0)
wait 2
