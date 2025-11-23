-- @noindex
-- ReArkitekt/gui/widgets/controls/checkbox.lua
-- Standalone checkbox component with ReArkitekt styling
-- Follows the same design patterns as button.lua

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Style = require('arkitekt.gui.style.defaults')
local Colors = require('arkitekt.core.colors')
local InteractionBlocking = require('arkitekt.gui.utils.interaction_blocking')

local M = {}

-- Instance storage for animation state
local instances = {}

-- ============================================================================
-- INSTANCE MANAGEMENT
-- ============================================================================

local Checkbox = {}
Checkbox.__index = Checkbox

function Checkbox.new(id)
  local instance = setmetatable({
    id = id,
    hover_alpha = 0,
    check_alpha = 0,
  }, Checkbox)
  return instance
end

function Checkbox:update(dt, is_hovered, is_active, is_checked)
  -- Hover animation
  local target_hover = (is_hovered or is_active) and 1.0 or 0.0
  local alpha_speed = 12.0
  self.hover_alpha = self.hover_alpha + (target_hover - self.hover_alpha) * alpha_speed * dt
  self.hover_alpha = math.max(0, math.min(1, self.hover_alpha))

  -- Check animation
  local target_check = is_checked and 1.0 or 0.0
  local check_speed = 15.0
  self.check_alpha = self.check_alpha + (target_check - self.check_alpha) * check_speed * dt
  self.check_alpha = math.max(0, math.min(1, self.check_alpha))
end

local function get_or_create_instance(unique_id)
  if not instances[unique_id] then
    instances[unique_id] = Checkbox.new(unique_id)
  end
  return instances[unique_id]
end

-- ============================================================================
-- CHECKBOX STYLE DEFAULTS
-- ============================================================================

local CHECKBOX_DEFAULTS = {
  size = 18,
  rounding = 0,
  alpha = 1.0,  -- Visual alpha for fade animations

  -- OFF state colors (unchecked)
  bg_color = Style.BUTTON_COLORS.bg,
  bg_hover_color = Style.BUTTON_COLORS.bg_hover,
  bg_active_color = Style.BUTTON_COLORS.bg_active,
  border_outer_color = Style.BUTTON_COLORS.border_outer,
  border_inner_color = Style.BUTTON_COLORS.border_inner,
  border_hover_color = Style.BUTTON_COLORS.border_hover,
  border_active_color = Style.BUTTON_COLORS.border_active,

  -- ON state colors (checked) - using teal variant
  bg_on_color = Style.BUTTON_COLORS.toggle_teal.bg_on,
  bg_on_hover_color = Style.BUTTON_COLORS.toggle_teal.bg_on_hover,
  bg_on_active_color = Style.BUTTON_COLORS.toggle_teal.bg_on_active,
  border_outer_on_color = Style.BUTTON_COLORS.border_outer,
  border_inner_on_color = Style.BUTTON_COLORS.toggle_teal.border_inner_on,
  border_on_hover_color = Style.BUTTON_COLORS.toggle_teal.border_inner_on_hover,
  border_on_active_color = Style.BUTTON_COLORS.toggle_teal.border_inner_on_active,

  -- Checkmark color
  check_color = Style.BUTTON_COLORS.toggle_teal.text_on,

  -- Label styling
  label_spacing = 8,
  label_color = Style.COLORS.TEXT_NORMAL,
  label_hover_color = Style.COLORS.TEXT_HOVER,
}

-- ============================================================================
-- RENDERING
-- ============================================================================

local function render_checkbox(ctx, dl, x, y, config, instance, is_checked)
  local size = config.size
  local is_hovered = InteractionBlocking.is_mouse_hovering_rect_unblocked(ctx, x, y, x + size, y + size, config.is_blocking)
  local is_active = ImGui.IsMouseDown(ctx, 0) and is_hovered

  -- Update animation
  local dt = ImGui.GetDeltaTime(ctx)
  instance:update(dt, is_hovered, is_active, is_checked)

  -- Interpolate between unchecked and checked states
  local bg_color, border_inner, border_outer

  if is_checked or instance.check_alpha > 0.01 then
    -- Checked or animating to checked
    local base_bg = is_active and config.bg_on_active_color or
                    (instance.hover_alpha > 0.01 and
                      Style.RENDER.lerp_color(config.bg_on_color, config.bg_on_hover_color, instance.hover_alpha) or
                      config.bg_on_color)
    local base_border = is_active and config.border_on_active_color or
                        (instance.hover_alpha > 0.01 and
                          Style.RENDER.lerp_color(config.border_inner_on_color, config.border_on_hover_color, instance.hover_alpha) or
                          config.border_inner_on_color)

    -- Blend with unchecked colors if animating
    if instance.check_alpha < 0.99 then
      local unchecked_bg = is_active and config.bg_active_color or
                           (instance.hover_alpha > 0.01 and
                             Style.RENDER.lerp_color(config.bg_color, config.bg_hover_color, instance.hover_alpha) or
                             config.bg_color)
      local unchecked_border = is_active and config.border_active_color or
                               (instance.hover_alpha > 0.01 and
                                 Style.RENDER.lerp_color(config.border_inner_color, config.border_hover_color, instance.hover_alpha) or
                                 config.border_inner_color)

      bg_color = Style.RENDER.lerp_color(unchecked_bg, base_bg, instance.check_alpha)
      border_inner = Style.RENDER.lerp_color(unchecked_border, base_border, instance.check_alpha)
    else
      bg_color = base_bg
      border_inner = base_border
    end

    border_outer = config.border_outer_on_color
  else
    -- Unchecked
    bg_color = is_active and config.bg_active_color or
               (instance.hover_alpha > 0.01 and
                 Style.RENDER.lerp_color(config.bg_color, config.bg_hover_color, instance.hover_alpha) or
                 config.bg_color)
    border_inner = is_active and config.border_active_color or
                   (instance.hover_alpha > 0.01 and
                     Style.RENDER.lerp_color(config.border_inner_color, config.border_hover_color, instance.hover_alpha) or
                     config.border_inner_color)
    border_outer = config.border_outer_color
  end

  local rounding = config.rounding or 0
  local inner_rounding = math.max(0, rounding - 2)

  -- Apply alpha to all colors for fade animation support
  local visual_alpha = config.alpha or 1.0
  bg_color = Colors.with_alpha(bg_color, math.floor(((bg_color & 0xFF) / 255) * visual_alpha * 255))
  border_inner = Colors.with_alpha(border_inner, math.floor(((border_inner & 0xFF) / 255) * visual_alpha * 255))
  border_outer = Colors.with_alpha(border_outer, math.floor(((border_outer & 0xFF) / 255) * visual_alpha * 255))

  -- Draw background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + size, y + size, bg_color, inner_rounding)

  -- Draw inner border
  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + size - 1, y + size - 1, border_inner, inner_rounding, 0, 1)

  -- Draw outer border
  ImGui.DrawList_AddRect(dl, x, y, x + size, y + size, border_outer, inner_rounding, 0, 1)

  -- Draw checkmark
  if instance.check_alpha > 0.01 then
    local check_color = Colors.with_alpha(config.check_color, math.floor(instance.check_alpha * visual_alpha * 255))
    local padding = size * 0.25
    local check_size = size - padding * 2

    -- Simple checkmark path
    local cx = x + padding
    local cy = y + size * 0.5
    local mx = cx + check_size * 0.3
    local my = cy + check_size * 0.3
    local ex = cx + check_size
    local ey = cy - check_size * 0.4

    ImGui.DrawList_AddLine(dl, cx, cy, mx, my, check_color, 2)
    ImGui.DrawList_AddLine(dl, mx, my, ex, ey, check_color, 2)
  end

  return is_hovered, is_active
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Draw a checkbox at specific coordinates
--- Supports two calling conventions:
--- 1. Panel header context: M.draw(ctx, dl, x, y, width, height, config, state)
--- 2. Standalone context: M.draw(ctx, dl, x, y, label, is_checked, user_config, id)
--- @param ctx ImGui context
--- @param dl ImGui draw list
--- @param x number X coordinate
--- @param y number Y coordinate
--- @param param5 number|string Width (panel) or label (standalone)
--- @param param6 number|boolean Height (panel) or is_checked (standalone)
--- @param param7 table|nil Config
--- @param param8 table|string State (panel) or id (standalone)
--- @return number total_width Total width used (checkbox + label)
--- @return boolean clicked True if checkbox was clicked
function M.draw(ctx, dl, x, y, param5, param6, param7, param8)
  local label, is_checked, config, id, instance, state

  -- Detect calling convention
  if type(param5) == "number" and type(param6) == "number" then
    -- Panel header context: (ctx, dl, x, y, width, height, config, state)
    local width, height = param5, param6
    config = Style.apply_defaults(CHECKBOX_DEFAULTS, param7)
    state = param8

    -- Extract checkbox-specific params from config
    label = config.label or ""
    id = config.id or "checkbox"

    -- Get checked state from element_state or config
    if state and state.checkbox_value ~= nil then
      is_checked = state.checkbox_value
    elseif config.checked ~= nil then
      is_checked = config.checked
    else
      is_checked = false
    end

    -- Create unique ID for panel context
    if type(state) == "table" and state._panel_id then
      id = string.format("%s_%s", state._panel_id, id)
    end

    instance = get_or_create_instance(id)
  else
    -- Standalone context: (ctx, dl, x, y, label, is_checked, user_config, id)
    label = param5
    is_checked = param6
    local user_config = param7
    id = param8
    config = Style.apply_defaults(CHECKBOX_DEFAULTS, user_config)
    instance = get_or_create_instance(id)
  end

  -- Render checkbox box
  local is_hovered, is_active = render_checkbox(ctx, dl, x, y, config, instance, is_checked)

  -- Render label
  local total_width = config.size
  if label and label ~= "" then
    local label_x = x + config.size + config.label_spacing
    local label_y = y + (config.size - ImGui.GetTextLineHeight(ctx)) * 0.5

    local label_color = instance.hover_alpha > 0.01 and
                        Style.RENDER.lerp_color(config.label_color, config.label_hover_color, instance.hover_alpha) or
                        config.label_color

    -- Apply visual alpha to label
    local visual_alpha = config.alpha or 1.0
    label_color = Colors.with_alpha(label_color, math.floor(((label_color & 0xFF) / 255) * visual_alpha * 255))

    ImGui.DrawList_AddText(dl, label_x, label_y, label_color, label)

    local label_width = ImGui.CalcTextSize(ctx, label)
    total_width = config.size + config.label_spacing + label_width
  end

  -- Create invisible button for interaction
  ImGui.SetCursorScreenPos(ctx, x, y)
  local button_pressed = ImGui.InvisibleButton(ctx, "##" .. id, total_width, config.size)

  local clicked = ImGui.IsItemClicked(ctx, 0)

  -- Handle interaction
  if clicked then
    local new_value = not is_checked

    -- Panel context: Update state and call callback
    if state then
      state.checkbox_value = new_value
      if config.on_change then
        config.on_change(new_value)
      end
    end
  end

  -- Handle tooltip
  if is_hovered and config.tooltip then
    ImGui.SetTooltip(ctx, config.tooltip)
  end

  return total_width, clicked
end

--- Convenience function to draw checkbox at cursor position
--- @param ctx ImGui context
--- @param label string Checkbox label text
--- @param is_checked boolean Current checked state
--- @param user_config table|nil Optional configuration overrides
--- @param id string Unique identifier for this checkbox
--- @param advance string|nil Cursor advancement direction: "horizontal" (default), "vertical", or "none"
--- @return boolean clicked True if checkbox was clicked
function M.draw_at_cursor(ctx, label, is_checked, user_config, id, advance)
  advance = advance or "horizontal"  -- Default to horizontal for backward compatibility

  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  local config = Style.apply_defaults(CHECKBOX_DEFAULTS, user_config)
  local total_width, clicked = M.draw(ctx, dl, cursor_x, cursor_y, label, is_checked, user_config, id)

  -- Advance cursor based on direction
  if advance == "horizontal" then
    ImGui.SetCursorScreenPos(ctx, cursor_x + total_width, cursor_y)
  elseif advance == "vertical" then
    local height = config.size
    ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + height)
  end
  -- "none" = don't advance cursor (caller manages it)

  return clicked
end

return M
