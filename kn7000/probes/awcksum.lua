-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- Per-frame front-page dump for the KN7000 Another World port, for pixel-exact
-- comparison against a reference VM (rustyworld). At every VM tick it captures
-- the 320x200 palette-index bytes of the DISPLAYED page (CUR_PAGE_2) and appends
-- them to a raw binary file, plus a text index of "tick frontaddr". CRC-32 of
-- each 64000-byte frame is computed offline (probes/cksum_pages.py) so it matches
-- the reference's IEEE/zlib crc32 exactly.
--
-- Tick capture is driven by a WRITE TAP on FRAME_NO (0x4408007C), which the
-- scheduler writes exactly once per frame (interp.s end-of-frame path), AFTER it
-- re-presents CUR_PAGE_2 -- so the front page read here is that tick's final
-- frame. FRAME_NO is written to 1 for the first frame, so tick = value - 1,
-- aligning tick 0 with the reference's first scheduler pass. The GameReset
-- zero-write is ignored.
--
-- Question it answers: what does our port actually display, pixel for pixel, at
-- VM frame N? (Diff its crc stream against the reference to find the first
-- diverging frame.)
--
--   mame-pr/kn7000 kn7000 -bios sp7001 -rompath <roms> -harddisk <sd.img> \
--     -autoboot_script probes/awcksum.lua -str <N> -window -nothrottle
-- env: AWCK_BIN (raw pages out), AWCK_IDX (tick index out), AWCK_MAX (last tick),
--      AW_START_PART (e.g. 0x3E83: request that part at the end of tick 0, so tick 1 on runs it
--      -- the same point rustyworld's refcksum switches with START_PART; for per-part checks).
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
-- The port starts with the splash unless NO_SPLASH (0x44080058) holds the magic 0x5EED0FF0; the
-- recorded fixtures and reference logs start at the intro, so write it (AW_SPLASH=1 keeps the splash).
if os.getenv("AW_SPLASH") ~= "1" then sp:write_u32(0x44080058, 0x5EED0FF0) end
local function field(tag, name)
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do if f.name == name then return f end end end
end
local SD = field(":cpanel:CPR_SEG1", "SD CARD LOAD (SW7)")
local CUR_PAGE_2 = 0x4407100C
local FRAME_NO   = 0x4408007C
local OUTBIN = os.getenv("AWCK_BIN") or "build/our_pages.bin"
local OUTIDX = os.getenv("AWCK_IDX") or "build/our_pages.idx"
local MAXTICK = tonumber(os.getenv("AWCK_MAX") or "2650")
local START_PART = os.getenv("AW_START_PART") and tonumber(os.getenv("AW_START_PART"))
local REQ_NEXT_PART = 0x4407102C
local binf = io.open(OUTBIN, "wb")
local idxf = io.open(OUTIDX, "w")
local pressed = false
local captured = 0
local finish = false

-- The data bus is 32-bit, so the tap range must span the whole word
-- (0x..7C-0x..7F); filter to the exact FRAME_NO offset in the callback.
-- The handle MUST be kept alive (a global here) or Lua GC removes the tap.
AWCK_TAP = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awframe", function(offset, data, mask)
  if finish then return end
  if offset ~= FRAME_NO then return end   -- ignore other writes in the word
  local v = data & 0xffff
  if v == 0 then return end        -- GameReset zero-write: not a frame
  local tick = v - 1               -- FRAME_NO==1 is the first frame -> tick 0
  -- NextThread applies REQ_NEXT_PART after this FRAME_NO bump, so setting it now switches parts
  -- between tick 0 and tick 1
  if tick == 0 and START_PART then sp:write_u16(REQ_NEXT_PART, START_PART) end
  local front = sp:read_u32(CUR_PAGE_2)
  local s = sp:read_range(front, front + 63999, 8)   -- 64000 index bytes, one call
  binf:write(s)
  idxf:write(string.format("%d %08X\n", tick, front))
  captured = captured + 1
  if tick >= MAXTICK then
    finish = true
    binf:close(); idxf:close()
    print(string.format("awcksum: captured %d frames (last tick %d); exiting", captured, tick))
  end
end)

emu.register_periodic(function()
  local t = M.time:as_double()
  if not pressed and t > 11 then SD:set_value(1); pressed = true end
  if pressed and t > 11.4 and SD then SD:set_value(0) end
  if finish then M:exit() end
end)
