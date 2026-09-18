-- @description PeIF Select items with non-1x playrate
-- @version 1.0
-- @author Dax Liniere

-- Begin undo block
reaper.Undo_BeginBlock()

-- Deselect all items first (optional, remove the following line if you want to add to the current item selection)
reaper.Main_OnCommand(40289, 0) -- Unselect all items

local num_items = reaper.CountMediaItems(0)

for i = 0, num_items - 1 do
    local item = reaper.GetMediaItem(0, i)
    if item then
        local take = reaper.GetActiveTake(item)
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
            if math.abs(playrate - 1.0) > 0.0001 then
                reaper.SetMediaItemSelected(item, true)
            end
        end
    end
end

-- Update UI
reaper.UpdateArrange()
reaper.Undo_EndBlock("Select items with non-1x playrate", -1)