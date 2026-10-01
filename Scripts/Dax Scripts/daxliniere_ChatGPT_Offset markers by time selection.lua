--[[
  @description Offset markers by time selection
  @version 1.1
  @author Dax Liniere / ChatGPT
  @about
    Offsets project markers and regions in selected ruler lanes by the
    length of the current time selection.

    Add:
      Markers/regions beginning at or after the time selection start
      are moved later by the time selection length.

    Subtract:
      Markers/regions beginning at or after the time selection end
      are moved earlier by the time selection length.

    Regions are moved as complete regions, preserving their length.
--]]

local proj = 0

local window_title = "Offset markers by time selection"
local window_w = 420
local row_h = 24
local margin = 16

local mode = "add"
local lanes = {}
local mouse_was_down = false


-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function point_in_rect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end


local function get_time_selection()
    local ts_start, ts_end =
        reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    return ts_start, ts_end, ts_end - ts_start
end


local function format_minutes_seconds(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining = seconds - (minutes * 60)

    return string.format("%02d:%06.3f", minutes, remaining)
end


local function format_bars(ts_start, ts_length)
    return reaper.format_timestr_len(
        ts_length,
        "",
        ts_start,
        2
    )
end


local function get_lane_name(lane_number)
    local _, name = reaper.GetSetProjectInfo_String(
        proj,
        "RULER_LANE_NAME:" .. lane_number,
        "",
        false
    )

    if name == "" then
        name = "Lane " .. (lane_number + 1)
    end

    return name
end


local function build_lane_list()
    local lane_count = math.floor(
        reaper.GetSetProjectInfo(
            proj,
            "RULER_LANE_COUNT",
            0,
            false
        )
    )

    lanes = {}

    if lane_count < 1 then
        lane_count = 1
    end

    for lane_number = 0, lane_count - 1 do
        lanes[#lanes + 1] = {
            number = lane_number,
            name = get_lane_name(lane_number),
            checked = true
        }
    end
end


local function lane_is_enabled(lane_number)
    for _, lane in ipairs(lanes) do
        if lane.number == lane_number then
            return lane.checked
        end
    end

    return false
end


local function draw_text(x, y, text)
    gfx.x = x
    gfx.y = y
    gfx.drawstr(text)
end


local function draw_radio(x, y, label, selected)
    local radius = 7
    local cy = y + 8

    gfx.circle(x + radius, cy, radius, false, true)

    if selected then
        gfx.circle(x + radius, cy, 3, true, true)
    end

    draw_text(x + 20, y, label)
end


local function draw_checkbox(x, y, label, checked)
    local size = 14

    gfx.rect(x, y + 1, size, size, false)

    if checked then
        gfx.line(x + 3, y + 8, x + 6, y + 12)
        gfx.line(x + 6, y + 12, x + 12, y + 4)
    end

    draw_text(x + 22, y, label)
end


local function draw_button(x, y, w, h, label)
    local tw

    gfx.rect(x, y, w, h, false)

    tw = gfx.measurestr(label)

    draw_text(
        x + (w - tw) / 2,
        y + (h - gfx.texth) / 2,
        label
    )
end


local function perform_offset()
    local ts_start, ts_end, ts_length = get_time_selection()
    local threshold
    local offset
    local marker_count
    local changes = {}

    if ts_length <= 0 then
        reaper.MB(
            "Please create a time selection first.",
            window_title,
            0
        )
        return
    end

    if mode == "add" then
        threshold = ts_start
        offset = ts_length
    else
        threshold = ts_end
        offset = -ts_length
    end

    marker_count = reaper.GetNumRegionsOrMarkers(proj)

    -- Collect everything before modifying anything.
    for index = 0, marker_count - 1 do
        local marker =
            reaper.GetRegionOrMarker(proj, index, "")

        if marker then
            local start_pos =
                reaper.GetRegionOrMarkerInfo_Value(
                    proj,
                    marker,
                    "D_STARTPOS"
                )

            local end_pos =
                reaper.GetRegionOrMarkerInfo_Value(
                    proj,
                    marker,
                    "D_ENDPOS"
                )

            local lane_number = math.floor(
                reaper.GetRegionOrMarkerInfo_Value(
                    proj,
                    marker,
                    "I_LANENUMBER"
                )
            )

            if start_pos >= threshold
            and lane_is_enabled(lane_number) then
                changes[#changes + 1] = {
                    marker = marker,
                    start_pos = start_pos + offset,
                    end_pos = end_pos + offset
                }
            end
        end
    end

    if #changes == 0 then
        return
    end

    reaper.Undo_BeginBlock2(proj)
    reaper.PreventUIRefresh(1)

    for _, change in ipairs(changes) do
        reaper.SetRegionOrMarkerInfo_Value(
            proj,
            change.marker,
            "D_STARTPOS",
            change.start_pos
        )

        reaper.SetRegionOrMarkerInfo_Value(
            proj,
            change.marker,
            "D_ENDPOS",
            change.end_pos
        )
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateTimeline()
    reaper.UpdateArrange()

    reaper.Undo_EndBlock2(
        proj,
        "Offset markers by time selection",
        -1
    )

    gfx.quit()
end


-- ------------------------------------------------------------
-- GUI
-- ------------------------------------------------------------

local function draw_gui()
    local ts_start, _, ts_length = get_time_selection()
    local time_text
    local bars_text
    local y
    local button_y

    gfx.setfont(1, "Arial", 16)

    gfx.set(0.15, 0.15, 0.15, 1)
    gfx.rect(0, 0, gfx.w, gfx.h, true)

    gfx.set(0.9, 0.9, 0.9, 1)

    time_text = format_minutes_seconds(math.max(0, ts_length))
    bars_text = format_bars(ts_start, math.max(0, ts_length))

    draw_text(
        margin,
        14,
        "Time selection: " .. time_text .. "   |   Bars: " .. bars_text
    )

    draw_text(margin, 48, "Direction")

    draw_radio(
        margin,
        76,
        "Add",
        mode == "add"
    )

    draw_radio(
        margin + 100,
        76,
        "Subtract",
        mode == "subtract"
    )

    draw_text(margin, 112, "Marker lanes")

    y = 142

    for _, lane in ipairs(lanes) do
        draw_checkbox(
            margin,
            y,
            lane.name,
            lane.checked
        )

        y = y + row_h
    end

    button_y = gfx.h - 46

    draw_button(
        gfx.w - 100 - margin,
        button_y,
        100,
        30,
        "Apply"
    )
end


local function handle_click()
    local mx = gfx.mouse_x
    local my = gfx.mouse_y
    local y
    local button_y

    if point_in_rect(mx, my, margin, 74, 80, 24) then
        mode = "add"
        return
    end

    if point_in_rect(mx, my, margin + 100, 74, 100, 24) then
        mode = "subtract"
        return
    end

    y = 142

    for _, lane in ipairs(lanes) do
        if point_in_rect(mx, my, margin, y, 360, row_h) then
            lane.checked = not lane.checked
            return
        end

        y = y + row_h
    end

    button_y = gfx.h - 46

    if point_in_rect(
        mx,
        my,
        gfx.w - 100 - margin,
        button_y,
        100,
        30
    ) then
        perform_offset()
    end
end


local function main()
    local char = gfx.getchar()
    local mouse_down

    if char < 0 or char == 27 then
        gfx.quit()
        return
    end

    mouse_down = (gfx.mouse_cap & 1) == 1

    if mouse_down and not mouse_was_down then
        handle_click()
    end

    mouse_was_down = mouse_down

    draw_gui()
    gfx.update()

    reaper.defer(main)
end


-- ------------------------------------------------------------
-- Start
-- ------------------------------------------------------------

local window_h

build_lane_list()

window_h =
    142
    + (#lanes * row_h)
    + 64

gfx.init(
    window_title,
    window_w,
    window_h
)

main()
