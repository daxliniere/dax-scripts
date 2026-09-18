-- @description Completely dismantle all folder tracks; delete empty former folder parents
-- @version 1.1
-- @author Dax Liniere with ChatGPT
-- @about
--   Works ONLY on the currently selected tracks.
--   - Removes folder structure markers inside the selection:
--       * folder starts (I_FOLDERDEPTH == 1) -> 0
--       * folder ends (I_FOLDERDEPTH < 0)    -> 0
--     (Leaves any folder markers on unselected tracks untouched.)
--   - Deletes former folder parent tracks (within selection) if they have no media items.

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local proj = 0
local sel_count = reaper.CountSelectedTracks(proj)
if sel_count == 0 then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Dismantle folders in selection; delete empty parents", -1)
  return
end

-- Collect selected tracks with their project indices (needed for bottom-up deletes)
local selected = {}
for i = 0, sel_count - 1 do
  local tr = reaper.GetSelectedTrack(proj, i)
  local idx = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1 -- 0-based
  selected[#selected + 1] = { tr = tr, idx = idx }
end

-- Sort by index ascending
table.sort(selected, function(a, b) return a.idx < b.idx end)

-- Collect former folder parents (within selection) BEFORE changing depths
local former_folder_parents = {}
for _, t in ipairs(selected) do
  local depth = reaper.GetMediaTrackInfo_Value(t.tr, "I_FOLDERDEPTH")
  if depth == 1 then
    former_folder_parents[#former_folder_parents + 1] = { tr = t.tr, idx = t.idx }
  end
end

-- Dismantle folder markers ONLY on selected tracks
for _, t in ipairs(selected) do
  local depth = reaper.GetMediaTrackInfo_Value(t.tr, "I_FOLDERDEPTH")
  if depth ~= 0 then
    reaper.SetMediaTrackInfo_Value(t.tr, "I_FOLDERDEPTH", 0)
  end

  -- Optional: un-compact folder display if present on these tracks
  local compact = reaper.GetMediaTrackInfo_Value(t.tr, "I_FOLDERCOMPACT")
  if compact ~= 0 then
    reaper.SetMediaTrackInfo_Value(t.tr, "I_FOLDERCOMPACT", 0)
  end
end

-- Delete empty former folder parents (selected only), bottom-up
table.sort(former_folder_parents, function(a, b) return a.idx > b.idx end)

for _, t in ipairs(former_folder_parents) do
  if reaper.ValidatePtr(t.tr, "MediaTrack*") then
    if reaper.CountTrackMediaItems(t.tr) == 0 then
      reaper.DeleteTrack(t.tr)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Dismantle folders in selection; delete empty parents", -1)
