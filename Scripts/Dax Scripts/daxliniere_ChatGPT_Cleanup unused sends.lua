-- @description Cleanup unused sends
-- @version 1.0
-- @author Dax Liniere

--[[
daxliniere_ChatGPT_Cleanup unused sends.lua
v1.5

Removes muted sends and sends set to -inf from selected tracks, then compacts remaining send slots.

What it does:
- Gets the track under the mouse
- If the track under the mouse is not selected, selects only that track
- Works on selected tracks
- Removes sends where B_MUTE is enabled
- Removes sends where D_VOL is at or extremely near silence
- Compacts the remaining send slots to remove gaps
- Only affects normal sends, not receives or hardware outputs
]]

local r = reaper
local SCRIPT_NAME = "Cleanup unused sends"
local SEND_CATEGORY = 0
local SLOT_PARAM = "I_SLOT_HINT"

-- REAPER's bottom fader value may not always report as exact 0.0.
-- This is intentionally tiny so it will not catch ordinary quiet sends.
local MINUS_INF_THRESHOLD = 0.00000005

local function get_track_under_mouse()
    r.BR_GetMouseCursorContext()
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
        return
    end

    if not is_track_selected(track) then
        select_only_track(track)
    end
end

local function get_selected_tracks()
    local tracks = {}
    local count = r.CountSelectedTracks(0)

    for i = 0, count - 1 do
        tracks[#tracks + 1] = r.GetSelectedTrack(0, i)
    end

    return tracks
end

local function get_send_slot(track, send_index)
    local slot = r.GetTrackSendInfo_Value(track, SEND_CATEGORY, send_index, SLOT_PARAM)

    if type(slot) ~= "number" then
        return send_index
    end

    if slot < 0 then
        return send_index
    end

    return slot
end

local function is_send_muted(track, send_index)
    local mute = r.GetTrackSendInfo_Value(track, SEND_CATEGORY, send_index, "B_MUTE")

    return mute == 1
end

local function is_send_minus_inf(track, send_index)
    local volume = r.GetTrackSendInfo_Value(track, SEND_CATEGORY, send_index, "D_VOL")

    if type(volume) ~= "number" then
        return false
    end

    return volume <= MINUS_INF_THRESHOLD
end

local function should_remove_send(track, send_index)
    if is_send_muted(track, send_index) then
        return true
    end

    if is_send_minus_inf(track, send_index) then
        return true
    end

    return false
end

local function collect_sends(track)
    local sends = {}
    local send_count = r.GetTrackNumSends(track, SEND_CATEGORY)

    for send_index = 0, send_count - 1 do
        sends[#sends + 1] = {
            index = send_index,
            slot = get_send_slot(track, send_index)
        }
    end

    table.sort(sends, function(a, b)
        local a_slot = a.slot or a.index
        local b_slot = b.slot or b.index

        if a_slot == b_slot then
            return a.index < b.index
        end

        return a_slot < b_slot
    end)

    return sends
end

local function compact_send_slots_on_track(track)
    local sends = collect_sends(track)
    local changed = false

    for new_slot = 0, #sends - 1 do
        local send = sends[new_slot + 1]
        local ok = r.SetTrackSendInfo_Value(track, SEND_CATEGORY, send.index, SLOT_PARAM, new_slot)

        if ok then
            changed = true
        end
    end

    return changed
end

local function remove_unused_sends_on_track(track)
    local send_count = r.GetTrackNumSends(track, SEND_CATEGORY)
    local removed_count = 0

    for send_index = send_count - 1, 0, -1 do
        if should_remove_send(track, send_index) then
            r.RemoveTrackSend(track, SEND_CATEGORY, send_index)
            removed_count = removed_count + 1
        end
    end

    return removed_count
end

local function process_track(track)
    local removed_count = remove_unused_sends_on_track(track)
    local compacted = compact_send_slots_on_track(track)

    return removed_count, compacted
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

    local total_removed = 0
    local changed_anything = false

    for i = 1, #tracks do
        local removed_count, compacted = process_track(tracks[i])

        total_removed = total_removed + removed_count

        if removed_count > 0 or compacted then
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