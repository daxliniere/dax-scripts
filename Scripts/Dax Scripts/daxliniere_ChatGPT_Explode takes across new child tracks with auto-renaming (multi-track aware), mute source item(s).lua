-- @description Explode takes across new child tracks with auto-renaming (multi-track aware), mute source item(s)
-- @version 1.0
-- @author Dax Liniere

--[[
  ChatGPT_daxliniere_Explode takes across child tracks with auto-renaming (multi-track aware), mute source item(s)

  • Works on selected items (multi-track aware)
  • Makes new tracks children of their source track
  • Mutes original selected items
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

-- Collect items and their source tracks
local sel_cnt = r.CountSelectedMediaItems(0)
if sel_cnt == 0 then return end

local sources_map, sources_list = {}, {}
local selected_items = {}
for i = 0, sel_cnt-1 do
  local it = r.GetSelectedMediaItem(0, i)
  selected_items[#selected_items+1] = it
  local tr = r.GetMediaItem_Track(it)
  local g = get_track_guid(tr)
  if not sources_map[g] then
    local entry = {
      tr = tr,
      guid = g,
      name = get_track_name(tr),
      started_folder = false
    }
    sources_map[g] = entry
    table.insert(sources_list, entry)
  end
end

-- Snapshot pre-existing tracks (by GUID)
local before = {}
local track_count_before = r.CountTracks(0)
for i = 0, track_count_before-1 do
  local tr = r.GetTrack(0, i)
  before[get_track_guid(tr)] = true
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- 1) Mute originals (they may get copied/moved; we'll unmute new ones later)
for _, it in ipairs(selected_items) do
  r.SetMediaItemInfo_Value(it, "B_MUTE", 1)
end

-- 2) Explode
r.Main_OnCommand(40224, 0)

local function is_new_track(tr)
  return not before[get_track_guid(tr)]
end

-- Stable processing order (by current index)
table.sort(sources_list, function(a, b)
  local ai = math.floor(r.GetMediaTrackInfo_Value(a.tr, "IP_TRACKNUMBER"))
  local bi = math.floor(r.GetMediaTrackInfo_Value(b.tr, "IP_TRACKNUMBER"))
  return ai < bi
end)

-- 3) For each source: collect its contiguous NEW tracks below, rename+unmute, and fold under source
for _, src in ipairs(sources_list) do
  local src_idx1 = math.floor(r.GetMediaTrackInfo_Value(src.tr, "IP_TRACKNUMBER"))
  local i0 = src_idx1          -- first track *after* source in 0-based
  local new_children = {}

  -- Gather contiguous block of NEW tracks that the explode inserted under this source
  while true do
    local tr = r.GetTrack(0, i0)
    if not tr then break end
    if not is_new_track(tr) then break end
    table.insert(new_children, tr)
    i0 = i0 + 1
  end

  -- Nothing created for this source? continue.
  if #new_children == 0 then goto continue end

  -- Rename children and ensure their items are unmuted
  for i, tr in ipairs(new_children) do
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", ("%s %d"):format(src.name, i), true)
    local item_cnt = r.CountTrackMediaItems(tr)
    for j = 0, item_cnt-1 do
      local it = r.GetTrackMediaItem(tr, j)
      r.SetMediaItemInfo_Value(it, "B_MUTE", 0)
    end
  end

  -- Make them children: if source isn't already a folder start, start one and close after last child
  local folder_flag = math.floor(r.GetMediaTrackInfo_Value(src.tr, "I_FOLDERDEPTH") or 0)
  if folder_flag <= 0 then
    r.SetMediaTrackInfo_Value(src.tr, "I_FOLDERDEPTH", 1)      -- start folder at source
    src.started_folder = true
  end
  if src.started_folder then
    local last_child = new_children[#new_children]
    r.SetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH", -1) -- end folder after last new child
  end

  ::continue::
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("Explode takes + rename + mute originals + nest children", -1)
