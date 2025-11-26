-- @noindex
-- arkitekt/gui/widgets/primitives/spinner.lua
-- Standardized spinner widget with Arkitekt styling
-- Uses unified opts-based API

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')
local Style = require('arkitekt.gui.style')
local Base = require('arkitekt.gui.widgets.base')

local hexrgb = Colors.hexrgb

local M = {}

-- ============================================================================
-- INSTANCE MANAGEMENT (strong tables with access tracking for cleanup)
-- ============================================================================

local instances = Base.create_instance_registry()

local function create_spinner_instance(id)
  return {
    left_hover_alpha = 0,
    value_hover_alpha = 0,
    right_hover_alpha = 0,
  }
end

local function get_instance(id)
  return Base.get_or_create_instance(instances, id, create_spinner_instance)
end

-- ============================================================================
-- DEFAULTS
-- ============================================================================

local DEFAULTS = {
  -- Identity
  id = "spinner",

  -- Position (nil = use cursor)
  x = nil,
  y = nil,

  -- Size
  width = 200,
  height = 24,
  button_width = 24,
  spacing = 2,

  -- State
  value = 1,         -- Current index (1-based)
  options = {},      -- Array of values to cycle through
  disabled = false,

  -- Callbacks
  on_change = nil,

  -- Cursor control
  advance = "vertical",

  -- Draw list
  draw_list = nil,
}

-- ============================================================================
-- INTERNAL RENDERING
-- ============================================================================

local function draw_arrow(dl, x, y, w, h, color, direction)
  local cx = (x + w / 2 + 0.5) // 1
  local cy = (y + h / 2 + 0.5) // 1
  local size = (math.min(w, h) * 0.35 + 0.5) // 1

  if direction == "left" then
    local x1 = (cx + size * 0.4 + 0.5) // 1
    local y1 = (cy - size * 0.6 + 0.5) // 1
    local x2 = (cx + size * 0.4 + 0.5) // 1
    local y2 = (cy + size * 0.6 + 0.5) // 1
    local x3 = (cx - size * 0.6 + 0.5) // 1
    local y3 = cy
    ImGui.DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, color)
  else
    local x1 = (cx - size * 0.4 + 0.5) // 1
    local y1 = (cy - size * 0.6 + 0.5) // 1
    local x2 = (cx - size * 0.4 + 0.5) // 1
    local y2 = (cy + size * 0.6 + 0.5) // 1
    local x3 = (cx + size * 0.6 + 0.5) // 1
    local y3 = cy
    ImGui.DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, color)
  end
end

local function draw_spinner_button(ctx, id, x, y, w, h, direction, disabled, hover_alpha)
  local dl = ImGui.GetWindowDrawList(ctx)

  x = (x + 0.5) // 1
  y = (y + 0.5) // 1
  w = (w + 0.5) // 1
  h = (h + 0.5) // 1

  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, id, w, h)

  local hovered = not disabled and ImGui.IsItemHovered(ctx)
  local active = not disabled and ImGui.IsItemActive(ctx)
  local clicked = not disabled and ImGui.IsItemClicked(ctx, 0)

  -- Get state colors with animation
  local bg_color, border_inner, border_outer, arrow_color

  if disabled then
    bg_color = Colors.with_opacity(Style.COLORS.BG_BASE, 0.5)
    border_inner = Colors.with_opacity(Style.COLORS.BORDER_INNER, 0.5)
    border_outer = Colors.with_opacity(Style.COLORS.BORDER_OUTER, 0.5)
    arrow_color = Colors.with_opacity(Style.COLORS.TEXT_NORMAL, 0.5)
  elseif active then
    bg_color = Style.COLORS.BG_ACTIVE
    border_inner = Style.COLORS.BORDER_HOVER
    border_outer = Style.COLORS.BORDER_OUTER
    arrow_color = Style.COLORS.TEXT_HOVER
  elseif hover_alpha > 0.01 then
    bg_color = Style.RENDER.lerp_color(Style.COLORS.BG_BASE, Style.COLORS.BG_HOVER, hover_alpha)
    border_inner = Style.COLORS.BORDER_HOVER
    border_outer = Style.COLORS.BORDER_OUTER
    arrow_color = Style.RENDER.lerp_color(Style.COLORS.TEXT_NORMAL, Style.COLORS.TEXT_HOVER, hover_alpha)
  else
    bg_color = Style.COLORS.BG_BASE
    border_inner = Style.COLORS.BORDER_INNER
    border_outer = Style.COLORS.BORDER_OUTER
    arrow_color = Style.COLORS.TEXT_NORMAL
  end

  -- Background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg_color, 0)

  -- Borders
  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + w - 1, y + h - 1, border_inner, 0, 0, 1)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border_outer, 0, 0, 1)

  -- Arrow
  draw_arrow(dl, x, y, w, h, arrow_color, direction)

  return clicked, hovered, active
end

local function draw_value_display(ctx, dl, x, y, w, h, text, hover_alpha, active, disabled)
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1
  w = (w + 0.5) // 1
  h = (h + 0.5) // 1

  local bg_color, border_inner, border_outer, text_color

  if disabled then
    bg_color = Colors.with_opacity(Style.COLORS.BG_BASE, 0.5)
    border_inner = Colors.with_opacity(Style.COLORS.BORDER_INNER, 0.5)
    border_outer = Colors.with_opacity(Style.COLORS.BORDER_OUTER, 0.5)
    text_color = Colors.with_opacity(Style.COLORS.TEXT_NORMAL, 0.5)
  elseif active then
    bg_color = Style.COLORS.BG_ACTIVE
    border_inner = Style.COLORS.BORDER_HOVER
    border_outer = Style.COLORS.BORDER_OUTER
    text_color = Style.COLORS.TEXT_HOVER
  elseif hover_alpha > 0.01 then
    bg_color = Style.RENDER.lerp_color(Style.COLORS.BG_BASE, Style.COLORS.BG_HOVER, hover_alpha)
    border_inner = Style.COLORS.BORDER_HOVER
    border_outer = Style.COLORS.BORDER_OUTER
    text_color = Style.RENDER.lerp_color(Style.COLORS.TEXT_NORMAL, Style.COLORS.TEXT_HOVER, hover_alpha)
  else
    bg_color = Style.COLORS.BG_BASE
    border_inner = Style.COLORS.BORDER_INNER
    border_outer = Style.COLORS.BORDER_OUTER
    text_color = Style.COLORS.TEXT_NORMAL
  end

  -- Background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg_color, 0)

  -- Borders
  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + w - 1, y + h - 1, border_inner, 0, 0, 1)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border_outer, 0, 0, 1)

  -- Text (centered with truncation)
  local text_w, text_h = ImGui.CalcTextSize(ctx, text)
  local max_text_w = w - 12

  if text_w > max_text_w then
    local est_chars = ((max_text_w / text_w) * #text * 0.9) // 1
    est_chars = math.max(1, math.min(est_chars, #text - 3))
    text = text:sub(1, est_chars) .. "..."
    text_w = ImGui.CalcTextSize(ctx, text)

    while text_w > max_text_w and est_chars > 1 do
      est_chars = est_chars - 1
      text = text:sub(1, est_chars) .. "..."
      text_w = ImGui.CalcTextSize(ctx, text)
    end
  end

  local text_x = (x + (w - text_w) / 2 + 0.5) // 1
  local text_y = (y + (h - text_h) / 2 + 0.5) // 1

  ImGui.DrawList_AddText(dl, text_x, text_y, text_color, text)
end

-- ============================================================================
-- PUBLIC API (Standardized)
-- ============================================================================

--- Draw a spinner widget
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { changed, value, width, height }
function M.draw(ctx, opts)
  opts = Base.parse_opts(opts, DEFAULTS)

  -- Resolve unique ID
  local unique_id = Base.resolve_id(opts, "spinner")

  -- Get instance for animation
  local inst = get_instance(unique_id)

  -- Get position and draw list
  local x, y = Base.get_position(ctx, opts)
  local dl = Base.get_draw_list(ctx, opts)

  -- Get size
  local total_w = opts.width or 200
  local h = opts.height or 24
  local button_w = opts.button_width or 24

  -- Get state
  local current_index = opts.value or 1
  local options = opts.options or {}
  local disabled = opts.disabled or false

  current_index = math.max(1, math.min(current_index, #options))

  local changed = false
  local new_index = current_index

  -- Round starting position
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1

  -- Calculate overlapping layout (arrows extend over value display edges)
  local overlap = (button_w * 0.3 + 0.5) // 1  -- 30% overlap
  local value_w = (total_w - button_w * 2 + overlap * 2 + 0.5) // 1
  local left_x = x
  local value_x = x + button_w - overlap
  local right_x = x + total_w - button_w

  -- Get delta time for animations
  local dt = ImGui.GetDeltaTime(ctx)

  -- Left arrow button
  local left_clicked, left_hovered, left_active = draw_spinner_button(
    ctx, unique_id .. "_left", left_x, y, button_w, h, "left", disabled, inst.left_hover_alpha
  )
  Base.update_hover_animation(inst, dt, left_hovered, left_active, "left_hover_alpha")

  if left_clicked then
    new_index = new_index - 1
    if new_index < 1 then new_index = #options end
    changed = true
  end

  -- Value display with dropdown
  ImGui.SetCursorScreenPos(ctx, value_x, y)
  ImGui.InvisibleButton(ctx, unique_id .. "_value", value_w, h)

  local value_hovered = not disabled and ImGui.IsItemHovered(ctx)
  local value_active = not disabled and ImGui.IsItemActive(ctx)
  local value_clicked = not disabled and ImGui.IsItemClicked(ctx, 0)

  Base.update_hover_animation(inst, dt, value_hovered, value_active, "value_hover_alpha")

  local current_text = tostring(options[current_index] or "")
  draw_value_display(ctx, dl, value_x, y, value_w, h, current_text, inst.value_hover_alpha, value_active, disabled)

  -- Right arrow button
  local right_clicked, right_hovered, right_active = draw_spinner_button(
    ctx, unique_id .. "_right", right_x, y, button_w, h, "right", disabled, inst.right_hover_alpha
  )
  Base.update_hover_animation(inst, dt, right_hovered, right_active, "right_hover_alpha")

  if right_clicked then
    new_index = new_index + 1
    if new_index > #options then new_index = 1 end
    changed = true
  end

  -- Popup dropdown using ContextMenu
  if value_clicked then
    ImGui.OpenPopup(ctx, unique_id .. "_popup")
  end

  local ContextMenu = require('arkitekt.gui.widgets.overlays.context_menu')
  if ContextMenu.begin(ctx, unique_id .. "_popup") then
    for i, value in ipairs(options) do
      local item_text = tostring(value)

      if ContextMenu.item(ctx, item_text) then
        new_index = i
        changed = true
      end
    end
    ContextMenu.end_menu(ctx)
  end

  -- Call change callback
  if changed and opts.on_change then
    opts.on_change(new_index, options[new_index])
  end

  -- Advance cursor
  Base.advance_cursor(ctx, x, y, total_w, h, opts.advance)

  -- Return standardized result
  return Base.create_result({
    changed = changed,
    value = new_index,
    width = total_w,
    height = h,
  })
end

--- Clean up all spinner instances
function M.cleanup()
  Base.cleanup_registry(instances)
end

return M
