-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_sound.lua -- does the KN7APP.BIN build's sound (src/audio.s) reach the firmware? One session
-- through the owner's loader floppy (-bios v13 = program 893): DISK MENU, STYLE CONVERT, OK; the splash
-- skipped (NO_SPLASH, as awcnv_cksum.lua), the whole intro with no input, so that it must reach the
-- lake by itself (it reads the music's sync mark var 0xF4); PART SELECT RIGHT 2 at intro + 20 s and
-- + 26 s (sound off, on); 5 s into the lake EXIT held 2 s (quit: all notes off, all sound off).
-- Record the audio with -wavwrite; probes/cnv/wavrms.py reads it.
--
-- Prints, once a second of emulated time: the part, the VM tick, var 0xF4, audio.s's counters
-- (messages sent, bytes dropped, module rows, PLAY_SOUNDs, the last mark), the MIDI IN 1 ring's rd and
-- wr (the firmware's consumer must follow the game's writes), and AU_ENABLED; every change of var
-- 0xF4; and after the quit the ring's last 48 bytes (the all-off messages).
--   env: AWS_OUT (log file), AWS_RING (MIDI IN 1 header: 893 0x5001F020, 941 0x5001F050)
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local log = io.open(os.getenv("AWS_OUT") or "awcnv_sound.log", "w")
local function P(...) local s = string.format(...); print(s); log:write(s, "\n"); log:flush() end
local RING = tonumber(os.getenv("AWS_RING") or "0x5001F020")
local CV, VARS, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local PART, FRAME_NO, NO_SPLASH = VARS + 0x102A, MISC + 0x7C, MISC + 0x58
local AU = 0x502DA000      -- platformcnv.inc AUDIO_VARS; audio.s AU_* offsets
local function press(tag, mask, v)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then f:set_value(v) end end
end
local STEPS = { { 30, "CPR_SEG1", 0x04, 0.4, "DISK MENU" }, { 36, "CPL_SEG0", 0x20, 0.4, "STYLE CONVERT" },
                { 44, "CPR_SEG6", 0x01, 0.4, "OK (KN7LOAD.CNV)" } }
local step, nosplash, tintro, tlake, lastsec, lastf4, quitted, tquit = 1, false, nil, nil, -1, -1, false, nil
local function var(i) return sp:read_u16(VARS + 2 * i) end
local function status(t)
  P("t=%6.1f part %04X tick %5d F4=%5d | sent %5d drops %d rows %4d sounds %3d mark %d enabled %d | ring rd %08X wr %08X free %d",
    t, sp:read_u16(PART), sp:read_u16(FRAME_NO), var(0xF4), sp:read_u32(AU + 0x2C), sp:read_u32(AU + 0x28),
    sp:read_u32(AU + 0x30), sp:read_u32(AU + 0x34), sp:read_u32(AU + 0x38), sp:read_u32(AU),
    sp:read_u32(RING + 8), sp:read_u32(RING + 12), sp:read_u16(RING + 16))
end
TICK = emu.register_periodic(function()
  local t = M.time:as_double()
  local s = STEPS[step]
  if s and t > s[1] then press(s[2], s[3], 1); s.down = s.down or t end
  if s and s.down and t > s.down + s[4] then press(s[2], s[3], 0); P("t=%.1f pressed %s", t, s[5]); step = step + 1 end
  if not nosplash and sp:read_u32(CV) >= 2 then sp:write_u32(NO_SPLASH, 0x5EED0FF0); nosplash = true end
  if sp:read_u32(CV) < 3 then return end
  local part = sp:read_u16(PART)
  if part == 0x3E81 and not tintro then tintro = t; P("t=%.1f the intro starts", t)
    STEPS[#STEPS + 1] = { t + 20, "CPR_SEG2", 0x02, 0.3, "PART SELECT RIGHT 2 (sound off)" }
    STEPS[#STEPS + 1] = { t + 26, "CPR_SEG2", 0x02, 0.3, "PART SELECT RIGHT 2 (sound on)" } end
  if part == 0x3E82 and not tlake then tlake = t; P("t=%.1f the lake starts (intro %.1f s)", t, t - tintro)
    STEPS[#STEPS + 1] = { t + 5, "CPC_SEG11", 0x80, 2.0, "EXIT held 2 s (quit)" } end
  local f4 = var(0xF4)
  if f4 ~= lastf4 then P("t=%.2f tick %d var F4 %d -> %d", t, sp:read_u16(FRAME_NO), lastf4, f4); lastf4 = f4 end
  if math.floor(t) ~= lastsec then lastsec = math.floor(t); status(t) end
  if sp:read_u32(CV + 0x08) == 1 and not quitted then quitted = true; tquit = t; P("t=%.1f the game task has ended", t) end
  if quitted and t > tquit + 3 then
    status(t)
    local st, wr = sp:read_u32(RING), sp:read_u32(RING + 12)
    local b = {}
    for k = 48, 1, -1 do local a = wr - k; if a < st then a = a + 0x400 end; b[#b + 1] = string.format("%02X", sp:read_u8(a)) end
    P("ring's last 48 bytes: %s", table.concat(b, " "))
    log:close(); M:exit()
  end
  if t > 400 then P("TIMEOUT"); status(t); log:close(); M:exit() end
end)
