-- @noindex
-- ReArkitekt/gui/fx/tile_fx_config.lua
-- Granular tile visual configuration

local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

M.DEFAULT = {
  -- Fill layer
  fill_opacity = 0.4,
  fill_saturation = 0.4,
  fill_brightness = 0.5,
  
  -- Border
  border_opacity = 1.0,
  border_saturation = 1,
  border_brightness = 1.6,
  border_thickness = 1.0,
  
  -- Index number (#1, #2, etc.) - region-colored
  index_saturation = 1,
  index_brightness = 1.6,
  
  -- Separator bullet (•) - region-colored
  separator_saturation = 1,
  separator_brightness = 1.6,
  separator_alpha = 0x99,
  
  -- Region name text - neutral white/gray (brightness adjusts the base neutral color)
  name_brightness = 1.0,
  name_base_color = hexrgb("#DDE3E9"),
  
  -- Duration/bars text - region-colored
  duration_saturation = 0.3,
  duration_brightness = 1,
  duration_alpha = 0x88,
  
  -- Gradient
  gradient_intensity = 0.16,
  gradient_opacity = 0.03,
  
  -- Specular
  specular_strength = 0.06,
  specular_coverage = 0.25,
  
  -- Inner shadow
  inner_shadow_strength = 0.20,
  
  -- Marching ants (uses border_saturation and border_brightness for color)
  ants_enabled = true,
  ants_replace_border = true,
  ants_thickness = 1,
  ants_dash = 8,
  ants_gap = 6,
  ants_speed = 20,
  ants_inset = 0,
  ants_alpha = 0xFF,
  
  -- Selection glow
  glow_strength = 0.4,
  glow_layers = 3,
  
  -- Hover
  hover_fill_boost = 0.06,
  hover_specular_boost = 0.5,
  
  -- Diagonal stripes (for playlists)
  stripe_enabled = true,  -- Toggle on/off
  stripe_spacing = 10,     -- Distance between stripes in pixels
  stripe_thickness = 4,    -- Line thickness
  stripe_opacity = 0.02,   -- Opacity (0.0 to 1.0)
}

function M.get()
  return M.DEFAULT
end

function M.override(overrides)
  local config = {}
  for k, v in pairs(M.DEFAULT) do
    config[k] = overrides[k] == nil and v or overrides[k]
  end
  return config
end

return M