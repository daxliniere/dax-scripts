-- @description Cycle mute of selected tracks
-- @version 1.0
-- @author Dax Liniere

-- Cycle mute of selected tracks
-- Desc: Unmute One Track at a Time in Rotation
-- Concept by Dax Liniere July 2025
-- Coded by ChatGPT

-- Unmute One Track at a Time in REAPER

local selected_tracks = reaper.CountSelectedTracks(0)
if selected_tracks <= 1 then
    reaper.ShowMessageBox("Make a selection of 2 or more tracks first.", "Track Selection Required", 0)
    return
end

local unmuted_indices = {}

-- Gather all unmuted tracks in the selection
for i = 0, selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track and reaper.GetMediaTrackInfo_Value(track, "B_MUTE") == 0 then
        table.insert(unmuted_indices, i)
    end
end

if #unmuted_indices ~= 1 then
    -- Reset: mute all except the first selected track
    for i = 0, selected_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", i == 0 and 0 or 1)
    end
else
    -- Cycle to next track
    local current_index = unmuted_indices[1]
    local next_index = (current_index + 1) % selected_tracks
    for i = 0, selected_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        reaper.SetMediaTrackInfo_Value(track, "B_MUTE", i == next_index and 0 or 1)
    end
end
