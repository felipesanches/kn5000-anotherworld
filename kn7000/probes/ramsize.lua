-- (c) 2026 Felipe Correa da Silva Sanches; GPL v3+
-- Find the real size of the 0x44 external-memory window: write a distinct value at
-- each offset, then read them all back. Aliases reveal the wrap size.
local M=manager.machine; local sp=M.devices[":maincpu"].spaces["program"]
local out=io.open(os.getenv("RAMSIZE_LOG") or "build/ramsize.log","w")
local function L(s) out:write(s.."\n"); out:flush() end
local offs={0x000000,0x010000,0x040000,0x080000,0x100000,0x200000,0x400000,0x800000,0xC00000,0xF00000}
local done=false
emu.register_periodic(function()
  if done or M.time:as_double()<8 then return end
  done=true
  for i,o in ipairs(offs) do sp:write_u32(0x44000000+o, 0xA0000000+i) end
  for i,o in ipairs(offs) do
    L(string.format("0x44%06X : wrote 0x%08X, read 0x%08X", o, 0xA0000000+i, sp:read_u32(0x44000000+o)&0xffffffff))
  end
  -- also work RAM 0x50 high region
  for _,o in ipairs({0x100000,0x200000,0x2C0000,0x300000,0x380000,0x3C0000}) do
    sp:write_u32(0x50000000+o, 0xB0000000+o)
  end
  L("--- work RAM 0x50 (after firmware is running) ---")
  for _,o in ipairs({0x100000,0x200000,0x2C0000,0x300000,0x380000,0x3C0000}) do
    L(string.format("0x50%06X : read 0x%08X", o, sp:read_u32(0x50000000+o)&0xffffffff))
  end
  M:exit()
end)
