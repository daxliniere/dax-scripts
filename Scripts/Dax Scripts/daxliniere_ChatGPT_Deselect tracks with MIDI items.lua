-- @description De-select tracks that contain MIDI items
-- @version 1.0
-- @author Dax Liniere with ChatGPT
-- @about
--   De-selects tracks that contain at least one MIDI item.
--   Default: only affects currently selected tracks (safer).
--   Set SCAN_ONLY_SELECTED_TRACKS = false to scan all tracks.

local SCAN_ONLY_SELECTED_TRACKS = true

local function track_has_midi_item(tr)
  local itemCount = reaper.CountTrackMediaItems(tr)
  for i = 0, itemCount - 1 do
    local item = reaper.GetTrackMediaItem(tr, i)

    -- Check all takes in the item (MIDI could be in a non-active take)
    local takeCount = reaper.CountTakes(item)
    for t = 0, takeCount - 1 do
      local take = reaper.GetTake(item, t)
      if take and reaper.TakeIsMIDI(take) then
        return true
      end
    end
  end
  return false
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Collect target tracks first (so changing selection doesn't break iteration)
local targets = {}

if SCAN_ONLY_SELECTED_TRACKS then
  local selCount = reaper.CountSelectedTracks(0)
  for i = 0, selCount - 1 do
    targets[#targets + 1] = reaper.GetSelectedTrack(0, i)
  end
else
  local trCount = reaper.CountTracks(0)
  for i = 0, trCount - 1 do
    targets[#targets + 1] = reaper.GetTrack(0, i)
  end
end

-- De-select tracks that contain MIDI
for _, tr in ipairs(targets) do
  if track_has_midi_item(tr) then
    reaper.SetTrackSelected(tr, false)
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("De-select tracks that contain MIDI items", -1)
