-- @noindex
-- arkitekt/gui/widgets/primitives/slider.lua
-- Standardized slider widget with Arkitekt styling
-- Uses unified opts-based API with double-click to reset

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Style = require('arkitekt.gui.style')
local Colors = require('arkitekt.core.colors')
local Base = require('arkitekt.gui.widgets.base')

local hexrgb = Colors.hexrgb

local M = {}

-- ============================================================================
-- DEFAULTS
-- ============================================================================

local DEFAULTS = {
  -- Identity
  id = "slider",

  -- Position (nil = use cursor)
  x = nil,
  y = nil,

  -- Size
  width = 200,
  height = 20,
  grab_width = 13,

  -- Value
  value = 0,
  min = 0,
  max = 100,
  default = nil,  -- Value to reset to on double-click
  step = nil,     -- Step for keyboard control (default: range/100)

  -- State
  disabled = false,

  -- Style
  rounding = 0,
  bg_color = nil,
  grab_color = nil,
  grab_hover_color = nil,
  grab_active_color = nil,
  border_color = nil,

  -- Content
  gradient_fn = nil,   -- Custom gradient rendering function
  tooltip_fn = nil,    -- Custom tooltip function
  format = "%.1f",     -- Value format string

  -- Callbacks
  on_change = nil,
  tooltip = nil,

  -- Cursor control
  advance = "vertical",

  -- Draw list
  draw_list = nil,
}

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

local slider_locks = {}  -- Prevents double-click interference with drag

-- ============================================================================
-- RENDERING HELPERS
-- ============================================================================

local function render_slider_background(dl, x, y, w, h, config, gradient_fn)
  local bg_color = config.bg_color or hexrgb("#1A1A1A")
  local border_color = config.border_color or hexrgb("#000000")

  -- Background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg_color, config.rounding or 0)

  -- Custom gradient if provided
  if gradient_fn then
    gradient_fn(dl, x + 1, y + 1, x + w - 1, y + h - 1, config)
  end

  -- Border
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border_color, config.rounding or 0, 0, 1)
end

local function render_grab(dl, gx, y, h, grab_w, active, hovered, disabled, config)
  local x_left = Base.snap_pixel(gx - grab_w / 2)
  local x_right = Base.snap_pixel(gx + grab_w / 2)

  -- Determine grab color
  local grab_color
  if disabled then
    grab_color = Colors.with_opacity(Colors.desaturate(config.grab_color or hexrgb("#383C45"), 0.5), 0.5)
  elseif active then
    grab_color = config.grab_active_color or hexrgb("#585C65")
  elseif hovered then
    grab_color = config.grab_hover_color or hexrgb("#484C55")
  else
    grab_color = config.grab_color or hexrgb("#383C45")
  end

  -- Shadow
  if not disabled then
    ImGui.DrawList_AddRectFilled(dl, x_left + 1, y + 1, x_right + 1, y + h + 1,
      hexrgb("#00000050"), 0)
  end

  -- Grab body
  ImGui.DrawList_AddRectFilled(dl, x_left, y, x_right, y + h, grab_color, 0)

  -- Border
  ImGui.DrawList_AddRect(dl, x_left, y, x_right, y + h, hexrgb("#000000"), 0, 0, 1)
end

-- ============================================================================
-- PUBLIC API (Standardized)
-- ============================================================================

--- Draw a slider widget
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { changed, value, width, height, hovered, active }
function M.draw(ctx, opts)
  opts = Base.parse_opts(opts, DEFAULTS)

  -- Resolve unique ID
  local unique_id = Base.resolve_id(opts, "slider")

  -- Get position and draw list
  local x, y = Base.get_position(ctx, opts)
  local dl = Base.get_draw_list(ctx, opts)

  -- Get size
  local w = opts.width or 200
  local h = opts.height or 20
  local grab_w = opts.grab_width or 13

  -- Get value range
  local min_val = opts.min or 0
  local max_val = opts.max or 100
  local default_val = opts.default or min_val
  local value = Base.clamp(opts.value or default_val, min_val, max_val)

  -- State
  local disabled = opts.disabled or false
  local changed = false

  -- Create invisible button for interaction
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "##" .. unique_id, w, h)

  local hovered = not disabled and ImGui.IsItemHovered(ctx)
  local active = not disabled and ImGui.IsItemActive(ctx)

  -- Check for lock (prevents double-click drag interference)
  local now = ImGui.GetTime(ctx)
  local locked = (slider_locks[unique_id] or 0) > now

  -- Double-click to reset
  if hovered and not locked and ImGui.IsMouseDoubleClicked(ctx, 0) then
    value = default_val
    changed = true
    slider_locks[unique_id] = now + 0.3
  end

  -- Drag to adjust
  if not locked and active and not ImGui.IsMouseDoubleClicked(ctx, 0) then
    local mx = select(1, ImGui.GetMousePos(ctx))
    local t = Base.clamp((mx - x) / w, 0, 1)
    local new_value = min_val + t * (max_val - min_val)
    if math.abs(new_value - value) > 1e-6 then
      value = new_value
      changed = true
    end
  end

  -- Keyboard control
  if not disabled and (ImGui.IsItemFocused(ctx) or active) then
    local step = opts.step or (max_val - min_val) / 100
    if ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow, false) then
      value = Base.clamp(value - step, min_val, max_val)
      changed = true
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow, false) then
      value = Base.clamp(value + step, min_val, max_val)
      changed = true
    end
  end

  -- Ensure value is clamped
  value = Base.clamp(value, min_val, max_val)

  -- Render slider background
  render_slider_background(dl, x, y, w, h, opts, opts.gradient_fn)

  -- Calculate grab position
  local t = (value - min_val) / (max_val - min_val)
  local gx = Base.clamp(x + t * w, x + grab_w / 2, x + w - grab_w / 2)
  gx = Base.snap_pixel(gx)

  -- Render grab
  render_grab(dl, gx, y, h, grab_w, active, hovered, disabled, opts)

  -- Tooltip
  if hovered then
    local tooltip_text
    if opts.tooltip_fn then
      tooltip_text = opts.tooltip_fn(value)
    elseif opts.tooltip then
      tooltip_text = opts.tooltip
    else
      tooltip_text = string.format(opts.format or "%.1f", value)
    end

    if ImGui.BeginTooltip(ctx) then
      ImGui.Text(ctx, tooltip_text)
      ImGui.EndTooltip(ctx)
    end
  end

  -- Call change callback
  if changed and opts.on_change then
    opts.on_change(value)
  end

  -- Advance cursor
  Base.advance_cursor(ctx, x, y, w, h, opts.advance)

  -- Return standardized result
  return Base.create_result({
    changed = changed,
    value = value,
    width = w,
    height = h,
    hovered = hovered,
    active = active,
  })
end

--- Draw a percentage slider (0-100)
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result
function M.percent(ctx, opts)
  opts = opts or {}
  opts.min = opts.min or 0
  opts.max = opts.max or 100
  opts.format = opts.format or "%.0f%%"
  opts.tooltip_fn = opts.tooltip_fn or function(v)
    return string.format("%.0f%%", v)
  end
  return M.draw(ctx, opts)
end

--- Draw an integer slider
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result
function M.int(ctx, opts)
  opts = opts or {}
  opts.step = opts.step or 1
  opts.format = opts.format or "%.0f"

  local result = M.draw(ctx, opts)
  result.value = (result.value + 0.5) // 1  -- Round to integer
  return result
end

--- Clean up slider state
function M.cleanup()
  for k in pairs(slider_locks) do
    slider_locks[k] = nil
  end
end

return M
