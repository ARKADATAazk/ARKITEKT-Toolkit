-- @noindex
-- ReArkitekt/gui/widgets/controls/button.lua
-- Standalone button component with ReArkitekt styling
-- Can be used anywhere, with optional panel integration

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Style = require('arkitekt.gui.style.defaults')
local Colors = require('arkitekt.core.colors')

local M = {}

-- ============================================================================
-- COLOR DERIVATION: HSL-based state colors from base
-- ============================================================================

-- Derive state colors from a base color using HSL adjustments
local function derive_state_color(base, state)
  if state == 'hover' then
    return Colors.adjust_brightness(base, 1.15)
  elseif state == 'active' then
    return Colors.adjust_brightness(base, 0.85)
  elseif state == 'disabled' then
    return Colors.with_alpha(Colors.desaturate(base, 0.5), 0x80)
  end
  return base
end

-- Get colors for current button state (data-driven approach)
local function get_state_colors(config, is_disabled, is_toggled, is_active, hover_alpha)
  if is_disabled then
    return config.bg_disabled_color or derive_state_color(config.bg_color, 'disabled'),
           config.border_inner_disabled_color or derive_state_color(config.border_inner_color, 'disabled'),
           config.border_outer_disabled_color or derive_state_color(config.border_outer_color, 'disabled'),
           config.text_disabled_color or derive_state_color(config.text_color, 'disabled')
  end

  -- Select base colors (toggled or normal)
  local prefix = is_toggled and '_on' or ''
  local bg = config['bg' .. prefix .. '_color'] or config.bg_color
  local border_inner = config['border_inner' .. prefix .. '_color'] or config.border_inner_color
  local border_outer = config['border_outer' .. prefix .. '_color'] or config.border_outer_color
  local text = config['text' .. prefix .. '_color'] or config.text_color

  -- Apply active/hover modulation
  if is_active then
    local active_suffix = prefix .. '_active_color'
    bg = config['bg' .. active_suffix] or derive_state_color(bg, 'active')
    border_inner = config['border' .. (is_toggled and '_on_active_color' or '_active_color')] or derive_state_color(border_inner, 'active')
    text = config['text' .. active_suffix] or text
  elseif hover_alpha > 0.01 then
    local hover_suffix = prefix .. '_hover_color'
    local hover_bg = config['bg' .. hover_suffix] or derive_state_color(bg, 'hover')
    local hover_border = config['border' .. (is_toggled and '_on_hover_color' or '_hover_color')] or derive_state_color(border_inner, 'hover')
    local hover_text = config['text' .. hover_suffix] or text
    bg = Style.RENDER.lerp_color(bg, hover_bg, hover_alpha)
    border_inner = Style.RENDER.lerp_color(border_inner, hover_border, hover_alpha)
    text = Style.RENDER.lerp_color(text, hover_text, hover_alpha)
  end

  return bg, border_inner, border_outer, text
end

-- Resolve config with preset support (shared by draw and measure)
local function resolve_config(user_config)
  local base = Style.BUTTON
  if user_config then
    if user_config.preset_name and Style[user_config.preset_name] then
      base = Style.apply_defaults(base, Style[user_config.preset_name])
    elseif user_config.preset and type(user_config.preset) == 'table' then
      base = Style.apply_defaults(base, user_config.preset)
    end
  end
  return Style.apply_defaults(base, user_config)
end

-- Instance storage for animation state
local instances = {}

-- ============================================================================
-- INSTANCE MANAGEMENT
-- ============================================================================

local Button = {}
Button.__index = Button

function Button.new(id)
  local instance = setmetatable({
    id = id,
    hover_alpha = 0,
  }, Button)
  return instance
end

function Button:update(dt, is_hovered, is_active)
  local target_alpha = (is_hovered or is_active) and 1.0 or 0.0
  local alpha_speed = 12.0
  self.hover_alpha = self.hover_alpha + (target_alpha - self.hover_alpha) * alpha_speed * dt
  self.hover_alpha = math.max(0, math.min(1, self.hover_alpha))
end

local function get_or_create_instance(unique_id)
  if not instances[unique_id] then
    instances[unique_id] = Button.new(unique_id)
  end
  return instances[unique_id]
end

-- ============================================================================
-- CONTEXT DETECTION
-- ============================================================================

local function resolve_context(config, state_or_id)
  local context = {
    unique_id = nil,
    corner_rounding = nil,
    is_panel_context = false,
  }
  
  -- Check if we're in a panel context
  if type(state_or_id) == "table" and state_or_id._panel_id then
    context.is_panel_context = true
    context.unique_id = string.format("%s_%s", state_or_id._panel_id, config.id or "button")
    context.corner_rounding = config.corner_rounding
  else
    -- Standalone context
    context.unique_id = type(state_or_id) == "string" and state_or_id or (config.id or "button")
    context.corner_rounding = nil
  end
  
  return context
end

-- ============================================================================
-- CORNER ROUNDING
-- ============================================================================

--- Converts corner_rounding config to ImGui corner flags.
--- Logic:
---   - nil corner_rounding = standalone button, return 0 (caller handles default)
---   - corner_rounding exists with flags = specific corners rounded
---   - corner_rounding exists with no flags = middle button, explicitly no rounding
--- @param corner_rounding table|nil Corner rounding configuration from layout engine
--- @return integer ImGui DrawFlags for corner rounding
local function get_corner_flags(corner_rounding)
  -- No corner_rounding config = standalone button (not in panel header)
  -- Return 0 so caller can apply default behavior
  if not corner_rounding then
    return 0
  end
  
  -- Panel context: build flags from individual corner settings
  local flags = 0
  if corner_rounding.round_top_left then
    flags = flags | ImGui.DrawFlags_RoundCornersTopLeft
  end
  if corner_rounding.round_top_right then
    flags = flags | ImGui.DrawFlags_RoundCornersTopRight
  end
  if corner_rounding.round_bottom_left then
    flags = flags | ImGui.DrawFlags_RoundCornersBottomLeft
  end
  if corner_rounding.round_bottom_right then
    flags = flags | ImGui.DrawFlags_RoundCornersBottomRight
  end
  
  -- If flags == 0 here, it means we're in panel context but no corners should round
  -- (middle button in a group). Return RoundCornersNone to explicitly disable rounding.
  if flags == 0 then
    return ImGui.DrawFlags_RoundCornersNone
  end
  
  return flags
end

-- ============================================================================
-- RENDERING
-- ============================================================================

local function render_button(ctx, dl, x, y, width, height, config, context, instance)
  local is_disabled = config.is_disabled or false
  local is_hovered = not is_disabled and ImGui.IsMouseHoveringRect(ctx, x, y, x + width, y + height)
  local is_active = not is_disabled and ImGui.IsMouseDown(ctx, 0) and is_hovered
  local is_toggled = config.is_toggled or false

  -- Update animation
  local dt = ImGui.GetDeltaTime(ctx)
  instance:update(dt, is_hovered, is_active)

  -- Get animated colors using data-driven approach
  local bg_color, border_inner, border_outer, text_color =
    get_state_colors(config, is_disabled, is_toggled, is_active, instance.hover_alpha)
  
  -- Calculate rounding
  local rounding = config.rounding or 0
  if context.corner_rounding then
    rounding = context.corner_rounding.rounding or rounding
  end
  local inner_rounding = math.max(0, rounding - 2)
  local corner_flags = get_corner_flags(context.corner_rounding)
  
  -- Draw background
  ImGui.DrawList_AddRectFilled(
    dl, x, y, x + width, y + height,
    bg_color, inner_rounding, corner_flags
  )
  
  -- Draw inner border
  ImGui.DrawList_AddRect(
    dl, x + 1, y + 1, x + width - 1, y + height - 1,
    border_inner, inner_rounding, corner_flags, 1
  )
  
  -- Draw outer border
  ImGui.DrawList_AddRect(
    dl, x, y, x + width, y + height,
    border_outer, inner_rounding, corner_flags, 1
  )
  
  -- Draw content (text or custom)
  local label = config.label or ""
  local icon = config.icon or ""
  local icon_font = config.icon_font
  local icon_size = config.icon_size

  if config.custom_draw then
    config.custom_draw(ctx, dl, x, y, width, height, is_hovered, is_active, text_color)
  elseif icon ~= "" or label ~= "" then
    if icon_font and icon ~= "" then
      -- Icon with separate font + optional label
      ImGui.PushFont(ctx, icon_font, icon_size or 16)
      local icon_w, icon_h = ImGui.CalcTextSize(ctx, icon), ImGui.GetTextLineHeight(ctx)
      ImGui.PopFont(ctx)

      local label_w = label ~= "" and ImGui.CalcTextSize(ctx, label) or 0
      local spacing = (label ~= "") and 4 or 0
      local start_x = x + (width - icon_w - spacing - label_w) * 0.5

      ImGui.PushFont(ctx, icon_font, icon_size or 16)
      ImGui.DrawList_AddText(dl, start_x, y + (height - icon_h) * 0.5, text_color, icon)
      ImGui.PopFont(ctx)

      if label ~= "" then
        local label_h = ImGui.GetTextLineHeight(ctx)
        ImGui.DrawList_AddText(dl, start_x + icon_w + spacing, y + (height - label_h) * 0.5, text_color, label)
      end
    else
      -- Simple text
      local display_text = icon .. (icon ~= "" and label ~= "" and " " or "") .. label
      local text_w = ImGui.CalcTextSize(ctx, display_text)
      ImGui.DrawList_AddText(dl, x + (width - text_w) * 0.5, y + (height - ImGui.GetTextLineHeight(ctx)) * 0.5, text_color, display_text)
    end
  end
  
  return is_hovered, is_active
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function M.draw(ctx, dl, x, y, width, height, user_config, state_or_id)
  local config = resolve_config(user_config)
  
  -- Resolve context (panel vs standalone)
  local context = resolve_context(config, state_or_id)
  
  -- Get or create instance for animation
  local instance = get_or_create_instance(context.unique_id)

  -- Render button (gets hover state internally)
  local is_hovered, is_active = render_button(ctx, dl, x, y, width, height, config, context, instance)
  
  -- Create invisible button for interaction (unless disabled)
  ImGui.SetCursorScreenPos(ctx, x, y)
  ImGui.InvisibleButton(ctx, "##" .. context.unique_id, width, height)

  local clicked = not config.is_disabled and ImGui.IsItemClicked(ctx, 0)
  local right_clicked = not config.is_disabled and ImGui.IsItemClicked(ctx, 1)

  -- Handle click callbacks
  if clicked and config.on_click then
    config.on_click()
  end

  if right_clicked and config.on_right_click then
    config.on_right_click()
  end
  
  -- Handle tooltip (use IsItemHovered which respects popup layering)
  if ImGui.IsItemHovered(ctx) and config.tooltip then
    ImGui.SetTooltip(ctx, config.tooltip)
  end
  
  return width, clicked
end

function M.measure(ctx, user_config)
  local config = resolve_config(user_config)
  
  -- Fixed width?
  if config.width then
    return config.width
  end
  
  -- Calculate from text
  local label = config.label or ""
  local icon = config.icon or ""
  local display_text = icon .. (icon ~= "" and label ~= "" and " " or "") .. label
  
  local text_w = ImGui.CalcTextSize(ctx, display_text)
  local padding = config.padding_x or 10
  
  return text_w + padding * 2
end

-- ============================================================================
-- CONVENIENCE FUNCTION (Cursor-based)
-- ============================================================================

--- Draw button at current cursor position with configurable cursor advancement
--- @param ctx userdata ImGui context
--- @param user_config table|nil Button configuration
--- @param id string|nil Unique identifier
--- @param advance string|nil Cursor advancement direction: "horizontal" (default), "vertical", or "none"
--- @return boolean clicked True if button was clicked
function M.draw_at_cursor(ctx, user_config, id, advance)
  id = id or (user_config and user_config.id) or "button"
  advance = advance or "horizontal"  -- Default to horizontal for backward compatibility

  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  local width = M.measure(ctx, user_config)
  local height = user_config and user_config.height or 24

  local used_width, clicked = M.draw(ctx, dl, cursor_x, cursor_y, width, height, user_config, id)

  -- Advance cursor based on direction
  if advance == "horizontal" then
    ImGui.SetCursorScreenPos(ctx, cursor_x + used_width, cursor_y)
  elseif advance == "vertical" then
    ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + height)
  end
  -- "none" = don't advance cursor (caller manages it)

  return clicked
end

return M