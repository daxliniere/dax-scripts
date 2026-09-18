-- @description Set Townhouse GR meter size and position
-- @version 1.0
-- @author Dax Liniere

-- Townhouse Buss Compressor - GR meter viewport
-- v0.31 safe build
-- Requires js_ReaScriptAPI.
--
-- Usage:
--   1. Open the Townhouse Buss Compressor floating FX window.
--   2. Run this script.
--
-- v0.31 safety changes:
--   Keep confirmed v0.29 geometry.
--   Do not use foreground/focused window.
--   Do not use JS_Window_SetZOrder.
--   Do not use JS_Window_Update.
--   Do not use reaper.defer.
--   Validate everything before touching any window.
--   After validation, perform only two JS_Window_SetPosition calls.

local SCRIPT_VERSION = "v0.31"

local FX_WINDOW_TITLE_MATCH = "VST: Townhouse Buss Compressor"
local FX_WINDOW_CLASS = "#32770"

local TARGET_SCREEN_X = 2457
local TARGET_SCREEN_Y = 1359

local TARGET_OUTER_WIDTH = 126
local TARGET_OUTER_HEIGHT = 110

local CONTENT_CONTAINER_CLASS = "#32770"
local CONTENT_CONTAINER_WIDTH = 1024
local CONTENT_CONTAINER_HEIGHT = 261

local PLUGIN_Y_WITHIN_CONTENT_CONTAINER = 27

local GR_METER_X = 813
local GR_METER_Y = 80

local TARGET_CONTENT_X = -GR_METER_X
local TARGET_CONTENT_Y = -(PLUGIN_Y_WITHIN_CONTENT_CONTAINER + GR_METER_Y)

local MIN_REASONABLE_FX_WIDTH = 100
local MIN_REASONABLE_FX_HEIGHT = 80
local MAX_REASONABLE_FX_WIDTH = 2000
local MAX_REASONABLE_FX_HEIGHT = 1200

local LOG_FILE_NAME = "Townhouse_GR_viewport_v0.31_log.txt"

local function get_log_path()
  return reaper.GetResourcePath() .. "\\" .. LOG_FILE_NAME
end

local function write_log_line(message)
  local file = io.open(get_log_path(), "a")

  if file then
    file:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(message) .. "\n")
    file:close()
  end
end

local function reset_log()
  local file = io.open(get_log_path(), "w")

  if file then
    file:write("Townhouse GR viewport " .. SCRIPT_VERSION .. "\n")
    file:write("Log started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    file:close()
  end
end

local function show_message(message)
  reaper.ShowMessageBox(message, "Townhouse GR viewport " .. SCRIPT_VERSION, 0)
end

local function require_api(function_name)
  if not reaper.APIExists(function_name) then
    show_message("Missing required API function: " .. function_name)
    return false
  end

  return true
end

local function trim_text(text)
  return tostring(text):match("^%s*(.-)%s*$")
end

local function get_hwnd_from_address_number(address_number)
  if not address_number then
    return nil
  end

  local hwnd = reaper.JS_Window_HandleFromAddress(address_number)

  if hwnd and reaper.JS_Window_IsWindow(hwnd) then
    return hwnd
  end

  return nil
end

local function address_to_hwnd(address_text)
  local trimmed_address_text = trim_text(address_text)

  local decimal_address = tonumber(trimmed_address_text)
  local hwnd_from_decimal = get_hwnd_from_address_number(decimal_address)

  if hwnd_from_decimal then
    return hwnd_from_decimal
  end

  local hex_address_text = trimmed_address_text:gsub("^0[xX]", "")
  local hex_address = tonumber(hex_address_text, 16)
  local hwnd_from_hex = get_hwnd_from_address_number(hex_address)

  if hwnd_from_hex then
    return hwnd_from_hex
  end

  return nil
end

local function get_window_title(hwnd)
  local ok, title = pcall(reaper.JS_Window_GetTitle, hwnd)

  if ok and title then
    return title
  end

  return ""
end

local function get_window_class(hwnd)
  local ok, class_name = pcall(reaper.JS_Window_GetClassName, hwnd)

  if ok and class_name then
    return class_name
  end

  return ""
end

local function get_window_rect(hwnd)
  local ok, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)

  if not ok then
    return nil
  end

  return {
    left = left,
    top = top,
    right = right,
    bottom = bottom,
    width = right - left,
    height = bottom - top
  }
end

local function rect_to_string(rect)
  if not rect then
    return "nil"
  end

  return
    "left=" .. tostring(rect.left) ..
    ", top=" .. tostring(rect.top) ..
    ", width=" .. tostring(rect.width) ..
    ", height=" .. tostring(rect.height)
end

local function collect_windows_from_list(list_text)
  local windows = {}

  if type(list_text) ~= "string" then
    return windows
  end

  for address_text in list_text:gmatch("[^,]+") do
    local hwnd = address_to_hwnd(address_text)

    if hwnd then
      windows[#windows + 1] = hwnd
    end
  end

  return windows
end

local function collect_top_windows()
  local count, list_text = reaper.JS_Window_ListAllTop()

  write_log_line("Top windows reported: " .. tostring(count))

  return collect_windows_from_list(list_text)
end

local function collect_child_windows(parent_hwnd)
  local count, list_text = reaper.JS_Window_ListAllChild(parent_hwnd)

  write_log_line("Child windows reported: " .. tostring(count))

  return collect_windows_from_list(list_text)
end

local function title_matches_fx_window(title)
  return tostring(title):lower():find(FX_WINDOW_TITLE_MATCH:lower(), 1, true) ~= nil
end

local function is_reasonable_fx_rect(rect)
  if not rect then
    return false
  end

  if rect.width < MIN_REASONABLE_FX_WIDTH then
    return false
  end

  if rect.height < MIN_REASONABLE_FX_HEIGHT then
    return false
  end

  if rect.width > MAX_REASONABLE_FX_WIDTH then
    return false
  end

  if rect.height > MAX_REASONABLE_FX_HEIGHT then
    return false
  end

  return true
end

local function find_fx_window()
  local top_windows = collect_top_windows()
  local matches = {}

  for i = 1, #top_windows do
    local hwnd = top_windows[i]
    local title = get_window_title(hwnd)
    local class_name = get_window_class(hwnd)
    local rect = get_window_rect(hwnd)

    if title_matches_fx_window(title) then
      write_log_line(
        "FX title match: title=\"" .. tostring(title) ..
        "\", class=\"" .. tostring(class_name) ..
        "\", " .. rect_to_string(rect)
      )

      if class_name == FX_WINDOW_CLASS and is_reasonable_fx_rect(rect) then
        matches[#matches + 1] = hwnd
      else
        write_log_line("Rejected FX title match due to class or unreasonable size.")
      end
    end
  end

  if #matches == 1 then
    return matches[1]
  end

  if #matches > 1 then
    write_log_line("Refusing to continue: multiple matching FX windows found.")
    return nil
  end

  write_log_line("No valid matching FX window found.")
  return nil
end

local function is_content_container(hwnd)
  local title = get_window_title(hwnd)
  local class_name = get_window_class(hwnd)
  local rect = get_window_rect(hwnd)

  write_log_line(
    "Child candidate: title=\"" .. tostring(title) ..
    "\", class=\"" .. tostring(class_name) ..
    "\", " .. rect_to_string(rect)
  )

  if not rect then
    return false
  end

  if class_name ~= CONTENT_CONTAINER_CLASS then
    return false
  end

  if rect.width ~= CONTENT_CONTAINER_WIDTH then
    return false
  end

  if rect.height ~= CONTENT_CONTAINER_HEIGHT then
    return false
  end

  return true
end

local function find_content_container(fx_hwnd)
  local child_windows = collect_child_windows(fx_hwnd)
  local matches = {}

  for i = 1, #child_windows do
    local child_hwnd = child_windows[i]

    if is_content_container(child_hwnd) then
      matches[#matches + 1] = child_hwnd
    end
  end

  if #matches == 1 then
    write_log_line("Found exactly one content container.")
    return matches[1]
  end

  if #matches > 1 then
    write_log_line("Refusing to continue: multiple content containers found.")
    return nil
  end

  write_log_line("No valid content container found.")
  return nil
end

local function validate_before_changes(fx_hwnd, content_hwnd)
  local fx_rect = get_window_rect(fx_hwnd)
  local content_rect = get_window_rect(content_hwnd)
  local fx_title = get_window_title(fx_hwnd)
  local fx_class = get_window_class(fx_hwnd)
  local content_class = get_window_class(content_hwnd)

  write_log_line("Pre-change FX title: " .. tostring(fx_title))
  write_log_line("Pre-change FX class: " .. tostring(fx_class))
  write_log_line("Pre-change FX rect: " .. rect_to_string(fx_rect))
  write_log_line("Pre-change content class: " .. tostring(content_class))
  write_log_line("Pre-change content rect: " .. rect_to_string(content_rect))

  if not fx_hwnd or not reaper.JS_Window_IsWindow(fx_hwnd) then
    write_log_line("Validation failed: FX HWND invalid.")
    return false
  end

  if not content_hwnd or not reaper.JS_Window_IsWindow(content_hwnd) then
    write_log_line("Validation failed: content HWND invalid.")
    return false
  end

  if not title_matches_fx_window(fx_title) then
    write_log_line("Validation failed: FX title no longer matches.")
    return false
  end

  if fx_class ~= FX_WINDOW_CLASS then
    write_log_line("Validation failed: FX class mismatch.")
    return false
  end

  if content_class ~= CONTENT_CONTAINER_CLASS then
    write_log_line("Validation failed: content class mismatch.")
    return false
  end

  if not content_rect then
    write_log_line("Validation failed: content rect unavailable.")
    return false
  end

  if content_rect.width ~= CONTENT_CONTAINER_WIDTH then
    write_log_line("Validation failed: content width mismatch.")
    return false
  end

  if content_rect.height ~= CONTENT_CONTAINER_HEIGHT then
    write_log_line("Validation failed: content height mismatch.")
    return false
  end

  return true
end

local function position_fx_window(fx_hwnd)
  write_log_line(
    "Setting FX window position: x=" .. tostring(TARGET_SCREEN_X) ..
    ", y=" .. tostring(TARGET_SCREEN_Y) ..
    ", width=" .. tostring(TARGET_OUTER_WIDTH) ..
    ", height=" .. tostring(TARGET_OUTER_HEIGHT)
  )

  local ok_position = reaper.JS_Window_SetPosition(
    fx_hwnd,
    TARGET_SCREEN_X,
    TARGET_SCREEN_Y,
    TARGET_OUTER_WIDTH,
    TARGET_OUTER_HEIGHT,
    "TOP",
    "NOACTIVATE"
  )

  write_log_line("FX position result: " .. tostring(ok_position))

  return ok_position
end

local function move_content_container(content_hwnd)
  write_log_line(
    "Moving content container: x=" .. tostring(TARGET_CONTENT_X) ..
    ", y=" .. tostring(TARGET_CONTENT_Y) ..
    ", width=" .. tostring(CONTENT_CONTAINER_WIDTH) ..
    ", height=" .. tostring(CONTENT_CONTAINER_HEIGHT)
  )

  local ok_move = reaper.JS_Window_SetPosition(
    content_hwnd,
    TARGET_CONTENT_X,
    TARGET_CONTENT_Y,
    CONTENT_CONTAINER_WIDTH,
    CONTENT_CONTAINER_HEIGHT,
    "TOP",
    "NOACTIVATE"
  )

  write_log_line("Content container move result: " .. tostring(ok_move))

  return ok_move
end

local function report_failure(message)
  write_log_line("FAILED: " .. tostring(message))
  show_message(
    tostring(message) .. "\n\n" ..
    "Log written to:\n" .. get_log_path()
  )
end

local function main()
  reset_log()

  write_log_line("Starting " .. SCRIPT_VERSION)

  if not require_api("JS_Window_IsWindow") then return end
  if not require_api("JS_Window_SetPosition") then return end
  if not require_api("JS_Window_GetRect") then return end
  if not require_api("JS_Window_GetTitle") then return end
  if not require_api("JS_Window_GetClassName") then return end
  if not require_api("JS_Window_ListAllTop") then return end
  if not require_api("JS_Window_ListAllChild") then return end
  if not require_api("JS_Window_HandleFromAddress") then return end

  local fx_hwnd = find_fx_window()

  if not fx_hwnd then
    report_failure("Could not find exactly one valid Townhouse FX window.")
    return
  end

  local content_hwnd = find_content_container(fx_hwnd)

  if not content_hwnd then
    report_failure("Could not find exactly one valid inner FX content container.")
    return
  end

  if not validate_before_changes(fx_hwnd, content_hwnd) then
    report_failure("Validation failed before making changes. No window manipulation was performed.")
    return
  end

  -- Do not show message boxes after this point unless the API call itself fails.
  -- This avoids modal UI during/after HWND manipulation.

  local ok_position = position_fx_window(fx_hwnd)

  if not ok_position then
    write_log_line("FAILED: FX position call returned false.")
    return
  end

  local ok_move = move_content_container(content_hwnd)

  if not ok_move then
    write_log_line("FAILED: content container move call returned false.")
    return
  end

  write_log_line("Completed successfully.")
end

main()