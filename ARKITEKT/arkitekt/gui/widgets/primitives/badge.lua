-- @noindex
-- arkitekt/gui/widgets/primitives/badge.lua
-- Standardized badge rendering system with consistent styling
-- Uses unified opts-based API

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')
local Base = require('arkitekt.gui.widgets.base')

local M = {}

-- ============================================================================
-- DEFAULTS
-- ============================================================================

M.DEFAULTS = {
  -- Position
  x = 0,
  y = 0,

  -- Size
  size = 18,  -- For icon badges

  -- Content
  text = "",
  icon = nil,

  -- Colors
  base_color = Colors.hexrgb("#555555"),  -- For border derivation
  alpha = 255,
  bg_color = Colors.hexrgb("#14181C"),
  text_color = Colors.hexrgb("#FFFFFFDD"),
  icon_color = Colors.hexrgb("#FFFFFF"),

  -- Style
  padding_x = 5,
  padding_y = 1,
  rounding = 3,
  border_alpha = 0x55,
  border_darken = 0.4,

  -- Font
  icon_font = nil,
  icon_font_size = 14,

  -- Interaction
  id = nil,
  on_click = nil,

  -- Draw list
  draw_list = nil,
}

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local function merge_config(opts)
  return {
    padding_x = opts.padding_x or M.DEFAULTS.padding_x,
    padding_y = opts.padding_y or M.DEFAULTS.padding_y,
    rounding = opts.rounding or M.DEFAULTS.rounding,
    bg_color = opts.bg_color or M.DEFAULTS.bg_color,
    border_alpha = opts.border_alpha or M.DEFAULTS.border_alpha,
    border_darken = opts.border_darken or M.DEFAULTS.border_darken,
    text_color = opts.text_color or M.DEFAULTS.text_color,
    icon_color = opts.icon_color or M.DEFAULTS.icon_color,
  }
end

-- ============================================================================
-- PUBLIC API (Standardized)
-- ============================================================================

--- Render a text badge
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { x1, y1, x2, y2, width, height }
function M.text(ctx, opts)
  opts = Base.parse_opts(opts, M.DEFAULTS)
  local cfg = merge_config(opts)

  local dl = opts.draw_list or ImGui.GetWindowDrawList(ctx)
  local x, y = opts.x, opts.y
  local text = opts.text or ""
  local base_color = opts.base_color
  local alpha = opts.alpha or 255

  -- Calculate dimensions
  local text_w, text_h = ImGui.CalcTextSize(ctx, text)
  local badge_w = text_w + cfg.padding_x * 2
  local badge_h = text_h + cfg.padding_y * 2

  local x2 = x + badge_w
  local y2 = y + badge_h

  -- Background
  local bg_alpha = ((cfg.bg_color & 0xFF) * (alpha / 255)) // 1
  local bg_color = (cfg.bg_color & 0xFFFFFF00) | bg_alpha
  ImGui.DrawList_AddRectFilled(dl, x, y, x2, y2, bg_color, cfg.rounding)

  -- Border using darker tile color
  local border_color = Colors.adjust_brightness(base_color, cfg.border_darken)
  border_color = Colors.with_alpha(border_color, cfg.border_alpha)
  ImGui.DrawList_AddRect(dl, x, y, x2, y2, border_color, cfg.rounding, 0, 0.5)

  -- Text
  local text_x = x + cfg.padding_x
  local text_y = y + cfg.padding_y
  local text_final = Colors.with_alpha(cfg.text_color, alpha)
  ImGui.DrawList_AddText(dl, text_x, text_y, text_final, text)

  return {
    x1 = x, y1 = y, x2 = x2, y2 = y2,
    width = badge_w, height = badge_h,
  }
end

--- Render an icon badge
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { x1, y1, x2, y2, width, height }
function M.icon(ctx, opts)
  opts = Base.parse_opts(opts, M.DEFAULTS)
  local cfg = merge_config(opts)

  local dl = opts.draw_list or ImGui.GetWindowDrawList(ctx)
  local x, y = opts.x, opts.y
  local size = opts.size or 18
  local icon_char = opts.icon or ""
  local base_color = opts.base_color
  local alpha = opts.alpha or 255

  local x2 = x + size
  local y2 = y + size

  -- Background
  local bg_alpha = ((cfg.bg_color & 0xFF) * (alpha / 255)) // 1
  local bg_color = (cfg.bg_color & 0xFFFFFF00) | bg_alpha
  ImGui.DrawList_AddRectFilled(dl, x, y, x2, y2, bg_color, cfg.rounding)

  -- Border using darker tile color
  local border_color = Colors.adjust_brightness(base_color, cfg.border_darken)
  border_color = Colors.with_alpha(border_color, cfg.border_alpha)
  ImGui.DrawList_AddRect(dl, x, y, x2, y2, border_color, cfg.rounding, 0, 0.5)

  -- Icon
  if opts.icon_font then
    ImGui.PushFont(ctx, opts.icon_font, opts.icon_font_size or 14)
  end

  local icon_color = Colors.with_alpha(cfg.icon_color, alpha)
  local icon_w, icon_h = ImGui.CalcTextSize(ctx, icon_char)
  local icon_x = x + (size - icon_w) / 2
  local icon_y = y + (size - icon_h) / 2
  ImGui.DrawList_AddText(dl, icon_x, icon_y, icon_color, icon_char)

  if opts.icon_font then
    ImGui.PopFont(ctx)
  end

  return {
    x1 = x, y1 = y, x2 = x2, y2 = y2,
    width = size, height = size,
  }
end

--- Render a clickable text badge
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { x1, y1, x2, y2, width, height, left_clicked, right_clicked }
function M.clickable(ctx, opts)
  opts = Base.parse_opts(opts, M.DEFAULTS)

  -- Render the text badge first
  local result = M.text(ctx, opts)

  -- Create invisible button over badge
  local unique_id = opts.id or "badge"
  ImGui.SetCursorScreenPos(ctx, result.x1, result.y1)
  ImGui.InvisibleButton(ctx, "##badge_" .. unique_id, result.width, result.height)

  -- Handle clicks
  local left_clicked = ImGui.IsItemClicked(ctx, 0)
  local right_clicked = ImGui.IsItemClicked(ctx, 1)

  if opts.on_click then
    if left_clicked then
      opts.on_click(1)  -- Left-click: increment (+1)
    elseif right_clicked then
      opts.on_click(-1)  -- Right-click: decrement (-1)
    end
  end

  result.left_clicked = left_clicked
  result.right_clicked = right_clicked
  result.clicked = left_clicked

  return result
end

--- Render a favorite badge (star icon)
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { x1, y1, x2, y2, width, height }
function M.favorite(ctx, opts)
  opts = Base.parse_opts(opts, M.DEFAULTS)

  -- Return empty result if not favorited
  if not opts.is_favorite then
    return {
      x1 = opts.x, y1 = opts.y, x2 = opts.x, y2 = opts.y,
      width = 0, height = 0,
    }
  end

  -- Use remixicon star-fill if available, otherwise fallback to Unicode star
  local star_char
  if opts.icon_font then
    star_char = utf8.char(0xF186)  -- Remixicon star-fill
  else
    star_char = "★"  -- U+2605 BLACK STAR
  end

  opts.icon = star_char
  return M.icon(ctx, opts)
end

return M
