-- @noindex
-- ReArkitekt/gui/fx/interactions/dnd.lua
-- Unified drag-and-drop visual system
-- Merged from dnd/config.lua, dnd/drag_indicator.lua, and dnd/drop_indicator.lua

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Draw = require('arkitekt.gui.draw')
local Colors = require('arkitekt.core.colors')
local ColorDefs = require('arkitekt.defs.colors')
local hexrgb = Colors.hexrgb

-- Cache math functions for performance
local sin, min, max = math.sin, math.min, math.max

local M = {}

-- Get operation colors from centralized definitions
local OP = ColorDefs.OPERATIONS

-- =============================================================================
-- CONFIGURATION
-- Centralized configuration for drag and drop visual indicators
-- =============================================================================

-- Extract base hex (without alpha) for glow colors
local function base_hex(hex)
  return hex:sub(1, 7)
end

M.MODES = {
  move = {
    stroke_color = hexrgb(OP.move),
    glow_color = hexrgb(base_hex(OP.move) .. "33"),
    badge_accent = hexrgb(OP.move),
  },
  copy = {
    stroke_color = hexrgb(OP.copy),
    glow_color = hexrgb(base_hex(OP.copy) .. "33"),
    badge_accent = hexrgb(OP.copy),
    indicator_text = "+",
    indicator_color = hexrgb(OP.copy),
  },
  delete = {
    stroke_color = hexrgb(OP.delete),
    glow_color = hexrgb(base_hex(OP.delete) .. "33"),
    badge_accent = hexrgb(OP.delete),
    indicator_text = "-",
    indicator_color = hexrgb(OP.delete),
  },
}

M.TILE_DEFAULTS = {
  width = 60,
  height = 40,
  base_fill = hexrgb("#1A1A1A"),
  stroke_thickness = 1.5,
  rounding = 4,
  global_opacity = 0.70,
}

M.STACK_DEFAULTS = {
  max_visible = 3,
  offset_x = 3,
  offset_y = 3,
  scale_factor = 0.94,
  opacity_falloff = 0.70,
}

M.BADGE_DEFAULTS = {
  bg = hexrgb("#1A1A1AEE"),
  border_color = hexrgb("#00000099"),
  border_thickness = 1,
  rounding = 6,
  padding_x = 6,
  padding_y = 3,
  offset_x = 35,
  offset_y = -35,
  min_width = 20,
  min_height = 18,
}

M.DROP_DEFAULTS = {
  line_width = 2,
  glow_width = 12,
  pulse_speed = 2.5,
  caps = {
    width = 12,
    height = 3,
    rounding = 0,
    glow_size = 6,
  },
}

M.SHADOW_DEFAULTS = {
  enabled = false,
  layers = 2,
  base_color = hexrgb("#00000044"),
  offset = 2,
  blur_spread = 1.0,
}

M.INNER_GLOW_DEFAULTS = {
  enabled = false,
  color = hexrgb(base_hex(OP.move) .. "22"),
  thickness = 2,
}

function M.get_mode_config(config, is_copy, is_delete)
  local mode_key = is_delete and 'delete' or (is_copy and 'copy' or 'move')
  local mode_cfg = (config and config[mode_key .. '_mode']) or M.MODES[mode_key]
  return mode_cfg
end

-- =============================================================================
-- DRAG INDICATOR
-- Modular drag ghost visualization system
-- =============================================================================

local DragIndicator = {}

local function apply_alpha_factor(color, factor)
  local current_alpha = color & 0xFF
  local new_alpha = (current_alpha * factor)//1
  return Colors.with_alpha(color, min(255, max(0, new_alpha)))
end

local function draw_shadow(dl, x1, y1, x2, y2, rounding, config)
  if not config or not config.enabled then return end

  local shadow_cfg = config or M.SHADOW_DEFAULTS
  local layers = shadow_cfg.layers or M.SHADOW_DEFAULTS.layers
  local base_color = shadow_cfg.base_color or M.SHADOW_DEFAULTS.base_color
  local offset = shadow_cfg.offset or M.SHADOW_DEFAULTS.offset
  local blur_spread = shadow_cfg.blur_spread or M.SHADOW_DEFAULTS.blur_spread

  local base_alpha = base_color & 0xFF

  for i = layers, 1, -1 do
    local t = i / layers
    local o = offset * t
    local spread = blur_spread * t
    local alpha = (base_alpha * (1 - t * 0.5))//1
    local color = (base_color & 0xFFFFFF00) | alpha

    ImGui.DrawList_AddRectFilled(dl,
      x1 + o - spread, y1 + o - spread,
      x2 + o + spread, y2 + o + spread,
      color, rounding)
  end
end

local function draw_tile(dl, x, y, w, h, fill, stroke, thickness, rounding, inner_glow_cfg)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, fill, rounding)

  if inner_glow_cfg and inner_glow_cfg.enabled then
    local glow_color = inner_glow_cfg.color or M.INNER_GLOW_DEFAULTS.color
    local glow_thick = inner_glow_cfg.thickness or M.INNER_GLOW_DEFAULTS.thickness

    for i = 1, glow_thick do
      local inset = i
      ImGui.DrawList_AddRect(dl, x + inset, y + inset, x + w - inset, y + h - inset,
                            glow_color, rounding - inset, 0, 1)
    end
  end

  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, stroke, rounding, 0, thickness)
end

local function draw_copy_indicator(ctx, dl, mx, my, config)
  local copy_cfg = (config and config.copy_mode) or M.MODES.copy
  local indicator_text = copy_cfg.indicator_text or M.MODES.copy.indicator_text
  local indicator_color = copy_cfg.indicator_color or M.MODES.copy.indicator_color

  local size = 24
  local ix = mx - size - 20
  local iy = my - size / 2

  ImGui.DrawList_AddCircleFilled(dl, ix + size/2, iy + size/2, size/2, hexrgb("#1A1A1AEE"))
  ImGui.DrawList_AddCircle(dl, ix + size/2, iy + size/2, size/2, indicator_color, 0, 2)

  local tw, th = ImGui.CalcTextSize(ctx, indicator_text)
  Draw.text(dl, ix + (size - tw)/2, iy + (size - th)/2, indicator_color, indicator_text)
end

local function draw_delete_indicator(ctx, dl, mx, my, config)
  local delete_cfg = (config and config.delete_mode) or M.MODES.delete
  local indicator_text = delete_cfg.indicator_text or M.MODES.delete.indicator_text
  local indicator_color = delete_cfg.indicator_color or M.MODES.delete.indicator_color

  local size = 24
  local ix = mx - size - 20
  local iy = my - size / 2

  ImGui.DrawList_AddCircleFilled(dl, ix + size/2, iy + size/2, size/2, hexrgb("#1A1A1AEE"))
  ImGui.DrawList_AddCircle(dl, ix + size/2, iy + size/2, size/2, indicator_color, 0, 2)

  local tw, th = ImGui.CalcTextSize(ctx, indicator_text)
  Draw.text(dl, ix + (size - tw)/2, iy + (size - th)/2, indicator_color, indicator_text)
end

function DragIndicator.draw_badge(ctx, dl, mx, my, count, config, is_copy_mode, is_delete_mode)
  if count <= 1 then return end

  local cfg = config or M.BADGE_DEFAULTS
  local mode_cfg = M.get_mode_config(config, is_copy_mode, is_delete_mode)

  local label = tostring(count)
  local tw, th = ImGui.CalcTextSize(ctx, label)

  local pad_x = cfg.padding_x or M.BADGE_DEFAULTS.padding_x
  local pad_y = cfg.padding_y or M.BADGE_DEFAULTS.padding_y
  local min_w = cfg.min_width or M.BADGE_DEFAULTS.min_width
  local min_h = cfg.min_height or M.BADGE_DEFAULTS.min_height
  local offset_x = cfg.offset_x or M.BADGE_DEFAULTS.offset_x
  local offset_y = cfg.offset_y or M.BADGE_DEFAULTS.offset_y

  local badge_w = max(min_w, tw + pad_x * 2)
  local badge_h = max(min_h, th + pad_y * 2)

  local bx = mx + offset_x
  local by = my + offset_y

  local rounding = cfg.rounding or M.BADGE_DEFAULTS.rounding

  if cfg.shadow and cfg.shadow.enabled then
    local shadow_offset = cfg.shadow.offset or 2
    local shadow_color = cfg.shadow.color or hexrgb("#00000099")
    ImGui.DrawList_AddRectFilled(dl,
      bx + shadow_offset, by + shadow_offset,
      bx + badge_w + shadow_offset, by + badge_h + shadow_offset,
      shadow_color, rounding)
  end

  local bg = cfg.bg or M.BADGE_DEFAULTS.bg
  ImGui.DrawList_AddRectFilled(dl, bx, by, bx + badge_w, by + badge_h, bg, rounding)

  local border_color = cfg.border_color or M.BADGE_DEFAULTS.border_color
  local border_thickness = cfg.border_thickness or M.BADGE_DEFAULTS.border_thickness
  ImGui.DrawList_AddRect(dl, bx + 0.5, by + 0.5, bx + badge_w - 0.5, by + badge_h - 0.5,
                        border_color, rounding, 0, border_thickness)

  local accent_color = mode_cfg.badge_accent or M.MODES.move.badge_accent
  local accent_thickness = 2
  ImGui.DrawList_AddRect(dl, bx + 1, by + 1, bx + badge_w - 1, by + badge_h - 1,
                        accent_color, rounding - 1, 0, accent_thickness)

  local text_x = bx + (badge_w - tw) / 2
  local text_y = by + (badge_h - th) / 2
  ImGui.DrawList_AddText(dl, text_x, text_y, accent_color, label)
end

function DragIndicator.draw(ctx, dl, mx, my, count, config, colors, is_copy_mode, is_delete_mode)
  local tile_cfg = (config and config.tile) or M.TILE_DEFAULTS
  local stack_cfg = (config and config.stack) or M.STACK_DEFAULTS
  local shadow_cfg = (config and config.shadow) or M.SHADOW_DEFAULTS

  local mode_cfg = M.get_mode_config(config, is_copy_mode, is_delete_mode)

  local base_w = tile_cfg.width or M.TILE_DEFAULTS.width
  local base_h = tile_cfg.height or M.TILE_DEFAULTS.height
  local base_fill = tile_cfg.base_fill or M.TILE_DEFAULTS.base_fill
  local base_stroke = mode_cfg.stroke_color or M.MODES.move.stroke_color
  local thickness = tile_cfg.stroke_thickness or M.TILE_DEFAULTS.stroke_thickness
  local rounding = tile_cfg.rounding or M.TILE_DEFAULTS.rounding
  local inner_glow = tile_cfg.inner_glow or M.INNER_GLOW_DEFAULTS
  local global_opacity = tile_cfg.global_opacity or M.TILE_DEFAULTS.global_opacity

  local max_visible = stack_cfg.max_visible or M.STACK_DEFAULTS.max_visible
  local offset_x = stack_cfg.offset_x or M.STACK_DEFAULTS.offset_x
  local offset_y = stack_cfg.offset_y or M.STACK_DEFAULTS.offset_y
  local scale_factor = stack_cfg.scale_factor or M.STACK_DEFAULTS.scale_factor
  local opacity_falloff = stack_cfg.opacity_falloff or M.STACK_DEFAULTS.opacity_falloff

  local visible_count = min(count, max_visible)

  if count == 1 then
    local x = mx - base_w / 2
    local y = my - base_h / 2

    local fill_color = (colors and colors[1]) or base_fill
    local stroke_color = base_stroke

    fill_color = apply_alpha_factor(fill_color, global_opacity)
    stroke_color = apply_alpha_factor(stroke_color, global_opacity)

    draw_shadow(dl, x, y, x + base_w, y + base_h, rounding, shadow_cfg)
    draw_tile(dl, x, y, base_w, base_h, fill_color, stroke_color, thickness, rounding, inner_glow)
  else
    for i = visible_count, 1, -1 do
      local scale = scale_factor ^ (visible_count - i)
      local w = base_w * scale
      local h = base_h * scale

      local ox = (i - 1) * offset_x
      local oy = (i - 1) * offset_y

      local x = mx - w / 2 + ox
      local y = my - h / 2 + oy

      if i == visible_count then
        draw_shadow(dl, x, y, x + w, y + h, rounding * scale, shadow_cfg)
      end

      local color_index = min(i, colors and #colors or 0)
      local item_fill = (colors and colors[color_index]) or base_fill
      local item_stroke = base_stroke

      local opacity_factor = 1.0 - ((visible_count - i) / visible_count) * opacity_falloff
      opacity_factor = opacity_factor * global_opacity

      local tile_fill = apply_alpha_factor(item_fill, opacity_factor)
      local tile_stroke = apply_alpha_factor(item_stroke, opacity_factor)

      draw_tile(dl, x, y, w, h, tile_fill, tile_stroke, thickness, rounding * scale, inner_glow)
    end

    DragIndicator.draw_badge(ctx, dl, mx, my, count, config and config.badge or nil, is_copy_mode, is_delete_mode)
  end

  if is_delete_mode then
    draw_delete_indicator(ctx, dl, mx, my, config)
  elseif is_copy_mode then
    draw_copy_indicator(ctx, dl, mx, my, config)
  end
end

-- =============================================================================
-- DROP INDICATOR
-- Drop indicator for drag and drop reordering
-- =============================================================================

local DropIndicator = {}

function DropIndicator.draw_vertical(ctx, dl, x, y1, y2, config, is_copy_mode)
  local cfg = config or M.DROP_DEFAULTS
  local mode_cfg = M.get_mode_config(config, is_copy_mode, false)

  -- Access nested line config
  local line_cfg = (mode_cfg and mode_cfg.line) or (cfg.line) or M.DROP_DEFAULTS
  local line_width = cfg.line_width or line_cfg.width or M.DROP_DEFAULTS.line_width
  local line_color = line_cfg.color or mode_cfg.stroke_color or M.MODES.move.stroke_color
  local glow_width = cfg.glow_width or line_cfg.glow_width or M.DROP_DEFAULTS.glow_width
  local glow_color = line_cfg.glow_color or mode_cfg.glow_color or M.MODES.move.glow_color

  -- Access nested caps config
  local caps_cfg = (mode_cfg and mode_cfg.caps) or (cfg.caps) or M.DROP_DEFAULTS.caps
  local cap_width = caps_cfg.width or M.DROP_DEFAULTS.caps.width
  local cap_height = caps_cfg.height or M.DROP_DEFAULTS.caps.height
  local cap_color = caps_cfg.color or mode_cfg.stroke_color or M.MODES.move.stroke_color
  local cap_rounding = caps_cfg.rounding or M.DROP_DEFAULTS.caps.rounding
  local cap_glow_size = caps_cfg.glow_size or M.DROP_DEFAULTS.caps.glow_size
  local cap_glow_color = caps_cfg.glow_color or mode_cfg.glow_color or M.MODES.move.glow_color

  local pulse_speed = cfg.pulse_speed or M.DROP_DEFAULTS.pulse_speed

  local pulse = (sin(reaper.time_precise() * pulse_speed) * 0.3 + 0.7)
  local pulsed_alpha = (pulse * 255)//1
  local pulsed_line = (line_color & 0xFFFFFF00) | pulsed_alpha

  ImGui.DrawList_AddRectFilled(dl, x - glow_width/2, y1, x + glow_width/2, y2, glow_color, glow_width/2)

  ImGui.DrawList_AddRectFilled(dl, x - line_width/2, y1, x + line_width/2, y2, pulsed_line, line_width/2)

  local cap_half_w = cap_width / 2
  local cap_half_h = cap_height / 2

  ImGui.DrawList_AddRectFilled(dl, x - cap_half_w - cap_glow_size, y1 - cap_half_h - cap_glow_size,
                                x + cap_half_w + cap_glow_size, y1 + cap_half_h + cap_glow_size,
                                cap_glow_color, cap_rounding + cap_glow_size)
  ImGui.DrawList_AddRectFilled(dl, x - cap_half_w - cap_glow_size, y2 - cap_half_h - cap_glow_size,
                                x + cap_half_w + cap_glow_size, y2 + cap_half_h + cap_glow_size,
                                cap_glow_color, cap_rounding + cap_glow_size)

  ImGui.DrawList_AddRectFilled(dl, x - cap_half_w, y1 - cap_half_h, x + cap_half_w, y1 + cap_half_h,
                                pulsed_line, cap_rounding)
  ImGui.DrawList_AddRectFilled(dl, x - cap_half_w, y2 - cap_half_h, x + cap_half_w, y2 + cap_half_h,
                                pulsed_line, cap_rounding)
end

function DropIndicator.draw_horizontal(ctx, dl, x1, x2, y, config, is_copy_mode)
  local cfg = config or M.DROP_DEFAULTS
  local mode_cfg = M.get_mode_config(config, is_copy_mode, false)

  -- Access nested line config
  local line_cfg = (mode_cfg and mode_cfg.line) or (cfg.line) or M.DROP_DEFAULTS
  local line_width = cfg.line_width or line_cfg.width or M.DROP_DEFAULTS.line_width
  local line_color = line_cfg.color or mode_cfg.stroke_color or M.MODES.move.stroke_color
  local glow_width = cfg.glow_width or line_cfg.glow_width or M.DROP_DEFAULTS.glow_width
  local glow_color = line_cfg.glow_color or mode_cfg.glow_color or M.MODES.move.glow_color

  -- Access nested caps config
  local caps_cfg = (mode_cfg and mode_cfg.caps) or (cfg.caps) or M.DROP_DEFAULTS.caps
  local cap_width = caps_cfg.width or M.DROP_DEFAULTS.caps.width
  local cap_height = caps_cfg.height or M.DROP_DEFAULTS.caps.height
  local cap_color = caps_cfg.color or mode_cfg.stroke_color or M.MODES.move.stroke_color
  local cap_rounding = caps_cfg.rounding or M.DROP_DEFAULTS.caps.rounding
  local cap_glow_size = caps_cfg.glow_size or M.DROP_DEFAULTS.caps.glow_size
  local cap_glow_color = caps_cfg.glow_color or mode_cfg.glow_color or M.MODES.move.glow_color

  local pulse_speed = cfg.pulse_speed or M.DROP_DEFAULTS.pulse_speed

  local pulse = (sin(reaper.time_precise() * pulse_speed) * 0.3 + 0.7)
  local pulsed_alpha = (pulse * 255)//1
  local pulsed_line = (line_color & 0xFFFFFF00) | pulsed_alpha

  ImGui.DrawList_AddRectFilled(dl, x1, y - glow_width/2, x2, y + glow_width/2, glow_color, glow_width/2)

  ImGui.DrawList_AddRectFilled(dl, x1, y - line_width/2, x2, y + line_width/2, pulsed_line, line_width/2)

  local cap_half_w = cap_width / 2
  local cap_half_h = cap_height / 2

  ImGui.DrawList_AddRectFilled(dl, x1 - cap_half_w - cap_glow_size, y - cap_half_h - cap_glow_size,
                                x1 + cap_half_w + cap_glow_size, y + cap_half_h + cap_glow_size,
                                cap_glow_color, cap_rounding + cap_glow_size)
  ImGui.DrawList_AddRectFilled(dl, x2 - cap_half_w - cap_glow_size, y - cap_half_h - cap_glow_size,
                                x2 + cap_half_w + cap_glow_size, y + cap_half_h + cap_glow_size,
                                cap_glow_color, cap_rounding + cap_glow_size)

  ImGui.DrawList_AddRectFilled(dl, x1 - cap_half_w, y - cap_half_h, x1 + cap_half_w, y + cap_half_h,
                                pulsed_line, cap_rounding)
  ImGui.DrawList_AddRectFilled(dl, x2 - cap_half_w, y - cap_half_h, x2 + cap_half_w, y + cap_half_h,
                                pulsed_line, cap_rounding)
end

function DropIndicator.draw(ctx, dl, config, is_copy_mode, orientation, ...)
  if orientation == 'horizontal' then
    local x1, x2, y = ...
    DropIndicator.draw_horizontal(ctx, dl, x1, x2, y, config, is_copy_mode)
  else
    local x, y1, y2 = ...
    DropIndicator.draw_vertical(ctx, dl, x, y1, y2, config, is_copy_mode)
  end
end

-- =============================================================================
-- EXPORTS
-- =============================================================================

M.DragIndicator = DragIndicator
M.DropIndicator = DropIndicator

return M
