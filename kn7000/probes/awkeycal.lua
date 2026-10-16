-- Calibrate keybed->RAM. Uses a self-incremented tick (not the VM FRAME_NO, which my
-- intro-skip resets on part switch). Holds each key ~40 ticks, samples the 9 moving bytes.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD=field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local KEYS={
  {":KEYS0","C3"},{":KEYS0","E3"},{":KEYS0","G3"},
  {":KEYS1","C4"},{":KEYS1","E4"},{":KEYS1","G4"},{":KEYS1","A4"},{":KEYS1","B4"},
  {":KEYS2","C5"},{":KEYS2","E5"},{":KEYS2","G5"},
}
local ADDRS={0x50149674,0x5014967C,0x50149686,0x501496A4,0x50149690,0x5014969A}
local function samp() local s={} for _,a in ipairs(ADDRS) do s[#s+1]=string.format("%02x",sp:read_u8(a)) end return table.concat(s," ") end
local function u16(a) return sp:read_u8(a)*256+sp:read_u8(a+1) end
local tick=0; local pressed=false; local idx=0; local cur=nil; local phaset=0
emu.register_periodic(function()
  tick=tick+1
  if not pressed and tick>120 then SD:set_value(1); pressed=true; io.write("addrs: 74 | 7C(u16) 86(u16) A4(u16) | 90 9A\n") end
  if pressed and tick>128 and SD then SD:set_value(0) end
  if not pressed then return end
  if idx==0 and tick>150 then io.write(string.format("RELEASED       : %s  [7C=%04x]\n",samp(),u16(0x5014967C))); idx=1; phaset=tick end
  if idx>=1 and idx<=#KEYS then
    if cur==nil then cur=field(KEYS[idx][1],KEYS[idx][2]); cur:set_value(1); phaset=tick end
    if tick>=phaset+40 then
      io.write(string.format("%-4s held      : %s  [7C=%04x 86=%04x A4=%04x]\n",KEYS[idx][2],samp(),u16(0x5014967C),u16(0x50149686),u16(0x501496A4)))
      cur:set_value(0); cur=nil; idx=idx+1; phaset=tick
    end
  end
  if idx>#KEYS and tick>=phaset+30 then io.write(string.format("RELEASED-END   : %s\n",samp())); M:exit() end
end)
