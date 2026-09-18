-- @description Set tracks sends' sending-channels (skip bypassed)
-- @version 1.0
-- @author Dax Liniere

--[[
Script: daxliniere_ChatGPT_Set non-muted sends source channels.lua
Version: 1.1
Purpose:
  Ask for a consecutive stereo source channel pair from 1 to 127,
  then set all non-muted sends on selected tracks to use that source pair.
  If needed, increase the sending track's channel count first.

Example:
  Entering 3 sets sends to source channels 3+4.
]]

local r = reaper

local SCRIPT_NAME = "Set non-muted sends source channels"
local MIN_CHANNEL = 1
local MAX_CHANNEL = 127
local SEND_CATEGORY = 0 -- 0 = normal sends

local function msg(text)
  r.ShowMessageBox(text, SCRIPT_NAME, 0)
end

local function parse_first_channel(input)
  local first_ch = tonumber(input)

  if not first_ch then
    return nil, "Please enter a number from 1 to 127."
  end

  first_ch = math.floor(first_ch)

  if first_ch < MIN_CHANNEL or first_ch > MAX_CHANNEL then
    return nil, "Please enter a number from 1 to 127."
  end

  if first_ch >= MAX_CHANNEL then
    return nil, "Channel 127 cannot be used as the first channel of a stereo pair, because 127+128 is not valid in REAPER."
  end

  return first_ch, nil
end

local function get_send_srcchan_value(first_ch)
  -- REAPER send source channels use zero-based stereo-pair indexing:
  -- 1+2 = 0
  -- 3+4 = 2
  -- 5+6 = 4
  return first_ch - 1
end

local function ensure_track_channel_count(track, required_channel_count)
  local current_channel_count = r.GetMediaTrackInfo_Value(track, "I_NCHAN")

  if current_channel_count < required_channel_count then
    r.SetMediaTrackInfo_Value(track, "I_NCHAN", required_channel_count)
    return true
  end

  return false
end

local function process_track(track, srcchan_value)
  local send_count = r.GetTrackNumSends(track, SEND_CATEGORY)
  local changed_count = 0

  for send_index = 0, send_count - 1 do
    local mute = r.GetTrackSendInfo_Value(track, SEND_CATEGORY, send_index, "B_MUTE")

    if mute == 0 then
      r.SetTrackSendInfo_Value(track, SEND_CATEGORY, send_index, "I_SRCCHAN", srcchan_value)
      changed_count = changed_count + 1
    end
  end

  return changed_count
end

local function main()
  local ok, input = r.GetUserInputs(
    SCRIPT_NAME,
    1,
    "First channel of stereo pair, e.g. 3 for 3+4:",
    ""
  )

  if not ok then
    return
  end

  local first_ch, err = parse_first_channel(input)

  if err then
    msg(err)
    return
  end

  local required_channel_count = first_ch + 1
  local srcchan_value = get_send_srcchan_value(first_ch)
  local selected_track_count = r.CountSelectedTracks(0)

  if selected_track_count == 0 then
    msg("No tracks selected.")
    return
  end

  local total_changed_count = 0
  local tracks_expanded_count = 0

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  for track_index = 0, selected_track_count - 1 do
    local track = r.GetSelectedTrack(0, track_index)

    if ensure_track_channel_count(track, required_channel_count) then
      tracks_expanded_count = tracks_expanded_count + 1
    end

    total_changed_count = total_changed_count + process_track(track, srcchan_value)
  end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock(
    "Set non-muted sends source channels to " .. first_ch .. "+" .. (first_ch + 1),
    -1
  )

  msg(
    "Set " .. total_changed_count .. " non-muted send(s) to source channels " ..
    first_ch .. "+" .. (first_ch + 1) .. ".\n\n" ..
    "Expanded " .. tracks_expanded_count .. " sending track(s) as needed."
  )
end

main()