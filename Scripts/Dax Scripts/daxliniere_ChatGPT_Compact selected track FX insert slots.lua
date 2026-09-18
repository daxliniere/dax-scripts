-- @description Compact selected track FX insert slots
-- @version 1.0
-- @author Dax Liniere

--[[
Dax_Compact selected track FX insert slots.lua
v1.1

Compacts REAPER 7 FX insert slots on selected tracks.

What it does:
- Gets the track under the mouse
- If the track under the mouse is not selected, selects only that track
- Works on selected tracks
- Reads each FX's current effective mixer slot
- Sorts FX by current visible slot order
- Reassigns slot hints to 0, 1, 2, 3...
- Does not reorder the FX processing chain
]]

local r = reaper
local SCRIPT_NAME = "Compact selected track FX insert slots"
local SLOT_PARAM = "slot_hint"

local function get_track_under_mouse()
    local window, segment, details = r.BR_GetMouseCursorContext()
    local track = r.BR_GetMouseCursorContext_Track()

    return track
end

local function is_track_selected(track)
    if not track then
        return false
    end

    return r.IsTrackSelected(track)
end

local function select_only_track(track)
    r.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    r.SetTrackSelected(track, true)
end

local function prepare_track_selection_from_mouse()
    local track = get_track_under_mouse()

    if not track then
        return true
    end

    if not is_track_selected(track) then
        select_only_track(track)
    end

    return true
end

local function get_selected_tracks()
    local tracks = {}
    local count = r.CountSelectedTracks(0)

    for i = 0, count - 1 do
        tracks[#tracks + 1] = r.GetSelectedTrack(0, i)
    end

    return tracks
end

local function tonumber_or_nil(value)
    if value == nil then
        return nil
    end

    return tonumber(value)
end

local function get_fx_slot(track, fx_index)
    local ok, slot = r.TrackFX_GetNamedConfigParm(track, fx_index, "chain_index_to_slot")
    local slot_number = tonumber_or_nil(slot)

    if ok and slot_number ~= nil then
        return slot_number
    end

    ok, slot = r.TrackFX_GetNamedConfigParm(track, fx_index, SLOT_PARAM)
    slot_number = tonumber_or_nil(slot)

    if ok and slot_number ~= nil and slot_number >= 0 then
        return slot_number
    end

    return fx_index
end

local function collect_fx(track)
    local fx_list = {}
    local fx_count = r.TrackFX_GetCount(track)

    for fx_index = 0, fx_count - 1 do
        fx_list[#fx_list + 1] = {
            index = fx_index,
            slot = get_fx_slot(track, fx_index)
        }
    end

    table.sort(fx_list, function(a, b)
        if a.slot == b.slot then
            return a.index < b.index
        end

        return a.slot < b.slot
    end)

    return fx_list
end

local function compact_fx_slots_on_track(track)
    local fx_list = collect_fx(track)
    local changed = false

    for new_slot = 0, #fx_list - 1 do
        local fx = fx_list[new_slot + 1]
        local ok = r.TrackFX_SetNamedConfigParm(track, fx.index, SLOT_PARAM, tostring(new_slot))

        if ok then
            changed = true
        end
    end

    return changed
end

local function main()
    if not r.APIExists("BR_GetMouseCursorContext") then
        r.MB("This script requires the SWS extension.", SCRIPT_NAME, 0)
        return
    end

    prepare_track_selection_from_mouse()

    local tracks = get_selected_tracks()

    if #tracks == 0 then
        r.MB("No tracks selected.", SCRIPT_NAME, 0)
        return
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local changed_anything = false

    for i = 1, #tracks do
        if compact_fx_slots_on_track(tracks[i]) then
            changed_anything = true
        end
    end

    r.PreventUIRefresh(-1)

    if changed_anything then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end

    r.Undo_EndBlock(SCRIPT_NAME, -1)
end

main()