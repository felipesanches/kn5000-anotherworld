-- awkbreplay.lua -- re-perform a recorded session on the KEYBED, under awmonitor.
--
-- Reads an awmonitor raw events file (K lines: emu time, note, on/off) and presses/releases the
-- same notes on the :KEYS ports at the same emu times (the run boots identically; a press lands
-- on the next periodic, ~16 ms). awmonitor.lua runs alongside and records the session, so
-- raw_vs_applied.py can compare what the firmware saw from the keybed with what the VM applied.
-- This is the keybed twin of re-performing a MIDI session through events_to_mid.py + -midiin1.
--   AW_KBEVENTS=probes/sessions/2026-10-17-fsanches-misinput1-events.csv AW_SESSION=kbrepro \
--   ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets -skip_gameinfo \
--     -window kn7000 -bios sp7001 -harddisk build/another_sd.img \
--     -autoboot_script probes/awkbreplay.lua -str 80
--   python3 -I probes/raw_vs_applied.py ~/compartilhado/tmp/aw-kbrepro
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
dofile(here .. "awmonitor.lua")
local M=manager.machine
local NAMES={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local function fname(n) local nm=NAMES[n%12+1]; local o=n//12-1      -- ioport names: "C6", "A5#"
  if nm:sub(2,2)=="#" then return nm:sub(1,1)..o.."#" end; return nm..o end
local F={}
for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do local p=M.ioport.ports[tag]
  if p then for _,f in pairs(p.fields) do F[f.name]=f end end end
local EV={}
for l in io.lines(os.getenv("AW_KBEVENTS")) do
  local k,t,note,on=l:match("^(K),([%d.]+),%d+,(%d+),(%d)")
  if k then EV[#EV+1]={tonumber(t),tonumber(note),on=="1"} end end
print("awkbreplay: "..#EV.." key events")
local ei=1; local miss={}
emu.register_periodic(function()
  local t=M.time:as_double()
  while ei<=#EV and EV[ei][1]<=t do local e=EV[ei]; local f=F[fname(e[2])]
    if f then f:set_value(e[3] and 1 or 0) elseif not miss[e[2]] then miss[e[2]]=true; print("no key for note "..e[2]) end
    ei=ei+1 end
end)
