-- @noindex
-- Demo/ui/grid_view.lua
--
-- Showcase ARKITEKT's grid and tile systems with Panel + tab_strip

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

-- ARKITEKT dependencies
local Colors = require('rearkitekt.core.colors')
local Panel = require('rearkitekt.gui.widgets.containers.panel')
local Shapes = require('rearkitekt.gui.rendering.shapes')
local Tooltips = require('Demo.ui.tooltips')

local M = {}
local hexrgb = Colors.hexrgb

-- ============================================================================
-- PANEL STATE
-- ============================================================================

local panel = nil
local active_tab = "parameters"

local function init_panel()
  local tab_items = {
    { id = "parameters", label = "📋 Parameters" },
    { id = "tiles", label = "🎨 Tiles" },
  }

  local tab_config = {
    spacing = 0,
    min_width = 80,
    max_width = 150,
    padding_x = 12,
    chip_radius = 6,
    on_change = function(new_tab)
      active_tab = new_tab
    end,
  }

  local panel_config = {
    header = {
      enabled = true,
      height = 32,
      elements = {
        {
          id = "tabs",
          type = "tab_strip",
          flex = 1,
          spacing_before = 0,
          config = tab_config,
        },
      },
    },
  }

  panel = Panel.new({
    id = "grid_demo_panel",
    config = panel_config,
  })

  panel:set_tabs(tab_items, active_tab)
end

-- ============================================================================
-- PARAMETER TILES (Vertical List)
-- ============================================================================

local function render_parameter_tile(ctx, dl, x, y, width, param, is_hovered)
  local height = 72
  local rounding = 6

  -- Background
  local bg_color = is_hovered and hexrgb("#2D3748") or hexrgb("#1E293B")
  ImGui.DrawList_AddRectFilled(dl, x, y, x + width, y + height, bg_color, rounding)

  -- Border
  ImGui.DrawList_AddRect(dl, x, y, x + width, y + height, hexrgb("#334155"), rounding, 0, 1)

  -- Icon circle (left side)
  local icon_cx = x + 36
  local icon_cy = y + height / 2
  local icon_radius = 20

  ImGui.DrawList_AddCircleFilled(dl, icon_cx, icon_cy, icon_radius, param.icon_color)

  -- Icon text
  local icon_w, icon_h = ImGui.CalcTextSize(ctx, param.icon)
  ImGui.DrawList_AddText(dl, icon_cx - icon_w/2, icon_cy - icon_h/2, hexrgb("#FFFFFF"), param.icon)

  -- Title
  ImGui.DrawList_AddText(dl, x + 64, y + 12, hexrgb("#F8FAFC"), param.title)

  -- Description
  ImGui.DrawList_AddText(dl, x + 64, y + 32, hexrgb("#94A3B8"), param.description)

  -- Value badge (right side)
  local badge_text = param.value
  local badge_w, badge_h = ImGui.CalcTextSize(ctx, badge_text)
  local badge_x = x + width - badge_w - 16
  local badge_y = y + height/2 - badge_h/2

  ImGui.DrawList_AddText(dl, badge_x, badge_y, hexrgb("#60A5FA"), badge_text)

  -- Hover indicator
  if is_hovered then
    ImGui.DrawList_AddRect(dl, x, y, x + width, y + height, hexrgb("#3B82F6"), rounding, 0, 2)
  end

  return height
end

local function render_parameters_tab(ctx, state)
  local dl = ImGui.GetWindowDrawList(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)

  ImGui.Spacing(ctx)

  -- Generate parameter data
  local params = {
    { icon = "⚡", icon_color = hexrgb("#F59E0B"), title = "Performance Mode", description = "Optimize for speed vs quality", value = "Balanced" },
    { icon = "🎨", icon_color = hexrgb("#EC4899"), title = "Color Scheme", description = "Theme color palette selection", value = "Dark" },
    { icon = "📐", icon_color = hexrgb("#3B82F6"), title = "Grid Density", description = "Items per row in grid view", value = "Auto" },
    { icon = "🔊", icon_color = hexrgb("#10B981"), title = "Audio Quality", description = "Sample rate and bit depth", value = "48kHz" },
    { icon = "💾", icon_color = hexrgb("#8B5CF6"), title = "Auto Save", description = "Automatic project backup", value = "Enabled" },
    { icon = "🎯", icon_color = hexrgb("#EF4444"), title = "Snap Mode", description = "Grid snapping behavior", value = "1/16" },
  }

  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
  local start_y = cursor_y
  local gap = 8

  for i, param in ipairs(params) do
    local tile_x = cursor_x
    local tile_y = start_y + (i - 1) * (72 + gap)

    -- Check hover
    local is_hovered = mouse_x >= tile_x and mouse_x <= tile_x + avail_w and
                       mouse_y >= tile_y and mouse_y <= tile_y + 72

    render_parameter_tile(ctx, dl, tile_x, tile_y, avail_w, param, is_hovered)

    if is_hovered then
      ImGui.SetTooltip(ctx, string.format("%s\n%s\nCurrent: %s", param.title, param.description, param.value))
    end
  end

  -- Advance cursor
  ImGui.SetCursorScreenPos(ctx, cursor_x, start_y + #params * (72 + gap))
  ImGui.Dummy(ctx, 1, 1)
end

-- ============================================================================
-- SQUARED TILES (Grid with Shapes)
-- ============================================================================

local function render_shape_tile(ctx, dl, x, y, size, tile, is_selected, is_hovered)
  local rounding = 8

  -- Background
  local bg_color = tile.bg_color
  if is_selected then
    bg_color = Colors.adjust_brightness(bg_color, 1.3)
  elseif is_hovered then
    bg_color = Colors.adjust_brightness(bg_color, 1.15)
  end

  ImGui.DrawList_AddRectFilled(dl, x, y, x + size, y + size, bg_color, rounding)

  -- Draw shape in center
  local cx = x + size / 2
  local cy = y + size / 2
  local shape_size = size * 0.35

  if tile.shape == "star" then
    Shapes.draw_star_filled(dl, cx, cy, shape_size, shape_size * 0.4, hexrgb("#FFFFFF"), 5)
  elseif tile.shape == "circle" then
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, shape_size, hexrgb("#FFFFFF"))
  elseif tile.shape == "square" then
    local half = shape_size
    ImGui.DrawList_AddRectFilled(dl, cx - half, cy - half, cx + half, cy + half, hexrgb("#FFFFFF"), 4)
  elseif tile.shape == "triangle" then
    ImGui.DrawList_PathClear(dl)
    ImGui.DrawList_PathLineTo(dl, cx, cy - shape_size)
    ImGui.DrawList_PathLineTo(dl, cx + shape_size, cy + shape_size)
    ImGui.DrawList_PathLineTo(dl, cx - shape_size, cy + shape_size)
    ImGui.DrawList_PathFillConvex(dl, hexrgb("#FFFFFF"))
  end

  -- Label at bottom
  local label_w, label_h = ImGui.CalcTextSize(ctx, tile.name)
  local label_x = x + (size - label_w) / 2
  local label_y = y + size - label_h - 8

  ImGui.DrawList_AddText(dl, label_x + 1, label_y + 1, hexrgb("#00000080"), tile.name)
  ImGui.DrawList_AddText(dl, label_x, label_y, hexrgb("#FFFFFF"), tile.name)

  -- Selection border
  if is_selected then
    ImGui.DrawList_AddRect(dl, x, y, x + size, y + size, hexrgb("#60A5FA"), rounding, 0, 3)
  elseif is_hovered then
    ImGui.DrawList_AddRect(dl, x, y, x + size, y + size, hexrgb("#FFFFFF40"), rounding, 0, 1)
  end
end

local function render_tiles_tab(ctx, state)
  local dl = ImGui.GetWindowDrawList(ctx)

  -- Initialize tiles if needed
  if not state.grid.shape_tiles then
    state.grid.shape_tiles = {
      { id = "star_red", name = "Star", shape = "star", bg_color = hexrgb("#EF4444") },
      { id = "circle_blue", name = "Circle", shape = "circle", bg_color = hexrgb("#3B82F6") },
      { id = "square_green", name = "Square", shape = "square", bg_color = hexrgb("#10B981") },
      { id = "triangle_purple", name = "Triangle", shape = "triangle", bg_color = hexrgb("#8B5CF6") },
      { id = "star_orange", name = "Star", shape = "star", bg_color = hexrgb("#F59E0B") },
      { id = "circle_pink", name = "Circle", shape = "circle", bg_color = hexrgb("#EC4899") },
      { id = "square_cyan", name = "Square", shape = "square", bg_color = hexrgb("#06B6D4") },
      { id = "triangle_lime", name = "Triangle", shape = "triangle", bg_color = hexrgb("#84CC16") },
    }
    state.grid.shape_selection = {}
  end

  ImGui.Spacing(ctx)

  -- Grid layout
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local tile_size = 120
  local gap = 12
  local columns = math.max(1, math.floor((avail_w + gap) / (tile_size + gap)))

  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
  local is_mouse_clicked = ImGui.IsMouseClicked(ctx, 0)

  local hovered_id = nil

  for i, tile in ipairs(state.grid.shape_tiles) do
    local row = math.floor((i - 1) / columns)
    local col = (i - 1) % columns

    local x = cursor_x + col * (tile_size + gap)
    local y = cursor_y + row * (tile_size + gap)

    -- Check hover
    local is_hovered = mouse_x >= x and mouse_x <= x + tile_size and
                       mouse_y >= y and mouse_y <= y + tile_size

    if is_hovered then
      hovered_id = tile.id
      if is_mouse_clicked then
        state.grid.shape_selection[tile.id] = not state.grid.shape_selection[tile.id]
      end
      ImGui.SetTooltip(ctx, string.format("%s\nShape: %s\nClick to select", tile.name, tile.shape))
    end

    local is_selected = state.grid.shape_selection[tile.id]
    render_shape_tile(ctx, dl, x, y, tile_size, tile, is_selected, is_hovered)
  end

  -- Advance cursor
  local total_rows = math.ceil(#state.grid.shape_tiles / columns)
  local total_height = total_rows * tile_size + (total_rows - 1) * gap
  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + total_height + 16)
  ImGui.Dummy(ctx, 1, 1)
end

-- ============================================================================
-- MAIN RENDER
-- ============================================================================

function M.render(ctx, state)
  -- Initialize panel
  if not panel then
    init_panel()
  end

  -- Initialize grid state
  if not state.grid then
    state.grid = {}
  end

  -- Update active tab from panel
  active_tab = panel:get_active_tab() or active_tab

  -- Render panel
  if panel:begin_draw(ctx) then
    -- Render content based on active tab
    if active_tab == "parameters" then
      render_parameters_tab(ctx, state)
    elseif active_tab == "tiles" then
      render_tiles_tab(ctx, state)
    end
  end
  panel:end_draw(ctx)
end

return M
