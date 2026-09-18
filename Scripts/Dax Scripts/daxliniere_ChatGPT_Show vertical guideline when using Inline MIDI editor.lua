-- @description Show vertical guideline when using Inline MIDI editor
-- @version 1.0
-- @author Dax Liniere

--[[
  Inline MIDI drag guide line via edit cursor
  v0.4
  by Dax Liniere / ChatGPT

  Purpose:
    While dragging a selected MIDI note in the inline MIDI editor, move REAPER's
    edit cursor to the inferred start position of the dragged note.

  Difference from v0.3:
    v0.3 could get out of sync if the mouse moved quickly and temporarily left
    the inline MIDI note-row context.

    v0.4 only requires valid inline MIDI context on mouse-down. Once dragging
    is armed, it keeps updating the guide from the mouse project position even
    if the mouse briefly leaves the note row.

    v0.4 also ignores pitch entirely. For a vertical guide line, only time
    matters.

  Requires:
    - SWS extension
    - js_ReaScriptAPI

  Notes:
    This does not draw anything itself.
    It borrows REAPER's native edit cursor drawing.

    Start this script once to enable it.
    Run it again to disable it.
]]

-- USER SETTINGS -------------------------------------------------------------

local SCRIPT_NAME = "Inline MIDI drag guide line via edit cursor"
local EXT_SECTION = "Dax_InlineMIDIDragGuide"
local EXT_KEY_ENABLED = "enabled"

local RESTORE_EDIT_CURSOR_ON_RELEASE = true
local REQUIRE_SELECTED_NOTE_UNDER_MOUSE = true

-- How much tolerance to allow around the note body, in PPQ ticks.
-- 0 means the mouse-down PPQ must be between note start and end.
local NOTE_HIT_TEST_TOLERANCE_PPQ = 0

-- If several selected notes match the mouse-down location, this chooses the
-- nearest note start to the mouse-down PPQ.
local PICK_NEAREST_MATCHING_NOTE = true

-- Clamp the guide to the project start.
local CLAMP_GUIDE_TO_PROJECT_START = true

-- API LOCALIZATION ----------------------------------------------------------

local APIExists = reaper.APIExists
local BR_GetMouseCursorContext = reaper.BR_GetMouseCursorContext
local BR_GetMouseCursorContext_MIDI = reaper.BR_GetMouseCursorContext_MIDI
local BR_GetMouseCursorContext_Position = reaper.BR_GetMouseCursorContext_Position
local BR_GetMouseCursorContext_Take = reaper.BR_GetMouseCursorContext_Take
local DeleteExtState = reaper.DeleteExtState
local GetCursorPosition = reaper.GetCursorPosition
local GetExtState = reaper.GetExtState
local JS_Mouse_GetState = reaper.JS_Mouse_GetState
local MIDI_CountEvts = reaper.MIDI_CountEvts
local MIDI_GetNote = reaper.MIDI_GetNote
local MIDI_GetPPQPosFromProjTime = reaper.MIDI_GetPPQPosFromProjTime
local MIDI_GetProjTimeFromPPQPos = reaper.MIDI_GetProjTimeFromPPQPos
local SetEditCurPos = reaper.SetEditCurPos
local SetExtState = reaper.SetExtState
local ShowMessageBox = reaper.ShowMessageBox
local defer = reaper.defer
local get_action_context = reaper.get_action_context
local SetToggleCommandState = reaper.SetToggleCommandState
local RefreshToolbar2 = reaper.RefreshToolbar2

-- STATE ---------------------------------------------------------------------

local is_dragging = false
local stored_edit_cursor_pos = nil
local locked_take = nil
local locked_grab_offset_project_time = nil
local previous_left_mouse_down = false
local last_valid_mouse_project_time = nil

-- FUNCTIONS -----------------------------------------------------------------

local function msg_box(text)
  ShowMessageBox(text, SCRIPT_NAME, 0)
end

local function dependency_check()
  if not APIExists("BR_GetMouseCursorContext") then
    msg_box("Missing dependency: SWS extension.")
    return false
  end

  if not APIExists("BR_GetMouseCursorContext_MIDI") then
    msg_box("Missing dependency: SWS extension with BR_GetMouseCursorContext_MIDI.")
    return false
  end

  if not APIExists("BR_GetMouseCursorContext_Position") then
    msg_box("Missing dependency: SWS extension with BR_GetMouseCursorContext_Position.")
    return false
  end

  if not APIExists("BR_GetMouseCursorContext_Take") then
    msg_box("Missing dependency: SWS extension with BR_GetMouseCursorContext_Take.")
    return false
  end

  if not APIExists("JS_Mouse_GetState") then
    msg_box("Missing dependency: js_ReaScriptAPI.")
    return false
  end

  return true
end

local function get_command_info()
  local is_new_value, filename, section_id, command_id, mode, resolution, val = get_action_context()
  return section_id, command_id
end

local function set_toolbar_state(state)
  local section_id, command_id = get_command_info()

  if command_id and command_id ~= 0 then
    SetToggleCommandState(section_id, command_id, state and 1 or 0)
    RefreshToolbar2(section_id, command_id)
  end
end

local function is_script_enabled()
  return GetExtState(EXT_SECTION, EXT_KEY_ENABLED) == "1"
end

local function set_script_enabled(state)
  if state then
    SetExtState(EXT_SECTION, EXT_KEY_ENABLED, "1", false)
  else
    DeleteExtState(EXT_SECTION, EXT_KEY_ENABLED, false)
  end

  set_toolbar_state(state)
end

local function left_mouse_is_down()
  local mouse_state = JS_Mouse_GetState(1)
  return mouse_state & 1 == 1
end

local function left_mouse_was_just_pressed(left_down)
  return left_down and not previous_left_mouse_down
end

local function left_mouse_was_just_released(left_down)
  return (not left_down) and previous_left_mouse_down
end

local function update_mouse_context()
  -- This call refreshes SWS mouse-context information.
  BR_GetMouseCursorContext()
end

local function get_mouse_project_time_loose()
  local mouse_project_time

  update_mouse_context()
  mouse_project_time = BR_GetMouseCursorContext_Position()

  if mouse_project_time then
    last_valid_mouse_project_time = mouse_project_time
    return mouse_project_time
  end

  return last_valid_mouse_project_time
end

local function get_inline_midi_mouse_down_context()
  local midi_editor, inline_editor, note_row, cc_lane, cc_lane_val, cc_lane_id
  local take
  local mouse_project_time

  update_mouse_context()

  midi_editor, inline_editor, note_row, cc_lane, cc_lane_val, cc_lane_id = BR_GetMouseCursorContext_MIDI()
  take = BR_GetMouseCursorContext_Take()
  mouse_project_time = BR_GetMouseCursorContext_Position()

  if not inline_editor then
    return false, nil, nil
  end

  if not take then
    return false, nil, nil
  end

  if not mouse_project_time then
    return false, nil, nil
  end

  last_valid_mouse_project_time = mouse_project_time

  return true, take, mouse_project_time
end

local function get_matching_selected_note_start_project_time(take, mouse_project_time)
  local note_count
  local mouse_ppq
  local best_start_ppq = nil
  local best_distance = nil
  local i

  if not take then
    return nil
  end

  if not mouse_project_time then
    return nil
  end

  mouse_ppq = MIDI_GetPPQPosFromProjTime(take, mouse_project_time)

  if not mouse_ppq then
    return nil
  end

  _, note_count = MIDI_CountEvts(take)

  for i = 0, note_count - 1 do
    local ok, selected, muted, start_ppq, end_ppq, chan, pitch, vel = MIDI_GetNote(take, i)

    if ok and selected then
      local hit_start_ppq = start_ppq - NOTE_HIT_TEST_TOLERANCE_PPQ
      local hit_end_ppq = end_ppq + NOTE_HIT_TEST_TOLERANCE_PPQ

      if mouse_ppq >= hit_start_ppq and mouse_ppq <= hit_end_ppq then
        if not PICK_NEAREST_MATCHING_NOTE then
          return MIDI_GetProjTimeFromPPQPos(take, start_ppq)
        end

        local distance = math.abs(mouse_ppq - start_ppq)

        if not best_distance or distance < best_distance then
          best_distance = distance
          best_start_ppq = start_ppq
        end
      end
    end
  end

  if not best_start_ppq then
    return nil
  end

  return MIDI_GetProjTimeFromPPQPos(take, best_start_ppq)
end

local function begin_drag_if_possible()
  local context_ok
  local take
  local mouse_project_time
  local note_start_project_time

  if is_dragging then
    return true
  end

  context_ok, take, mouse_project_time = get_inline_midi_mouse_down_context()

  if not context_ok then
    return false
  end

  note_start_project_time = get_matching_selected_note_start_project_time(take, mouse_project_time)

  if REQUIRE_SELECTED_NOTE_UNDER_MOUSE and not note_start_project_time then
    return false
  end

  is_dragging = true
  locked_take = take

  if RESTORE_EDIT_CURSOR_ON_RELEASE then
    stored_edit_cursor_pos = GetCursorPosition()
  end

  if note_start_project_time then
    locked_grab_offset_project_time = mouse_project_time - note_start_project_time
  else
    locked_grab_offset_project_time = 0
  end

  return true
end

local function end_drag_if_needed()
  if not is_dragging then
    return
  end

  is_dragging = false
  locked_take = nil
  locked_grab_offset_project_time = nil
  last_valid_mouse_project_time = nil

  if RESTORE_EDIT_CURSOR_ON_RELEASE and stored_edit_cursor_pos then
    SetEditCurPos(stored_edit_cursor_pos, false, false)
  end

  stored_edit_cursor_pos = nil
end

local function update_edit_cursor_to_inferred_note_start()
  local mouse_project_time
  local guide_project_time

  if not is_dragging then
    return
  end

  if not locked_grab_offset_project_time then
    return
  end

  mouse_project_time = get_mouse_project_time_loose()

  if not mouse_project_time then
    return
  end

  guide_project_time = mouse_project_time - locked_grab_offset_project_time

  if CLAMP_GUIDE_TO_PROJECT_START and guide_project_time < 0 then
    guide_project_time = 0
  end

  SetEditCurPos(guide_project_time, false, false)
end

local function handle_mouse_state()
  local left_down = left_mouse_is_down()
  local just_pressed = left_mouse_was_just_pressed(left_down)
  local just_released = left_mouse_was_just_released(left_down)

  if just_released then
    end_drag_if_needed()
    previous_left_mouse_down = left_down
    return
  end

  if not left_down then
    end_drag_if_needed()
    previous_left_mouse_down = left_down
    return
  end

  if just_pressed then
    begin_drag_if_possible()
  end

  if is_dragging then
    update_edit_cursor_to_inferred_note_start()
  end

  previous_left_mouse_down = left_down
end

local function main()
  if not is_script_enabled() then
    end_drag_if_needed()
    set_toolbar_state(false)
    return
  end

  handle_mouse_state()
  defer(main)
end

local function startup()
  local was_enabled = is_script_enabled()

  if not dependency_check() then
    return
  end

  if was_enabled then
    set_script_enabled(false)
    return
  end

  set_script_enabled(true)
  main()
end

-- RUN -----------------------------------------------------------------------

startup()