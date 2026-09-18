-- @description LFO Automation
-- @version 1.0
-- @author Dax Liniere

-- Parameter Modulation Automation Bridge v19
--
-- Uses the open Parameter Modulation/Link window to identify the exact
-- track, FX instance and parameter being modulated.
--
-- The JSFX exposes one automation parameter named:
--
--     Automation Parameter
--
-- Current real-range implementation:
--   - LFO Speed: 0.01 Hz to 8.00 Hz
--
-- Requirements:
--   - js_ReaScriptAPI
--   - "Parameter Modulation Automation" JSFX on the same track
--
-- v19 fixes the v18 regression where controller detection incorrectly
-- required the JSFX to report exactly one parameter.
--
-- Keep declarations before calls.

local CONTROLLER_PARAM_NAME
local CONTROLLER_PARAM
local UPDATE_INTERVAL
local WINDOW_PREFIX
local APP_TITLE
local target_hwnd
local target_title
local target_track_number
local target_track_name
local target_fx_name
local target_param_name
local target_track
local target_fx
local target_param
local controller_fx
local selected_key
local last_update
local last_value
local action_retval
local action_filename
local section_id
local command_id
local action_mode
local action_resolution
local action_value
local action_context

local function trim(text)
    local s

    s = tostring(text or "")
    s = s:match("^%s*(.-)%s*$") or s

    return s
end

local function find_parameter_modulation_window()
    local hwnd
    local title

    hwnd = reaper.JS_Window_FindTop(WINDOW_PREFIX, false)

    if hwnd == nil then
        return nil, nil
    end

    title = reaper.JS_Window_GetTitle(hwnd)

    if title == nil or title == "" then
        return nil, nil
    end

    return hwnd, title
end

local function parse_parameter_modulation_title(title)
    local body
    local param_name
    local fx_name
    local track_number
    local track_name

    body = title:match("^Parameter Modulation/Link for%s+(.+)$")

    if body == nil then
        return nil
    end

    param_name, fx_name, track_number, track_name =
        body:match("^(.-)%s*/%s*(.-)%s*%-%s*%((%d+):%s*(.-)%)$")

    if param_name == nil then
        return nil
    end

    return tonumber(track_number), trim(track_name), trim(fx_name), trim(param_name)
end

local function show_centered_menu(title, menu)
    local ok
    local left
    local top
    local right
    local bottom
    local view_left
    local view_top
    local view_right
    local view_bottom
    local center_x
    local center_y
    local choice

    ok, left, top, right, bottom = reaper.JS_Window_GetRect(target_hwnd)

    if not ok then
        gfx.init(title, 1, 1, 0, 0, 0)
        gfx.x = 0
        gfx.y = 0
        choice = gfx.showmenu(menu)
        gfx.quit()
        return choice
    end

    view_left, view_top, view_right, view_bottom =
        reaper.JS_Window_GetViewportFromRect(left, top, right, bottom, true)

    center_x = math.floor((view_left + view_right) / 2)
    center_y = math.floor((view_top + view_bottom) / 2)

    gfx.init(title, 1, 1, 0, center_x, center_y)
    gfx.x = 0
    gfx.y = 0
    choice = gfx.showmenu(menu)
    gfx.quit()

    return choice
end

local function find_matching_fx(track, wanted_fx_name, wanted_param_name)
    local fx_count
    local fx
    local ok
    local fx_name
    local param_count
    local param
    local param_ok
    local param_name
    local matches
    local match_count
    local menu
    local choice

    fx_count = reaper.TrackFX_GetCount(track)
    matches = {}
    match_count = 0

    for fx = 0, fx_count - 1 do
        ok, fx_name = reaper.TrackFX_GetFXName(track, fx, "")

        if ok and fx_name ~= "" and fx_name:find(wanted_fx_name, 1, true) then
            param_count = reaper.TrackFX_GetNumParams(track, fx)

            for param = 0, param_count - 1 do
                param_ok, param_name =
                    reaper.TrackFX_GetParamName(track, fx, param, "")

                if param_ok and param_name == wanted_param_name then
                    match_count = match_count + 1
                    matches[match_count] = {
                        fx = fx,
                        param = param,
                        fx_name = fx_name
                    }
                end
            end
        end
    end

    if match_count == 0 then
        return -1, -1
    end

    if match_count == 1 then
        return matches[1].fx, matches[1].param
    end

    menu = ""

    for fx = 1, match_count do
        menu = menu ..
            tostring(matches[fx].fx + 1) .. ": " ..
            matches[fx].fx_name:gsub("|", "/") .. "|"
    end

    choice = show_centered_menu("Choose matching FX instance", menu)

    if choice < 1 or matches[choice] == nil then
        return -1, -1
    end

    return matches[choice].fx, matches[choice].param
end

local function find_controller_fx(track)
    local fx_count
    local fx
    local param_count
    local ok
    local name

    fx_count = reaper.TrackFX_GetCount(track)

    for fx = 0, fx_count - 1 do
        param_count = reaper.TrackFX_GetNumParams(track, fx)

        if param_count > 0 then
            ok, name = reaper.TrackFX_GetParamName(track, fx, 0, "")

            if ok and name == CONTROLLER_PARAM_NAME then
                return fx
            end
        end
    end

    return -1
end

local function choose_modulation_control()
    local menu
    local choice

    menu =
        "#Baseline|" ..
        "#Audio control signal: Attack|" ..
        "#Audio control signal: Release|" ..
        "#Audio control signal: Min volume|" ..
        "#Audio control signal: Max volume|" ..
        "#Audio control signal: Strength|" ..
        "LFO: Speed|" ..
        "#LFO: Strength|" ..
        "#LFO: Phase|"

    choice = show_centered_menu(
        "Choose Parameter Modulation control",
        menu
    )

    if choice == 7 then
        return ".lfo.speed"
    end

    return nil
end

local function set_toolbar_state(state)
    if section_id ~= nil and command_id ~= nil and command_id ~= 0 then
        reaper.SetToggleCommandState(section_id, command_id, state)
        reaper.RefreshToolbar2(section_id, command_id)
    end
end

local function cleanup()
    set_toolbar_state(0)
end

local function main()
    local now
    local value
    local minval
    local maxval
    local ok

    if not reaper.ValidatePtr2(0, target_track, "MediaTrack*") then
        reaper.MB(
            "The target track is no longer available.",
            APP_TITLE,
            0
        )
        return
    end

    now = reaper.time_precise()

    if now - last_update >= UPDATE_INTERVAL then
        value, minval, maxval =
            reaper.TrackFX_GetParam(
                target_track,
                controller_fx,
                CONTROLLER_PARAM
            )

        if value < minval then
            value = minval
        elseif value > maxval then
            value = maxval
        end

        if last_value == nil or math.abs(value - last_value) > 0.0000001 then
            ok = reaper.TrackFX_SetNamedConfigParm(
                target_track,
                target_fx,
                selected_key,
                string.format("%.9f", value)
            )

            if not ok then
                reaper.MB(
                    "REAPER rejected the Parameter Modulation write.",
                    APP_TITLE,
                    0
                )
                return
            end

            last_value = value
        end

        last_update = now
    end

    reaper.defer(main)
end

CONTROLLER_PARAM_NAME = "Automation Parameter"
CONTROLLER_PARAM = 0
UPDATE_INTERVAL = 0.02
WINDOW_PREFIX = "Parameter Modulation/Link for "
APP_TITLE = "Parameter Modulation Automation"
target_hwnd = nil
target_title = nil
target_track_number = nil
target_track_name = nil
target_fx_name = nil
target_param_name = nil
target_track = nil
target_fx = -1
target_param = -1
controller_fx = -1
selected_key = nil
last_update = 0
last_value = nil
section_id = nil
command_id = nil

if reaper.JS_Window_FindTop == nil or reaper.JS_Window_GetTitle == nil then
    reaper.MB(
        "Parameter Modulation Automation requires js_ReaScriptAPI.",
        APP_TITLE,
        0
    )
    return
end

action_retval,
action_filename,
section_id,
command_id,
action_mode,
action_resolution,
action_value,
action_context = reaper.get_action_context()

target_hwnd, target_title = find_parameter_modulation_window()

if target_hwnd == nil then
    reaper.MB(
        "Open the target parameter's Parameter Modulation/Link window, then run this script again.",
        APP_TITLE,
        0
    )
    return
end

target_track_number,
target_track_name,
target_fx_name,
target_param_name = parse_parameter_modulation_title(target_title)

if target_track_number == nil then
    reaper.MB(
        "Could not parse the open Parameter Modulation window title:\n\n" ..
        tostring(target_title),
        APP_TITLE,
        0
    )
    return
end

target_track = reaper.GetTrack(0, target_track_number - 1)

if target_track == nil then
    reaper.MB(
        "Could not resolve track " .. tostring(target_track_number) .. ".",
        APP_TITLE,
        0
    )
    return
end

target_fx, target_param =
    find_matching_fx(target_track, target_fx_name, target_param_name)

if target_fx < 0 or target_param < 0 then
    reaper.MB(
        "Could not resolve the FX/parameter shown in the Parameter Modulation window.\n\n" ..
        "Track: " .. tostring(target_track_number) .. " - " .. target_track_name .. "\n" ..
        "FX: " .. target_fx_name .. "\n" ..
        "Parameter: " .. target_param_name,
        APP_TITLE,
        0
    )
    return
end

controller_fx = find_controller_fx(target_track)

if controller_fx < 0 then
    reaper.MB(
        'Could not find the "Parameter Modulation Automation" JSFX on track ' ..
        tostring(target_track_number) ..
        ".",
        APP_TITLE,
        0
    )
    return
end

selected_key = choose_modulation_control()

if selected_key == nil then
    return
end

selected_key =
    "param." .. tostring(target_param) .. selected_key

reaper.atexit(cleanup)
set_toolbar_state(1)

main()
