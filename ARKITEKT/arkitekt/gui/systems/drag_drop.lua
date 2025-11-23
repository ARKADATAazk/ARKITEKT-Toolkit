-- @noindex
-- ReArkitekt/gui/systems/drag_drop.lua
-- Generic drag and drop helpers for ImGui

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')
local Draw = require('arkitekt.gui.draw')

local M = {}

-- Default drag drop flags
M.FLAGS = {
  SOURCE_NO_PREVIEW = ImGui.DragDropFlags_SourceNoPreviewTooltip,
  SOURCE_NO_DISABLE = ImGui.DragDropFlags_SourceNoDisableHover,
  SOURCE_NO_HOLD = ImGui.DragDropFlags_SourceNoHoldToOpenOthers,
  ACCEPT_NO_HIGHLIGHT = ImGui.DragDropFlags_AcceptNoDrawDefaultRect,
  ACCEPT_BEFORE_DELIVERY = ImGui.DragDropFlags_AcceptBeforeDelivery,
  ACCEPT_NO_PREVIEW = ImGui.DragDropFlags_AcceptNoPreviewTooltip,
}

-- Default colors for drop indicators
M.COLORS = {
  POTENTIAL_TARGET = Colors.hexrgb("#FFFFFF30"),  -- Subtle highlight for all potential targets
  ACTIVE_TARGET = Colors.hexrgb("#FFFFFFAA"),     -- Brighter when hovering
  ACTIVE_FILL = Colors.hexrgb("#FFFFFF10"),       -- Fill for active target
  GLOW_COLOR = Colors.hexrgb("#FFFFFF"),          -- White glow
}

-- Track active drag type globally
M._active_drag_type = nil
M._hovered_drop_target = nil  -- Track which item is being hovered for drop

-- Set the active drag type (call when drag starts)
function M.set_active_drag_type(drag_type)
  M._active_drag_type = drag_type
end

-- Get the current active drag type
function M.get_active_drag_type()
  return M._active_drag_type
end

-- Clear the active drag type (call when drag ends)
function M.clear_active_drag_type()
  M._active_drag_type = nil
  M._hovered_drop_target = nil
end

-- Set the hovered drop target (call when BeginDragDropTarget succeeds)
function M.set_hovered_drop_target(id)
  M._hovered_drop_target = id
end

-- Get the hovered drop target
function M.get_hovered_drop_target()
  return M._hovered_drop_target
end

-- Clear hovered drop target (call at start of frame)
function M.clear_hovered_drop_target()
  M._hovered_drop_target = nil
end

-- Begin a drag source on the last item
-- Returns true if drag is active
function M.begin_source(ctx, payload_type, payload_data, flags)
  flags = flags or 0

  if ImGui.BeginDragDropSource(ctx, flags) then
    -- Serialize payload data as string
    local payload_str = type(payload_data) == "table"
      and M._serialize(payload_data)
      or tostring(payload_data)

    ImGui.SetDragDropPayload(ctx, payload_type, payload_str)
    return true
  end

  return false
end

-- End the drag source (call after drawing preview)
function M.end_source(ctx)
  ImGui.EndDragDropSource(ctx)
end

-- Begin a drag target on the last item
-- accepted_types can be a string or table of strings
-- Returns true if target is active and can accept a drop
function M.begin_target(ctx)
  return ImGui.BeginDragDropTarget(ctx)
end

-- End the drag target
function M.end_target(ctx)
  ImGui.EndDragDropTarget(ctx)
end

-- Accept a drop and return the payload
-- Returns payload_data (deserialized) or nil if not accepted
function M.accept_drop(ctx, payload_type, flags)
  flags = flags or 0

  local retval, payload = ImGui.AcceptDragDropPayload(ctx, payload_type, flags)

  if retval and payload and type(payload) == "string" then
    -- Deserialize if it looks like serialized data
    local data = M._deserialize(payload) or payload
    return data
  end

  return nil
end

-- Peek at the current drag payload without accepting it
-- Returns payload_data if a matching type is being dragged
function M.peek_payload(ctx, payload_type)
  -- Use AcceptBeforeDelivery and AcceptNoDrawDefaultRect to peek without side effects
  local flags = ImGui.DragDropFlags_AcceptBeforeDelivery | ImGui.DragDropFlags_AcceptNoDrawDefaultRect
  local payload = ImGui.AcceptDragDropPayload(ctx, payload_type, flags)

  if payload and type(payload) == "string" then
    return M._deserialize(payload) or payload
  end

  return nil
end

-- Check if any drag is active
function M.is_drag_active(ctx)
  return ImGui.GetDragDropPayload(ctx) ~= nil
end

-- Draw a simple text preview during drag
function M.draw_preview_text(ctx, text, color)
  color = color or Colors.hexrgb("#FFFFFF")
  ImGui.Text(ctx, text)
end

-- Draw a chip-style preview during drag
function M.draw_preview_chip(ctx, label, bg_color, text_color)
  bg_color = bg_color or Colors.hexrgb("#5B8FB9")
  text_color = text_color or Colors.hexrgb("#FFFFFF")

  local dl = ImGui.GetForegroundDrawList(ctx)
  local text_w, text_h = ImGui.CalcTextSize(ctx, label)
  local padding = 8
  local chip_w = text_w + padding * 2
  local chip_h = text_h + 6

  local mx, my = ImGui.GetMousePos(ctx)
  local x = mx + 10
  local y = my + 10

  -- Background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + chip_w, y + chip_h, bg_color, 3)

  -- Text
  Draw.text(dl, x + padding, y + 3, text_color, label)
end

-- Draw highlight for a potential drop target (shown on all valid targets while dragging)
function M.draw_potential_target(ctx, rect, color)
  color = color or M.COLORS.POTENTIAL_TARGET

  local dl = ImGui.GetWindowDrawList(ctx)
  local x1, y1, x2, y2 = rect[1], rect[2], rect[3], rect[4]

  -- Subtle border
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, color, 4, 0, 1.5)
end

-- Draw highlight for an active drop target (shown when hovering a valid target)
-- Includes a multi-layer glow effect
function M.draw_active_target(ctx, rect, border_color, fill_color, glow_color)
  border_color = border_color or M.COLORS.ACTIVE_TARGET
  fill_color = fill_color or M.COLORS.ACTIVE_FILL
  glow_color = glow_color or M.COLORS.GLOW_COLOR

  local dl = ImGui.GetWindowDrawList(ctx)
  local x1, y1, x2, y2 = rect[1], rect[2], rect[3], rect[4]

  -- Extract RGB from glow color for alpha manipulation
  local gr, gg, gb = Colors.rgba_to_components(glow_color)

  -- Draw glow layers (outer to inner) - reduced by 80%
  local glow_layers = {
    { expand = 8, alpha = 0x02 },   -- Outermost, very faint
    { expand = 5, alpha = 0x05 },   -- Middle
    { expand = 3, alpha = 0x08 },   -- Inner glow
  }

  for _, layer in ipairs(glow_layers) do
    local e = layer.expand
    local glow = Colors.components_to_rgba(gr, gg, gb, layer.alpha)
    ImGui.DrawList_AddRectFilled(dl, x1 - e, y1 - e, x2 + e, y2 + e, glow, 6)
  end

  -- Fill
  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, fill_color, 4)

  -- Main border (brightest)
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, border_color, 4, 0, 2.5)
end

-- Legacy function for backward compatibility
function M.draw_target_highlight(ctx, rect, color, thickness)
  color = color or Colors.hexrgb("#5588FFAA")
  thickness = thickness or 2

  local dl = ImGui.GetWindowDrawList(ctx)
  local x1, y1, x2, y2 = rect[1], rect[2], rect[3], rect[4]

  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, color, 4, 0, thickness)
end

-- Simple serialization for tables (supports strings, numbers, booleans)
function M._serialize(t)
  if type(t) ~= "table" then return tostring(t) end

  local parts = {}
  for k, v in pairs(t) do
    local key = type(k) == "string" and k or tostring(k)
    local val = type(v) == "string" and ('"' .. v:gsub('"', '\\"') .. '"') or tostring(v)
    parts[#parts + 1] = key .. "=" .. val
  end

  return "{" .. table.concat(parts, ",") .. "}"
end

-- Simple deserialization
function M._deserialize(str)
  -- Type check first
  if type(str) ~= "string" then return nil end
  if str == "" then return nil end

  -- If it doesn't look like serialized data, return as-is
  if str:sub(1, 1) ~= "{" then return str end

  -- Parse simple key=value format
  local result = {}
  local content = str:sub(2, -2)  -- Remove { }

  for pair in content:gmatch("[^,]+") do
    local key, val = pair:match("([^=]+)=(.+)")
    if key and val then
      key = key:match("^%s*(.-)%s*$")  -- Trim whitespace
      val = val:match("^%s*(.-)%s*$")

      -- Parse value type
      if val:sub(1, 1) == '"' then
        -- String
        val = val:sub(2, -2):gsub('\\"', '"')
      elseif val == "true" then
        val = true
      elseif val == "false" then
        val = false
      else
        -- Try number
        val = tonumber(val) or val
      end

      result[key] = val
    end
  end

  return result
end

return M
