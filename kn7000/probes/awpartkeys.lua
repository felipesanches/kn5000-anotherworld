-- awpartkeys.lua -- play a part from its start with scripted keybed presses, recorded by awmonitor.
--
-- Enters AW_START_PART at the end of tick 0 (as awcksum.lua / awreplay.lua do) and then presses
-- keybed keys on a schedule RELATIVE to the part start: AW_KEYS = "t:note:on,t:note:on,..."
-- (t in seconds after the switch, on = 1/0). awmonitor.lua (loaded first) records the raw key
-- events and the applied hero vars, so raw_vs_applied.py checks ReadInput in that part, and the
-- inputs.csv replays into both VMs (awreplay.lua / replaycksum, both with START_PART).
--   AW_SESSION=prison AW_START_PART=0x3E83 AW_KEYS="$(python3 -I probes/gen_shake_keys.py)" \
--   ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets -skip_gameinfo -window \
--     kn7000 -bios sp7001 -harddisk build/another_sd.img -autoboot_script probes/awpartkeys.lua -str 120
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
dofile(here .. "awmonitor.lua")
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local P=tonumber(os.getenv("AW_START_PART")); local FRAME_NO=0x4408007C
local NAMES={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local function fname(n) local nm=NAMES[n%12+1]; local o=n//12-1
  if nm:sub(2,2)=="#" then return nm:sub(1,1)..o.."#" end; return nm..o end
local F={}
for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do local p=M.ioport.ports[tag]
  if p then for _,f in pairs(p.fields) do F[f.name]=f end end end
local EV={}
for t,n,on in (os.getenv("AW_KEYS") or ""):gmatch("([%d.]+):(%d+):(%d)") do EV[#EV+1]={tonumber(t),tonumber(n),on=="1"} end
table.sort(EV, function(a,b) return a[1]<b[1] end)
local t0=nil
AWPK_TAP=sp:install_write_tap(FRAME_NO,FRAME_NO+3,"awpk",function(o,d,m)
  if o==FRAME_NO and (d&0xffff)==1 and P then sp:write_u16(0x4407102C,P) end end)
local ei=1
emu.register_periodic(function()
  local t=M.time:as_double()
  if not t0 and sp:read_u16(0x4407102A)==P then t0=t; print(string.format("awpartkeys: part %04X at %.2f s", P, t)) end
  if t0 then while ei<=#EV and EV[ei][1]<=t-t0 do local e=EV[ei]; local f=F[fname(e[2])]
    if f then f:set_value(e[3] and 1 or 0) end; ei=ei+1 end end
end)
