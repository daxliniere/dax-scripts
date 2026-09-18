-- @description Split at time selection and mute
-- @version 1.0
-- @author Dax Liniere

--[[
  Dax - Split time selection and mute.lua
  v0.2

  Behaviour:
  - Always start from the media item under the mouse cursor.
  - If that item is selected AND more than one item is selected,
    process all selected items.
  - Otherwise, process only the item under the mouse cursor.
  - Split each target item at the time selection boundaries.
  - Mute the portion inside the time selection.
  - Create a 7 ms crossfade at each available boundary.
]]

local r = reaper

local CROSSFADE_LEN = 0.007

local function get_item_end(item)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")

    return pos + len
end

local function move_item_start_earlier(item, amount)
    local old_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local old_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local take_count = r.CountTakes(item)

    r.SetMediaItemInfo_Value(item, "D_POSITION", old_pos - amount)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", old_len + amount)

    for take_index = 0, take_count - 1 do
        local take = r.GetTake(item, take_index)

        if take then
            local old_offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            local playrate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
            local new_offset = old_offset - (amount * playrate)

            r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offset)
        end
    end
end

local function extend_item_end(item, amount)
    local old_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")

    r.SetMediaItemInfo_Value(item, "D_LENGTH", old_len + amount)
end

local function process_item(item, time_start, time_end)
    local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_end = get_item_end(item)

    local overlaps_selection = item_end > time_start and item_start < time_end

    if not overlaps_selection then
        return
    end

    local middle_item = item
    local right_item = nil
    local left_item = nil

    local has_left_boundary = time_start > item_start and time_start < item_end
    local has_right_boundary = time_end > item_start and time_end < item_end

    -- Split the right boundary first so the original item reference
    -- continues to represent everything to the left of that boundary.
    if has_right_boundary then
        right_item = r.SplitMediaItem(item, time_end)
    end

    -- Split the left boundary.
    if has_left_boundary then
        middle_item = r.SplitMediaItem(item, time_start)
        left_item = item
    end

    if not middle_item then
        return
    end

    local middle_len = r.GetMediaItemInfo_Value(middle_item, "D_LENGTH")
    local left_crossfade = 0
    local right_crossfade = 0

    if left_item and right_item then
        left_crossfade = math.min(CROSSFADE_LEN, middle_len * 0.5)
        right_crossfade = math.min(CROSSFADE_LEN, middle_len * 0.5)
    elseif left_item then
        left_crossfade = math.min(CROSSFADE_LEN, middle_len)
    elseif right_item then
        right_crossfade = math.min(CROSSFADE_LEN, middle_len)
    end

    -- Mute the portion covered by the time selection.
    r.SetMediaItemInfo_Value(middle_item, "B_MUTE", 1)

    -- Left boundary:
    -- extend the audible item into the muted section and fade it out.
    if left_item and left_crossfade > 0 then
        extend_item_end(left_item, left_crossfade)

        r.SetMediaItemInfo_Value(left_item, "D_FADEOUTLEN", left_crossfade)
        r.SetMediaItemInfo_Value(left_item, "D_FADEOUTLEN_AUTO", 0)

        r.SetMediaItemInfo_Value(middle_item, "D_FADEINLEN", left_crossfade)
        r.SetMediaItemInfo_Value(middle_item, "D_FADEINLEN_AUTO", 0)
    end

    -- Right boundary:
    -- move the audible right-hand item backwards into the muted section
    -- and fade it in.
    if right_item and right_crossfade > 0 then
        move_item_start_earlier(right_item, right_crossfade)

        r.SetMediaItemInfo_Value(middle_item, "D_FADEOUTLEN", right_crossfade)
        r.SetMediaItemInfo_Value(middle_item, "D_FADEOUTLEN_AUTO", 0)

        r.SetMediaItemInfo_Value(right_item, "D_FADEINLEN", right_crossfade)
        r.SetMediaItemInfo_Value(right_item, "D_FADEINLEN_AUTO", 0)
    end
end

local function main()
    local time_start
    local time_end
    local mouse_x
    local mouse_y
    local item_under_mouse
    local selected_count
    local item_under_mouse_selected
    local target_items = {}

    time_start, time_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)

    if time_end <= time_start then
        return
    end

    mouse_x, mouse_y = r.GetMousePosition()
    item_under_mouse = r.GetItemFromPoint(mouse_x, mouse_y, true)

    if not item_under_mouse then
        return
    end

    selected_count = r.CountSelectedMediaItems(0)
    item_under_mouse_selected =
        r.GetMediaItemInfo_Value(item_under_mouse, "B_UISEL") == 1

    if item_under_mouse_selected and selected_count > 1 then
        for i = 0, selected_count - 1 do
            target_items[#target_items + 1] = r.GetSelectedMediaItem(0, i)
        end
    else
        target_items[1] = item_under_mouse
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    for i = 1, #target_items do
        process_item(target_items[i], time_start, time_end)
    end

	-- Remove selection
	r.Main_OnCommand(40635, 0)

    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.Undo_EndBlock("Split time selection and mute with 7ms crossfades", -1)
end

main()