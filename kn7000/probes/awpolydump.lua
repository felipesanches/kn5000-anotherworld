-- (c) 2026 Felipe Correa da Silva Sanches <juca@members.fsf.org>; GPL v3+
--
-- Dump the exact inputs our KN7000 port feeds the polygon fill, per VM tick, so
-- they can be diffed against the reference VM's (rustyworld) polygon stream to
-- localize a rendering divergence. A WRITE TAP on POLY_YMAX (written once per
-- FillPolygon, after bbox/colour/points are set and before rasterizing) captures
-- each non-degenerate polygon's state from the POLY_* fields. A second tap on
-- FRAME_NO tracks the rendering tick. (Degenerate single-point polys return
-- before POLY_YMAX is written -- the reference's dump skips them too.)
--
--   mame-pr/kn7000 kn7000 -bios sp7001 -rompath <roms> -harddisk <sd.img> \
--     -autoboot_script probes/awpolydump.lua -str <N> -window -nothrottle
-- env: AWPD_OUT (output path), AWPD_MAXTICK (stop after this rendering tick).
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local function field(tag, name)
  local p = M.ioport.ports[tag]
  if p then for _, f in pairs(p.fields) do if f.name == name then return f end end end
end
local SD = field(":cpanel:CPR_SEG1", "SD CARD LOAD (SW7)")
local VM_STATE = 0x44050000
local POLY_NUM_POINTS = VM_STATE + 0x00
local POLY_BBOX_W     = VM_STATE + 0x02
local POLY_BBOX_H     = VM_STATE + 0x04
local POLY_XMIN       = VM_STATE + 0x06
local POLY_XMAX       = VM_STATE + 0x08
local POLY_YMIN       = VM_STATE + 0x0A
local POLY_YMAX       = VM_STATE + 0x0C
local DRAW_COLOR      = VM_STATE + 0x38
local POLY_POINTS     = VM_STATE + 0x40
local FRAME_NO        = 0x4408007C
local OUT     = os.getenv("AWPD_OUT") or "build/our_polys.txt"
local MAXTICK = tonumber(os.getenv("AWPD_MAXTICK") or "3")
local outf = io.open(OUT, "w")
local rt = 0          -- current rendering tick
local pressed = false
local finish = false

local function s16(v) v = v & 0xffff; if v >= 0x8000 then return v - 0x10000 end return v end

AWPD_FTAP = sp:install_write_tap(FRAME_NO, FRAME_NO + 3, "awpd_frame", function(offset, data, mask)
  if offset ~= FRAME_NO then return end
  local v = data & 0xffff
  rt = v            -- FRAME_NO written to v => tick v begins rendering
  if rt > MAXTICK and not finish then finish = true; outf:close() end
end)

AWPD_YTAP = sp:install_write_tap(POLY_YMAX, POLY_YMAX + 3, "awpd_poly", function(offset, data, mask)
  if finish then return end
  if offset ~= POLY_YMAX then return end
  if rt > MAXTICK then return end
  local xmin = s16(sp:read_u16(POLY_XMIN))
  local xmax = s16(sp:read_u16(POLY_XMAX))
  local ymin = s16(sp:read_u16(POLY_YMIN))
  local ymax = s16(data & 0xffff)                 -- being written now
  local bw = sp:read_u16(POLY_BBOX_W)
  local bh = sp:read_u16(POLY_BBOX_H)
  local n = sp:read_u8(POLY_NUM_POINTS)
  local color = sp:read_u8(DRAW_COLOR)
  local cx = (xmin + xmax) // 2
  local cy = (ymin + ymax) // 2
  local pts = {}
  for k = 0, n - 1 do
    local px = sp:read_u16(POLY_POINTS + k * 4)
    local py = sp:read_u16(POLY_POINTS + k * 4 + 2)
    pts[#pts + 1] = string.format("%d,%d", px, py)
  end
  outf:write(string.format("POLY t=%d color=%d cx=%d cy=%d w=%d h=%d n=%d pts=%s\n",
    rt, color, cx, cy, bw, bh, n, table.concat(pts, ";")))
end)

emu.register_periodic(function()
  local t = M.time:as_double()
  if not pressed and t > 11 then SD:set_value(1); pressed = true end
  if pressed and t > 11.4 and SD then SD:set_value(0) end
  if finish then print("awpolydump: done"); M:exit() end
end)
