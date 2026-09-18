-- @description Explode takes across tracks with auto-renaming (multi-track aware)
-- @version 1.0
-- @author Dax Liniere

--[[
  ChatGPT_daxliniere_Explode takes across child tracks with auto-renaming (multi-track aware), mute source item(s)

  • Works on selected items (multi-track aware)
  • Robust with folders/nesting (measures what changed)
  • No SWS required
--]]

local r = reaper

local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function get_track_guid(tr)
  local _, guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return guid
end
local function get_track_name(tr)
  local ok, name = r.GetTrackName(tr, "")
  if not ok then name = "" end
  name = trim(name or "")
  if name == "" then
    local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
    name = ("Track %d"):format(idx)
  end
  return name
end

-- Collect unique source tracks from selected items
local sel_cnt = r.CountSelectedMediaItems(0)
if sel_cnt == 0 then return end

local sources_map, sources_list = {}, {}
for i = 0, sel_cnt-1 do
  local it = r.GetSelectedMediaItem(0, i)
  local tr = r.GetMediaItem_Track(it)
  local g = get_track_guid(tr)
  if not sources_map[g] then
    local entry = { tr = tr, guid = g, name = get_track_name(tr) }
    sources_map[g] = entry
    table.insert(sources_list, entry)
  end
end

-- Snapshot all pre-existing tracks (by GUID)
local before = {}
local track_count_before = r.CountTracks(0)
for i = 0, track_count_before-1 do
  local tr = r.GetTrack(0, i)
  before[get_track_guid(tr)] = true
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- Run the native explode action
r.Main_OnCommand(40224, 0) -- Take: Explode takes of items across tracks

-- Helper: track is new iff its GUID wasn't present before
local function is_new_track(tr)
  return not before[get_track_guid(tr)]
end

-- Process sources in current order (after explode)
table.sort(sources_list, function(a, b)
  local ai = math.floor(r.GetMediaTrackInfo_Value(a.tr, "IP_TRACKNUMBER"))
  local bi = math.floor(r.GetMediaTrackInfo_Value(b.tr, "IP_TRACKNUMBER"))
  return ai < bi
end)

-- For each source, rename the contiguous block of NEW tracks directly below it
for _, src in ipairs(sources_list) do
  local src_idx1 = math.floor(r.GetMediaTrackInfo_Value(src.tr, "IP_TRACKNUMBER")) -- 1-based
  local i0 = src_idx1 -- 0-based index of first track AFTER source
  local n = 0
  while true do
    local tr = r.GetTrack(0, i0)
    if not tr then break end
    if not is_new_track(tr) then break end
    n = n + 1
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", ("%s %d"):format(src.name, n), true)
    i0 = i0 + 1
  end
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Explode takes across tracks + rename created tracks", -1)
