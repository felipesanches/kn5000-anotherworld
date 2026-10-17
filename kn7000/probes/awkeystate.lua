-- awkeystate.lua -- does the firmware keep a held-key table for the keybed (or MIDI IN)?
-- Snapshots work RAM 0x50000000..0x501FFFFF in states with known held notes; keystate_find.py
-- then searches them for bits/bytes that track each note exactly. Keybed: C6(84) 17.0-17.3 s;
-- C3(48) 17.6-18.0; E3(52) 17.8-18.2. MIDI (gen_q2_mid.py): 84 at 19.0-19.3; 48 at 19.6-20.0;
-- 52 at 19.8-20.2 (channel 1). Answer (program 942, 2026-10-17): no per-note held-key table for
-- either source. The exact matches are bits of TG voice nodes (0x500D1xxx: node+0x0E nonzero
-- while sounding) and the voice held mask (0x500D2894..), one single-note coincidence
-- (0x5003AC66.0), and last-note registers (0x5009261C, 0x500AE69E) that never clear.
--   python3 -I probes/gen_q2_mid.py ~/compartilhado/tmp/q2.mid; mkdir -p ~/compartilhado/tmp/ks
--   cd ~/compartilhado && KS_OUT=$HOME/compartilhado/tmp/ks ~/compartilhado/mame-pr/kn7000 \
--     -rompath ~/compartilhado/technics_romsets -skip_gameinfo -window kn7000 -bios sp7001 \
--     -harddisk ~/compartilhado/kn5000-anotherworld/kn7000/build/another_sd.img \
--     -midiin1 ~/compartilhado/tmp/q2.mid -autoboot_script <this file> -str 40
--   python3 -I probes/keystate_find.py ~/compartilhado/tmp/ks
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local OUT=os.getenv("KS_OUT")
local SNAP={{16.9,"idle0"},{17.15,"kb84"},{17.45,"idle1"},{17.7,"kb48"},{17.9,"kb48_52"},{18.1,"kb52"},{18.4,"idle2"},
            {19.15,"mi84"},{19.45,"idle3"},{19.7,"mi48"},{19.9,"mi48_52"},{20.1,"mi52"},{20.4,"idle4"}}
local si=1
local K={}
for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do local p=M.ioport.ports[tag]
  if p then for _,f in pairs(p.fields) do if f.name=="C6" or f.name=="C3" or f.name=="E3" then K[f.name]=f end end end end
emu.register_periodic(function()
  local t=M.time:as_double()
  K.C6:set_value((t>17.0 and t<17.3) and 1 or 0)
  K.C3:set_value((t>17.6 and t<18.0) and 1 or 0)
  K.E3:set_value((t>17.8 and t<18.2) and 1 or 0)
  local s=SNAP[si]
  if s and t>=s[1] then local f=io.open(OUT.."/"..s[2]..".bin","wb"); f:write(sp:read_range(0x50000000,0x501FFFFF,8)); f:close()
    print("snap",s[2],t); si=si+1 end
  if t>20.6 then M:exit() end
end)
