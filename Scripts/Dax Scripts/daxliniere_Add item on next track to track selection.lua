-- @description Select N Items On Tracks Below (keep original item selection & track selection)
-- @author adapted for user
-- @version 1.0
-- behaviour: deterministic, does NOT use native action 41140

local function no_undo() reaper.defer(function() end) end
local proj = 0

local cnt_sel = reaper.CountSelectedMediaItems(proj)
if cnt_sel == 0 then no_undo() return end

-- how many tracks down to grab (set to 2 for your custom-action need)
local NUM_TRACKS_DOWN = 1

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- store originally selected items (as pointers) and a lookup table for dedupe
local orig_items = {}
local orig_items_map = {}
for i = 0, cnt_sel-1 do
  local it = reaper.GetSelectedMediaItem(proj, i)
  orig_items[#orig_items+1] = it
  orig_items_map[tostring(it)] = true
end

-- choose anchor = last item in the selection list (commonly the most-recently selected)
local anchor = orig_items[#orig_items]
if not anchor or not reaper.ValidatePtr2(proj, anchor, "MediaItem*") then
  -- fallback to first selected item
  anchor = orig_items[1]
  if not anchor or not reaper.ValidatePtr2(proj, anchor, "MediaItem*") then
    -- nothing valid
    no_undo()
    return
  end
end

-- store original track selection
local track_count = reaper.CountTracks(proj)
local saved_tracks = {}
for i = 0, track_count-1 do
  local tr = reaper.GetTrack(proj, i)
  if reaper.IsTrackSelected(tr) then
    saved_tracks[#saved_tracks+1] = tr
  end
end

-- get anchor's track index
local anchor_tr = reaper.GetMediaItemTrack(anchor)
local anchor_tr_idx = nil
for i = 0, track_count-1 do
  if reaper.GetTrack(proj, i) == anchor_tr then
    anchor_tr_idx = i
    break
  end
end
if not anchor_tr_idx then
  -- weird, abort
  no_undo()
  return
end

-- anchor time window (we'll match overlaps first; if none, use center-distance)
local anchor_start = reaper.GetMediaItemInfo_Value(anchor, "D_POSITION")
local anchor_len = reaper.GetMediaItemInfo_Value(anchor, "D_LENGTH")
local anchor_end = anchor_start + anchor_len
local anchor_center = anchor_start + anchor_len * 0.5

-- collect items to additionally select
local to_select = {}

for offset = 1, NUM_TRACKS_DOWN do
  local t_idx = anchor_tr_idx + offset
  if t_idx >= track_count then break end
  local tr = reaper.GetTrack(proj, t_idx)

  local best_overlap_item = nil
  local best_overlap_amount = 0 -- amount of overlap in seconds
  local best_dist_item = nil
  local best_dist = math.huge

  local tr_item_cnt = reaper.CountTrackMediaItems(tr)
  for j = 0, tr_item_cnt-1 do
    local it = reaper.GetTrackMediaItem(tr, j)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local e = s + l
    -- compute overlap with anchor
    local overlap = math.max(0, math.min(e, anchor_end) - math.max(s, anchor_start))
    if overlap > 0 then
      -- prefer the item with the greatest overlap
      if overlap > best_overlap_amount then
        best_overlap_amount = overlap
        best_overlap_item = it
      end
    else
      -- compute distance between centers
      local center = s + l*0.5
      local d = math.abs(center - anchor_center)
      if d < best_dist then
        best_dist = d
        best_dist_item = it
      end
    end
  end

  local chosen = best_overlap_item or best_dist_item
  if chosen and reaper.ValidatePtr2(proj, chosen, "MediaItem*") then
    local key = tostring(chosen)
    if not orig_items_map[key] and not to_select[key] then
      to_select[key] = chosen
    end
  end
end

-- Now apply selection:
-- keep original selections, just set B_UISEL=1 for found items
for k, it in pairs(to_select) do
  reaper.SetMediaItemInfo_Value(it, "B_UISEL", 1)
end

-- Restore track selection: clear all tracks, then reselect saved ones
for i = 0, track_count-1 do
  local tr = reaper.GetTrack(proj, i)
  reaper.SetTrackSelected(tr, false)
end
for _, tr in ipairs(saved_tracks) do
  if reaper.ValidatePtr2(proj, tr, "MediaTrack*") then
    reaper.SetTrackSelected(tr, true)
  end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Select items on tracks below (keep selection)", -1)
reaper.UpdateArrange()
