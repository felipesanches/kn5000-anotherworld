-- awmidi2loss.lua -- does MIDI IN 2 keep every byte while the SP7001 plug-in runs?
--
-- Feeds an SMF on -midiin2, optionally launches the plug-in (M2_SD=1 presses SD CARD LOAD at
-- 11 s), logs every SC2 receive-register read (0x34000829) between 14.5 and 14.8 s with its PC and
-- PSW, and dumps the MIDI IN 2 receive ring (header 0x5001FC88) at 15.0 and 18.5 s.
-- Answer (program 942, 2026-10-17, input probes/sessions/...-misinput1 via events_to_mid.py):
--   M2_SD=0: ring 90 3C 4C 80 3C 40 90 52 56 90 3C 4A   -- every byte, each read ~0.4 ms after it
--   M2_SD=1: ring 90 4C 40 56 4A                        -- bytes lost: the read comes ~4 ms after
--            the byte, so back-to-back MIDI bytes (0.32 ms apart) overwrite each other in the UART.
-- In both cases the reader (PC 0x484B28E2) runs with PSW IE=0, IM=7 -- the base mask level, not
-- an interrupt level the way the MIDI IN 1 ISR runs (IM=1) -- i.e. MIDI IN 2 is polled, and the
-- poll slows down while the plug-in runs.
-- MIDI IN 1 keeps every byte in the same state (raw_vs_applied: 0 wrong ticks), so the game
-- reads MIDI IN 1 only.
--   python3 -I probes/events_to_mid.py probes/sessions/2026-10-17-fsanches-misinput1-events.csv ~/compartilhado/tmp/mi.mid
--   cd ~/compartilhado && M2_SD=1 ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets \
--     -skip_gameinfo -window kn7000 -bios sp7001 \
--     -harddisk ~/compartilhado/kn5000-anotherworld/kn7000/build/another_sd.img \
--     -midiin2 ~/compartilhado/tmp/mi.mid -autoboot_script <this file> -str 20
local M=manager.machine; local cpu=M.devices[":maincpu"]; local sp=cpu.spaces["program"]
local function dump(h,nm) local st=sp:read_u32(h); local wr=sp:read_u32(h+12); local s={}
  for a=st,wr-1 do s[#s+1]=string.format("%02X",sp:read_u8(a)) end
  print(string.format("t=%.2f %s ring: %s", M.time:as_double(), nm, table.concat(s," "))) end
AWM2_RX=sp:install_read_tap(0x34000828,0x3400082B,"sc2rx",function(o,d,m)
  local t=M.time:as_double(); if t<14.5 or t>14.8 or (m & 0xff00)==0 then return end
  local psw=cpu.state["PSW"].value
  print(string.format("t=%.5f SC2 RXD=%02X pc=%08X PSW=%04X IE=%d IM=%d",t,(d>>8)&0xff,cpu.state["PC"].value,
    psw,(psw>>11)&1,(psw>>8)&7)) end)
local SD; do local p=M.ioport.ports[":cpanel:CPR_SEG1"]; for _,f in pairs(p.fields) do if f.name=="SD CARD LOAD (SW7)" then SD=f end end end
local launch=os.getenv("M2_SD")=="1"
local done1=false
emu.register_periodic(function() local t=M.time:as_double()
  if launch then SD:set_value((t>11 and t<11.4) and 1 or 0) end
  if t>15.0 and not done1 then done1=true; dump(0x5001FC88,"MIDI IN 2") end
  if t>18.5 then dump(0x5001FC88,"MIDI IN 2"); M:exit() end end)
