-- @noindex
-- ReArkitekt/gui/style/defaults.lua
-- Centralized colors, presets, and styling utilities for all ReArkitekt components
--
-- This is the SINGLE SOURCE OF TRUTH for all colors and component style presets.
-- Colors are organized by component for easy modification and theming.
--
-- For ImGui native widgets, see imgui_defaults.lua instead.

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb
local ConfigUtil = require('arkitekt.core.config')

local M = {}

-- ============================================================================
-- SHARED PRIMITIVES (Used across multiple components)
-- ============================================================================
-- These are foundational colors that multiple components reference.
-- Modify these to change the overall theme of the application.
-- ============================================================================

M.COLORS = {
  -- Backgrounds
  BG_BASE = hexrgb("#252525FF"),        -- Standard control background
  BG_HOVER = hexrgb("#2A2A2AFF"),       -- Hovered control background
  BG_ACTIVE = hexrgb("#303030FF"),      -- Active/pressed control background
  BG_TRANSPARENT = hexrgb("#00000000"), -- Transparent background

  -- Borders
  BORDER_OUTER = hexrgb("#000000DD"),   -- Black outer border (strong contrast)
  BORDER_INNER = hexrgb("#2f2f2fff"),   -- Gray inner highlight border
  BORDER_HOVER = hexrgb("#505050FF"),   -- Lighter border on hover
  BORDER_ACTIVE = hexrgb("#B0B0B077"),  -- Active state border (semi-transparent)
  BORDER_FOCUS = hexrgb("#7B7B7BFF"),   -- Focus state border

  -- Text
  TEXT_NORMAL = hexrgb("#CCCCCCFF"),    -- Standard text color
  TEXT_HOVER = hexrgb("#FFFFFFFF"),     -- Bright text on hover
  TEXT_ACTIVE = hexrgb("#FFFFFFFF"),    -- Bright text when active
  TEXT_DIMMED = hexrgb("#AAAAAAFF"),    -- Dimmed/secondary text
  TEXT_DARK = hexrgb("#707070FF"),      -- Dark text for high-contrast areas
  TEXT_BRIGHT = hexrgb("#EEEEEEFF"),    -- Extra bright text

  -- Accents (for warnings, errors, success states)
  ACCENT_PRIMARY = hexrgb("#4A9EFF"),   -- Primary accent (blue)
  ACCENT_SUCCESS = hexrgb("#4CAF50"),   -- Success/confirmation (green)
  ACCENT_WARNING = hexrgb("#FFA726"),   -- Warning state (orange)
  ACCENT_DANGER = hexrgb("#EF5350"),    -- Error/danger state (red)
}

-- ============================================================================
-- PANEL COLORS (All panel widget colors)
-- ============================================================================
-- Controls colors for panel containers, headers, tabs, and decorative elements.
--
-- When to modify:
-- - Want to change panel background darkness
-- - Adjust header bar styling
-- - Modify tab appearance
-- - Change separator line visibility
-- - Adjust background pattern colors
-- ============================================================================

M.PANEL_COLORS = {
  -- Panel container
  bg_panel = hexrgb("#1A1A1AFF"),       -- Main panel container background (darker than controls)
  border_panel = M.COLORS.BORDER_OUTER, -- Panel outer border (reuse shared)

  -- Header bar
  bg_header = hexrgb("#1E1E1EFF"),      -- Header bar background
  border_header = hexrgb("#00000066"),  -- Subtle header border

  -- Tab strip
  bg_tab = M.COLORS.BG_BASE,            -- Tab background (inactive)
  bg_tab_hover = M.COLORS.BG_HOVER,     -- Tab background (hovered)
  bg_tab_active = M.COLORS.BG_ACTIVE,   -- Tab background (active/selected)
  text_tab = M.COLORS.TEXT_DIMMED,      -- Tab text (inactive)
  text_tab_hover = M.COLORS.TEXT_HOVER, -- Tab text (hovered)
  text_tab_active = M.COLORS.TEXT_ACTIVE, -- Tab text (active)
  border_tab_inner = M.COLORS.BORDER_INNER,  -- Tab inner border
  border_tab_hover = M.COLORS.BORDER_HOVER,  -- Tab border on hover
  border_tab_focus = M.COLORS.BORDER_FOCUS,  -- Tab border when focused

  -- Tab track (background behind tabs)
  bg_tab_track = hexrgb("#1A1A1AFF"),   -- Track background
  border_tab_track = M.COLORS.BORDER_OUTER, -- Track border

  -- Separator
  separator_line = hexrgb("#30303080"),  -- Separator line color (semi-transparent)

  -- Scrollbar
  bg_scrollbar = M.COLORS.BG_TRANSPARENT, -- Scrollbar background

  -- Background pattern (decorative grid/dot pattern)
  pattern_primary = hexrgb("#14141490"),   -- Primary grid/dot color
  pattern_secondary = hexrgb("#14141420"), -- Secondary grid/dot color
}

-- ============================================================================
-- BUTTON COLORS (All button-related colors including toggle variants)
-- ============================================================================
-- Controls colors for standard buttons and toggle button variants.
--
-- When to modify:
-- - Change button color scheme
-- - Add new toggle button color variants (e.g., BLUE, RED, PURPLE)
-- - Adjust toggle button ON state colors
-- - Modify button state transitions (hover, active)
-- ============================================================================

M.BUTTON_COLORS = {
  -- Base button (non-toggle)
  bg = M.COLORS.BG_BASE,
  bg_hover = M.COLORS.BG_HOVER,
  bg_active = M.COLORS.BG_ACTIVE,
  border_outer = M.COLORS.BORDER_OUTER,
  border_inner = M.COLORS.BORDER_INNER,
  border_hover = M.COLORS.BORDER_HOVER,
  border_active = M.COLORS.BORDER_ACTIVE,
  text = M.COLORS.TEXT_NORMAL,
  text_hover = M.COLORS.TEXT_HOVER,
  text_active = M.COLORS.TEXT_ACTIVE,

  -- Toggle button variants (ON state colors)
  -- Each variant defines colors for when the toggle is ON

  -- WHITE variant: Classic white/gray toggle (high contrast)
  toggle_white = {
    bg_on = hexrgb("#2f2f2fff"),
    bg_on_hover = hexrgb("#373737ff"),
    bg_on_active = hexrgb("#343434ff"),
    border_inner_on = hexrgb("#585858ff"),
    border_inner_on_hover = hexrgb("#8b8b8bff"),
    border_inner_on_active = hexrgb("#737373ff"),
    text_on = hexrgb("#FFFFFFFF"),
  },

  -- TEAL variant: Teal/green accent toggle (softer, colorful)
  toggle_teal = {
    bg_on = hexrgb("#295650FF"),        -- Teal background when ON
    bg_on_hover = hexrgb("#2E6459FF"),  -- Slightly lighter on hover
    bg_on_active = hexrgb("#234B46FF"), -- Slightly darker when pressed
    border_inner_on = hexrgb("#37775FFF"),        -- Teal inner border
    border_inner_on_hover = hexrgb("#42866DFF"),  -- Lighter teal on hover
    border_inner_on_active = hexrgb("#2D6851FF"), -- Darker teal when pressed
    text_on = hexrgb("#41E0A3FF"),      -- Bright teal/green text
  },

  -- TRANSPARENT variant: Semi-transparent overlay style (for corner buttons over content)
  toggle_transparent = {
    bg_on = hexrgb("#434343AA"),        -- Semi-transparent gray when ON (67% opacity)
    bg_on_hover = hexrgb("#484848BB"),  -- Slightly lighter on hover (73% opacity)
    bg_on_active = hexrgb("#3E3E3E99"), -- Slightly darker when pressed (60% opacity)
    border_inner_on = hexrgb("#898989AA"),        -- Semi-transparent border
    border_inner_on_hover = hexrgb("#9A9A9ABB"),  -- Lighter on hover
    border_inner_on_active = hexrgb("#7E7E7E99"), -- Darker when pressed
    text_on = hexrgb("#FFFFFFDD"),      -- Bright white text (87% opacity)
  },
}

-- ============================================================================
-- DROPDOWN COLORS (All dropdown menu colors)
-- ============================================================================
-- Controls colors for dropdown menus including button, popup, and items.
--
-- When to modify:
-- - Change dropdown button appearance
-- - Adjust popup menu styling
-- - Modify item hover/selection colors
-- - Change arrow indicator color
-- ============================================================================

M.DROPDOWN_COLORS = {
  -- Dropdown button (closed state)
  bg = M.COLORS.BG_BASE,
  bg_hover = M.COLORS.BG_HOVER,
  bg_active = M.COLORS.BG_ACTIVE,
  border_outer = M.COLORS.BORDER_OUTER,
  border_inner = M.COLORS.BORDER_INNER,
  border_hover = M.COLORS.BORDER_HOVER,
  border_active = M.COLORS.BORDER_ACTIVE,
  text = M.COLORS.TEXT_NORMAL,
  text_hover = M.COLORS.TEXT_HOVER,
  text_active = M.COLORS.TEXT_ACTIVE,

  -- Arrow indicator
  arrow = M.COLORS.TEXT_NORMAL,
  arrow_hover = M.COLORS.TEXT_HOVER,

  -- Popup menu (lighter grey with much darker borders)
  popup_bg = hexrgb("#222222FF"),         -- Popup background (lighter grey)
  popup_border = hexrgb("#0F0F0FFF"),     -- Popup border (much darker, almost black)

  -- Menu items (enhanced styling)
  item_bg = hexrgb("#00000000"),          -- Item background (transparent)
  item_hover = hexrgb("#2E2E2EFF"),       -- Item background on hover (subtle highlight)
  item_active = hexrgb("#353535FF"),      -- Item background when active (more visible)
  item_selected = hexrgb("#303030FF"),    -- Item background when selected
  item_text = M.COLORS.TEXT_NORMAL,       -- Item text
  item_text_hover = M.COLORS.TEXT_HOVER,  -- Item text on hover
  item_text_selected = M.COLORS.TEXT_BRIGHT, -- Item text when selected (brighter)
}

-- ============================================================================
-- SEARCH INPUT COLORS
-- ============================================================================
-- Darker than buttons/combobox for clear visual distinction
-- Input fields are recessed/inset elements, so darker background emphasizes depth

M.SEARCH_INPUT_COLORS = {
  bg = M.COLORS.BG_BASE,
  bg_hover = M.COLORS.BG_HOVER,
  bg_active = M.COLORS.BG_ACTIVE,
  border_outer = M.COLORS.BORDER_OUTER,
  border_inner = M.COLORS.BORDER_INNER,
  border_hover = M.COLORS.BORDER_HOVER,
  border_active = M.COLORS.BORDER_ACTIVE,
  text = M.COLORS.TEXT_NORMAL,         -- More transparent/dimmed text
}

-- ============================================================================
-- TOOLTIP COLORS
-- ============================================================================

M.TOOLTIP_COLORS = {
  bg = hexrgb("#2A2A2AFF"),
  border = M.COLORS.BORDER_INNER,
  text = hexrgb("#EEEEEEFF"),
}

-- ============================================================================
-- TOGGLE BUTTON STYLE BUILDER
-- ============================================================================
-- Creates complete toggle button configurations from color variants.
-- This combines base button colors (OFF state) with variant colors (ON state).
-- ============================================================================

--- Creates a toggle button style from a variant
--- @param variant table Color variant from M.BUTTON_COLORS.toggle_*
--- @return table Complete toggle button style configuration
local function create_toggle_style(variant)
  local BC = M.BUTTON_COLORS
  return {
    -- Normal/OFF state (inherit from base button colors)
    bg_color = BC.bg,
    bg_hover_color = BC.bg_hover,
    bg_active_color = BC.bg_active,
    border_outer_color = BC.border_outer,
    border_inner_color = BC.border_inner,
    border_hover_color = BC.border_hover,
    border_active_color = BC.border_active,
    text_color = BC.text,
    text_hover_color = BC.text_hover,
    text_active_color = BC.text_active,

    -- ON state (from variant)
    bg_on_color = variant.bg_on,
    bg_on_hover_color = variant.bg_on_hover,
    bg_on_active_color = variant.bg_on_active,
    border_outer_on_color = M.COLORS.BORDER_OUTER, -- Always black outer border
    border_inner_on_color = variant.border_inner_on,
    border_on_hover_color = variant.border_inner_on_hover,
    border_on_active_color = variant.border_inner_on_active,
    text_on_color = variant.text_on,
    text_on_hover_color = variant.text_on,
    text_on_active_color = variant.text_on,

    padding_x = 10,
    padding_y = 6,
    rounding = 0,
  }
end

-- ============================================================================
-- COMPONENT STYLE PRESETS
-- ============================================================================
-- Pre-built complete style configurations for each component type.
-- These combine colors with geometry settings (padding, rounding, etc.).
--
-- Usage: Pass preset_name to component config, e.g.:
--   config = { preset_name = "BUTTON_TOGGLE_TEAL" }
-- ============================================================================

M.BUTTON = {
  bg_color = M.BUTTON_COLORS.bg,
  bg_hover_color = M.BUTTON_COLORS.bg_hover,
  bg_active_color = M.BUTTON_COLORS.bg_active,
  border_outer_color = M.BUTTON_COLORS.border_outer,
  border_inner_color = M.BUTTON_COLORS.border_inner,
  border_hover_color = M.BUTTON_COLORS.border_hover,
  border_active_color = M.BUTTON_COLORS.border_active,
  text_color = M.BUTTON_COLORS.text,
  text_hover_color = M.BUTTON_COLORS.text_hover,
  text_active_color = M.BUTTON_COLORS.text_active,
  -- Disabled state colors
  bg_disabled_color = hexrgb("#1a1a1a"),  -- Darker, dimmed background
  border_inner_disabled_color = hexrgb("#202020"),  -- Very dark inner border
  border_outer_disabled_color = hexrgb("#000000DD"),  -- Same outer border as normal
  text_disabled_color = hexrgb("#555555"),  -- Dimmed text
  padding_x = 10,
  padding_y = 6,
  rounding = 0,
}

-- Toggle button presets - built from color variants
M.BUTTON_TOGGLE = create_toggle_style(M.BUTTON_COLORS.toggle_white)
M.BUTTON_TOGGLE_WHITE = create_toggle_style(M.BUTTON_COLORS.toggle_white)
M.BUTTON_TOGGLE_TEAL = create_toggle_style(M.BUTTON_COLORS.toggle_teal)
M.BUTTON_TOGGLE_TRANSPARENT = create_toggle_style(M.BUTTON_COLORS.toggle_transparent)

-- Legacy alias for backward compatibility
M.BUTTON_TOGGLE_ACCENT = M.BUTTON_TOGGLE_TEAL

M.SEARCH_INPUT = {
  placeholder = "Search...",
  fade_speed = 8.0,
  bg_color = M.SEARCH_INPUT_COLORS.bg,
  bg_hover_color = M.SEARCH_INPUT_COLORS.bg_hover,
  bg_active_color = M.SEARCH_INPUT_COLORS.bg_active,
  border_outer_color = M.SEARCH_INPUT_COLORS.border_outer,
  border_inner_color = M.SEARCH_INPUT_COLORS.border_inner,
  border_hover_color = M.SEARCH_INPUT_COLORS.border_hover,
  border_active_color = M.SEARCH_INPUT_COLORS.border_active,
  text_color = M.SEARCH_INPUT_COLORS.text,
  padding_x = 6,
  rounding = 0,
  tooltip_delay = 0.5,
}

-- Action chip presets - colored rectangles with dark text
M.ACTION_CHIP_WILDCARD = {
  bg_color = hexrgb("#5B8FB9"),  -- Muted blue for technical wildcards
  text_color = hexrgb("#1a1a1a"),  -- Dark text
  border_color = Colors.with_alpha(hexrgb("#000000"), 100),
  rounding = 2,
  padding_h = 8,
}

M.ACTION_CHIP_TAG = {
  bg_color = hexrgb("#8B7355"),  -- Warm amber for tags/names
  text_color = hexrgb("#1a1a1a"),  -- Dark text
  border_color = Colors.with_alpha(hexrgb("#000000"), 100),
  rounding = 2,
  padding_h = 8,
}

M.DROPDOWN = {
  bg_color = M.DROPDOWN_COLORS.bg,
  bg_hover_color = M.DROPDOWN_COLORS.bg_hover,
  bg_active_color = M.DROPDOWN_COLORS.bg_active,
  border_outer_color = M.DROPDOWN_COLORS.border_outer,
  border_inner_color = M.DROPDOWN_COLORS.border_inner,
  border_hover_color = M.DROPDOWN_COLORS.border_hover,
  border_active_color = M.DROPDOWN_COLORS.border_active,
  text_color = M.DROPDOWN_COLORS.text,
  text_hover_color = M.DROPDOWN_COLORS.text_hover,
  text_active_color = M.DROPDOWN_COLORS.text_active,
  rounding = 0,
  padding_x = 10,
  padding_y = 6,
  arrow_size = 6,
  arrow_color = M.DROPDOWN_COLORS.arrow,
  arrow_hover_color = M.DROPDOWN_COLORS.arrow_hover,
  enable_mousewheel = true,
  tooltip_delay = 0.5,
  popup = {
    bg_color = M.DROPDOWN_COLORS.popup_bg,
    border_color = M.DROPDOWN_COLORS.popup_border,
    item_bg_color = M.DROPDOWN_COLORS.item_bg,
    item_hover_color = M.DROPDOWN_COLORS.item_hover,
    item_active_color = M.DROPDOWN_COLORS.item_active,
    item_text_color = M.DROPDOWN_COLORS.item_text,
    item_text_hover_color = M.DROPDOWN_COLORS.item_text_hover,
    item_selected_color = M.DROPDOWN_COLORS.item_selected,
    item_selected_text_color = M.DROPDOWN_COLORS.item_text_selected,
    rounding = 2,             -- Slight rounding for modern look
    padding = 6,              -- More padding for breathing room
    item_height = 26,         -- Taller items for better touch targets
    item_padding_x = 12,      -- More horizontal padding
    border_thickness = 1,
  },
}

M.TOOLTIP = {
  bg_color = M.TOOLTIP_COLORS.bg,
  border_color = M.TOOLTIP_COLORS.border,
  text_color = M.TOOLTIP_COLORS.text,
  padding_x = 8,
  padding_y = 6,
  rounding = 4,
  border_thickness = 1,
  delay = 0.5,
}

-- ============================================================================
-- RENDERING UTILITIES
-- ============================================================================

M.RENDER = {}

--- Converts corner_rounding config to ImGui corner flags.
--- Logic:
---   - nil corner_rounding = standalone element, return 0 (caller handles default)
---   - corner_rounding exists with flags = specific corners rounded
---   - corner_rounding exists with no flags = middle element, explicitly no rounding
--- @param corner_rounding table|nil Corner rounding configuration from layout engine
--- @return integer ImGui DrawFlags for corner rounding
function M.RENDER.get_corner_flags(corner_rounding)
  -- No corner_rounding config = standalone element (not in panel header)
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
  -- (middle element in a group). Return RoundCornersNone to explicitly disable rounding.
  if flags == 0 then
    return ImGui.DrawFlags_RoundCornersNone
  end

  return flags
end

-- Draw standard double-border control background
function M.RENDER.draw_control_background(dl, x, y, w, h, bg_color, border_inner, border_outer, rounding, corner_flags)
  corner_flags = corner_flags or 0
  local inner_rounding = math.max(0, rounding - 2)

  -- Background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg_color, inner_rounding, corner_flags)

  -- Inner border
  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + w - 1, y + h - 1, border_inner, inner_rounding, corner_flags, 1)

  -- Outer border
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border_outer, inner_rounding, corner_flags, 1)
end

-- Get state-based colors for a control
function M.RENDER.get_state_colors(config, is_hovered, is_active)
  local colors = {
    bg = config.bg_color,
    border_inner = config.border_inner_color,
    border_outer = config.border_outer_color,
    text = config.text_color,
  }

  if is_active then
    colors.bg = config.bg_active_color or colors.bg
    colors.border_inner = config.border_active_color or colors.border_inner
    colors.text = config.text_active_color or colors.text
  elseif is_hovered then
    colors.bg = config.bg_hover_color or colors.bg
    colors.border_inner = config.border_hover_color or colors.border_inner
    colors.text = config.text_hover_color or colors.text
  end

  return colors
end

-- Lerp between two colors
function M.RENDER.lerp_color(a, b, t)
  local ar = (a >> 24) & 0xFF
  local ag = (a >> 16) & 0xFF
  local ab = (a >> 8) & 0xFF
  local aa = a & 0xFF

  local br = (b >> 24) & 0xFF
  local bg = (b >> 16) & 0xFF
  local bb = (b >> 8) & 0xFF
  local ba = b & 0xFF

  local r = (ar + (br - ar) * t)//1
  local g = (ag + (bg - ag) * t)//1
  local b = (ab + (bb - ab) * t)//1
  local a = (aa + (ba - aa) * t)//1

  return (r << 24) | (g << 16) | (b << 8) | a
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Apply defaults to user config
-- Delegates to centralized Config utility for consistency
function M.apply_defaults(defaults, user_config)
  return ConfigUtil.apply_defaults(defaults, user_config)
end

-- Apply alpha to color
function M.apply_alpha(color, alpha_factor)
  local a = color & 0xFF
  local new_a = (a * alpha_factor)//1
  return (color & 0xFFFFFF00) | new_a
end

-- Get state-based color (normal, hover, active)
function M.get_state_color(colors, is_hovered, is_active, color_key)
  local active_key = color_key .. "_active"
  local hover_key = color_key .. "_hover"

  if is_active and colors[active_key] then
    return colors[active_key]
  elseif is_hovered and colors[hover_key] then
    return colors[hover_key]
  else
    return colors[color_key]
  end
end

return M
