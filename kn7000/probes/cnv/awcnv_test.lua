-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- awcnv_test.lua -- the KN7APP.BIN build's acceptance session in MAME (probes/cnv/README.md), on any
-- program build (-bios v13 = program 893, the owner's; v16 = 941). Run by run_cnv_tests.sh, with the
-- owner's loader floppy (KN7LOAD.CNV) in the drive and KN7APP.BIN and the game's files in the root of
-- a copy of the real KN7000's SD card.
--
-- AWT_MODE=game (default): DISK MENU > STYLE CONVERT > OK runs KN7LOAD.CNV, which loads and runs
-- KN7APP.BIN, and a whole session is played through the instrument's own inputs, each step printed as
-- "awcnv_test: <name> PASS|FAIL detail":
--   found    the loader ran the game; its firmware search found everything and the loader's service
--            table passed its check; the global files loaded; the game task runs
--   splash   the splash (part 0x3E80, loaded from the SD card) plays
--   intro    it hands over to the intro (0x3E81, loaded at the switch)
--   skip     holding C4 (keybed) skips the intro: the lake (0x3E82)
--   panel    the panel's former D-pad and fire (PART SELECT RIGHT 1 twice / LEFT, R1/R2 OCTAVE + / -, SUSTAIN
--            twice) set no hero variable (var[0xFC], var[0xE5], var[0xFA]): no panel button is a game control
--            since 2026-10-21 (RIGHT 1 is now the keybed-sound toggle, pressed twice so it ends as it began)
--   settings IC23's live panel settings (its header) end as they began; the firmware's own effect of
--            each press (it still handles OCTAVE and SUSTAIN while parked) is listed
--   keybed   holding C4 sets the hero's action variable var[0xFA] to 1
--   help     HELP shows the help screens (the VM pauses), PAGE DOWN turns to page 2, EXIT returns
--   speed    the speed figures (perf.s): HELP and PAGE DOWN three times show the fourth page; PAGE UP
--            turns the overlay on and off; PAGE DOWN switches to the old blit and back, the VM running
--            on in both; the figures the game measured (in MAME's time) are printed
--   report   (after NO) at each quit the game wrote its speed figures to a new file: the first quit
--            AWPERF0.TXT, the second (after YES) AWPERF1.TXT, never over the first (CV_REPORT = 1,
--            CV_REPORT_K = 1); the second's text is saved as AWT_OUT/awperf_ram.txt, which
--            run_cnv_tests.sh compares with the file on the card
--   prison   OTHER PART & FR opens the code screen (0x3E88); HTDC entered with the keybed D-pad and
--            action (gen_code_keys.py's grid) takes it to the prison (0x3E83)
--   city     the code screen again; CLLD takes it to the city (0x3E84), the largest part
--   quit     holding EXIT for 2 s ends the game task; the VM stops
--   menus    EXIT closes the firmware's message, "Continue Next?" appears; the VM stays stopped
--   again    YES starts a new game (the loader reads KN7APP.BIN again; a new task, the splash part
--            loaded again)
--   leave    quitting again and answering NO leaves STYLE CONVERT
--   guard    the run-time guard never refused anything and no part list failed; a file read that
--            failed and worked at a later attempt (cnv_main.s FILE_TRIES) is listed, not failed
--   resources each time a part's files are resident, every resource in RES_TAB equals the reference
--            unpack (AWT_RES = build/res: resource-0xNN.bin from tools/aw_extract.py), or, for a bitmap
--            kept packed, its card file sdfiles/AWRxx.AW
-- AWT_MODE=control: the same boot, floppy, card and menu walk with an application that ends at once
-- (noop_app.s as KN7APP.BIN): OK, the firmware's message, EXIT, "Continue Next?", NO. The baseline for
-- the IC23 and pool checks.
--
-- Throughout, in both modes, write taps record (written to AWT_OUT at the end):
--   ic23.txt     every write into CS1 (0x44000000-0x47FFFFFF, 0x84000000-0x87FFFFFF: IC23 repeating),
--                per PC and 4 KB page; "IC23 verdict: CLEAN" unless a PC lies in the converter area
--                0x502B8000-0x502E7FFF (the loader's code or the game's) or a write lands past IC23's
--                first 256 KB
--   pools.txt    every write into the user-memory pools (0x50180000-0x50297FFF and the 0x90 view), per
--                PC; "POOLS verdict: CLEAN" unless one comes from the converter area
--   awarea.txt   every write into the game's RAM (0x502BA000-0x50379FFF and its 0x90 view, but the
--                mailbox page) that is not the game's own (PC outside KN7APP.BIN, 0x502BA000-0x502BDFFF),
--                per phase and PC: "loading" (into the application area 0x502BA000-0x502E7FFF while the
--                loader is not running an application, LV_STATE != 1: the firmware zeroing the converter
--                area and reading KN7LOAD.CNV in, the loader zeroing it and reading KN7APP.BIN), "fileread"
--                (an SD read the game asked for, LD_IN_READ = 1, into the current record's destination),
--                and "foreign": anything else during the game. "AWAREA verdict: CLEAN" when there is no
--                foreign write
--   loader.txt   every write into the loader's resident area (0x502B8000-0x502B9FFF and its 0x90 view),
--                per phase, writer and PC: "loader" (its own code, 0x502B8000-0x502B9BFF), "GAME"
--                (KN7APP.BIN's code, at any time), and, from the menu walk to NO, "loading" (the firmware
--                loading KN7LOAD.CNV, before the loader has filled in its service table) and "foreign"
--                (anything else after that): "LOADER verdict: CLEAN" when there is no GAME or foreign
--                write
-- and at the end, just before POWER OFF (AWT_POWER=1) or the exit: pools.bin (the 1,146,880 bytes of
-- 0x50180000-0x50297FFF) and the firmware's own IC23 verdict for this boot (AWT_VALID = the address
-- of BackupSramChecksumVerify's byte: 893 0x5006CC7C, 941 0x5006CC80; 0 = valid).
-- AWT_MODE=verify: boot only, print that verdict at 40 s, then POWER OFF (AWT_POWER) or exit.
local M = manager.machine
local cpu = M.devices[":maincpu"]
local sp = cpu.spaces["program"]
local MODE = os.getenv("AWT_MODE") or "game"
local OUT = os.getenv("AWT_OUT") or "."
local VALID = tonumber(os.getenv("AWT_VALID") or "")
local POWER = (os.getenv("AWT_POWER") or "") ~= ""
-- addresses (src/platformcnv.inc, src/vm.inc, src/cnv_main.s; the loader's kn7cnv.inc and loader.s)
local CV, FW, INTERP, MISC = 0x502DF000, 0x502DF400, 0x502E1000, 0x502E3000
local CV_STATE, CV_QUIT, CV_DONE, CV_CALLS, CV_FAIL, CV_TASK = CV, CV + 4, CV + 8, CV + 0x10, CV + 0x14, CV + 0x1C
local LD_CUR, LD_FAILED, LD_IN_READ, LD_MS, LD_LISTS, LD_ERRORS = CV + 0x44, CV + 0x58, CV + 0x5C, CV + 0x64, CV + 0x68, CV + 0x70
local PART, FRAME_NO, HELP_PAGE = INTERP + 0x102A, MISC + 0x7C, MISC + 0x5C
local GUARD_WHAT, GUARD_ADDR, GUARD_COUNT = MISC + 0x210, MISC + 0x214, MISC + 0x218
local PERF = 0x502E6000                              -- vm.inc VM_PERF_BASE: PF_STATE +0x1C, PF_MODE +0x80,
local PF_STATE, PF_MODE, PF_SHOW, PF_BENCH, PF_REGS = PERF + 0x1C, PERF + 0x80, PERF + 0xC0, PERF + 0x100, PERF + 0x140
local CV_REPORT, CV_REPORT_N, CV_REPORT_K, REPORT_BUF = CV + 0x34, CV + 0x38, CV + 0x3C, 0x50370000
local CODE_LO, CODE_HI = 0x502BA000, 0x502C8000      -- KN7APP.BIN's image (APP_BASE..IMAGE_END_MAX)
local CNV_LO, CNV_HI = 0x502B8000, 0x502E8000        -- the converter area the firmware zeroes
local APP_BASE = 0x502BA000                          -- the loader's application area: APP_BASE..CNV_HI
local LOADER_LO, LOADER_HI, LOADER_CODE_HI = 0x502B8000, 0x502BA000, 0x502B9C00  -- resident; its image
local LV_STATE, SVC = 0x502B9D00, 0x502B9E00         -- loader.s: 1 = running an application; "KN7S"
local SV_FOUND, SV_OPEN = SVC + 0x64, SVC + 0x10
local LD_REC = CV + 0x4C                             -- the record being loaded: +4 destination, +8 bytes
local AW_LO, AW_HI, MB_LO, MB_HI = 0x502BA000, 0x5037A000, 0x5031B000, 0x5031C000

local RES_DIR = os.getenv("AWT_RES")
local RES_TAB = 0x502E5000
local results, fails = {}, 0
local function now() return M.time:as_double() end
local function log(s) print("awcnv_test: " .. s) end
local function result(name, ok, detail)
  results[#results + 1] = name
  if not ok then fails = fails + 1 end
  log(string.format("%-8s %s  %s", name, ok and "PASS" or "FAIL", detail))
  M.video:snapshot()
end
-- ---- resources: the part's files against the reference unpack ------------------------------------
local RES = { checked = 0, bad = 0, loads = 0, last = 0, types = {}, badlist = {} }
if RES_DIR then
  for line in io.lines(RES_DIR .. "/memlist.tsv") do
    local id, ty = line:match("^0x(%x+)\t(%a+)")
    if id then RES.types[tonumber(id, 16)] = ty end
  end
end
local function readfile(p) local f = io.open(p, "rb"); if not f then return nil end; local d = f:read("a"); f:close(); return d end
local function check_resources()
  RES.loads = RES.loads + 1
  for id = 0, 145 do
    local a = sp:read_u32(RES_TAB + 4 * id)
    if a ~= 0 then
      local ref = readfile(string.format("%s/resource-0x%02x.bin", RES_DIR, id))
      local packed = readfile(string.format("%s/sdfiles/AWR%02X.AW", RES_DIR, id))
      if RES.types[id] == "bitmap" and packed and ref and #packed ~= #ref then ref = packed end
      RES.checked = RES.checked + 1
      if not ref or sp:read_range(a, a + #ref - 1, 8) ~= ref then
        RES.bad = RES.bad + 1
        RES.badlist[#RES.badlist + 1] = string.format("%02X@%08X", id, a)
      end
    end
  end
end

local function var(i) local v = sp:read_u16(INTERP + 2 * i); return v >= 0x8000 and v - 0x10000 or v end
local function frame() return sp:read_u32(FRAME_NO) & 0xffff end
local function part() return sp:read_u16(PART) end

-- ---- the write taps ---------------------------------------------------------------------------
local phase = "boot"                 -- boot, game (first converter call .. NO), after
local T = { ic23 = {}, pools = {}, area = {}, loader = {}, ic23_n = 0, ic23_game = 0, ic23_beyond = 0, pools_game = 0,
            area_foreign = 0, area_fileread = 0, area_loading = 0, own_sp_lo = 0xffffffff, own_sp_hi = 0,
            loader_own = 0, loader_loading = 0, loader_game = 0, loader_foreign = 0 }
local function bump(t, k) t[k] = (t[k] or 0) + 1 end
local function pc() return cpu.state["PC"].value end
local function ic23_tap(base)
  return sp:install_write_tap(base, base + 0x3FFFFFF, string.format("t%08X", base), function(offset, data, mask)
    local p = pc()
    T.ic23_n = T.ic23_n + 1
    if p >= CNV_LO and p < CNV_HI then T.ic23_game = T.ic23_game + 1 end
    if (offset & 0x3FFFFFF) >= 0x40000 then T.ic23_beyond = T.ic23_beyond + 1 end
    bump(T.ic23, string.format("%s pc=%08X page=%08X", phase, p, offset & 0xFFFFF000))
  end)
end
local function pool_tap(base)
  return sp:install_write_tap(base + 0x180000, base + 0x297FFF, string.format("p%08X", base), function(offset, data, mask)
    local p = pc()
    if p >= CNV_LO and p < CNV_HI then T.pools_game = T.pools_game + 1 end
    bump(T.pools, string.format("%s pc=%08X page=%08X", phase, p, offset & 0xFFFFF000))
  end)
end
local function area_tap(base)
  local d = base - 0x50000000
  return sp:install_write_tap(AW_LO + d, AW_HI - 1 + d, string.format("a%08X", base), function(offset, data, mask)
    local a = offset - d
    if a >= MB_LO and a < MB_HI then return end           -- the mailbox page is the firmware's
    local p = pc()
    if p >= CODE_LO and p < CODE_HI then return end         -- the game's own write
    local kind
    local rec = sp:read_u32(LD_REC)
    if phase ~= "game" then kind = phase
    elseif sp:read_u32(LV_STATE) ~= 1 and a >= APP_BASE and a < CNV_HI then
      kind = "loading"; T.area_loading = T.area_loading + 1
    elseif sp:read_u32(LD_IN_READ) == 1 and rec ~= 0 and a >= sp:read_u32(rec + 4)
           and a < sp:read_u32(rec + 4) + sp:read_u32(rec + 8) then
      kind = "fileread"; T.area_fileread = T.area_fileread + 1
    else kind = "foreign"; T.area_foreign = T.area_foreign + 1 end
    bump(T.area, string.format("%-8s pc=%08X page=%08X", kind, p, a & 0xFFFFF000))
  end)
end
local function loader_tap(base)
  local d = base - 0x50000000
  return sp:install_write_tap(LOADER_LO + d, LOADER_HI - 1 + d, string.format("l%08X", base), function(offset, data, mask)
    local p = pc()
    local kind
    if p >= LOADER_LO and p < LOADER_CODE_HI then kind = "loader"; T.loader_own = T.loader_own + 1
    elseif p >= CODE_LO and p < CODE_HI then kind = "GAME"; T.loader_game = T.loader_game + 1
    elseif phase ~= "game" then kind = phase
    elseif sp:read_u32(SVC) ~= 0x53374E4B then kind = "loading"; T.loader_loading = T.loader_loading + 1
    else kind = "foreign"; T.loader_foreign = T.loader_foreign + 1 end
    bump(T.loader, string.format("%-8s %-7s pc=%08X page=%08X", phase, kind, p, (offset - d) & 0xFFFFFF00))
  end)
end
AWT_TAPS = { ic23_tap(0x44000000), ic23_tap(0x84000000), pool_tap(0x50000000), pool_tap(0x90000000),
             area_tap(0x50000000), area_tap(0x90000000), loader_tap(0x50000000), loader_tap(0x90000000) }

local function dump_table(f, t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  for _, k in ipairs(ks) do f:write(string.format("%s %d\n", k, t[k])) end
end
local function report()
  local f = io.open(OUT .. "/ic23.txt", "w")
  local v = "CLEAN"
  if T.ic23_game > 0 then v = string.format("GAME WROTE IC23 %d times", T.ic23_game) end
  if T.ic23_beyond > 0 then v = v .. string.format("; %d writes past 256 KB", T.ic23_beyond) end
  f:write(string.format("# IC23 verdict: %s (writes %d, from 0x%08X-0x%08X: %d, past 256 KB: %d)\n# phase pc page count\n",
    v, T.ic23_n, CNV_LO, CNV_HI - 1, T.ic23_game, T.ic23_beyond))
  dump_table(f, T.ic23); f:close()
  log("IC23 verdict: " .. v .. " (firmware writes " .. T.ic23_n .. ")")
  f = io.open(OUT .. "/pools.txt", "w")
  v = T.pools_game == 0 and "CLEAN" or string.format("GAME WROTE THE POOLS %d times", T.pools_game)
  f:write("# POOLS verdict: " .. v .. "\n# phase pc page count\n"); dump_table(f, T.pools); f:close()
  log("POOLS verdict: " .. v)
  f = io.open(OUT .. "/awarea.txt", "w")
  v = T.area_foreign == 0 and "CLEAN" or string.format("%d FOREIGN WRITES", T.area_foreign)
  f:write(string.format("# AWAREA verdict: %s (the firmware's and the loader's loads %d, SD reads for the game %d; SP seen in the game's code at 0x%08X-0x%08X)\n# kind pc page count\n",
    v, T.area_loading, T.area_fileread, T.own_sp_lo, T.own_sp_hi))
  dump_table(f, T.area); f:close()
  log(string.format("AWAREA verdict: %s (loads %d, SD reads %d; SP in game code 0x%08X-0x%08X)",
    v, T.area_loading, T.area_fileread, T.own_sp_lo, T.own_sp_hi))
  f = io.open(OUT .. "/loader.txt", "w")
  v = (T.loader_game == 0 and T.loader_foreign == 0) and "CLEAN"
      or string.format("GAME WROTE THE LOADER %d times, FOREIGN %d", T.loader_game, T.loader_foreign)
  f:write(string.format("# LOADER verdict: %s (the loader's own writes %d, the firmware loading it %d, the game's %d, foreign %d)\n# phase kind pc 256-byte block count\n",
    v, T.loader_own, T.loader_loading, T.loader_game, T.loader_foreign))
  dump_table(f, T.loader); f:close()
  log(string.format("LOADER verdict: %s (own %d, loading %d, game %d, foreign %d)", v, T.loader_own, T.loader_loading,
    T.loader_game, T.loader_foreign))
end

-- ---- inputs -------------------------------------------------------------------------------------
local function field(tag, mask)
  local p = M.ioport.ports[":cpanel:" .. tag] or M.ioport.ports[":" .. tag]
  for _, f in pairs(p.fields) do if f.mask == mask then return f end end
end
local KEY = {}
for _, tag in ipairs({ ":KEYS0", ":KEYS1", ":KEYS2", ":KEYS3" }) do
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do KEY[f.name] = f end end
end
local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function keyfield(n)            -- MIDI note -> the keybed field ("C4", "A5#", as probes/awpartkeys.lua)
  local nm, o = NAMES[n % 12 + 1], n // 12 - 1
  return KEY[nm:sub(2, 2) == "#" and (nm:sub(1, 1) .. o .. "#") or (nm .. o)]
end

-- ---- the session, as a coroutine resumed every frame ----------------------------------------------
local function wait(s) local t = now() + s; while now() < t do coroutine.yield() end end
local function wait_until(cond, s) local t = now() + s; while now() < t do if cond() then return true end; coroutine.yield() end; return cond() end
-- A panel press, confirmed in the firmware's own switch bitmap (AWT_PANEL = PANEL_CPR of the BIOS:
-- 893 0x5006BE4C, 941 0x5006BE50; CPL/CPC segments at +0x30): the emulated panel sometimes loses a
-- press (probes/cnv/README.md), so one the firmware never saw is released and tried again.
local PANEL = tonumber(os.getenv("AWT_PANEL") or "")
local LOST = 0
-- press_while(tag, mask, cond, s): hold the button until cond() (or s seconds); -> cond().
local function press_while(tag, mask, cond, s)
  local f = field(tag, mask)
  local seg = tonumber(tag:match("SEG(%d+)"))
  local byte = PANEL and (PANEL + seg + (tag:sub(1, 3) == "CPR" and 0 or 0x30))
  for try = 1, 6 do
    f:set_value(1)
    local seen = not byte or wait_until(function() return (sp:read_u8(byte) & mask) ~= 0 end, 1.0)
    if seen then local r = wait_until(cond, s); f:set_value(0); return r end
    f:set_value(0); LOST = LOST + 1
    local bm = ""
    for i = 0, 15 do bm = bm .. string.format("%02X", sp:read_u8(PANEL + i)) end
    bm = bm .. "|"
    for i = 0, 15 do bm = bm .. string.format("%02X", sp:read_u8(PANEL + 0x30 + i)) end
    log(string.format("press %s %02X not seen by the firmware at t=%.1f s (try %d; bitmaps CPR|CPL %s; converter calls %d); again",
      tag, mask, now(), try, bm, sp:read_u32(CV_CALLS)))
    wait(1.5)
  end
  return false
end
local function press(tag, mask, hold) press_while(tag, mask, function() return false end, hold or 0.4) end
local function key(n, hold) local f = keyfield(n); f:set_value(1); wait(hold or 0.3); f:set_value(0) end
local function menus_to_convert()     -- DISK MENU, STYLE CONVERT (left button 3), OK (right button 4)
  wait_until(function() return now() > 30 end, 60)
  press("CPR_SEG1", 0x04); wait(6)
  press("CPL_SEG0", 0x20); wait(8)
  phase = "game"
  -- OK, until the firmware loads the converter (KN7LOAD.CNV): with some IC23 contents (the owner's;
  -- a stamped blank one on 941) the converter list is not ready for OK 8 s after STYLE CONVERT, and
  -- the press is lost (the screen still shows the list). The load shows as the firmware's writes
  -- into the converter area, which it zeroes, before the loader runs (the area tap's "loading").
  for i = 1, 8 do
    press("CPR_SEG6", 0x01)
    if wait_until(function() return T.area_loading > 0 end, 6) then return end
    log(string.format("OK press %d not taken at t=%.0f s; again", i, now()))
  end
end
local function enter_code(code)       -- the code screen's letter grid with the keybed D-pad (gen_code_keys.py)
  local grid = { OK = { 0, 6 } }
  for i, c in ipairs({ "B", "C", "D", "F", "G", "H" }) do grid[c] = { 0, i - 1 } end
  for i, c in ipairs({ "J", "K", "L", "R", "T", "X" }) do grid[c] = { 1, i - 1 } end
  local r, c = 0, 3                   -- the cursor starts on F
  local seq = {}
  for ch in code:gmatch(".") do seq[#seq + 1] = ch end
  seq[#seq + 1] = "OK"
  for _, ch in ipairs(seq) do
    local g = grid[ch]
    while r < g[1] do key(81); wait(0.4); r = r + 1 end   -- A5 down
    while r > g[1] do key(82); wait(0.4); r = r - 1 end   -- Bb5 up
    while c < g[2] do key(84); wait(0.4); c = c + 1 end   -- C6 right
    while c > g[2] do key(77); wait(0.4); c = c - 1 end   -- F5 left
    key(48); wait(0.4)                                    -- C3 action
  end
end
local function to_part(code, want)
  press("CPC_SEG5", 0x01)                                -- OTHER PART & FR: the code screen
  local ok = wait_until(function() return part() == 0x3E88 and frame() > 0 end, 60)
  if not ok then return false, string.format("no code screen (part %04X)", part()) end
  wait(3)
  enter_code(code)
  ok = wait_until(function() return part() == want and sp:read_u32(LD_CUR) == want end, 90)
  local f0 = frame(); wait(3)
  return ok and frame() > f0, string.format("part %04X resident %04X, frames %d -> %d", part(), sp:read_u32(LD_CUR), f0, frame())
end
local function quit_game()            -- hold EXIT 2 s: the task ends, the converter answers 0xFE
  press("CPC_SEG11", 0x80, 2.0)
  return wait_until(function() return sp:read_u32(CV_DONE) == 1 end, 10)
end

local function game()
  menus_to_convert()
  local ok = wait_until(function() return sp:read_u32(CV_STATE) == 3 and sp:read_u32(CV_TASK) ~= 0 end, 120)
  local s = ""
  for i = 0, 0x1C, 4 do s = s .. string.format(" %08X", sp:read_u32(FW + i)) end
  result("found", ok, string.format("loader state %d found %02X; state %d fail %X task %d; open/read/close/cre/sta/dly/exd/setext%s; ms %08X panel %08X midi %08X/%08X",
    sp:read_u32(LV_STATE), sp:read_u32(SV_FOUND), sp:read_u32(CV_STATE), sp:read_u32(CV_FAIL), sp:read_u32(CV_TASK), s,
    sp:read_u32(MISC + 0x200), sp:read_u32(MISC + 0x204), sp:read_u32(MISC + 0x208), sp:read_u32(MISC + 0x20C)))
  if not ok then return end
  ok = wait_until(function() return part() == 0x3E80 and frame() > 30 end, 120)
  result("splash", ok, string.format("part %04X frame %d; splash files loaded in %d ms", part(), frame(), sp:read_u32(LD_MS)))
  ok = wait_until(function() return part() == 0x3E81 and frame() > 0 end, 120)
  wait(4)
  result("intro", ok, string.format("part %04X frame %d; intro files loaded in %d ms", part(), frame(), sp:read_u32(LD_MS)))
  keyfield(60):set_value(1)
  ok = wait_until(function() return part() == 0x3E82 end, 60)
  keyfield(60):set_value(0)
  ok = ok and wait_until(function() return sp:read_u32(LD_CUR) == 0x3E82 end, 60)
  wait(4)
  result("skip", ok, string.format("part %04X frame %d; lake files loaded in %d ms", part(), frame(), sp:read_u32(LD_MS)))
  -- the five panel buttons that were the D-pad and fire until 2026-10-21, each with the hero variable it
  -- must NOT set any more (it is "(moved)" in the result if it does). While
  -- AW.CNV parks the firmware, the firmware still acts on R1/R2 OCTAVE + / - (the octave setting,
  -- IC23 header byte 0x6EA) and SUSTAIN (header 0xCE bit 0x08): awcnv_panelsettings.lua. So they
  -- are pressed in pairs that cancel (+ then -, SUSTAIN twice), each press's effect on IC23's header
  -- (the live panel settings, 0x84000000-0x840007A3) is recorded, and "settings" requires the
  -- header to end as it began: whatever IC23 holds afterwards is then the game's doing alone.
  local function header() return sp:read_range(0x84000000, 0x840007A3, 8) end
  local function diff(a, b)
    local d = {}
    for i = 1, #a do if a:byte(i) ~= b:byte(i) then d[#d + 1] = string.format("%03X", i - 1) end end
    return table.concat(d, ",")
  end
  local h0, got, fx = header(), {}, {}
  -- (the firmware writes SUSTAIN's second toggle only with a later panel event: probe output, so
  -- the pairs come first and the two PART SELECT presses after them)
  for _, b in ipairs({ { "FIRE", "CPR_SEG5", 0x08, 0xFA, 1 }, { "FIRE", "CPR_SEG5", 0x08, 0xFA, 1 },
                       { "UP", "CPR_SEG6", 0x02, 0xE5, -1 }, { "DOWN", "CPR_SEG7", 0x02, 0xE5, 1 },
                       { "RIGHT", "CPR_SEG1", 0x02, 0xFC, 1 }, { "RIGHT", "CPR_SEG1", 0x02, 0xFC, 1 },
                       { "LEFT", "CPR_SEG2", 0x01, 0xFC, -1 } }) do
    local hb = header()
    local ok = press_while(b[2], b[3], function() return var(b[4]) == b[5] end, 1.5)
    wait(2)
    got[#got + 1] = b[1] .. (ok and "(moved)" or "")
    local d = diff(hb, header())
    if d ~= "" then fx[#fx + 1] = b[1] .. "->" .. d end
  end
  wait(3)
  local dend = diff(h0, header())
  local all = not table.concat(got, " "):find("moved")
  result("panel", all, "no button set its hero variable: " .. table.concat(got, " "))
  result("settings", dend == "", string.format("header bytes the firmware changed per press: %s; changed at the end: %s",
    #fx > 0 and table.concat(fx, " ") or "none", dend ~= "" and dend or "none"))
  wait(1); local seen = 0
  keyfield(60):set_value(1)
  wait_until(function() if var(0xFA) == 1 then seen = 1 end; return seen == 1 end, 1.5)
  keyfield(60):set_value(0)
  result("keybed", seen == 1, "var[0xFA] reached " .. seen)
  wait(2)
  press("CPC_SEG5", 0x02)                                -- HELP
  wait(2)
  local f0 = frame(); wait(2)
  local paused = frame() == f0
  local p0 = sp:read_u32(HELP_PAGE)
  M.video:snapshot()
  press("CPC_SEG11", 0x20); wait(2)                       -- PAGE DOWN
  local p1 = sp:read_u32(HELP_PAGE)
  M.video:snapshot()
  press("CPC_SEG11", 0x80); wait(3)                       -- EXIT
  f0 = frame(); wait(2)
  result("help", paused and p0 == 0 and p1 == 1 and frame() > f0,
    string.format("VM paused %s, page %d then %d after PAGE DOWN, running again after EXIT %s", tostring(paused), p0, p1, tostring(frame() > f0)))
  -- the speed figures: the fourth help page, the overlay, the old blit and back
  local hb = sp:read_range(0x84000000, 0x840007A3, 8)
  press("CPC_SEG5", 0x02); wait(2)                        -- HELP
  for i = 1, 3 do press("CPC_SEG11", 0x20); wait(1.5) end -- PAGE DOWN x3: the speed page
  local p3 = sp:read_u32(HELP_PAGE)
  M.video:snapshot()
  press("CPC_SEG11", 0x80); wait(3)                       -- EXIT
  press("CPC_SEG11", 0x10); wait(3)                       -- PAGE UP: the overlay on
  local ovl = sp:read_u32(PF_STATE) & 1
  M.video:snapshot()
  press("CPC_SEG11", 0x20); wait(1)                       -- PAGE DOWN: the old blit
  local m1, f1 = sp:read_u32(PF_MODE), frame(); wait(3)
  local run1 = frame() > f1
  M.video:snapshot()
  press("CPC_SEG11", 0x20); wait(1)                       -- PAGE DOWN: the new blit again
  local m2, f2 = sp:read_u32(PF_MODE), frame(); wait(3)
  local run2 = frame() > f2
  press("CPC_SEG11", 0x10); wait(2)                       -- PAGE UP: the overlay off
  local ovl2 = sp:read_u32(PF_STATE) & 1
  local hd = (sp:read_range(0x84000000, 0x840007A3, 8) == hb) and "unchanged" or "CHANGED"
  local fig = {}
  for i, k in ipairs({ "fps x10", "frame ms x10", "longest x10", "LCD px/frame" }) do fig[#fig + 1] = k .. " " .. sp:read_u32(PF_SHOW + 4 * (i - 1)) end
  local bn = {}
  for i = 0, 8 do bn[#bn + 1] = tostring(sp:read_u32(PF_BENCH + 4 * i)) end
  result("speed", p3 == 3 and ovl == 1 and m1 == 1 and run1 and m2 == 0 and run2 and ovl2 == 0,
    string.format("speed page %d; overlay on %d, off %d; old blit %d running %s, new blit %d running %s; IC23 header %s; last window (MAME's time): %s; bench ns x10 %s",
      p3, ovl, ovl2, m1, tostring(run1), m2, tostring(run2), hd, table.concat(fig, ", "), table.concat(bn, " ")))
  ok, s = to_part("HTDC", 0x3E83)
  result("prison", ok, "HTDC: " .. s .. string.format("; %d ms", sp:read_u32(LD_MS)))
  ok, s = to_part("CLLD", 0x3E84)
  result("city", ok, "CLLD: " .. s .. string.format("; %d ms", sp:read_u32(LD_MS)))
  wait(5)
  ok = quit_game()
  local fq = frame(); wait(3)
  result("quit", ok and frame() == fq, string.format("TASK_DONE %d, frame stays %d", sp:read_u32(CV_DONE), fq))
  press("CPC_SEG11", 0x80); wait(4)                       -- EXIT: the message box -> "Continue Next?"
  result("menus", frame() == fq, "frame stayed " .. fq .. " (snapshot: Continue Next? YES/NO)")
  press("CPR_SEG7", 0x01)                                -- YES (right button 3): play again
  ok = wait_until(function() return sp:read_u32(CV_DONE) == 0 and part() == 0x3E80 and frame() > 20 end, 90)
  result("again", ok, string.format("YES: task %d, part %04X frame %d", sp:read_u32(CV_TASK), part(), frame()))
  wait(3)
  ok = quit_game()
  press("CPC_SEG11", 0x80); wait(4)
  press("CPR_SEG6", 0x01); wait(2)                        -- NO (right button 4)
  phase = "after"
  local calls = sp:read_u32(CV_CALLS); wait(6)
  result("leave", ok and sp:read_u32(CV_CALLS) == calls, "second quit, NO; the converter is not called any more (snapshot: main screen)")
  local elog = {}
  for i = 0, math.min(sp:read_u32(LD_ERRORS), 8) - 1 do elog[#elog + 1] = string.format("%08X", sp:read_u32(CV + 0x100 + 4 * i)) end
  result("guard", sp:read_u32(GUARD_COUNT) == 0 and sp:read_u32(LD_FAILED) == 0,
    string.format("guard refusals %d (last %d at %08X); no list failed: %s; part lists loaded %d; failed file attempts %d (kind<<24|id<<8|try: %s), files loaded only at a later attempt %d",
      sp:read_u32(GUARD_COUNT), sp:read_u32(GUARD_WHAT), sp:read_u32(GUARD_ADDR), tostring(sp:read_u32(LD_FAILED) == 0),
      sp:read_u32(LD_LISTS), sp:read_u32(LD_ERRORS), table.concat(elog, " "), sp:read_u32(CV + 0x7C)))
  local rn = sp:read_u32(CV_REPORT_N)
  if sp:read_u32(CV_REPORT) == 1 and rn > 0 and rn < 0x2000 then
    local f = io.open(OUT .. "/awperf_ram.txt", "wb"); f:write(sp:read_range(REPORT_BUF, REPORT_BUF + rn - 1, 8)); f:close()
  end
  result("report", sp:read_u32(CV_REPORT) == 1 and rn > 0 and sp:read_u32(CV_REPORT_K) == 1,
    string.format("the second quit's report: state %d, AWPERF%d.TXT, %d bytes written (awperf_ram.txt)",
    sp:read_u32(CV_REPORT), sp:read_u32(CV_REPORT_K), rn))
  if RES_DIR then
    result("resources", RES.bad == 0 and RES.loads >= 6, string.format("%d parts made resident, %d resident resources compared, %d differ %s",
      RES.loads, RES.checked, RES.bad, table.concat(RES.badlist, " ")))
  end
end

local function control()
  menus_to_convert()                  -- the no-op application answers 0xFE at once: the firmware's message
  wait(6)
  press("CPC_SEG11", 0x80); wait(4)   -- EXIT -> "Continue Next?"
  press("CPR_SEG6", 0x01); wait(2)    -- NO
  phase = "after"
  wait(6)
  result("control", true, string.format("no-op application run (loader state %d, found %02X), NO (snapshot: main screen)",
    sp:read_u32(LV_STATE), sp:read_u32(SV_FOUND)))
end

local function finish()
  wait(4)
  local f = io.open(OUT .. "/pools.bin", "wb")
  f:write(sp:read_range(0x50180000, 0x50297FFF, 8)); f:close()
  if VALID then log(string.format("IC23 at this boot: the firmware's verdict byte %02X (0 = valid)", sp:read_u8(VALID))) end
  report()
  log(string.format("%d checks, %d failed (t=%.0f s); panel presses the emulated panel lost and the harness repeated: %d", #results, fails, now(), LOST))
  if POWER then
    log("POWER OFF")
    for _, fl in pairs(M.ioport.ports[":POWER"].fields) do fl:set_value(1) end
  else
    M:exit()
  end
end

local co = coroutine.create(function()
  if MODE == "game" then game() elseif MODE == "control" then control() else wait(40) end
  finish()
  while true do coroutine.yield() end
end)
AWT_TICK = emu.add_machine_frame_notifier(function()   -- every emulated frame: timing independent of the host
  if RES_DIR and phase == "game" then  -- a part has just become resident: check its files
    local cur = sp:read_u32(LD_CUR)
    if cur ~= 0 and cur ~= RES.last then check_resources() end
    RES.last = cur
  end
  local p = pc()                      -- where the game's code runs with its stack (the kernel allocates it)
  if p >= CODE_LO and p < CODE_HI then
    local st = cpu.state["SP"].value
    if st < T.own_sp_lo then T.own_sp_lo = st end
    if st > T.own_sp_hi then T.own_sp_hi = st end
  end
  if coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then log("ERROR " .. tostring(err)); report(); M:exit() end
  end
end)
