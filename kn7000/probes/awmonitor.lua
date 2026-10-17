-- awmonitor.lua -- PASSIVE live input/VM correlation monitor for the Another World port.
--
-- Runs while YOU play (it never drives game input; it only auto-presses SD CARD LOAD once to
-- launch). Every VM frame it records, and correlates:
--   * your keybed keypresses        (the :KEYS ports -- physical/host keys; MIDI-in is NOT here)
--   * what the tone generator sees  (the active-voice ring 0x500D1050 -- keybed AND MIDI-in)
--   * the panel D-pad shadow         (so the prediction matches ReadInput exactly)
--   * the applied hero variables     (var 0xFC LR, 0xE5 UD, 0xFB jump, 0xFA action, 0xFD mask)
--   * the module's sticky state       (PREV_LR_BITS 0x44080048 / PREV_UD_BITS 0x4408004A)
--   * VM context                      (CURRENT_PART, FRAME_NO)
--
-- It then PREDICTS what the hero vars should be from the inputs (the keybed map + the sticky
-- opposing-key rule) and FLAGS any frame where reality disagrees:
--   GHOST   a keybed key you pressed is missing from the ring (voice dropped / matrix ghost)
--   STICKY  the module's resolved direction != the sticky rule's expectation
--   VALUE   the applied var != the value implied by the resolved bits
--   NODIR   the ring holds a single clear direction but the applied direction is 0
-- Output, one set per session (AW_SESSION=<name>; default a timestamp), in ~/compartilhado/tmp/:
--   aw-<session>-monitor.log  human per-frame log (flags also print to the console)
--   aw-<session>-events.csv   RAW input events (keybed/MIDI make/break + panel at each ReadInput)
--                             -> replay in the reference through ITS input handling
--   aw-<session>-inputs.csv   the hero vars this VM applied -> VM-vs-VM differential replay
--
-- Run (normal speed so you can play: no -nothrottle, and no -str, which would end the session):
--   AW_SESSION=mytest ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets \
--     -skip_gameinfo -window kn7000 -bios sp7001 \
--     -harddisk ~/compartilhado/kn5000-anotherworld/kn7000/build/another_sd.img \
--     -autoboot_script ~/compartilhado/kn5000-anotherworld/kn7000/probes/awmonitor.lua
-- Add -midiin1 "<port>" to also drive it from a USB-MIDI controller.

local M  = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]

-- ---- addresses -------------------------------------------------------------------------
local VMVARS   = 0x44070000
local CURPART  = 0x4407102A
local REQPART  = 0x4407102C
local FRAMENO  = 0x4408007C
local PREV_LR  = 0x44080048
local PREV_UD  = 0x4408004A
local RING     = 0x500D1050
local RING_LO, RING_HI = 0x500D1000, 0x500D3000
local HELD     = 0x500D288C
local NODE     = 0x500D1278   -- note at +slot*0x2C+0x0C
-- panel D-pad shadow (CPR_SEGn at PANEL_CPR+n); matches vm.inc BTN_* addrs
local BTN = { {a=0x5006BE62,b=0x01,bit=2,name="L"},   -- left   -> mask 2
              {a=0x5006BE61,b=0x02,bit=1,name="R"},   -- right  -> mask 1
              {a=0x5006BE66,b=0x02,bit=8,name="U"},   -- up     -> mask 8
              {a=0x5006BE67,b=0x02,bit=4,name="D"},   -- down   -> mask 4
              {a=0x5006BE65,b=0x08,bit=0x80,name="A"} } -- fire  -> mask 0x80

-- ---- mapping (match vm.inc KBD_*) ------------------------------------------------------
local ACTION_MAX = 60
local function noteToMask(n)
  if n == 0 then return 0 end
  if n <= ACTION_MAX then return 0x80 end      -- bass/C4 = action
  if n == 77 then return 2 end                 -- F5 left
  if n == 81 then return 4 end                 -- A5 down
  if n == 84 then return 1 end                 -- C6 right
  if n == 82 or n == 83 then return 8 end      -- Bb5 / B5 up
  return 0
end
local NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local function noteName(n) return NAMES[(n%12)+1]..tostring(math.floor(n/12)-1) end

-- ---- readers ---------------------------------------------------------------------------
local function s16(a) local v=sp:read_u16(a); if v>=0x8000 then v=v-0x10000 end; return v end
local function keybedNotes()  -- user's physical keybed presses, via :KEYS ports
  local t={}
  for p=0,3 do
    local port=M.ioport.ports[":KEYS"..p]
    if port then local v=port:read()
      for bit=0,15 do if (v>>bit)&1==1 then t[#t+1]=(p*16+bit)+36 end end end
  end
  return t
end
local function ringNotes()
  local L=sp:read_u32(RING); local n=0; local seen={}; local t={}
  while L~=0 and not seen[L] and n<64 and L>=RING_LO and L<RING_HI do
    seen[L]=true; t[#t+1]=sp:read_u8(L-4); L=sp:read_u32(L); n=n+1 end
  return t
end
local function heldNotes()
  local t={}
  for byte=0,15 do local b=sp:read_u8(HELD+byte)
    if b~=0 then for bit=0,7 do if (b>>bit)&1==1 then local sl=byte*8+bit
      t[#t+1]=sp:read_u8(NODE+sl*0x2C+0x0C) end end end end
  return t
end
local function panelMask()
  local m=0
  for _,x in ipairs(BTN) do if (sp:read_u8(x.a)&x.b)~=0 then m=m|x.bit end end
  return m
end
local function maskOf(notes) local m=0; for _,n in ipairs(notes) do m=m|noteToMask(n) end; return m end
local function lrVal(bits) if bits==1 then return 1 elseif bits==2 then return -1 else return 0 end end
local function udVal(bits) if bits==4 then return 1 elseif bits==8 then return -1 else return 0 end end
local function fmtNotes(t) local s={} for _,n in ipairs(t) do s[#s+1]=noteName(n) end return "{"..table.concat(s,",").."}" end
local function fmtmask(m) local s=""
  if m&1~=0 then s=s.."R" end; if m&2~=0 then s=s.."L" end
  if m&4~=0 then s=s.."D" end; if m&8~=0 then s=s.."U" end
  if m&0x80~=0 then s=s.."A" end; return s=="" and "-" or s end

-- ---- log files (one set per session: AW_SESSION=<name>, default a timestamp) ------------------
local SESSION = os.getenv("AW_SESSION") or os.date("%Y%m%d-%H%M%S")
local BASE = os.getenv("HOME").."/compartilhado/tmp/aw-"..SESSION
local LOGPATH = BASE.."-monitor.log"
local log = io.open(LOGPATH, "w")
local function w(line) if log then log:write(line.."\n"); log:flush() end end
w("# awmonitor -- frame | part | keybed-keys | ring(TG) | panel | applied LR/UD/JMP/ACT mask="..
  "resolved | prevBits | FLAGS")
-- (a) Applied-vars log: the six hero variables THIS VM applied, one row per ReadInput. Logged at
-- the exact instant ReadInput writes var 0xFE (its last write), so it is jitter-free. Row frame
-- V+1 holds the vars ReadInput set while FRAME_NO=V, which drive tick V -- the "row F drives tick
-- F-1" convention replaycksum and awreplay use. Replaying THIS file reproduces the KN7000's own
-- input handling (including any mishandling) -- useful for VM-vs-VM, not for judging inputs.
local INPUTS = BASE.."-inputs.csv"
local inlog = io.open(INPUTS, "w")
local function wi(line) if inlog then inlog:write(line.."\n"); inlog:flush() end end
wi("frame,part,lr(0xFC),ud(0xE5),jump(0xFB),posmask(0xFD),action(0xFA),actmask(0xFE)")
-- (b) RAW input events: what the player physically did, before any of this port's input handling.
--   K,<emu_time>,<FRAME_NO>,<midi_note>,<1=on|0=off>,<velocity>,<kb|midi>  every make/break:
--        keybed (host keys) tapped as the firmware reads the key FIFO 0x98050004; MIDI-in tapped
--        as the firmware reads the MIDI UART (SIO1) receive register -- see below
--   R,<emu_time>,<FRAME_NO>,<part>,<panel_mask>                    each ReadInput instant (the input
--        drives tick FRAME_NO) with the panel D-pad state (R1 L2 D4 U8 A0x80) at that moment
-- A reference VM replays these through ITS OWN input mapping, answering "does a correct AW engine
-- handle these presses the same way?".
local EVENTS = BASE.."-events.csv"
local evlog = io.open(EVENTS, "w")
local function we(line) if evlog then evlog:write(line.."\n"); evlog:flush() end end
we("# kind,emu_time,frame_no,... (K=key event: note,on,vel ; R=ReadInput: part,panel_mask)")

AWMON_FIFO = sp:install_read_tap(0x98050004, 0x98050007, "awmon_fifo", function(offset, data, mask)
  if data ~= 0xffff and data ~= 0 then
    local low = data & 0xff
    we(string.format("K,%.6f,%d,%d,%d,%d,kb", M.time:as_double(), sp:read_u16(FRAMENO),
      (low & 0x7f) + 36, ((low & 0x80) == 0) and 1 or 0, (data >> 8) & 0xff))
  end
  return data
end)
-- MIDI-in does NOT use the keybed FIFO on this driver: -midiin1 feeds the CPU's real MIDI UART
-- (MN10300 SIO1) and the firmware parses the bytes itself. Tap the firmware's reads of the SIO1
-- receive register (0x34000819, byte 1 of the 32-bit word at 0x34000818) and parse the stream:
-- note-on/off with running status; system/realtime bytes are ignored. Logged as K,...,midi.
local mst, mdata = 0, {}
AWMON_MIDI = sp:install_read_tap(0x34000818, 0x3400081B, "awmon_midi", function(offset, data, mask)
  if (mask & 0xff00) == 0 then return end                  -- only reads of the RXD byte
  local b = (data >> 8) & 0xff
  if b >= 0xF8 then return end                             -- realtime (clock, active sensing...)
  if b >= 0x80 then mst = (b < 0xF0) and b or 0; mdata = {}; return end
  if mst == 0 then return end
  mdata[#mdata+1] = b
  local hi = mst & 0xF0
  if #mdata < (((hi == 0xC0) or (hi == 0xD0)) and 1 or 2) then return end
  if hi == 0x90 or hi == 0x80 then
    local on = (hi == 0x90 and mdata[2] > 0) and 1 or 0
    we(string.format("K,%.6f,%d,%d,%d,%d,midi", M.time:as_double(), sp:read_u16(FRAMENO), mdata[1], on, mdata[2]))
  end
  mdata = {}                                               -- running status: keep mst
end)
local A_FE = VMVARS + 0xFE*2
local lastRIframe = -1
AWMON_RI = sp:install_write_tap(A_FE, A_FE+3, "awmon_ri", function(offset, data, mask)
  if offset ~= A_FE or (mask & 0xffff) == 0 then return end   -- var 0xFE only (0xFF shares the word)
  local fr = sp:read_u16(FRAMENO)
  if fr == lastRIframe then return end                        -- first 0xFE write after a FRAME_NO bump = ReadInput
  lastRIframe = fr
  local part = sp:read_u16(CURPART)
  we(string.format("R,%.6f,%d,%04X,%d", M.time:as_double(), fr, part, panelMask()))
  wi(string.format("%d,%04X,%d,%d,%d,%d,%d,%d", fr+1, part, s16(VMVARS+0xFC*2), s16(VMVARS+0xE5*2),
    s16(VMVARS+0xFB*2), sp:read_u16(VMVARS+0xFD*2), sp:read_u16(VMVARS+0xFA*2), data & 0xffff))
end)
print("awmonitor: session "..SESSION)
print("awmonitor:   human log      -> "..LOGPATH)
print("awmonitor:   raw key events -> "..EVENTS)
print("awmonitor:   applied vars   -> "..INPUTS.."  (play normally; flags print below)")

-- ---- per-frame correlation -------------------------------------------------------------
local ph="sd"; local lf=-1
local lastResLR, lastResUD = 0, 0     -- previous frame's module-resolved bits (sticky reference)
local nFrames, nGhost, nValue, nNodir = 0,0,0,0
local ghostStreak, nodirStreak = 0, 0
local CONFIRM = 3                     -- a GHOST/NODIR must hold this many frames to be "confirmed"
                                      -- (the ring is read a hair after ReadInput saw it, so a
                                      -- 1-frame mismatch on a transition is a race, not a bug)
local function csv(t) local s={} for _,n in ipairs(t) do s[#s+1]=tostring(n) end return table.concat(s,",") end

emu.register_periodic(function()
  local t=M.time:as_double()
  -- auto-launch only (press SD CARD LOAD once); never touch game inputs afterwards
  if ph=="sd" then
    local sdf; local p=M.ioport.ports[":cpanel:CPR_SEG1"]
    if p then for _,f in pairs(p.fields) do if f.name=="SD CARD LOAD (SW7)" then sdf=f end end end
    if sdf then if t>11 then sdf:set_value(1) end; if t>11.4 then sdf:set_value(0); ph="run" end end
    return
  end
  local fn=sp:read_u16(FRAMENO)
  if fn==lf then return end
  lf=fn; nFrames=nFrames+1

  local kb   = keybedNotes()
  local ring = ringNotes()
  local held = heldNotes()
  local pmask= panelMask()
  local rmask= maskOf(ring)
  local full = rmask | pmask

  local aLR=s16(VMVARS+0xFC*2); local aUD=s16(VMVARS+0xE5*2); local aJMP=s16(VMVARS+0xFB*2)
  local aACT=sp:read_u16(VMVARS+0xFA*2); local aMASK=sp:read_u16(VMVARS+0xFD*2)
  local aFE=sp:read_u16(VMVARS+0xFE*2)
  local mPrevLR=sp:read_u16(PREV_LR); local mPrevUD=sp:read_u16(PREV_UD)
  local part=sp:read_u16(CURPART)

  -- predict the module's sticky resolution from the inputs + the PREVIOUS resolved bits
  local lrBits=full&3;  local expLR=(lrBits==3) and lastResLR or lrBits
  local udBits=full&0xC;local expUD=(udBits==0xC) and lastResUD or udBits

  -- Raw conditions: all are written to the log every frame (full detail). Only the RELIABLE ones
  -- raise a console alarm / count, to avoid transition-race false positives.
  local raw={}
  -- GHOST: a keybed key is held but its note is absent from the ring (held-key drop / matrix
  -- ghost). Needs persistence (a fresh press is in the ring ~6 ms later, < 1 frame).
  local ghost=false
  for _,n in ipairs(kb) do
    local inring=false; for _,rn in ipairs(ring) do if rn==n then inring=true break end end
    if not inring and noteToMask(n)~=0 then raw[#raw+1]="GHOST:"..noteName(n); ghost=true end
  end
  -- VALUE: applied var != value implied by the module's resolved bits. Both are the module's own
  -- state this frame -> race-free -> alarms immediately. A hit here is a real derive bug.
  local value=false
  if aLR~=lrVal(mPrevLR) then raw[#raw+1]=string.format("VALUE-LR(app=%d bits=%d)",aLR,mPrevLR); value=true end
  if aUD~=udVal(mPrevUD) then raw[#raw+1]=string.format("VALUE-UD(app=%d bits=%d)",aUD,mPrevUD); value=true end
  -- NODIR: a single clear direction in the ring but nothing applied (input not reaching the
  -- game). Needs persistence (a 1-frame lag at a switch is normal).
  local nodir=false
  if lrBits==1 and aLR~=1 then raw[#raw+1]="NODIR-R"; nodir=true end
  if lrBits==2 and aLR~=-1 then raw[#raw+1]="NODIR-L"; nodir=true end
  if udBits==4 and aUD~=1 then raw[#raw+1]="NODIR-D"; nodir=true end
  if udBits==8 and aUD~=-1 then raw[#raw+1]="NODIR-U"; nodir=true end
  -- STICKY: a prediction cross-check (module resolved vs expected). It races on transitions, so
  -- it is LOGGED only (lowercase) -- VM-logic correctness is proven exactly by the differential
  -- replay vs rustyworld (probes/aw-differential/), not by this live heuristic.
  if mPrevLR~=expLR then raw[#raw+1]=string.format("sticky?LR(mod=%d exp=%d)",mPrevLR,expLR) end
  if mPrevUD~=expUD then raw[#raw+1]=string.format("sticky?UD(mod=%d exp=%d)",mPrevUD,expUD) end

  ghostStreak = ghost and (ghostStreak+1) or 0
  nodirStreak = nodir and (nodirStreak+1) or 0
  local confirmed={}
  if value              then confirmed[#confirmed+1]="VALUE"; nValue=nValue+1 end
  if ghostStreak==CONFIRM then confirmed[#confirmed+1]="GHOST(held)"; nGhost=nGhost+1 end
  if nodirStreak==CONFIRM then confirmed[#confirmed+1]="NODIR(stuck)"; nNodir=nNodir+1 end

  local line=string.format(
    "f=%d t=%.2f part=%04X kb=[%s]%s ring=%s held=%s pnl=%s | LR=%+d UD=%+d JMP=%+d ACT=%d mask=0x%02X(%s) prev=%d/%d%s",
    fn, t, part, csv(kb), fmtNotes(kb), fmtNotes(ring), fmtNotes(held), fmtmask(pmask),
    aLR, aUD, aJMP, aACT, aMASK, fmtmask(full), mPrevLR, mPrevUD,
    (#raw>0) and ("  <<< "..table.concat(raw," ")) or "")
  w(line)
  if #confirmed>0 then print(string.format("[f=%d part=%04X] %s | kb=%s ring=%s LR=%+d UD=%+d ACT=%d",
    fn, part, table.concat(confirmed," "), fmtNotes(kb), fmtNotes(ring), aLR, aUD, aACT)) end

  lastResLR, lastResUD = mPrevLR, mPrevUD
end)

-- Exit summary. The stop hook's name differs across MAME versions (emu.add_machine_stop_notifier
-- in current builds, emu.register_stop in older ones); if neither exists, skip it -- both logs are
-- flushed after every line, so nothing is lost without the hook.
local function summary()
  local s=string.format("awmonitor summary: %d frames; confirmed anomalies: VALUE=%d GHOST=%d NODIR=%d",
    nFrames, nValue, nGhost, nNodir)
  w("# "..s); print(s); if log then log:close() end; if inlog then inlog:close() end; if evlog then evlog:close() end
end
if emu.add_machine_stop_notifier then AWMON_STOP = emu.add_machine_stop_notifier(summary)
elseif emu.register_stop then emu.register_stop(summary) end
