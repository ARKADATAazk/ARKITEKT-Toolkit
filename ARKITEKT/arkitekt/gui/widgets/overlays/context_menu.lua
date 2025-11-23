-- @noindex
-- ReArkitekt/gui/widgets/controls/context_menu.lua
-- Reusable context menu widget

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')

local M = {}
local hexrgb = Colors.hexrgb

local DEFAULTS = {
  bg_color = hexrgb("#222222"),         -- Lighter grey background
  border_color = hexrgb("#0F0F0F"),     -- Much darker border (almost black)
  item_bg_color = hexrgb("#00000000"),  -- Transparent default
  item_hover_color = hexrgb("#2E2E2E"), -- Subtle hover highlight
  item_active_color = hexrgb("#353535"), -- Active state
  item_text_color = hexrgb("#CCCCCC"),  -- Standard text
  item_text_hover_color = hexrgb("#FFFFFF"), -- Bright on hover
  item_disabled_color = hexrgb("#666666"),
  separator_color = hexrgb("#0F0F0F"),   -- Match border color
  rounding = 2,                          -- Slight rounding for modern look
  padding = 8,                           -- More padding for breathing room
  item_height = 26,                      -- Taller items
  item_padding_x = 12,                   -- More horizontal padding
  border_thickness = 1,
}

function M.begin(ctx, id, config)
  config = config or {}

  local bg_color = config.bg_color or DEFAULTS.bg_color
  local border_color = config.border_color or DEFAULTS.border_color
  local rounding = config.rounding or DEFAULTS.rounding
  local padding = config.padding or DEFAULTS.padding
  local border_thickness = config.border_thickness or DEFAULTS.border_thickness
  local min_width = config.min_width or 180  -- Minimum width for better appearance

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, padding, padding)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, rounding)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, rounding)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, border_thickness)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowMinSize, min_width, 0)

  ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, bg_color)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, border_color)

  local popup_open = ImGui.BeginPopup(ctx, id)

  if not popup_open then
    ImGui.PopStyleColor(ctx, 2)
    ImGui.PopStyleVar(ctx, 5)
  else
    -- Draw subtle shadow/halo effect
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local bg_dl = ImGui.GetBackgroundDrawList(ctx)

    -- Draw multi-layer shadow for soft glow effect
    local shadow_offset = 3
    local shadow_spread = 6
    ImGui.DrawList_AddRectFilled(
      bg_dl,
      wx + shadow_offset - shadow_spread,
      wy + shadow_offset - shadow_spread,
      wx + ww + shadow_offset + shadow_spread,
      wy + wh + shadow_offset + shadow_spread,
      hexrgb("#00000040"),  -- 25% opacity
      rounding + shadow_spread
    )
    ImGui.DrawList_AddRectFilled(
      bg_dl,
      wx + shadow_offset - shadow_spread/2,
      wy + shadow_offset - shadow_spread/2,
      wx + ww + shadow_offset + shadow_spread/2,
      wy + wh + shadow_offset + shadow_spread/2,
      hexrgb("#00000030"),  -- 19% opacity
      rounding + shadow_spread/2
    )
  end

  return popup_open
end

function M.end_menu(ctx)
  ImGui.EndPopup(ctx)
  ImGui.PopStyleColor(ctx, 2)
  ImGui.PopStyleVar(ctx, 5)
end

function M.item(ctx, label, config)
  config = config or {}

  local item_height = config.item_height or DEFAULTS.item_height
  local item_padding_x = config.item_padding_x or DEFAULTS.item_padding_x
  local item_hover_color = config.item_hover_color or DEFAULTS.item_hover_color
  local item_text_color = config.item_text_color or DEFAULTS.item_text_color
  local item_text_hover_color = config.item_text_hover_color or DEFAULTS.item_text_hover_color

  local dl = ImGui.GetWindowDrawList(ctx)
  local item_x, item_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)

  local text_w, text_h = ImGui.CalcTextSize(ctx, label)
  local item_w = math.max(avail_w, text_w + item_padding_x * 2)

  local item_hovered = ImGui.IsMouseHoveringRect(ctx, item_x, item_y, item_x + item_w, item_y + item_height)

  if item_hovered then
    ImGui.DrawList_AddRectFilled(dl, item_x, item_y, item_x + item_w, item_y + item_height, item_hover_color, 2)
  end

  local text_color = item_hovered and item_text_hover_color or item_text_color
  local text_x = item_x + item_padding_x
  local text_y = item_y + (item_height - text_h) * 0.5

  ImGui.DrawList_AddText(dl, text_x, text_y, text_color, label)

  ImGui.InvisibleButton(ctx, label .. "_item", item_w, item_height)

  return ImGui.IsItemClicked(ctx, 0)
end

function M.checkbox_item(ctx, label, checked, config)
  config = config or {}

  local item_height = config.item_height or DEFAULTS.item_height
  local item_padding_x = config.item_padding_x or DEFAULTS.item_padding_x
  local item_hover_color = config.item_hover_color or DEFAULTS.item_hover_color
  local item_text_color = config.item_text_color or DEFAULTS.item_text_color
  local item_text_hover_color = config.item_text_hover_color or DEFAULTS.item_text_hover_color

  local dl = ImGui.GetWindowDrawList(ctx)
  local item_x, item_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)

  local checkbox_size = 14
  local checkbox_padding = 8
  local text_w, text_h = ImGui.CalcTextSize(ctx, label)
  local item_w = math.max(avail_w, text_w + item_padding_x * 2 + checkbox_size + checkbox_padding)

  local item_hovered = ImGui.IsMouseHoveringRect(ctx, item_x, item_y, item_x + item_w, item_y + item_height)

  if item_hovered then
    ImGui.DrawList_AddRectFilled(dl, item_x, item_y, item_x + item_w, item_y + item_height, item_hover_color, 2)
  end

  -- Draw checkbox
  local checkbox_x = item_x + item_padding_x
  local checkbox_y = item_y + (item_height - checkbox_size) * 0.5

  local checkbox_bg = checked and hexrgb("#4A9EFF40") or hexrgb("#00000000")
  local checkbox_border = checked and hexrgb("#4A9EFF") or hexrgb("#404040")

  ImGui.DrawList_AddRectFilled(dl, checkbox_x, checkbox_y, checkbox_x + checkbox_size, checkbox_y + checkbox_size, checkbox_bg, 2)
  ImGui.DrawList_AddRect(dl, checkbox_x, checkbox_y, checkbox_x + checkbox_size, checkbox_y + checkbox_size, checkbox_border, 2, 0, 1)

  -- Draw checkmark if checked
  if checked then
    local check_color = hexrgb("#4A9EFF")
    local check_padding = 3
    -- Draw checkmark using lines
    ImGui.DrawList_AddLine(dl,
      checkbox_x + check_padding,
      checkbox_y + checkbox_size * 0.5,
      checkbox_x + checkbox_size * 0.4,
      checkbox_y + checkbox_size - check_padding,
      check_color, 2)
    ImGui.DrawList_AddLine(dl,
      checkbox_x + checkbox_size * 0.4,
      checkbox_y + checkbox_size - check_padding,
      checkbox_x + checkbox_size - check_padding,
      checkbox_y + check_padding,
      check_color, 2)
  end

  -- Draw label text
  local text_color = item_hovered and item_text_hover_color or item_text_color
  local text_x = checkbox_x + checkbox_size + checkbox_padding
  local text_y = item_y + (item_height - text_h) * 0.5

  ImGui.DrawList_AddText(dl, text_x, text_y, text_color, label)

  ImGui.InvisibleButton(ctx, label .. "_checkbox_item", item_w, item_height)

  return ImGui.IsItemClicked(ctx, 0)
end

function M.separator(ctx, config)
  config = config or {}
  local separator_color = config.separator_color or DEFAULTS.separator_color

  ImGui.Dummy(ctx, 1, 4)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)

  local dl = ImGui.GetWindowDrawList(ctx)
  -- Enhanced separator with inset from edges
  ImGui.DrawList_AddLine(dl, x + 8, y, x + avail_w - 8, y, separator_color, 1)

  ImGui.Dummy(ctx, 1, 6)
end

return M