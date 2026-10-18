-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_session.lua -- a whole session of the STYLE CONVERT (.CNV) build on program 941:
-- start, input, quit, restart. Questions it answers, each printed as PASS/FAIL:
--   start    DISK MENU > STYLE CONVERT > OK loads AW.CNV and the VM runs (FRAME_NO advances)
--   skip     a key (C4 = ACTION) skips the intro: the part becomes 0x3E82 (the lake)
--   panel    PART SELECT RIGHT 1 sets the hero's left/right variable var[0xFC] to +1
--   keybed   holding C4 sets the hero's action variable var[0xFA] to 1
--   quit     holding EXIT for 2 s ends the game task (the module's TASK_DONE) and the VM stops
--   menus    EXIT closes the firmware's message and its "Continue Next?" appears; the VM stays stopped
--   again    YES on "Continue Next?" starts the game again (a new task; the data is still in RAM)
--   leave    quitting again and answering NO leaves STYLE CONVERT (snapshot: the main screen)
--   rerun    DISK MENU > STYLE CONVERT > OK reloads AW.CNV, which starts at once (load < 1 s)
-- Snapshots at each step go to -snapshot_directory.
--
--   kn7000 kn7000 -rompath ROMS -flop build/another_floppy.img -harddisk SD.img \
--     -autoboot_script probes/cnv/awcnv_session.lua -window -nothrottle -snapshot_directory DIR
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local function port(tag) return M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag] end
local function set(tag, mask, v)
  for _, f in pairs(port(tag).fields) do if f.mask == mask then f:set_value(v) end end
end
local FRAME_NO, PART, VARS = 0x4408007C, 0x4407102A, 0x44070000
local function var(i) local v = sp:read_u16(VARS + 2 * i); return v >= 0x8000 and v - 0x10000 or v end
local CV = 0x502E0000                   -- the module's variables (src/cnv_main.s)
sp:write_u32(0x44080058, 0x5EED0FF0)   -- NO_SPLASH: start at the intro (as awcnv_cksum.lua)
local results, t0, state = {}, nil, "boot"
local seen = { fc = 0, fa = 0 }
local function result(name, ok, detail)
  results[#results + 1] = name
  print(string.format("awcnv_session: %-8s %s  %s", name, ok and "PASS" or "FAIL", detail))
end
local function now() return M.time:as_double() end
-- a press = {at, port, mask, hold}; the queue runs in order, timed from when it was queued
local queue = {}
local function press_after(dt, tag, mask, hold) queue[#queue + 1] = { at = now() + dt, tag = tag, mask = mask, hold = hold or 0.4 } end
local function run_queue()
  local p = queue[1]
  if not p then return end
  if not p.down and now() >= p.at then set(p.tag, p.mask, 1); p.down = now() end
  if p.down and now() >= p.down + p.hold then set(p.tag, p.mask, 0); table.remove(queue, 1) end
end
local function start_from_disk_menu() press_after(0, "CPL_SEG0", 0x20); press_after(6, "CPR_SEG6", 0x01) end

local frame_at_quit, wait_until
AWCNV_SESSION = emu.register_periodic(function()
  run_queue()
  local t = now()
  local f = sp:read_u32(FRAME_NO) & 0xffff   -- as awcksum.lua: the frame number is the low 16 bits
  if state == "boot" and t > 30 then
    press_after(0, "CPR_SEG1", 0x04); start_from_disk_menu(); state = "starting"; wait_until = t + 400
  elseif state == "starting" then
    if f > 50 then
      result("start", true, string.format("frame %d at t=%.0f s; load %d ms, errors %d, task %d", f, t,
        sp:read_u32(CV + 0x18), sp:read_u32(CV + 0x14), sp:read_u32(CV + 0x1C)))
      M.video:snapshot()
      set("KEYS1", 0x0100, 1); t0 = t; state = "skip"
    elseif t > wait_until then result("start", false, "no frames"); state = "done" end
  elseif state == "skip" then
    if t > t0 + 0.5 then set("KEYS1", 0x0100, 0) end
    if sp:read_u16(PART) == 0x3E82 then
      result("skip", true, string.format("part 0x3E82 at frame %d", f)); M.video:snapshot()
      t0 = t; state = "panel"; press_after(2, "CPR_SEG1", 0x02, 1.0)
    elseif t > t0 + 60 then result("skip", false, string.format("part %04X", sp:read_u16(PART))); state = "quit0" end
  elseif state == "panel" then
    if var(0xFC) == 1 then seen.fc = 1 end
    if t > t0 + 5 then
      result("panel", seen.fc == 1, "var[0xFC] reached " .. seen.fc)
      t0 = t; state = "keybed"; set("KEYS1", 0x0100, 1)
    end
  elseif state == "keybed" then
    if var(0xFA) == 1 then seen.fa = 1 end
    if t > t0 + 1.0 then set("KEYS1", 0x0100, 0) end
    if t > t0 + 2.0 then
      result("keybed", seen.fa == 1, "var[0xFA] reached " .. seen.fa)
      state = "quit0"
    end
  elseif state == "quit0" then
    press_after(0, "CPC_SEG11", 0x80, 2.0); t0 = t; state = "quit"
  elseif state == "quit" then
    if t > t0 + 4 then
      frame_at_quit = f
      local done = sp:read_u32(CV + 0x08)
      result("quit", done == 1, string.format("TASK_DONE=%d QUIT_REQ=%d", done, sp:read_u32(CV + 0x04)))
      M.video:snapshot()                -- the firmware's message box (0xFE ends the conversion)
      press_after(0, "CPC_SEG11", 0x80); t0 = t; state = "menus"
    end
  elseif state == "menus" then
    if t > t0 + 4 then
      result("menus", (sp:read_u32(FRAME_NO) & 0xffff) == frame_at_quit,
        string.format("frame stayed %d after quitting; snapshot: Continue Next? YES/NO", frame_at_quit))
      M.video:snapshot()
      press_after(0, "CPR_SEG7", 0x01)  -- YES (right button 3): play again
      t0 = t; state = "again"
    end
  elseif state == "again" then
    local fr = sp:read_u32(FRAME_NO) & 0xffff
    if sp:read_u32(CV + 0x08) == 0 and fr > 10 and fr ~= frame_at_quit then
      result("again", true, string.format("YES restarted the game (frame %d, task %d)", fr, sp:read_u32(CV + 0x1C)))
      M.video:snapshot()
      press_after(0, "CPC_SEG11", 0x80, 2.0)   -- quit again, then leave with NO
      press_after(3, "CPC_SEG11", 0x80)
      press_after(4, "CPR_SEG6", 0x01)         -- NO (right button 4)
      t0 = t; state = "leave"
    elseif t > t0 + 30 then result("again", false, "no frames after YES"); state = "done" end
  elseif state == "leave" then
    if t > t0 + 14 then
      M.video:snapshot()                -- NO leaves STYLE CONVERT (the main screen)
      frame_at_quit = sp:read_u32(FRAME_NO) & 0xffff
      result("leave", sp:read_u32(CV + 0x08) == 1, "second quit, NO; snapshot shows the main screen")
      press_after(0, "CPR_SEG1", 0x04); start_from_disk_menu()   -- run AW.CNV again from the menus
      t0 = t; state = "rerun"
    end
  elseif state == "rerun" then
    local fr = sp:read_u32(FRAME_NO) & 0xffff
    if sp:read_u32(CV + 0x10) > 0 and sp:read_u32(CV + 0x08) == 0 and fr > 10 and fr ~= frame_at_quit then
      local ms = sp:read_u32(CV + 0x18)
      result("rerun", ms < 1000, string.format("reloaded AW.CNV runs at once: load %d ms (data still in RAM)", ms))
      M.video:snapshot(); state = "done"
    elseif t > t0 + 60 then result("rerun", false, "no frames after running AW.CNV again"); state = "done" end
  elseif state == "done" then
    print(string.format("awcnv_session: %d checks run", #results)); M:exit()
  end
end)
