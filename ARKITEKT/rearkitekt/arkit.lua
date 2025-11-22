-- @noindex
-- rearkitekt/arkit.lua
-- Common imports and utilities for all ReArkitekt scripts
--
-- This is your single entry point for ReArkitekt utilities.
-- The specialized modules (math.lua, easing.lua, draw.lua) are no longer needed
-- unless you need their advanced/rarely-used functions.

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path

local M = {}

-- ============================================================================
-- SECTION 1: Core Dependencies
-- ============================================================================

M.ImGui = require 'imgui' '0.10'
M.Colors = require('rearkitekt.core.colors')

-- ============================================================================
-- SECTION 2: Frequently Used Color Functions
-- ============================================================================

M.hexrgb = M.Colors.hexrgb
M.with_alpha = M.Colors.with_alpha
M.auto_text_color = M.Colors.auto_text_color
M.lerp_color = M.Colors.lerp
M.adjust_brightness = M.Colors.adjust_brightness
M.desaturate = M.Colors.desaturate
M.saturate = M.Colors.saturate

-- ============================================================================
-- SECTION 2: Math Utilities
-- ============================================================================

function M.lerp(a, b, t)
  return a + (b - a) * math.min(1.0, t)
end

function M.clamp(val, min, max)
  return math.max(min, math.min(max, val))
end

function M.remap(value, in_min, in_max, out_min, out_max)
  local range = in_max - in_min
  if range == 0 then return out_min end
  return out_min + (value - in_min) * (out_max - out_min) / range
end

function M.snap(value, step)
  return math.floor(value / step + 0.5) * step
end

function M.approximately(a, b, epsilon)
  epsilon = epsilon or 0.0001
  return math.abs(a - b) < epsilon
end

-- ============================================================================
-- SECTION 3: Drawing Utilities
-- ============================================================================

-- Snap to pixel boundary for crisp rendering
function M.snap_pixel(x)
  return math.floor(x + 0.5)
end

-- Draw centered text within a rectangle
function M.centered_text(ctx, text, x1, y1, x2, y2, color)
  local dl = M.ImGui.GetWindowDrawList(ctx)
  local tw, th = M.ImGui.CalcTextSize(ctx, text)
  local cx = x1 + math.floor((x2 - x1 - tw) * 0.5)
  local cy = y1 + math.floor((y2 - y1 - th) * 0.5)
  M.ImGui.DrawList_AddText(dl, cx, cy, color or M.hexrgb("#FFFFFF"), text)
end

-- Draw a crisp rectangle (pixel-aligned)
function M.rect(dl, x1, y1, x2, y2, color, rounding, thickness)
  x1 = M.snap_pixel(x1)
  y1 = M.snap_pixel(y1) 
  x2 = M.snap_pixel(x2)
  y2 = M.snap_pixel(y2)
  thickness = thickness or 1
  rounding = rounding or 0
  
  if thickness == 1 then
    M.ImGui.DrawList_AddRect(dl, x1 + 0.5, y1 + 0.5, x2 - 0.5, y2 - 0.5, 
                            color, rounding, 0, thickness)
  else
    M.ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, color, rounding, 0, thickness)
  end
end

-- Draw a filled rectangle (pixel-aligned)
function M.rect_filled(dl, x1, y1, x2, y2, color, rounding)
  x1 = M.snap_pixel(x1)
  y1 = M.snap_pixel(y1)
  x2 = M.snap_pixel(x2)
  y2 = M.snap_pixel(y2)
  M.ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, color, rounding or 0)
end

-- Draw a crisp line (pixel-aligned)
function M.line(dl, x1, y1, x2, y2, color, thickness)
  x1 = M.snap_pixel(x1)
  y1 = M.snap_pixel(y1)
  x2 = M.snap_pixel(x2)
  y2 = M.snap_pixel(y2)
  thickness = thickness or 1
  M.ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, color, thickness)
end

-- Draw left-aligned text
function M.text(dl, x, y, color, text)
  M.ImGui.DrawList_AddText(dl, M.snap_pixel(x), M.snap_pixel(y), color, text or "")
end

-- Draw right-aligned text
function M.text_right(ctx, x, y, color, text)
  local dl = M.ImGui.GetWindowDrawList(ctx)
  local tw = select(1, M.ImGui.CalcTextSize(ctx, text))
  M.ImGui.DrawList_AddText(dl, M.snap_pixel(x - tw), M.snap_pixel(y), color, text or "")
end

-- Draw clipped text (for tab labels etc)
function M.text_clipped(ctx, text, x, y, max_width, color)
  local dl = M.ImGui.GetWindowDrawList(ctx)
  local tw, th = M.ImGui.CalcTextSize(ctx, text)
  
  if tw <= max_width then
    M.ImGui.DrawList_AddText(dl, M.snap_pixel(x), M.snap_pixel(y), color, text)
  else
    local clip_x1 = M.snap_pixel(x)
    local clip_x2 = M.snap_pixel(x + max_width)
    M.ImGui.DrawList_PushClipRect(dl, clip_x1, y - 2, clip_x2, y + th + 2, true)
    M.ImGui.DrawList_AddText(dl, M.snap_pixel(x), M.snap_pixel(y), color, text)
    M.ImGui.DrawList_PopClipRect(dl)
  end
end

-- Check if point is in rectangle
function M.point_in_rect(x, y, x1, y1, x2, y2)
  return x >= math.min(x1, x2) and x <= math.max(x1, x2)
     and y >= math.min(y1, y2) and y <= math.max(y1, y2)
end

-- Check if rectangles intersect
function M.rects_intersect(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2)
  local a_left = math.min(ax1, ax2)
  local a_right = math.max(ax1, ax2)
  local a_top = math.min(ay1, ay2)
  local a_bottom = math.max(ay1, ay2)
  
  local b_left = math.min(bx1, bx2)
  local b_right = math.max(bx1, bx2)
  local b_top = math.min(by1, by2)
  local b_bottom = math.max(by1, by2)
  
  return not (a_left > b_right or a_right < b_left or 
              a_top > b_bottom or a_bottom < b_top)
end

-- ============================================================================
-- SECTION 4: Common Easing Functions
-- ============================================================================

function M.ease_linear(t)
  return t
end

function M.ease_in_quad(t)
  return t * t
end

function M.ease_out_quad(t)
  return 1 - (1 - t) * (1 - t)
end

function M.ease_in_out_quad(t)
  if t < 0.5 then
    return 2 * t * t
  else
    return 1 - (-2 * t + 2) * (-2 * t + 2) / 2
  end
end

function M.ease_out_cubic(t)
  return 1 - (1 - t) * (1 - t) * (1 - t)
end

function M.ease_in_out_cubic(t)
  if t < 0.5 then
    return 4 * t * t * t
  else
    return 1 - (-2 * t + 2) * (-2 * t + 2) * (-2 * t + 2) / 2
  end
end

function M.ease_out_sine(t)
  return math.sin((t * math.pi) / 2)
end

function M.ease_in_out_sine(t)
  return -(math.cos(math.pi * t) - 1) / 2
end

function M.smoothstep(t)
  return t * t * (3.0 - 2.0 * t)
end

function M.smootherstep(t)
  return t * t * t * (t * (t * 6 - 15) + 10)
end

-- ============================================================================
-- SECTION 5: Unicode Utilities
-- ============================================================================

--- Convert a Unicode code point to UTF-8 encoded string
--- @param codepoint number|string The code point (e.g., 0xF3B4 or "F3B4")
--- @return string The UTF-8 encoded string
function M.utf8(codepoint)
  -- Handle string input (e.g., "F3B4" or "0xF3B4")
  if type(codepoint) == "string" then
    codepoint = codepoint:gsub("^0x", ""):gsub("^U%+", "")
    codepoint = tonumber(codepoint, 16)
  end

  if not codepoint then return "" end

  if codepoint < 0x80 then
    -- 1-byte ASCII
    return string.char(codepoint)
  elseif codepoint < 0x800 then
    -- 2-byte sequence
    return string.char(
      0xC0 + math.floor(codepoint / 0x40),
      0x80 + (codepoint % 0x40)
    )
  elseif codepoint < 0x10000 then
    -- 3-byte sequence (most common for icons)
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + math.floor((codepoint % 0x1000) / 0x40),
      0x80 + (codepoint % 0x40)
    )
  else
    -- 4-byte sequence
    return string.char(
      0xF0 + math.floor(codepoint / 0x40000),
      0x80 + math.floor((codepoint % 0x40000) / 0x1000),
      0x80 + math.floor((codepoint % 0x1000) / 0x40),
      0x80 + (codepoint % 0x40)
    )
  end
end

return M