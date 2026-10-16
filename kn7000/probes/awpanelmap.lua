-- Auto-map every cpanel button to its bit in the firmware switch-shadow region, and
-- check it holds a LEVEL (stays set while held) vs an edge. Reproducibility artifact for
-- choosing a reliable AW D-pad: button -> (shadow offset, bit), + held-stability.
local M=manager.machine
local sp=M.devices[":maincpu"].spaces["program"]
local LO,HI=0x5006BE40,0x5006BEA0
local function snap() local t={} for a=LO,HI-1 do t[a]=sp:read_u8(a) end return t end
local function fields()
  local out={}
  for _,seg in ipairs({"CPR_SEG0","CPR_SEG1","CPR_SEG2","CPR_SEG3","CPR_SEG4","CPR_SEG5","CPR_SEG6","CPR_SEG7","CPR_SEG8","CPR_SEG9",
                       "CPL_SEG0","CPL_SEG1","CPL_SEG2","CPL_SEG3","CPL_SEG4","CPL_SEG5","CPL_SEG6","CPL_SEG7",
                       "CPC_SEG5","CPC_SEG6","CPC_SEG7","CPC_SEG8","CPC_SEG9","CPC_SEG10","CPC_SEG11"}) do
    local p=M.ioport.ports[":cpanel:"..seg]
    if p then for _,f in pairs(p.fields) do out[#out+1]={seg=seg,name=f.name,f=f} end end
  end
  return out
end
local SD=nil
local FL=nil
local tick=0; local pressed=false; local idx=1; local st=0; local base=nil; local held1=nil
emu.register_periodic(function()
  tick=tick+1
  if FL==nil then FL=fields(); for _,e in ipairs(FL) do if e.name:find("SD CARD LOAD") then SD=e.f end end
     io.write(string.format("cpanel fields: %d ; shadow %06x..%06x\n",#FL,LO,HI-1)) end
  if not pressed and tick>120 then SD:set_value(1); pressed=true end
  if pressed and tick>128 and SD then SD:set_value(0) end
  if not pressed then return end
  if tick<160 then return end          -- let game settle
  local e=FL[idx]
  if e==nil then M:exit(); return end
  if st==0 then base=snap(); e.f:set_value(1); st=1; stt=tick; return end
  if st==1 and tick>=stt+8 then held1=snap(); st=2; return end         -- early during hold
  if st==2 and tick>=stt+22 then                                        -- late during hold
    local held2=snap()
    local parts={}
    for a=LO,HI-1 do
      if held1[a]~=base[a] or held2[a]~=base[a] then
        local lvl = (held2[a]==held1[a]) and "LVL" or "edge"
        parts[#parts+1]=string.format("+%02x:%02x->%02x/%02x(%s)",a-LO,base[a],held1[a],held2[a],lvl)
      end
    end
    if #parts>0 then io.write(string.format("%-10s %-28s %s\n",e.seg,e.name,table.concat(parts," "))) end
    e.f:set_value(0); st=3; stt=tick; return
  end
  if st==3 and tick>=stt+6 then idx=idx+1; st=0; return end             -- release settle
end)
