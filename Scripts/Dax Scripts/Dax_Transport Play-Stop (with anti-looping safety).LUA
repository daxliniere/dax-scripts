-- @description Transport Play-Stop (with anti-looping safety)
-- @version 1.0
-- @author Dax Liniere

function main() 
  ts_startOut, ts_endOut = reaper.GetSet_LoopTimeRange2( 0, false, false, -1, -1, 1 )
  if reaper.GetPlayStateEx( 0 ) == 0 then -- is stopped
    reaper.Main_OnCommandEx( 1007, 0, 0 ) -- start playing
    if ts_endOut - ts_startOut < 0.5  and  reaper.GetToggleCommandStateEx( 0, 1068 ) then -- is repeat
      if reaper.GetToggleCommandStateEx( 0, 40621 )==1 then reaper.Main_OnCommandEx( 40621, 0, 0 )end  --Options: Toggle loop points linked to time selection
      reaper.GetSet_LoopTimeRange2( 0, 1, 1, ts_startOut,  reaper.GetProjectLength( 0 ), false )
    end
   elseif reaper.GetPlayStateEx( 0 ) == 1 then
      reaper.Main_OnCommand( 40044, 0 ) -- stop
    if reaper.GetToggleCommandStateEx( 0, 40621 )==0 then reaper.Main_OnCommandEx( 40621, 0, 0 )end  --Options: Toggle loop points linked to time selection
  end
end

reaper.defer(main) -- run without undo point