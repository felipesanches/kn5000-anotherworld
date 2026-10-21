-- awmidiq.lua -- which firmware byte ring does each input path feed?
--
-- The firmware's lib keeps byte rings with the header {start @+0, last @+4, rd @+8, wr @+0xC,
-- free u16 @+0x10} (enqueue lib 0x4C024D16; per-ring wrappers at lib 0x4C024A1F.. load the
-- header address). This logs the eight rings' headers once, then every rd/wr change with the
-- byte just written. Answer (program 942 / SP7001, 2026-10-17):
--   Q1 0x5001F060 (1024 B) gets the MIDI IN 1 bytes (90 54 64 / 80 54 40 / 90 51 64 / 90 51 00);
--   Q2 0x5001F874 and Q4 0x5002049C (2048 B each) get every keybed note as MIDI (90 54 42, then
--   running-status 54 00 on release) -- the two MIDI OUT transmit rings (awmidiqtrace.lua).
--
-- MIDI: probes/gen_q_mid.py writes the SMF (C6 on/off, then A5 on + running-status vel-0 off,
-- at emu 14.0..15.5 s); a keybed C6 is pressed at emu 17.0..17.3 s.
--   python3 -I probes/gen_q_mid.py ~/compartilhado/tmp/q.mid
--   cd ~/compartilhado && ~/compartilhado/mame-pr/kn7000 -rompath ~/compartilhado/technics_romsets \
--     -skip_gameinfo -window kn7000 -bios sp7001 \
--     -harddisk ~/compartilhado/technics-anotherworld/kn7000/build/another_sd.img \
--     -midiin1 ~/compartilhado/tmp/q.mid -autoboot_script <this file> -str 30
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
-- program 942 (SP7001) addresses; the default 941 build's are 0x10 lower
local Q={0x5001F060,0x5001F874,0x5001FC88,0x5002049C,0x500208B0,0x50020CC4,0x500210D8,0x500214EC}
local function hdr(q) return {sp:read_u32(q),sp:read_u32(q+4),sp:read_u32(q+8),sp:read_u32(q+12),sp:read_u16(q+16)} end
local last={}; local C6
for _,tag in ipairs({":KEYS0",":KEYS1",":KEYS2",":KEYS3"}) do local p=M.ioport.ports[tag]
  if p then for _,f in pairs(p.fields) do if f.name=="C6" then C6=f end end end end
local shown=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if t>8 and not shown then shown=true
    for i,q in ipairs(Q) do local h=hdr(q)
      print(string.format("Q%d %08X start=%08X last=%08X rd=%08X wr=%08X free=%d (size %d)",i,q,h[1],h[2],h[3],h[4],h[5],h[2]-h[1]+1)) end end
  if t>8 then for i,q in ipairs(Q) do local h=hdr(q); local k=h[3]..":"..h[4]
    if last[i] and last[i]~=k then
      local p=h[4]-1; if p<h[1] then p=h[2] end
      print(string.format("t=%.3f Q%d rd=%08X wr=%08X free=%d lastbyte=%02X",t,i,h[3],h[4],h[5],sp:read_u8(p))) end
    last[i]=k end end
  if C6 then C6:set_value((t>17.0 and t<17.3) and 1 or 0) end
  if t>19 then M:exit() end
end)
