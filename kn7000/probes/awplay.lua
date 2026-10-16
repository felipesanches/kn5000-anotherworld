-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Watch the Another World intro play: snapshot the LCD at several times and log the
-- VM frame count + a cheap checksum of the displayed page, so we can tell whether it
-- is animating. Run via mame-pr/kn7000 with -str to clear the warning screen.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("RENDER_LOG") or "build/awplay.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local function u8(a) return sp:read_u8(a) end
local function u32(a) return sp:read_u32(a) end
local pressed=false
local shots = {15,19,23,27,31,35,39,43}
local idx = 1
local function page_sig(base)
  local s=0; for i=0,63999,101 do s=(s*31 + u8(base+i)) & 0xffffffff end return s
end
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if idx<=#shots and t>shots[idx] then
    local disp=u32(0x4407100C)   -- CUR_PAGE_2
    local sig = (disp>=0x44100000 and disp<0x44200000) and page_sig(disp) or 0
    L(string.format("t=%2d  frames=%d  insns=%d  thread=%d  disp=%08X  sig=%08X",
      shots[idx], u32(0x44080054), u32(0x44080010), u8(0x44071000), disp, sig))
    M.video:snapshot()
    idx = idx + 1
    if idx > #shots then M:exit() end
  end
end)
