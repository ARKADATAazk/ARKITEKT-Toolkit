-- @noindex
-- arkitekt/gui/widgets/primitives/corner_button.lua
-- Standardized corner-shaped button with asymmetric rounding
-- Uses unified opts-based API

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Style = require('arkitekt.gui.style')
local Colors = require('arkitekt.core.colors')
local Base = require('arkitekt.gui.widgets.base')

local M = {}

-- ============================================================================
-- DEFAULTS
-- ============================================================================

local DEFAULTS = {
  -- Identity
  id = "corner_button",

  -- Position (nil = use cursor)
  x = nil,
  y = nil,

  -- Size
  size = 24,

  -- Corner position and rounding
  position = "tl",        -- Corner position: "tl", "tr", "bl", "br"
  outer_rounding = 0,     -- Rounding for outer corner
  inner_rounding = 0,     -- Rounding for inner corner

  -- Content
  label = "",
  icon = "",

  -- State
  disabled = false,
  is_blocking = false,

  -- Colors (nil = use Style.BUTTON defaults)
  bg_color = nil,
  bg_hover_color = nil,
  bg_active_color = nil,
  bg_disabled_color = nil,
  border_inner_color = nil,
  border_hover_color = nil,
  border_active_color = nil,
  border_outer_color = nil,
  text_color = nil,
  text_hover_color = nil,
  text_active_color = nil,
  text_disabled_color = nil,

  -- Callbacks
  on_click = nil,
  tooltip = nil,

  -- Custom rendering
  custom_draw = nil,

  -- Cursor control
  advance = "vertical",

  -- Draw list
  draw_list = nil,
}

-- ============================================================================
-- INSTANCE MANAGEMENT (strong tables with access tracking for cleanup)
-- ============================================================================

local instances = Base.create_instance_registry()

local function create_corner_button_instance(id)
  return { hover_alpha = 0 }
end

local function get_instance(id)
  return Base.get_or_create_instance(instances, id, create_corner_button_instance)
end

-- ============================================================================
-- RENDERING HELPERS
-- ============================================================================

local function snap_pixel(v)
  return (v + 0.5) // 1
end

local function draw_rounded_rect_path(dl, x1, y1, x2, y2, color, filled, rt, rr, rb, rl, thickness)
  x1 = snap_pixel(x1)
  y1 = snap_pixel(y1)
  x2 = snap_pixel(x2)
  y2 = snap_pixel(y2)

  if not filled and thickness == 1 then
    x1 = x1 + 0.5
    y1 = y1 + 0.5
    x2 = x2 - 0.5
    y2 = y2 - 0.5
  end

  local w = x2 - x1
  local h = y2 - y1
  local max_r = math.min(w, h) * 0.5
  rt = math.min(rt or 0, max_r)
  rr = math.min(rr or 0, max_r)
  rb = math.min(rb or 0, max_r)
  rl = math.min(rl or 0, max_r)

  local function segs(r)
    if r <= 0 then return 0 end
    return math.max(4, (r * 0.6) // 1)
  end

  ImGui.DrawList_PathClear(dl)

  if rt > 0 then
    ImGui.DrawList_PathArcTo(dl, x1 + rt, y1 + rt, rt, math.pi, math.pi * 1.5, segs(rt))
  else
    ImGui.DrawList_PathLineTo(dl, x1, y1)
  end

  if rr > 0 then
    ImGui.DrawList_PathArcTo(dl, x2 - rr, y1 + rr, rr, math.pi * 1.5, math.pi * 2.0, segs(rr))
  else
    ImGui.DrawList_PathLineTo(dl, x2, y1)
  end

  if rb > 0 then
    ImGui.DrawList_PathArcTo(dl, x2 - rb, y2 - rb, rb, 0, math.pi * 0.5, segs(rb))
  else
    ImGui.DrawList_PathLineTo(dl, x2, y2)
  end

  if rl > 0 then
    ImGui.DrawList_PathArcTo(dl, x1 + rl, y2 - rl, rl, math.pi * 0.5, math.pi, segs(rl))
  else
    ImGui.DrawList_PathLineTo(dl, x1, y2)
  end

  if filled then
    ImGui.DrawList_PathFillConvex(dl, color)
  else
    ImGui.DrawList_PathStroke(dl, color, ImGui.DrawFlags_Closed, thickness or 1)
  end
end

local function draw_corner_shape(dl, x, y, size, bg, border_inner, border_outer, outer_rounding, inner_rounding, position)
  local rtl, rtr, rbr, rbl = 0, 0, 0, 0
  if position == 'tl' then
    rtl = outer_rounding; rbr = inner_rounding
  elseif position == 'tr' then
    rtr = outer_rounding; rbl = inner_rounding
  elseif position == 'bl' then
    rbl = outer_rounding; rtr = inner_rounding
  elseif position == 'br' then
    rbr = outer_rounding; rtl = inner_rounding
  end

  local itl = math.max(0, rtl - 2)
  local itr = math.max(0, rtr - 2)
  local ibr = math.max(0, rbr - 2)
  local ibl = math.max(0, rbl - 2)

  draw_rounded_rect_path(dl, x, y, x + size, y + size, bg, true, itl, itr, ibr, ibl)
  draw_rounded_rect_path(dl, x + 1, y + 1, x + size - 1, y + size - 1, border_inner, false, itl, itr, ibr, ibl, 1)
  draw_rounded_rect_path(dl, x, y, x + size, y + size, border_outer, false, itl, itr, ibr, ibl, 1)
end

-- ============================================================================
-- PUBLIC API (Standardized)
-- ============================================================================

--- Draw a corner button widget
--- @param ctx userdata ImGui context
--- @param opts table Widget options
--- @return table Result { clicked, width, height, hovered, active }
function M.draw(ctx, opts)
  opts = Base.parse_opts(opts, DEFAULTS)
  -- Build config dynamically from Style.COLORS (enables dynamic theming)
  local config = Style.build_button_config()
  -- Apply dynamic preset if specified
  if opts.preset_name then
    Style.apply_dynamic_preset(config, opts.preset_name)
  end
  -- Apply user overrides (copy ALL opts, not just color keys)
  for k, v in pairs(opts) do
    if v ~= nil then
      config[k] = v
    end
  end

  -- Resolve unique ID
  local unique_id = Base.resolve_id(opts, "corner_button")

  -- Get instance for animation
  local inst = get_instance(unique_id)

  -- Get position and draw list
  local x, y = Base.get_position(ctx, opts)
  local dl = Base.get_draw_list(ctx, opts)

  -- Get size
  local size = opts.size or 24

  -- Get state
  local disabled = opts.disabled or false
  local is_blocking = opts.is_blocking or false

  local hovered = false
  local active = false

  if not disabled and not is_blocking then
    local mx, my = ImGui.GetMousePos(ctx)
    hovered = mx >= x and mx < x + size and my >= y and my < y + size
    active = hovered and ImGui.IsMouseDown(ctx, 0)
  end

  -- Update animation
  local dt = ImGui.GetDeltaTime(ctx)
  local target = (hovered or active) and 1.0 or 0.0

  if is_blocking or disabled then
    inst.hover_alpha = 0
  else
    inst.hover_alpha = inst.hover_alpha + (target - inst.hover_alpha) * 12.0 * dt
    inst.hover_alpha = math.max(0, math.min(1, inst.hover_alpha))
  end

  -- Calculate colors
  local bg, border_inner, text

  if disabled then
    bg = config.bg_disabled_color or Colors.with_opacity(Colors.desaturate(config.bg_color, 0.5), 0.5)
    border_inner = Colors.with_opacity(Colors.desaturate(config.border_inner_color, 0.5), 0.5)
    text = config.text_disabled_color or Colors.with_opacity(Colors.desaturate(config.text_color, 0.5), 0.5)
  elseif active then
    bg = config.bg_active_color or config.bg_color
    border_inner = config.border_active_color or config.border_inner_color
    text = config.text_active_color or config.text_color
  elseif inst.hover_alpha > 0.01 then
    bg = Style.RENDER.lerp_color(config.bg_color, config.bg_hover_color or config.bg_color, inst.hover_alpha)
    border_inner = Style.RENDER.lerp_color(config.border_inner_color, config.border_hover_color or config.border_inner_color, inst.hover_alpha)
    text = Style.RENDER.lerp_color(config.text_color, config.text_hover_color or config.text_color, inst.hover_alpha)
  else
    bg = config.bg_color
    border_inner = config.border_inner_color
    text = config.text_color
  end

  -- Draw button visuals
  draw_corner_shape(dl, x, y, size, bg, border_inner, config.border_outer_color,
                    opts.outer_rounding, opts.inner_rounding, opts.position)

  -- Draw content
  if config.custom_draw then
    config.custom_draw(ctx, dl, x, y, size, size, hovered, active, text)
  else
    local label = config.icon or config.label or ''
    if label ~= '' then
      local tw, th = ImGui.CalcTextSize(ctx, label)
      local tx = x + (size - tw) * 0.5
      local ty = y + (size - th) * 0.5
      ImGui.DrawList_AddText(dl, tx, ty, text, label)
    end
  end

  -- Create interaction area
  local clicked = false
  if not is_blocking and not disabled then
    ImGui.SetCursorScreenPos(ctx, x, y)
    ImGui.InvisibleButton(ctx, '##' .. unique_id, size, size)
    clicked = ImGui.IsItemClicked(ctx, 0)

    if clicked and config.on_click then
      config.on_click()
    end

    -- Handle tooltip
    if hovered and config.tooltip then
      ImGui.SetTooltip(ctx, config.tooltip)
    end
  end

  -- Advance cursor
  Base.advance_cursor(ctx, x, y, size, size, opts.advance)

  -- Return standardized result
  return Base.create_result({
    clicked = clicked,
    width = size,
    height = size,
    hovered = hovered,
    active = active,
  })
end

--- Clean up all corner button instances
function M.cleanup()
  Base.cleanup_registry(instances)
end

return M
