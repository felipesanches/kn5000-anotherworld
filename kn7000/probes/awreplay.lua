-- awreplay.lua -- deterministic KN7000-side REPLAY for differential testing against rustyworld.
--
-- Feeds the KN7000 Another World VM the exact per-frame hero inputs recorded from a play
-- session (probes/awmonitor.lua -> aw-inputs.csv), by OVERRIDING the six hero variables each
-- frame right after ReadInput writes them, and captures the displayed page per VM tick (same
-- format as awcksum.lua). Run the reference rustyworld on the SAME csv (replaycksum) and diff
-- the two crc streams (cksum_pages.py + compare_frames.py): any divergence is pure VM logic.
--
--   AWCK_BIN=our.bin AWCK_IDX=our.idx AWCK_MAX=<lastTick> AW_INPUTS=~/compartilhado/tmp/aw-inputs.csv \
--     mame-pr/kn7000 kn7000 -bios sp7001 -rompath <roms> -harddisk <sd.img> \
--     -autoboot_script probes/awreplay.lua -str <N> -window -nothrottle
local M = manager.machine
local sp = M.devices[":maincpu"].spaces["program"]
local function field(tag,name) local p=M.ioport.ports[tag]; if p then for _,f in pairs(p.fields) do if f.name==name then return f end end end end
local SD = field(":cpanel:CPR_SEG1","SD CARD LOAD (SW7)")
local CUR_PAGE_2=0x4407100C; local FRAME_NO=0x4408007C
-- hero var addresses (VM_VARIABLES 0x44070000 + idx*2)
local A_LR=0x440701F8; local A_UD=0x440701CA; local A_JMP=0x440701F6
local A_PMASK=0x440701FA; local A_ACT=0x440701F4; local A_AMASK=0x440701FC

-- load the recorded inputs: frame -> {lr,ud,jmp,pmask,act,amask}
local INPATH = os.getenv("AW_INPUTS") or (os.getenv("HOME").."/compartilhado/tmp/aw-inputs.csv")
local INP = {}
do local f=io.open(INPATH,"r")
  if f then for line in f:lines() do
    if not (line:sub(1,1)=="#" or line:sub(1,5)=="frame" or line=="") then
      local c={}; for tok in line:gmatch("[^,]+") do c[#c+1]=tok end
      if #c>=8 then local fr=tonumber(c[1])
        if fr then INP[fr]={tonumber(c[3]),tonumber(c[4]),tonumber(c[5]),tonumber(c[6]),tonumber(c[7]),tonumber(c[8])} end end
    end
  end f:close() end
end
local ncsv=0; for _ in pairs(INP) do ncsv=ncsv+1 end
print(string.format("awreplay: loaded %d input rows from %s", ncsv, INPATH))

-- override the hero vars from the csv, right after ReadInput writes var[0xFE] (its last write)
local overriding=false
AWREPLAY_OVR = sp:install_write_tap(A_AMASK, A_AMASK+3, "awovr", function(offset,data,mask)
  if overriding then return end
  if offset~=A_AMASK then return end
  -- The 32-bit word also holds var 0xFF (upper half); act only on writes touching var 0xFE.
  if (mask & 0xffff) == 0 then return end
  -- ReadInput runs AFTER FRAME_NO was bumped to V, and the vars it sets render as tick V
  -- (captured at the next FRAME_NO write, tick = V+1-1). The csv row that drives tick V is
  -- frame V+1 (awmonitor logs each FRAME_NO change before that frame's ReadInput has run, so
  -- row F holds the vars of tick F-1 -- the same convention replaycksum keys by frame-1).
  local fr = sp:read_u16(FRAME_NO)
  local r = INP[fr + 1]
  if r then
    overriding=true
    sp:write_u16(A_LR, r[1]&0xffff);  sp:write_u16(A_UD, r[2]&0xffff)
    sp:write_u16(A_JMP, r[3]&0xffff); sp:write_u16(A_PMASK, r[4]&0xffff)
    sp:write_u16(A_ACT, r[5]&0xffff)
    overriding=false
    -- var 0xFE is the write in flight: a write_u16 here would be clobbered when MAME commits the
    -- pending write after the tap returns, so replace the in-flight data instead (low half).
    return (data & ~0xffff) | (r[6] & 0xffff)
  end
end)

-- capture the displayed page per tick (identical to awcksum.lua: tick = FRAME_NO-1)
local OUTBIN=os.getenv("AWCK_BIN") or "build/replay_pages.bin"
local OUTIDX=os.getenv("AWCK_IDX") or "build/replay_pages.idx"
local MAXTICK=tonumber(os.getenv("AWCK_MAX") or "4000")
local binf=io.open(OUTBIN,"wb"); local idxf=io.open(OUTIDX,"w")
local captured=0; local finish=false
-- optional diagnostics: AW_DUMP_FROM..AW_DUMP_TO prints all 256 VM vars at the END of each tick
-- (rustyworld's DUMP_FROM/TO prints them at the START of tick+1 -- the same instant), and
-- AW_TRACE=path dumps the VM instruction trace (frame thread pc op) on exit.
local DFROM=tonumber(os.getenv("AW_DUMP_FROM") or "-1"); local DTO=tonumber(os.getenv("AW_DUMP_TO") or "-1")
local VMV=0x44070000
AWREPLAY_CAP = sp:install_write_tap(FRAME_NO, FRAME_NO+3, "awframe", function(offset,data,mask)
  if finish then return end
  if offset~=FRAME_NO then return end
  local v=data&0xffff; if v==0 then return end
  local tick=v-1
  if tick>=DFROM and tick<=DTO then local parts={}
    for i=0,255 do local x=sp:read_u16(VMV+i*2); if x~=0 then if x>=0x8000 then x=x-0x10000 end; parts[#parts+1]=string.format("%02x=%d",i,x) end end
    print("VARS t="..tick.." "..table.concat(parts," ")) end
  if tick>=MAXTICK and os.getenv("AW_TRACE") then
    local n=sp:read_u32(0x44080078); local tf=io.open(os.getenv("AW_TRACE"),"w")
    for i=0,n-1 do local b=0x44800000+i*8
      tf:write(string.format("%d %d %d %02x\n", sp:read_u16(b), sp:read_u8(b+2), sp:read_u16(b+4), sp:read_u8(b+3))) end
    tf:close() end
  local front=sp:read_u32(CUR_PAGE_2)
  binf:write(sp:read_range(front, front+63999, 8))
  idxf:write(string.format("%d %08X\n", tick, front))
  captured=captured+1
  if tick>=MAXTICK then finish=true; binf:close(); idxf:close()
    print(string.format("awreplay: captured %d frames (last tick %d); exiting", captured, tick)) end
end)

local pressed=false
emu.register_periodic(function()
  local t=M.time:as_double()
  if not pressed and t>11 then SD:set_value(1); pressed=true end
  if pressed and t>11.4 and SD then SD:set_value(0) end
  if finish then M:exit() end
end)
