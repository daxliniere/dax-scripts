-- @description Sid ChatGPT Close FX hidden by mixer
-- @version 1.0
-- @author Dax Liniere

-- Close FX Windows Hidden Behind Mixer
--
-- desc: FX windows that are fully-contained within the bounds of the mixer are closed when the mixer is in focus (foreground)
--
-- Original code by Sid, reworked by daxliniere with ChatGPT
-- Requires: js_ReaScriptAPI
-- FX windows must start with one of ":", "vst:", "vsti:", "vst3:", "vst3i:", "js:", "au:", "clap:", "dx:", "fx:"
-- FG = foreground
-- Hint: Add the : character to your containers' alias (name) for it to be included in this script's actions.

-- === Tuning ===
local SCAN_INTERVAL = 0.5   -- seconds; only runs when Mixer is foreground

-- === Fast locals ===
local r = reaper
local time_precise = r.time_precise
local defer        = r.defer

local JS_Window_ListAllTop         = r.JS_Window_ListAllTop
local JS_Window_HandleFromAddress  = r.JS_Window_HandleFromAddress
local JS_Window_GetParent          = r.JS_Window_GetParent
local JS_Window_GetTitle           = r.JS_Window_GetTitle
local JS_Window_GetRect            = r.JS_Window_GetRect
local JS_Window_GetForeground      = r.JS_Window_GetForeground
local JS_WindowMessage_Send        = r.JS_WindowMessage_Send
local JS_Window_FromPoint          = r.JS_Window_FromPoint      -- used only on macOS
local JS_Window_GetLong            = r.JS_Window_GetLong        -- used only on Windows
local GetMainHwnd                  = r.GetMainHwnd

if not JS_Window_ListAllTop then return end

-- === OS detection (once) ===
local os = (r.GetOS() or "")
local is_macos = os:match("^OSX") ~= nil   -- e.g. "OSX64" → true; "Win64" → false

-- === Helpers ===
local function fully_inside(L,T,R,B, l2,t2,r2,b2)
  if is_macos then
    -- macOS coordinate polarity (per user report)
    return (L >= l2) and (T <= t2) and (R <= r2) and (B >= b2)
  else
    -- Windows / others (original logic)
    return (L >= l2) and (T >= t2) and (R <= r2) and (B <= b2)
  end
end

local function belongs_to_reaper(hwnd)
  -- Walk parents to ensure this window is part of REAPER’s main tree
  local main = GetMainHwnd()
  local h = hwnd
  while h do
    if h == main then return true end
    h = JS_Window_GetParent(h)
  end
  return false
end

-- Normalize REAPER status banners that may precede plugin prefixes (case-insensitive)
local function normalize_banner(s)
  if not s or s == "" then return s end
  s = s:lower()
  -- strip a single leading "BYPASSED - " or "OFFLINE - "
  s = s:gsub("^%s*bypassed%s*%-%s*", "")
  s = s:gsub("^%s*offline%s*%-%s*", "")
  return s
end

-- FX detection via title/parent-title prefixes (":" included; no special-case)
local FX_PREFIXES = { ":", "vst:", "vsti:", "vst3:", "vst3i:", "js:", "au:", "clap:", "dx:", "fx:" }
local function has_prefix(s)
  for i = 1, #FX_PREFIXES do
    local p = FX_PREFIXES[i]
    if s:sub(1, #p) == p then return true end
  end
  return false
end

local function looks_like_fx(hwnd)
  local t = JS_Window_GetTitle(hwnd)
  if t and t ~= "" and has_prefix(normalize_banner(t)) then return true end

  local parent = JS_Window_GetParent(hwnd)
  if parent then
    local pt = JS_Window_GetTitle(parent)
    if pt and pt ~= "" and has_prefix(normalize_banner(pt)) then return true end
  end

  return false
end

-- Windows: detect pinned (always-on-top) via EXSTYLE bit
local WS_EX_TOPMOST = 0x00000008
local function is_pinned_windows(hwnd)
  if is_macos or not JS_Window_GetLong then return false end
  local ex = JS_Window_GetLong(hwnd, "EXSTYLE") or 0
  return (math.floor(ex / WS_EX_TOPMOST) % 2) == 1
end

-- macOS: best-effort "is on top" probe using one z-order sample
local function is_effectively_pinned_macos(hwnd_fx)
  if not is_macos or not JS_Window_FromPoint then return false end
  local ok, L,T,R,B = JS_Window_GetRect(hwnd_fx)
  if not ok then return false end
  local cx = (L + R) / 2
  local cy = (T + B) / 2
  local top = JS_Window_FromPoint(cx, cy)
  return top == hwnd_fx
end

-- === Main loop (FG-only; no work when Mixer isn’t FG) ===
local next_scan_ts = 0

local function main()
  local now = time_precise()

  local fg = JS_Window_GetForeground()
  if not fg then defer(main); return end

  local fg_title = JS_Window_GetTitle(fg) or ""
  -- Only act when the Mixer is foreground
  if not fg_title:lower():find("mixer", 1, true) then
    defer(main); return
  end

  -- Mixer is FG: get its rect (cheap) and scan at the set cadence
  local ok, mixL, mixT, mixR, mixB = JS_Window_GetRect(fg)
  if not ok then defer(main); return end

  if now >= next_scan_ts then
    local ok2, list = JS_Window_ListAllTop()
    if ok2 and list and list ~= "" then
      for addr in string.gmatch(list, "[^,]+") do
        local hwnd = JS_Window_HandleFromAddress(addr)
        if hwnd and hwnd ~= fg and belongs_to_reaper(hwnd) and looks_like_fx(hwnd) then
          local _, L, T, R, B = JS_Window_GetRect(hwnd)

          -- Full containment first (cheap gate)
          if fully_inside(L, T, R, B, mixL, mixT, mixR, mixB) then

            -- Skip pinned windows (Windows precise, macOS best-effort)
            if (not is_macos and is_pinned_windows(hwnd))
               or (is_macos and is_effectively_pinned_macos(hwnd)) then
              goto continue
            end

            -- macOS: some plugins close only when WM_CLOSE is sent to the parent window
            local target = hwnd
            if is_macos then
              local p = JS_Window_GetParent(hwnd)
              if p then target = p end
            end

            JS_WindowMessage_Send(target, "WM_CLOSE", 0, 0, 0, 0) -- gentle close
          end
        end
        ::continue::
      end
    end
    next_scan_ts = now + SCAN_INTERVAL
  end

  defer(main)
end

main()