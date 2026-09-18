-- @description Split MIDI items at notes (remove overlap)
-- @version 2.6
-- @author Dax Liniere with ChatGPT
-- @about
--   Splits each selected MIDI item into one MIDI item per note.
--   Before splitting, note lengths are sanitised to avoid overlapping notes
--   Same-start notes are treated as chords and are not truncated against each other.
--   v2.1 sets each output take custom color from the note velocity:
--   velocity 1 = green (0,255,0), velocity 127 = red (255,0,0).
--   v2.6 explicitly disables Loop Source on created items in both API state and chunks.

local SCRIPT_NAME = "Split selected MIDI items into exact-length note/chord-group MIDI items"

local CUSTOM_COLOR_USE_FLAG = 16777216
local VELOCITY_MIN = 1
local VELOCITY_MAX = 127
local START_COLOR_R = 0
local START_COLOR_G = 255
local START_COLOR_B = 0
local END_COLOR_R = 255
local END_COLOR_G = 0
local END_COLOR_B = 0

local guid_random_seeded = false

local function seed_guid_random_once()
    local seed = 0

    if guid_random_seeded then
        return
    end

    if reaper.time_precise ~= nil then
        seed = math.floor(reaper.time_precise() * 1000000)
    else
        seed = os.time()
    end

    math.randomseed(seed % 2147483647)
    guid_random_seeded = true
end

local function random_hex_digit()
    return string.format("%X", math.random(0, 15))
end

local function random_hex_string(length)
    local chars = {}

    for i = 1, length do
        chars[i] = random_hex_digit()
    end

    return table.concat(chars)
end

local function make_guid()
    local ok = false
    local guid = nil

    if reaper.genGuid ~= nil then
        ok, guid = pcall(function()
            return reaper.genGuid()
        end)

        if ok and type(guid) == "string" and guid:match("^{[%x%-]+}$") then
            return guid
        end
    end

    seed_guid_random_once()

    return "{" ..
        random_hex_string(8) .. "-" ..
        random_hex_string(4) .. "-" ..
        random_hex_string(4) .. "-" ..
        random_hex_string(4) .. "-" ..
        random_hex_string(12) ..
        "}"
end

local function clamp_number(value, min_value, max_value)
    if value == nil then
        return min_value
    end

    if value < min_value then
        return min_value
    end

    if value > max_value then
        return max_value
    end

    return value
end

local function round_to_int(value)
    return math.floor(value + 0.5)
end

local function velocity_to_rgb(velocity)
    local clamped_velocity = 0
    local position = 0
    local red = 0
    local green = 0
    local blue = 0

    clamped_velocity = clamp_number(velocity or VELOCITY_MIN, VELOCITY_MIN, VELOCITY_MAX)
    position = (clamped_velocity - VELOCITY_MIN) / (VELOCITY_MAX - VELOCITY_MIN)

    red = round_to_int(START_COLOR_R + (END_COLOR_R - START_COLOR_R) * position)
    green = round_to_int(START_COLOR_G + (END_COLOR_G - START_COLOR_G) * position)
    blue = round_to_int(START_COLOR_B + (END_COLOR_B - START_COLOR_B) * position)

    return red, green, blue
end

local function velocity_to_custom_color(velocity)
    local red = 0
    local green = 0
    local blue = 0
    local native_color = 0

    red, green, blue = velocity_to_rgb(velocity)
    native_color = reaper.ColorToNative(red, green, blue)

    return native_color + CUSTOM_COLOR_USE_FLAG
end

local function set_take_color_from_velocity(item, take, velocity)
    local custom_color = 0
    local ok = false

    if item == nil or take == nil then
        return false
    end

    custom_color = velocity_to_custom_color(velocity)

    -- Clear the item custom color so the take custom color is not masked by
    -- item color drawing preferences.
    reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)

    ok = reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", custom_color)

    return ok
end

local function safe_get_active_take(item)
    local ok = false
    local take = nil

    if item == nil then
        return nil
    end

    ok, take = pcall(reaper.GetActiveTake, item)

    if not ok then
        return nil
    end

    return take
end

local function safe_get_item_track(item)
    local ok = false
    local track = nil

    if item == nil then
        return nil
    end

    ok, track = pcall(reaper.GetMediaItem_Track, item)

    if not ok then
        return nil
    end

    return track
end

local function safe_take_is_midi(take)
    local ok = false
    local is_midi = false

    if take == nil then
        return false
    end

    ok, is_midi = pcall(reaper.TakeIsMIDI, take)

    if not ok then
        return false
    end

    return is_midi
end

local function safe_delete_item(item)
    local track = nil

    if item == nil then
        return
    end

    track = safe_get_item_track(item)

    if track ~= nil then
        pcall(reaper.DeleteTrackMediaItem, track, item)
    end
end

local function get_active_midi_take_from_item(item)
    local take = nil

    take = safe_get_active_take(item)

    if not safe_take_is_midi(take) then
        return nil
    end

    return take
end

local function append_unique_source(sources, seen_items, item, take)
    local key = ""
    local track = nil

    if item == nil or take == nil then
        return
    end

    key = tostring(item)

    if seen_items[key] then
        return
    end

    track = safe_get_item_track(item)

    if track == nil then
        return
    end

    sources[#sources + 1] = {
        item = item,
        take = take,
        track = track
    }

    seen_items[key] = true
end

local function collect_source_items()
    local sources = {}
    local seen_items = {}
    local selected_item_count = 0
    local editor = nil
    local editor_take = nil
    local editor_item = nil

    selected_item_count = reaper.CountSelectedMediaItems(0)

    for i = 0, selected_item_count - 1 do
        local item = nil
        local take = nil

        item = reaper.GetSelectedMediaItem(0, i)
        take = get_active_midi_take_from_item(item)

        if take ~= nil then
            append_unique_source(sources, seen_items, item, take)
        end
    end

    -- Fallback for running from the MIDI editor section.
    if #sources == 0 and reaper.MIDIEditor_GetActive ~= nil and reaper.MIDIEditor_GetTake ~= nil then
        editor = reaper.MIDIEditor_GetActive()

        if editor ~= nil then
            editor_take = reaper.MIDIEditor_GetTake(editor)

            if safe_take_is_midi(editor_take) then
                editor_item = reaper.GetMediaItemTake_Item(editor_take)

                if editor_item ~= nil then
                    append_unique_source(sources, seen_items, editor_item, editor_take)
                end
            end
        end
    end

    return sources, selected_item_count
end

local function collect_notes(take)
    local notes = {}
    local retval = false
    local note_count = 0
    local cc_count = 0
    local text_sysex_count = 0

    retval, note_count, cc_count, text_sysex_count = reaper.MIDI_CountEvts(take)

    if note_count == nil then
        note_count = 0
    end

    for note_index = 0, note_count - 1 do
        local ok = false
        local selected = false
        local muted = false
        local start_ppq = 0
        local end_ppq = 0
        local chan = 0
        local pitch = 0
        local vel = 0

        ok, selected, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_index)

        if ok and end_ppq > start_ppq then
            notes[#notes + 1] = {
                index = note_index,
                selected = selected,
                muted = muted,
                start_ppq = start_ppq,
                end_ppq = end_ppq,
                chan = chan,
                pitch = pitch,
                vel = vel
            }
        end
    end

    return notes, note_count
end

local function collect_distinct_sorted_starts(notes)
    local starts = {}
    local seen = {}

    for _, note in ipairs(notes) do
        local key = ""

        key = tostring(note.start_ppq)

        if not seen[key] then
            starts[#starts + 1] = note.start_ppq
            seen[key] = true
        end
    end

    table.sort(starts)

    return starts
end

local function get_next_distinct_start_after(starts, ppq_pos)
    local low = 1
    local high = #starts
    local result = nil

    while low <= high do
        local mid = 0

        mid = math.floor((low + high) / 2)

        if starts[mid] > ppq_pos then
            result = starts[mid]
            high = mid - 1
        else
            low = mid + 1
        end
    end

    return result
end

local function build_sanitised_notes(take, notes)
    local sanitised_notes = {}
    local starts = {}

    starts = collect_distinct_sorted_starts(notes)

    for _, note in ipairs(notes) do
        local next_start = nil
        local sanitised_end_ppq = 0

        next_start = get_next_distinct_start_after(starts, note.start_ppq)
        sanitised_end_ppq = note.end_ppq

        if next_start ~= nil and next_start < sanitised_end_ppq then
            sanitised_end_ppq = next_start
        end

        if sanitised_end_ppq > note.start_ppq then
            sanitised_notes[#sanitised_notes + 1] = {
                index = note.index,
                selected = note.selected,
                muted = note.muted,
                start_ppq = note.start_ppq,
                end_ppq = sanitised_end_ppq,
                start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, note.start_ppq),
                end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sanitised_end_ppq),
                start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, note.start_ppq),
                end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, sanitised_end_ppq),
                chan = note.chan,
                pitch = note.pitch,
                vel = note.vel
            }
        end
    end

    table.sort(sanitised_notes, function(a, b)
        if a.start_ppq == b.start_ppq then
            if a.end_ppq == b.end_ppq then
                if a.pitch == b.pitch then
                    return a.chan < b.chan
                end

                return a.pitch < b.pitch
            end

            return a.end_ppq < b.end_ppq
        end

        return a.start_ppq < b.start_ppq
    end)

    return sanitised_notes
end

local function get_note_group_key(note)
    return tostring(note.start_ppq) .. "|" .. tostring(note.end_ppq)
end

local function sort_notes_inside_group(notes)
    table.sort(notes, function(a, b)
        if a.pitch == b.pitch then
            if a.chan == b.chan then
                return a.vel < b.vel
            end

            return a.chan < b.chan
        end

        return a.pitch < b.pitch
    end)
end

local function build_note_groups(sanitised_notes)
    local note_groups = {}
    local group_by_key = {}

    for _, note in ipairs(sanitised_notes) do
        local key = ""
        local group = nil

        key = get_note_group_key(note)
        group = group_by_key[key]

        if group == nil then
            group = {
                start_ppq = note.start_ppq,
                end_ppq = note.end_ppq,
                start_qn = note.start_qn,
                end_qn = note.end_qn,
                start_time = note.start_time,
                end_time = note.end_time,
                vel = note.vel,
                notes = {}
            }

            note_groups[#note_groups + 1] = group
            group_by_key[key] = group
        end

        if note.vel > group.vel then
            group.vel = note.vel
        end

        group.notes[#group.notes + 1] = note
    end

    for _, group in ipairs(note_groups) do
        sort_notes_inside_group(group.notes)
    end

    table.sort(note_groups, function(a, b)
        if a.start_ppq == b.start_ppq then
            return a.end_ppq < b.end_ppq
        end

        return a.start_ppq < b.start_ppq
    end)

    return note_groups
end

local function get_item_chunk(item)
    local ok = false
    local chunk = ""

    ok, chunk = reaper.GetItemStateChunk(item, "", false)

    if not ok then
        return nil
    end

    return chunk
end

local function replace_chunk_identity(chunk)
    local prepared_chunk = ""

    prepared_chunk = chunk

    -- Fresh item GUID.
    prepared_chunk = prepared_chunk:gsub("(\n%s*IGUID%s+){[%x%-]+}", function(prefix)
        return prefix .. make_guid()
    end)

    -- Fresh take/source GUIDs. This intentionally covers every standalone GUID line.
    prepared_chunk = prepared_chunk:gsub("(\n%s*GUID%s+){[%x%-]+}", function(prefix)
        return prefix .. make_guid()
    end)

    return prepared_chunk
end

local function prepare_independent_clone_chunk(chunk)
    local prepared_chunk = ""

    prepared_chunk = chunk

    -- Do not let every clone inherit selected state from the original.
    prepared_chunk = prepared_chunk:gsub("\nSEL%s+1", "\nSEL 0")

    -- Do not let cloned items inherit Loop Source from the original item.
    prepared_chunk = prepared_chunk:gsub("(\n%s*LOOP%s+)%S+", "%1 0")

    -- Critical for pooled MIDI items:
    -- strip pooled MIDI event source references so each clone has its own event data.
    prepared_chunk = prepared_chunk:gsub("\n%s*POOLEDEVTS[^\r\n]*", "")
    prepared_chunk = prepared_chunk:gsub("\r%s*POOLEDEVTS[^\r\n]*", "")

    -- Do not inherit source-offset or take-marker state from the original item.
    -- Each created item should contain a self-contained MIDI source beginning at PPQ 0.
    prepared_chunk = prepared_chunk:gsub("(\n%s*SOFFS)[^\r\n]*", "%1 0 0")
    prepared_chunk = prepared_chunk:gsub("\n%s*TKM[^\r\n]*", "")
    prepared_chunk = prepared_chunk:gsub("\r%s*TKM[^\r\n]*", "")

    -- Prevent cloned chunks from carrying source item fades forward.
    -- The API fade values are also explicitly zeroed after item creation.
    prepared_chunk = prepared_chunk:gsub("(\n%s*FADEIN)[^\r\n]*", "%1 1 0 0 1 0 0 0 1 0 0 1 0 0")
    prepared_chunk = prepared_chunk:gsub("(\n%s*FADEOUT)[^\r\n]*", "%1 1 0 0 1 0 0 0 1 0 0 1 0 0")

    prepared_chunk = replace_chunk_identity(prepared_chunk)

    return prepared_chunk
end

local function clone_item_from_chunk(track, chunk)
    local item = nil
    local take = nil
    local ok = false

    item = reaper.AddMediaItemToTrack(track)

    if item == nil then
        return nil, nil, "AddMediaItemToTrack returned nil"
    end

    ok = reaper.SetItemStateChunk(item, chunk, false)

    if not ok then
        safe_delete_item(item)
        return nil, nil, "SetItemStateChunk failed while cloning the source MIDI item"
    end

    take = safe_get_active_take(item)

    if take == nil then
        safe_delete_item(item)
        return nil, nil, "Cloned item did not have an active take"
    end

    if not safe_take_is_midi(take) then
        safe_delete_item(item)
        return nil, nil, "Cloned item active take was not MIDI"
    end

    return item, take, ""
end

local function normalise_created_item_chunk(item)
    local ok = false
    local chunk = ""
    local normalised_chunk = ""

    if item == nil then
        return false
    end

    ok, chunk = reaper.GetItemStateChunk(item, "", false)

    if not ok then
        return false
    end

    normalised_chunk = chunk

    -- Make the new MIDI source local to the item start. This is the main fix
    -- for the dirty-state symptom where source events remained anchored at the
    -- original project PPQ position, for example SOFFS 156... and E 354952....
    normalised_chunk = normalised_chunk:gsub("(\n%s*SOFFS)[^\r\n]*", "%1 0 0")

    -- Keep item Loop Source disabled in the saved item state.
    normalised_chunk = normalised_chunk:gsub("(\n%s*LOOP%s+)%S+", "%1 0")

    -- The cloned source item may carry take markers from the original source.
    -- They are not part of the new note/chord item and can keep the source
    -- looking like a trimmed window onto old data.
    normalised_chunk = normalised_chunk:gsub("\n%s*TKM[^\r\n]*", "")
    normalised_chunk = normalised_chunk:gsub("\r%s*TKM[^\r\n]*", "")

    -- Keep fades explicitly neutral in the saved item state too.
    normalised_chunk = normalised_chunk:gsub("(\n%s*FADEIN)[^\r\n]*", "%1 0 0 0 0 0 0 0 1 0 0 1 0 0")
    normalised_chunk = normalised_chunk:gsub("(\n%s*FADEOUT)[^\r\n]*", "%1 0 0 0 0 0 0 0 1 0 0 1 0 0")

    if normalised_chunk == chunk then
        return true
    end

    return reaper.SetItemStateChunk(item, normalised_chunk, false)
end

local function clear_all_midi_events(take)
    local ok = false
    local note_count = 0
    local cc_count = 0
    local text_sysex_count = 0

    ok, note_count, cc_count, text_sysex_count = reaper.MIDI_CountEvts(take)

    if not ok then
        return false
    end

    if note_count == nil then
        note_count = 0
    end

    if cc_count == nil then
        cc_count = 0
    end

    if text_sysex_count == nil then
        text_sysex_count = 0
    end

    reaper.MIDI_DisableSort(take)

    for i = note_count - 1, 0, -1 do
        reaper.MIDI_DeleteNote(take, i)
    end

    for i = cc_count - 1, 0, -1 do
        reaper.MIDI_DeleteCC(take, i)
    end

    for i = text_sysex_count - 1, 0, -1 do
        reaper.MIDI_DeleteTextSysexEvt(take, i)
    end

    reaper.MIDI_Sort(take)

    return true
end

local function copy_basic_item_properties(source_item, target_item)
    local custom_color = 0
    local group_id = 0
    local item_volume = 1
    local item_mute = 0
    local beat_attach_mode = 0
    local auto_stretch = 0

    custom_color = reaper.GetMediaItemInfo_Value(source_item, "I_CUSTOMCOLOR")
    group_id = reaper.GetMediaItemInfo_Value(source_item, "I_GROUPID")
    item_volume = reaper.GetMediaItemInfo_Value(source_item, "D_VOL")
    item_mute = reaper.GetMediaItemInfo_Value(source_item, "B_MUTE")
    beat_attach_mode = reaper.GetMediaItemInfo_Value(source_item, "C_BEATATTACHMODE")
    auto_stretch = reaper.GetMediaItemInfo_Value(source_item, "C_AUTOSTRETCH")

    reaper.SetMediaItemInfo_Value(target_item, "I_CUSTOMCOLOR", custom_color)
    reaper.SetMediaItemInfo_Value(target_item, "I_GROUPID", group_id)
    reaper.SetMediaItemInfo_Value(target_item, "D_VOL", item_volume)
    reaper.SetMediaItemInfo_Value(target_item, "B_MUTE", item_mute)
    reaper.SetMediaItemInfo_Value(target_item, "C_BEATATTACHMODE", beat_attach_mode)
    reaper.SetMediaItemInfo_Value(target_item, "C_AUTOSTRETCH", auto_stretch)
    reaper.SetMediaItemInfo_Value(target_item, "B_LOOPSRC", 0)
end

local function clear_item_fades(item)
    if item == nil then
        return
    end

    -- Explicit fades.
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)

    -- Automatic fades from preferences or previous item state.
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", 0)

    -- Reset shapes and curves too, so the item is unambiguously fade-free.
    reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
    reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEINDIR", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", 0)
end

local function count_midi_events(take)
    local ok = false
    local note_count = 0
    local cc_count = 0
    local text_sysex_count = 0

    ok, note_count, cc_count, text_sysex_count = reaper.MIDI_CountEvts(take)

    if not ok then
        return false, 0, 0, 0
    end

    return true, note_count or 0, cc_count or 0, text_sysex_count or 0
end

local function make_note_signature(chan, pitch, vel, muted)
    return tostring(chan) .. "|" .. tostring(pitch) .. "|" .. tostring(vel) .. "|" .. tostring(muted)
end

local function validate_note_group_take(take, expected_group)
    local ok = false
    local note_count = 0
    local cc_count = 0
    local text_sysex_count = 0
    local expected_counts = {}
    local actual_counts = {}

    ok, note_count, cc_count, text_sysex_count = count_midi_events(take)

    if not ok then
        return false
    end

    if expected_group == nil or expected_group.notes == nil then
        return false
    end

    if note_count ~= #expected_group.notes or cc_count ~= 0 or text_sysex_count ~= 0 then
        return false
    end

    for _, expected_note in ipairs(expected_group.notes) do
        local signature = ""

        signature = make_note_signature(expected_note.chan, expected_note.pitch, expected_note.vel, expected_note.muted)
        expected_counts[signature] = (expected_counts[signature] or 0) + 1
    end

    for note_index = 0, note_count - 1 do
        local note_ok = false
        local selected = false
        local muted = false
        local start_ppq = 0
        local end_ppq = 0
        local chan = 0
        local pitch = 0
        local vel = 0
        local signature = ""

        note_ok, selected, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_index)

        if not note_ok or end_ppq <= start_ppq then
            return false
        end

        signature = make_note_signature(chan, pitch, vel, muted)
        actual_counts[signature] = (actual_counts[signature] or 0) + 1
    end

    for signature, expected_count in pairs(expected_counts) do
        if actual_counts[signature] ~= expected_count then
            return false
        end
    end

    return true
end

local function copy_basic_take_properties(source_take, target_take)
    local ok = false
    local take_name = ""
    local take_volume = 1
    local take_pan = 0

    ok, take_name = reaper.GetSetMediaItemTakeInfo_String(source_take, "P_NAME", "", false)

    if ok and take_name ~= "" then
        reaper.GetSetMediaItemTakeInfo_String(target_take, "P_NAME", take_name, true)
    end

    take_volume = reaper.GetMediaItemTakeInfo_Value(source_take, "D_VOL")
    take_pan = reaper.GetMediaItemTakeInfo_Value(source_take, "D_PAN")

    reaper.SetMediaItemTakeInfo_Value(target_take, "D_VOL", take_volume)
    reaper.SetMediaItemTakeInfo_Value(target_take, "D_PAN", take_pan)
    reaper.SetMediaItemTakeInfo_Value(target_take, "D_PLAYRATE", 1)
    reaper.SetMediaItemTakeInfo_Value(target_take, "D_STARTOFFS", 0)
end

local function set_item_to_note_extents(item, note)
    local length = 0
    local take = nil

    length = note.end_time - note.start_time

    if length <= 0 then
        return false
    end

    -- Do not use MIDI_SetItemExtents here. It can preserve the source as a
    -- window onto the original absolute project PPQ position, leaving SOFFS
    -- non-zero and the first event at a huge delta. We want a self-contained
    -- MIDI item whose source starts at PPQ 0.
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", note.start_time)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)

    take = safe_get_active_take(item)

    if take ~= nil then
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1)
    end

    return true
end

local function get_note_ppq_range_for_clone(take, note_group)
    local start_ppq = 0
    local end_ppq = 0

    -- The created item is normalised so its MIDI source begins at the item
    -- start. Therefore the note/chord group should be written at PPQ 0, not
    -- at the original project-QN-derived PPQ position.
    start_ppq = 0
    end_ppq = note_group.end_ppq - note_group.start_ppq

    return start_ppq, end_ppq
end

local function insert_note_group(take, note_group)
    local start_ppq = 0
    local end_ppq = 0

    start_ppq, end_ppq = get_note_ppq_range_for_clone(take, note_group)

    if end_ppq <= start_ppq then
        return false
    end

    reaper.MIDI_DisableSort(take)

    for _, note in ipairs(note_group.notes) do
        local ok = false

        ok = reaper.MIDI_InsertNote(
            take,
            note.selected,
            note.muted,
            start_ppq,
            end_ppq,
            note.chan,
            note.pitch,
            note.vel,
            true
        )

        if not ok then
            reaper.MIDI_Sort(take)
            return false
        end
    end

    reaper.MIDI_Sort(take)

    return true
end

local function create_note_group_item(work_item, note_group)
    local new_item = nil
    local new_take = nil
    local failure_reason = ""
    local ok = false

    new_item, new_take, failure_reason = clone_item_from_chunk(work_item.track, prepare_independent_clone_chunk(work_item.original_chunk))

    if new_item == nil or new_take == nil then
        return nil, failure_reason
    end

    copy_basic_item_properties(work_item.item, new_item)
    copy_basic_take_properties(work_item.take, new_take)

    ok = set_item_to_note_extents(new_item, note_group)
    clear_item_fades(new_item)

    if not ok then
        safe_delete_item(new_item)
        return nil, "Could not set cloned item to note-group extents"
    end

    new_take = safe_get_active_take(new_item)

    if not safe_take_is_midi(new_take) then
        safe_delete_item(new_item)
        return nil, "Cloned item stopped reporting as MIDI after trimming"
    end

    ok = clear_all_midi_events(new_take)

    if not ok then
        safe_delete_item(new_item)
        return nil, "Could not clear cloned MIDI events"
    end

    ok = insert_note_group(new_take, note_group)

    if not ok then
        safe_delete_item(new_item)
        return nil, "Could not insert note group into cloned MIDI item"
    end

    ok = normalise_created_item_chunk(new_item)

    if not ok then
        safe_delete_item(new_item)
        return nil, "Could not normalise cloned MIDI item chunk"
    end

    new_take = safe_get_active_take(new_item)

    if not safe_take_is_midi(new_take) then
        safe_delete_item(new_item)
        return nil, "Cloned item stopped reporting as MIDI after normalising"
    end

    if not validate_note_group_take(new_take, note_group) then
        safe_delete_item(new_item)
        return nil, "Created MIDI take did not validate as a clean note group"
    end

    set_item_to_note_extents(new_item, note_group)
    clear_item_fades(new_item)

    -- A chord group can only have one take color. Use the highest velocity in
    -- the group so the strongest note determines the item colour.
    ok = set_take_color_from_velocity(new_item, new_take, note_group.vel)

    if not ok then
        safe_delete_item(new_item)
        return nil, "Could not set take color from note-group velocity"
    end

    clear_item_fades(new_item)
    reaper.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
    normalise_created_item_chunk(new_item)
    reaper.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
    reaper.UpdateItemInProject(new_item)

    return new_item, ""
end

local function get_item_position(item)
    local ok = false
    local position = 0

    if item == nil then
        return 0
    end

    ok, position = pcall(reaper.GetMediaItemInfo_Value, item, "D_POSITION")

    if not ok then
        return 0
    end

    return position
end

local function get_track_id(track)
    local ok = false
    local track_id = 0

    if track == nil then
        return 0
    end

    if reaper.CSurf_TrackToID == nil then
        return 0
    end

    ok, track_id = pcall(reaper.CSurf_TrackToID, track, false)

    if not ok or track_id == nil then
        return 0
    end

    return track_id
end

local function sort_items_by_track_and_position(items)
    table.sort(items, function(a, b)
        local track_a = nil
        local track_b = nil
        local track_id_a = 0
        local track_id_b = 0

        track_a = safe_get_item_track(a)
        track_b = safe_get_item_track(b)
        track_id_a = get_track_id(track_a)
        track_id_b = get_track_id(track_b)

        if track_id_a == track_id_b then
            return get_item_position(a) < get_item_position(b)
        end

        return track_id_a < track_id_b
    end)
end

local function sort_work_items_for_creation(work_items)
    table.sort(work_items, function(a, b)
        if a.track_id == b.track_id then
            return a.item_position > b.item_position
        end

        return a.track_id < b.track_id
    end)
end

local function create_items_for_work_item(work_item)
    local created_items = {}

    -- AddMediaItemToTrack plus SetItemStateChunk can leave REAPER's internal
    -- item list in reverse insertion order until a manual edit forces a rebuild.
    -- Creating groups from right to left leaves the final track item list in
    -- chronological order.
    for group_index = #work_item.note_groups, 1, -1 do
        local note_group = nil
        local new_item = nil
        local failure_reason = ""

        note_group = work_item.note_groups[group_index]
        new_item, failure_reason = create_note_group_item(work_item, note_group)

        if new_item == nil then
            for _, created_item in ipairs(created_items) do
                safe_delete_item(created_item)
            end

            return {}, false, failure_reason
        end

        created_items[#created_items + 1] = new_item
    end

    sort_items_by_track_and_position(created_items)

    return created_items, true, ""
end

local function build_work_items()
    local work_items = {}
    local sources = {}
    local selected_item_count = 0
    local total_raw_note_count = 0
    local total_sanitised_note_count = 0

    sources, selected_item_count = collect_source_items()

    for _, source in ipairs(sources) do
        local raw_notes = {}
        local raw_note_count = 0
        local sanitised_notes = {}
        local note_groups = {}
        local original_chunk = nil

        raw_notes, raw_note_count = collect_notes(source.take)
        sanitised_notes = build_sanitised_notes(source.take, raw_notes)
        note_groups = build_note_groups(sanitised_notes)
        original_chunk = get_item_chunk(source.item)

        total_raw_note_count = total_raw_note_count + raw_note_count
        total_sanitised_note_count = total_sanitised_note_count + #sanitised_notes

        if #note_groups > 0 and original_chunk ~= nil then
            work_items[#work_items + 1] = {
                item = source.item,
                take = source.take,
                track = source.track,
                track_id = get_track_id(source.track),
                item_position = get_item_position(source.item),
                original_chunk = original_chunk,
                note_groups = note_groups
            }
        end
    end

    sort_work_items_for_creation(work_items)

    return work_items, selected_item_count, #sources, total_raw_note_count, total_sanitised_note_count
end

local function force_project_item_refresh(items)
    for _, item in ipairs(items) do
        if item ~= nil then
            reaper.UpdateItemInProject(item)
        end
    end

    reaper.MarkProjectDirty(0)

    if reaper.TrackList_AdjustWindows ~= nil then
        reaper.TrackList_AdjustWindows(false)
    end

    reaper.UpdateTimeline()
    reaper.UpdateArrange()
end

local function select_only_items(items)
    reaper.SelectAllMediaItems(0, false)

    sort_items_by_track_and_position(items)

    for _, item in ipairs(items) do
        if item ~= nil then
            reaper.SetMediaItemSelected(item, true)
        end
    end
end

local function show_no_notes_message(selected_item_count, midi_item_count, raw_note_count)
    local message = ""

    message = message .. "No MIDI notes were found to split.\n\n"
    message = message .. "Arrange selected items: " .. tostring(selected_item_count) .. "\n"
    message = message .. "MIDI items/takes found: " .. tostring(midi_item_count) .. "\n"
    message = message .. "Raw MIDI notes found: " .. tostring(raw_note_count)

    reaper.ShowMessageBox(message, SCRIPT_NAME, 0)
end

local function show_failed_message(failed_item_count, last_failure_reason)
    local message = ""

    message = message .. tostring(failed_item_count) .. " MIDI item(s) could not be split and were left unchanged."

    if last_failure_reason ~= nil and last_failure_reason ~= "" then
        message = message .. "\n\nLast failure reason:\n" .. last_failure_reason
    end

    reaper.ShowMessageBox(message, SCRIPT_NAME, 0)
end

local function process_work_item(work_item)
    local created_items = {}
    local ok = false
    local failure_reason = ""

    if work_item.original_chunk == nil then
        return {}, false, "Could not read original item state chunk"
    end

    created_items, ok, failure_reason = create_items_for_work_item(work_item)

    if not ok then
        return {}, false, failure_reason
    end

    return created_items, true, ""
end

local function main()
    local work_items = {}
    local selected_item_count = 0
    local midi_item_count = 0
    local raw_note_count = 0
    local sanitised_note_count = 0
    local all_new_items = {}
    local originals_to_delete = {}
    local failed_item_count = 0
    local last_failure_reason = ""

    work_items, selected_item_count, midi_item_count, raw_note_count, sanitised_note_count = build_work_items()

    if sanitised_note_count == 0 then
        show_no_notes_message(selected_item_count, midi_item_count, raw_note_count)
        return
    end

    for _, work_item in ipairs(work_items) do
        local new_items = {}
        local ok = false
        local failure_reason = ""

        new_items, ok, failure_reason = process_work_item(work_item)

        if ok then
            for _, item in ipairs(new_items) do
                all_new_items[#all_new_items + 1] = item
            end

            originals_to_delete[#originals_to_delete + 1] = work_item.item
        else
            failed_item_count = failed_item_count + 1
            last_failure_reason = failure_reason
        end
    end

    if #all_new_items > 0 then
        for _, original_item in ipairs(originals_to_delete) do
            safe_delete_item(original_item)
        end

        sort_items_by_track_and_position(all_new_items)
        force_project_item_refresh(all_new_items)
        select_only_items(all_new_items)
    end

    if failed_item_count > 0 then
        show_failed_message(failed_item_count, last_failure_reason)
    end
end

local function run()
    local ok = false
    local err = nil

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    ok, err = xpcall(main, debug.traceback)

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    if ok then
        reaper.Undo_EndBlock(SCRIPT_NAME, -1)
    else
        reaper.Undo_EndBlock(SCRIPT_NAME .. " - failed", -1)
        reaper.ShowConsoleMsg(err .. "\n")
    end
end

run()
