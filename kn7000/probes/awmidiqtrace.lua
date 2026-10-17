-- awmidiqtrace.lua -- producer and consumer of each input ring, byte by byte.
--
-- Logs every rd/wr pointer write of the MIDI IN 1 ring (Q1, header 0x5001F060) and the two
-- keybed rings (Q2 0x5001F874, Q4 0x5002049C) with the PC and the byte enqueued. Answer
-- (program 942, 2026-10-17): the lib enqueue (PC 0x4C024D3C) writes all three; Q1 is read
-- right after each received byte (lib dequeue 0x4C024D68), Q2/Q4 are drained one byte per
-- ~0.32 ms -- MIDI baud, i.e. the MIDI OUT transmit ISRs (return addresses 0x484B1F18 and
-- 0x484B2192). Keybed notes arrive as MIDI with running status (C3 release = "30 00").
-- Keys: C6 at 17.0-17.3 s; C3+E3 overlapped at 17.6-18.2 s. MIDI: the SMF from gen_q_mid.py.
-- Run as awmidiq.lua (same command, this file as the autoboot script).
local M=manager.machine; local cpu=M.devices[":maincpu"]; local sp=cpu.spaces["program"]
local H={[0x5001F060]="Q1",[0x5001F874]="Q2",[0x5002049C]="Q4"}
AWMQT_TAPS={}
for h,nm in pairs(H) do
  AWMQT_TAPS[#AWMQT_TAPS+1]=sp:install_write_tap(h+8,h+15,"q"..nm,function(o,d,m)
    local t=M.time:as_double(); if t<13.9 then return end
    local which=(o==h+8) and "rd" or "wr"
    local s=""; if which=="wr" then s=string.format(" byte=%02X",sp:read_u8(sp:read_u32(h+12))) end
    print(string.format("t=%.4f %s %s=%08X pc=%08X ret=%08X%s",t,nm,which,d,cpu.state["PC"].value,
      sp:read_u32(cpu.state["SP"].value),s)) end)
end
local K={}
for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do local p=M.ioport.ports[tag]
  if p then for _,f in pairs(p.fields) do if f.name=="C6" or f.name=="C3" or f.name=="E3" then K[f.name]=f end end end end
emu.register_periodic(function()
  local t=M.time:as_double()
  K.C6:set_value((t>17.0 and t<17.3) and 1 or 0)
  K.C3:set_value((t>17.6 and t<18.0) and 1 or 0)
  K.E3:set_value((t>17.8 and t<18.2) and 1 or 0)
  if t>18.6 then M:exit() end
end)
