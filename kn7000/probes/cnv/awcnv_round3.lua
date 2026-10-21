-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_round3.lua -- Felipe's third round of requests (README-CNV.md; probes/cnv/README.md, "Round 3"), one MAME
-- session through the program menu as he runs it (run_round3.sh builds the card, as run_dsp.sh does).
--
-- AWR_MODE=bank: only the sample bank's first load, timed and taken apart, then MAME exits. Works on the build
-- before round 3 (KN7APP.BIN a2fbbaa6...) and after it: it reads only variables both keep (dsp.inc DV_*,
-- cnv_main.s CV_*) and the host port itself.
-- AWR_MODE=full (the default): the bank load as above, then
--   * the intro with the sound on the DSP (voices sounding, the mix not 0);
--   * a C4 skips to the lake; Bb5 alone, B5 alone: var 0xE5 (up/down) must read -1 and var 0xFD hold 8 while each is
--     held; then the panel's old game buttons (R1/R2 OCTAVE +, OCTAVE -, PART SELECT LEFT, RIGHT 1 (twice: now the
--     keybed-sound toggle), SUSTAIN), each held: vars 0xFC, 0xE5, 0xFA and 0xFD must stay 0;
--   * the keybed's own sound (PART SELECT RIGHT 1): the game's sound OFF (RIGHT 2 twice), then A5 held 1 s with the
--     keybed sound on ("keys window on1"), RIGHT 1, A5 ("keys window off"), RIGHT 1, A5 ("keys window on2"): the
--     recording (round3_report.py) must be loud, silent, loud; IC23 (the panel memories, 0x44000000, 256 KB) read
--     before and after must be the same; then RIGHT 2: the DSP again;
--   * HELP: the first page, RIGHT 2 three times (DSP -> TG -> OFF -> DSP), RIGHT 1 twice: the mode and its lines
--     must change each time while the help screen stays up (snapshots); PAGE DOWN twice: page 3, the URL
--     (snapshot); EXIT;
--   * RIGHT 1 (the keybed sound off), then EXIT held: the slots back as at boot, MSGR4-7 0, the keybed sound told
--     to come back (AU_KEYSENT 0); EXIT, "Continue Next?" YES, the menu, RUN: the bank found by its marker and
--     checked by the DSP's checksum, not sent again (AWR_OUT/bank2.txt; DV_BK_SENT 2); HELP (snapshot: "CHECKED
--     IN"); EXIT; EXIT held; EXIT; NO; a C4 on the main screen ("keys window after"): loud again.
-- AWR_EXPR (893: 0x5000B36B): the firmware's expression byte for channel 1 (awcnv_keymute.lua), logged with the
-- keybed sound's state: 0x7F with the sound on, 0 with it off.
--
-- The bank timing. Every access the firmware makes to the DSP's data port (0x9C000000) first waits for the DSP's
-- per-frame handshake (G17ICR 0x3400015C written 1, then polled): one access a DSP frame, 22.68 us. The tap counts:
--   hs       handshakes (writes of 1 to G17ICR)
--   up       data-port writes after the EPB0 index (4): the halves of a block upload (the bank's chunks, the marker)
--   regw     other data-port writes: register halves (IIEP0, IMEP0, CEP0, DMAC0, MSGR4, MSGR5 ...)
--   rd4      data-port reads after the MSGR4 index (0x0C): the copy polls
--   rdo      other data-port reads (readback through EPB0, other registers)
-- and splits the emulated time from the first BankStep to the game task's start into
--   card     inside BankRead, reading: from the write of DV_NAME (the file's name) to the unpacker's first write of its
--            state (cnv_main.s BK_CRC..BK_D2), or to the write of DV_BK_LEN when the file is stored, not packed
--   unpack   from there to the write of DV_BK_LEN (its length, once it is read and unpacked)
--   fw       outside the converter: from our answer (the mailbox's request byte) to the next call (CV_CALLS)
--   dsp      the rest: host-port traffic and our own work inside the calls
-- Writes $AWR_OUT/events.txt and $AWR_OUT/bank.txt (key value lines).
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local dsp = M.devices[":dsp"]
local dm, pm = dsp.spaces["data"], dsp.spaces["program"]
local OUT = assert(os.getenv("AWR_OUT"), "set AWR_OUT")
local MODE = os.getenv("AWR_MODE") or "full"
local DEAD = tonumber(os.getenv("AWR_DEAD") or "0x500066D8")
local PANEL = tonumber(os.getenv("AWR_PANEL") or "0x5006BE4C")
local CV, INTERP, MISC = 0x502DF000, 0x502E1000, 0x502E3000
local CV_STATE, CV_DONE, CV_CALLS = CV, CV + 8, CV + 0x10
local PART, NO_SPLASH = INTERP + 0x102A, MISC + 0x58
local DH = 0x502DA600
local DV_STATE, DV_FAIL, DV_HOOKED, DV_MODE = DH, DH + 4, DH + 0x54, DH + 0x60
local DV_BK_LEN, DV_BK_DONE, DV_BK_SENT, DV_FOUND, DV_NAME = DH + 0x70, DH + 0x74, DH + 0x7C, DH + 0x28, DH + 0x180
local DV_MODETXT, DV_KEYSTXT, DV_BANKTXT = DH + 0x1A0, DH + 0x1D0, DH + 0x1E8
local AU = 0x502DA000
local AU_KEYWANT, AU_KEYSENT, AU_DROPS, AU_SENT = AU + 0x50, AU + 0x54, AU + 0x28, AU + 0x2C
local BANKTAB = 0x502E7000
local MV, V_NPROG, ORDER, PR_NAME = 0x502C0000, 0x502C0034, 0x502C3800, 0x40
local MAILBOX = 0x5031BC00
local G17ICR = 0x3400015C
local VOICES, MIX = 0x9D20, 0x9D13

local function now() return M.time:as_double() end
local ev = assert(io.open(OUT .. "/events.txt", "w"))
local function E(...) local s = string.format("%8.2f ", now()) .. string.format(...); print("awr3: " .. s); ev:write(s, "\n"); ev:flush() end
local function cstr(a, n)
  local s = ""
  for i = 0, (n or 64) - 1 do local c = sp:read_u8(a + i); if c == 0 then break end; s = s .. string.char(c) end
  return s
end
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEY = {}
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3", ":KEYS4", ":KEYS5", ":KEYS6", ":KEYS7" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do KEY[f.name] = f end end
end
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(cond, s) local t = now() + s; while now() < t do if cond() then return true end; coroutine.yield() end; return cond() end
local function press(tag, mask, hold, keep)
  local f = field(tag, mask)
  local seg = tonumber(tag:match("SEG(%d+)"))
  local byte = PANEL + seg + (tag:sub(1, 3) == "CPR" and 0 or 0x30)
  for try = 1, 6 do
    f:set_value(1)
    local seen = wait_until(function() return (sp:read_u8(byte) & mask) ~= 0 end, 1.0)
    if seen then
      wait(hold or 0.4)
      if keep then keep() end
      f:set_value(0); return true
    end
    f:set_value(0); E("press %s %02X not seen (try %d): again", tag, mask, try); wait(1.5)
  end
  return false
end
local function slot(a) return pm:read_u64(a) & 0xFFFFFFFFFFFF end
local function var(n) local v = sp:read_u16(INTERP + 2 * n); if v >= 0x8000 then v = v - 0x10000 end; return v end

-- ---- the bank timing ----------------------------------------------------------------------------
local B = { on = false, t0 = 0, last = 0, phase = "dsp", card = 0, unpack = 0, fw = 0, dsp = 0, hs = 0, up = 0, regw = 0, rd4 = 0,
            rdo = 0, calls = 0, files = 0, idx = -1 }
local function bswitch(ph)
  if not B.on then return end
  local t = now()
  B[B.phase] = B[B.phase] + (t - B.last)
  B.last, B.phase = t, ph
end
AWR_T = {
  sp:install_write_tap(0x98000000, 0x98000003, "awr_idx", function(o, d, m) B.idx = d & 0xFFFF end),
  sp:install_write_tap(0x9C000000, 0x9C000003, "awr_dw", function(o, d, m)
    if not B.on then return end
    if B.idx == 4 then B.up = B.up + 1 else B.regw = B.regw + 1 end
  end),
  sp:install_read_tap(0x9C000000, 0x9C000003, "awr_dr", function(o, d, m)
    if not B.on then return end
    if B.idx == 0x0C then B.rd4 = B.rd4 + 1 else B.rdo = B.rdo + 1 end
  end),
  sp:install_write_tap(G17ICR, G17ICR + 3, "awr_hs", function(o, d, m) if B.on then B.hs = B.hs + 1 end end),
  sp:install_write_tap(DV_NAME, DV_NAME + 3, "awr_name", function(o, d, m)
    if B.on and B.phase ~= "card" then B.files = B.files + 1; bswitch("card") end
  end),
  sp:install_write_tap(DV_BK_LEN, DV_BK_LEN + 3, "awr_len", function(o, d, m)
    if B.phase == "card" or B.phase == "unpack" then bswitch("dsp") end
  end),
  sp:install_write_tap(CV + 0x80, CV + 0x97, "awr_unpack", function(o, d, m) if B.phase == "card" then bswitch("unpack") end end),
  sp:install_write_tap(MAILBOX, MAILBOX + 3, "awr_mb", function(o, d, m) if B.on and o == MAILBOX and (m & 0xFF) ~= 0 then bswitch("fw") end end),
  sp:install_write_tap(CV_CALLS, CV_CALLS + 3, "awr_call", function(o, d, m)
    if B.on then B.calls = B.calls + 1; if B.phase == "fw" then bswitch("dsp") end end
  end),
}

-- ---- the session --------------------------------------------------------------------------------
local function to_converter()
  press("CPR_SEG1", 0x04); wait(6)
  press("CPL_SEG0", 0x20); wait(8)
  for i = 1, 8 do
    press("CPR_SEG6", 0x01)
    if wait_until(function() return sp:read_u32(0x502B9E00) == 0x53374E4B end, 20) then break end
    E("OK %d not taken; again", i)
  end
end
local function run_aw()
  local ok = wait_until(function() return sp:read_u32(MV) == 4 and cstr(0x502BA020, 32) ~= "ANOTHER WORLD" end, 150)
  local n, idx = sp:read_u32(V_NPROG), nil
  for i = 0, n - 1 do if cstr(sp:read_u32(ORDER + 4 * i) + PR_NAME) == "Another World" then idx = idx or i end end
  E("menu: %s, %d programs, Another World at %s", ok and "up" or "NOT UP", n, tostring(idx))
  if not idx then return false end
  for _ = 1, idx // 5 do press("CPR_SEG5", 0x20); wait(1) end
  press("CPL_SEG0", ({ 0x02, 0x08, 0x20, 0x01, 0x04 })[idx % 5 + 1]); wait(1)
  press("CPR_SEG5", 0x01)
  ok = wait_until(function() return cstr(0x502BA020, 32) == "ANOTHER WORLD" end, 30)
  E("RUN: %q at APP_BASE", cstr(0x502BA020, 32))
  return ok
end
local EXPR = tonumber(os.getenv("AWR_EXPR") or "0x5000B36B")
local function bank(file)
  wait_until(function() return sp:read_u32(CV_STATE) >= 2 end, 120)
  sp:write_u32(NO_SPLASH, 0x5EED0FF0)
  wait_until(function() return sp:read_u32(CV_STATE) == 5 end, 60)
  for _, k in ipairs({ "card", "unpack", "fw", "dsp", "hs", "up", "regw", "rd4", "rdo", "calls", "files" }) do B[k] = 0 end
  B.on, B.t0, B.last, B.phase = true, now(), now(), "dsp"
  wait_until(function() return sp:read_u32(CV_STATE) == 3 end, 600)
  bswitch("dsp"); B.on = false
  local total = now() - B.t0
  local f = assert(io.open(OUT .. "/" .. (file or "bank.txt"), "w"))
  local function kv(k, v) f:write(string.format("%s %s\n", k, tostring(v))) end
  kv("kn7app_state", string.format("dvstate=%d fail=%d hooked=%d mode=%d sent=%d", sp:read_u32(DV_STATE),
     sp:read_u32(DV_FAIL), sp:read_u32(DV_HOOKED), sp:read_u32(DV_MODE), sp:read_u32(DV_BK_SENT)))
  kv("words_sent", sp:read_u32(DV_BK_DONE)); kv("words_bank", sp:read_u32(BANKTAB + 0x0C))
  kv("total_s", string.format("%.3f", total))
  for _, k in ipairs({ "card", "unpack", "fw", "dsp" }) do kv(k .. "_s", string.format("%.3f", B[k])) end
  for _, k in ipairs({ "hs", "up", "regw", "rd4", "rdo", "calls", "files" }) do kv(k, B[k]) end
  kv("hs_s_at_44100", string.format("%.3f", B.hs / 44100))
  f:close()
  E("bank: %.2f s (card %.2f, unpacking %.2f, outside the converter %.2f, in the calls otherwise %.2f); %d handshakes (%.2f s at 44,100 a s): "
    .. "upload halves %d, register halves %d, MSGR4 polls %d, other reads %d; %d calls, %d files; sent %d (%d of %d words)",
    total, B.card, B.unpack, B.fw, B.dsp, B.hs, B.hs / 44100, B.up, B.regw, B.rd4, B.rdo, B.calls, B.files,
    sp:read_u32(DV_BK_SENT), sp:read_u32(DV_BK_DONE), sp:read_u32(BANKTAB + 0x0C))
end

local function quit(label)
  press("CPC_SEG11", 0x80, 2.0)
  local ok = wait_until(function() return sp:read_u32(CV_DONE) == 1 and sp:read_u32(DV_STATE) == 3 end, 20)
  wait(1)
  E("%s quit: task done %d, DSP state %d, hooked %d, slots %012X %012X, MSGR4-7 %X %X %X %X", label,
    sp:read_u32(CV_DONE), sp:read_u32(DV_STATE), sp:read_u32(DV_HOOKED), slot(0x8080), slot(0x80A0),
    dm:read_u32(0x0C), dm:read_u32(0x0D), dm:read_u32(0x0E), dm:read_u32(0x0F))
  press("CPC_SEG11", 0x80); wait(4)
  return ok
end

local function hero() return string.format("LR %d UD %d JUMP %d POS %02X ACT %d AMASK %02X", var(0xFC), var(0xE5), var(0xFB),
  var(0xFD) & 0xFF, var(0xFA), var(0xFE) & 0xFF) end
local function hold_key(name)
  local k = KEY[name]
  if not k then E("no key %s", name); return end
  k:set_value(1); wait(0.5)
  E("%s held: %s", name, hero())
  k:set_value(0); wait(0.5)
  E("%s released: %s", name, hero())
end
local function ic23()
  local t = {}
  for a = 0x44000000, 0x4403FFFF, 4 do t[#t + 1] = sp:read_u32(a) end
  return t
end
local function window(label, name)
  local k = KEY[name]
  local t0 = now()
  k:set_value(1); wait(1.0); k:set_value(0)
  E("keys window %s %.3f %.3f (%s held; keybed sound want %d sent %d; the firmware's expression, channel 1: %02X)",
    label, t0 + 0.1, now(), name, sp:read_u32(AU_KEYWANT), sp:read_u32(AU_KEYSENT), sp:read_u8(EXPR))
  wait(1.5)
end
local function hold_panel(label, tag, mask)
  local s
  press(tag, mask, 0.5, function() s = hero() end)
  E("panel %s held: %s", label, s)
  wait(0.5)
end

local co = coroutine.create(function()
  wait_until(function() return now() > 30 end, 60)
  E("boot: slots %012X %012X, dead %d", slot(0x8080), slot(0x80A0), sp:read_u8(DEAD))
  to_converter()
  run_aw()
  bank()
  if MODE == "bank" then E("end"); ev:close(); M:exit(); return end
  wait_until(function() return sp:read_u16(PART) == 0x3E81 end, 60)
  E("the intro starts; mode %d hooked %d slots %012X %012X", sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED), slot(0x8080), slot(0x80A0))
  local vm, mx = 0, 0
  local t1 = now() + 15
  while now() < t1 do
    for v = 0, 7 do local b = VOICES + 8 * v; if dm:read_u32(b) < dm:read_u32(b + 4) then vm = vm | (1 << v) end end
    local m = dm:read_u32(MIX); if m >= 0x80000000 then m = 0x100000000 - m end; if m > mx then mx = m end
    coroutine.yield()
  end
  E("intro, 15 s in DSP mode: voices seen %02X, |mix| max %d, dead %d", vm, mx, sp:read_u8(DEAD))
  KEY["C4"]:set_value(1); wait(0.3); KEY["C4"]:set_value(0)
  wait_until(function() return sp:read_u16(PART) == 0x3E82 end, 30)
  wait(8)
  E("the lake (part %04X): %s", sp:read_u16(PART), hero())
  hold_key("A5#"); hold_key("B5"); hold_key("A5")
  hold_panel("R1/R2 OCTAVE +", "CPR_SEG6", 0x02); hold_panel("R1/R2 OCTAVE +", "CPR_SEG6", 0x02)
  hold_panel("R1/R2 OCTAVE -", "CPR_SEG7", 0x02); hold_panel("R1/R2 OCTAVE -", "CPR_SEG7", 0x02)
  hold_panel("PART SELECT LEFT", "CPR_SEG2", 0x01)
  hold_panel("PART SELECT RIGHT 1", "CPR_SEG1", 0x02); hold_panel("PART SELECT RIGHT 1", "CPR_SEG1", 0x02)
  hold_panel("SUSTAIN", "CPR_SEG5", 0x08); hold_panel("SUSTAIN", "CPR_SEG5", 0x08)
  E("after the panel buttons: keybed sound want %d sent %d, %s", sp:read_u32(AU_KEYWANT), sp:read_u32(AU_KEYSENT), hero())
  -- the keybed's own sound, with the game's sound off
  press("CPR_SEG2", 0x02, 0.3); wait(1); press("CPR_SEG2", 0x02, 0.3); wait(2)
  E("game sound mode %d (2 = off), MIDI sent %d", sp:read_u32(DV_MODE), sp:read_u32(AU_SENT))
  local before = ic23()
  window("on1", "A5")
  press("CPR_SEG1", 0x02, 0.3); wait(1)
  window("off", "A5")
  press("CPR_SEG1", 0x02, 0.3); wait(1)
  window("on2", "A5")
  local after, diff = ic23(), 0
  for i = 1, #before do if before[i] ~= after[i] then diff = diff + 1 end end
  E("IC23 words that differ, before the keybed-sound toggles and after: %d of %d; MIDI drops %d", diff, #before, sp:read_u32(AU_DROPS))
  press("CPR_SEG2", 0x02, 0.3); wait(2)
  E("game sound mode %d (0 = DSP), hooked %d", sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED))
  -- HELP
  press("CPC_SEG5", 0x02, 0.3); wait(2)
  E("HELP: mode %d, lines %q %q %q", sp:read_u32(DV_MODE), cstr(DV_MODETXT, 48), cstr(DV_KEYSTXT, 24), cstr(DV_BANKTXT, 24))
  M.video:snapshot()
  for i = 1, 3 do
    press("CPR_SEG2", 0x02, 0.3); wait(2)
    E("HELP, RIGHT 2 #%d: still in help %s, mode %d, hooked %d, line %q, slots %012X %012X", i,
      tostring(sp:read_u32(AU + 4) == 1), sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED),
      cstr(DV_MODETXT, 48), slot(0x8080), slot(0x80A0))
    M.video:snapshot()
  end
  for i = 1, 2 do
    press("CPR_SEG1", 0x02, 0.3); wait(2)
    E("HELP, RIGHT 1 #%d: keybed sound want %d sent %d, line %q", i, sp:read_u32(AU_KEYWANT), sp:read_u32(AU_KEYSENT),
      cstr(DV_KEYSTXT, 24))
    M.video:snapshot()
  end
  press("CPC_SEG11", 0x20, 0.3); wait(1); press("CPC_SEG11", 0x20, 0.3); wait(2)
  E("HELP, page 3"); M.video:snapshot()
  press("CPC_SEG11", 0x80, 0.3); wait(3)
  E("HELP left: part %04X, mode %d, hooked %d", sp:read_u16(PART), sp:read_u32(DV_MODE), sp:read_u32(DV_HOOKED))
  press("CPR_SEG1", 0x02, 0.3); wait(1)
  E("before the quit: keybed sound want %d sent %d", sp:read_u32(AU_KEYWANT), sp:read_u32(AU_KEYSENT))
  quit("first")
  E("after the quit: keybed sound want %d sent %d; the firmware's expression, channel 1: %02X", sp:read_u32(AU_KEYWANT),
    sp:read_u32(AU_KEYSENT), sp:read_u8(EXPR))
  press("CPR_SEG7", 0x01)                               -- YES (right 3): the menu again, the game again
  run_aw()
  bank("bank2.txt")
  wait(6)
  press("CPC_SEG5", 0x02, 0.3); wait(2)
  E("again, HELP: lines %q %q %q", cstr(DV_MODETXT, 48), cstr(DV_KEYSTXT, 24), cstr(DV_BANKTXT, 24))
  M.video:snapshot()
  press("CPC_SEG11", 0x80, 0.3); wait(3)
  quit("again")
  press("CPR_SEG6", 0x01); wait(6)
  E("left STYLE CONVERT; slots %012X %012X; dead %d", slot(0x8080), slot(0x80A0), sp:read_u8(DEAD))
  window("after", "C4")
  E("end")
  ev:close()
  M:exit()
end)
AWR_TICK = emu.add_machine_frame_notifier(function()
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then E("ERROR %s", tostring(err)); ev:close(); M:exit() end
  end
end)
E("installed (mode %s)", MODE)
