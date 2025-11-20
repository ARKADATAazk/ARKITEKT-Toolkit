-- @noindex
-- Demo/ui/grid_view.lua
--
-- WHY THIS EXISTS: Showcase ARKITEKT's grid system with modern tile rendering
-- Demonstrates responsive layout, selection, and custom tile visuals
--
-- PATTERN: Uses colorblock-style tiles similar to package tiles demo
-- This is simplified for demonstration - real apps use full Grid widget

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

-- ARKITEKT dependencies
local Colors = require('rearkitekt.core.colors')
local Button = require('rearkitekt.gui.widgets.primitives.button')
local Tooltips = require('Demo.ui.tooltips')

local M = {}
local hexrgb = Colors.hexrgb

-- ============================================================================
-- TILE RENDERER
-- ============================================================================

local function render_tile(ctx, dl, x, y, size, item, is_selected, is_hovered)
  local rounding = 8

  -- Background color with selection/hover states
  local bg_color = item.color
  if is_selected then
    bg_color = Colors.adjust_brightness(bg_color, 1.3)
  elseif is_hovered then
    bg_color = Colors.adjust_brightness(bg_color, 1.15)
  end

  -- Draw tile background
  ImGui.DrawList_AddRectFilled(
    dl,
    x, y,
    x + size, y + size,
    bg_color,
    rounding
  )

  -- Selection border
  if is_selected then
    ImGui.DrawList_AddRect(
      dl,
      x, y,
      x + size, y + size,
      hexrgb("#60A5FA"),
      rounding,
      0,
      3
    )
  end

  -- Item icon/emoji (centered)
  local icon_x = x + size / 2 - 12
  local icon_y = y + size / 2 - 20
  ImGui.DrawList_AddText(dl, icon_x, icon_y, hexrgb("#FFFFFF"), item.icon)

  -- Item name (bottom, centered)
  local text_size_w, text_size_h = ImGui.CalcTextSize(ctx, item.name)
  local text_x = x + (size - text_size_w) / 2
  local text_y = y + size - text_size_h - 8

  -- Text shadow for readability
  ImGui.DrawList_AddText(dl, text_x + 1, text_y + 1, hexrgb("#00000080"), item.name)
  ImGui.DrawList_AddText(dl, text_x, text_y, hexrgb("#FFFFFF"), item.name)

  -- Badge (top-right corner)
  if item.badge then
    local badge_size = 20
    local badge_x = x + size - badge_size - 4
    local badge_y = y + 4

    ImGui.DrawList_AddCircleFilled(
      dl,
      badge_x + badge_size / 2,
      badge_y + badge_size / 2,
      badge_size / 2,
      hexrgb("#EF4444")
    )

    local badge_text = tostring(item.badge)
    local badge_text_w, badge_text_h = ImGui.CalcTextSize(ctx, badge_text)
    ImGui.DrawList_AddText(
      dl,
      badge_x + (badge_size - badge_text_w) / 2,
      badge_y + (badge_size - badge_text_h) / 2,
      hexrgb("#FFFFFF"),
      badge_text
    )
  end

  -- Hover overlay
  if is_hovered and not is_selected then
    ImGui.DrawList_AddRect(
      dl,
      x, y,
      x + size, y + size,
      hexrgb("#FFFFFF40"),
      rounding,
      0,
      1
    )
  end
end

-- ============================================================================
-- GRID LAYOUT CALCULATOR
-- ============================================================================

local function calculate_grid_layout(available_width, tile_size, gap)
  local columns = math.max(1, math.floor((available_width + gap) / (tile_size + gap)))
  local total_gap_width = (columns - 1) * gap
  local available_for_tiles = available_width - total_gap_width
  local actual_tile_size = math.floor(available_for_tiles / columns)

  return columns, actual_tile_size
end

-- ============================================================================
-- GRID INTERACTION
-- ============================================================================

local function handle_grid_interaction(ctx, items, columns, tile_size, gap, start_x, start_y, selected_items)
  local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
  local is_mouse_clicked = ImGui.IsMouseClicked(ctx, 0)

  local hovered_item = nil

  for i, item in ipairs(items) do
    local row = math.floor((i - 1) / columns)
    local col = (i - 1) % columns

    local x = start_x + col * (tile_size + gap)
    local y = start_y + row * (tile_size + gap)

    -- Check if mouse is over this tile
    if mouse_x >= x and mouse_x <= x + tile_size and
       mouse_y >= y and mouse_y <= y + tile_size then
      hovered_item = item.id

      -- Handle click
      if is_mouse_clicked then
        -- Toggle selection
        selected_items[item.id] = not selected_items[item.id]
      end

      -- Show tooltip
      if item.tooltip then
        ImGui.SetTooltip(ctx, item.tooltip)
      end
    end
  end

  return hovered_item
end

-- ============================================================================
-- SAMPLE DATA GENERATOR
-- ============================================================================

local function generate_sample_items()
  local items = {}

  local icons = {"📦", "🎨", "🎭", "🎪", "🎯", "🎲", "🎸", "🎹", "🎺", "🎻",
                 "🎬", "🎮", "🎰", "🎱", "🏀", "🏈", "⚽", "🏐", "🏓", "🏸",
                 "🎣", "🎿", "🏂", "🏋", "🚴", "🚵", "🏇", "⛷", "🏊", "🏄"}

  local colors = {
    hexrgb("#EF4444"), hexrgb("#F59E0B"), hexrgb("#10B981"),
    hexrgb("#3B82F6"), hexrgb("#6366F1"), hexrgb("#8B5CF6"),
    hexrgb("#EC4899"), hexrgb("#14B8A6"), hexrgb("#F97316"),
    hexrgb("#84CC16"), hexrgb("#06B6D4"), hexrgb("#A855F7"),
  }

  for i = 1, 24 do
    local icon = icons[((i - 1) % #icons) + 1]
    local color = colors[((i - 1) % #colors) + 1]

    items[i] = {
      id = "item_" .. i,
      name = "Item " .. i,
      icon = icon,
      color = color,
      badge = (i % 5 == 0) and i or nil,
      tooltip = "Click to select/deselect\n" .. icon .. " Item " .. i,
    }
  end

  return items
end

-- ============================================================================
-- MAIN RENDER
-- ============================================================================

function M.render(ctx, state)
  local dl = ImGui.GetWindowDrawList(ctx)

  -- Generate items if needed
  if not state.grid or not state.grid.items then
    if not state.grid then state.grid = {} end
    state.grid.items = generate_sample_items()
    state.grid.selected_items = {}
    state.grid.tile_size = 120
    state.grid.gap = 12
  end

  -- Header
  ImGui.TextColored(ctx, hexrgb("#3B82F6"), "📦 Grid System Showcase")
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.TextWrapped(ctx, "Responsive grid layout with modern tile rendering. Click tiles to select, hover for tooltips. This demonstrates the visual patterns used in production ARKITEKT apps.")
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Controls
  ImGui.Text(ctx, "Tile Size:")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 150)
  local size_changed, new_size = ImGui.SliderInt(ctx, "##tile_size", state.grid.tile_size, 80, 180)
  if size_changed then
    state.grid.tile_size = new_size
  end

  ImGui.SameLine(ctx, 0, 16)
  ImGui.Text(ctx, "Gap:")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 150)
  local gap_changed, new_gap = ImGui.SliderInt(ctx, "##gap", state.grid.gap, 4, 24)
  if gap_changed then
    state.grid.gap = new_gap
  end

  ImGui.SameLine(ctx, 0, 16)

  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local clear_clicked = Button.draw(ctx, dl, cursor_x, cursor_y, 120, 28, {
    label = "Clear Selection",
    bg_color = hexrgb("#475569"),
    bg_hover_color = hexrgb("#334155"),
    text_color = hexrgb("#F8FAFC"),
    rounding = 6,
    tooltip = "Clear all selected tiles",
  }, "clear_btn")

  if clear_clicked then
    state.grid.selected_items = {}
  end

  ImGui.SetCursorScreenPos(ctx, cursor_x + 125, cursor_y)

  -- Selection count
  local selected_count = 0
  for _ in pairs(state.grid.selected_items) do
    selected_count = selected_count + 1
  end

  ImGui.SameLine(ctx, 0, 16)
  ImGui.Text(ctx, string.format("Selected: %d / %d", selected_count, #state.grid.items))

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Grid rendering
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local columns, tile_size = calculate_grid_layout(avail_w, state.grid.tile_size, state.grid.gap)

  cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local grid_start_x = cursor_x
  local grid_start_y = cursor_y

  -- Handle interaction
  local hovered_item = handle_grid_interaction(
    ctx,
    state.grid.items,
    columns,
    tile_size,
    state.grid.gap,
    grid_start_x,
    grid_start_y,
    state.grid.selected_items
  )

  -- Render tiles
  for i, item in ipairs(state.grid.items) do
    local row = math.floor((i - 1) / columns)
    local col = (i - 1) % columns

    local x = grid_start_x + col * (tile_size + state.grid.gap)
    local y = grid_start_y + row * (tile_size + state.grid.gap)

    local is_selected = state.grid.selected_items[item.id]
    local is_hovered = (hovered_item == item.id)

    render_tile(ctx, dl, x, y, tile_size, item, is_selected, is_hovered)
  end

  -- Calculate total height and advance cursor
  local total_rows = math.ceil(#state.grid.items / columns)
  local total_height = total_rows * tile_size + (total_rows - 1) * state.grid.gap
  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + total_height + 16)

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Production Grid Info
  ImGui.TextColored(ctx, hexrgb("#A78BFA"), "🎯 Production Grid Features")
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.TextWrapped(ctx, "This is a simplified grid for demonstration. The production Grid widget (rearkitekt.gui.widgets.containers.grid) provides:")
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)

  local features = {
    "• Factory pattern for custom tile types and renderers",
    "• Drag & drop reordering with visual drop indicators",
    "• Multi-selection (Ctrl+Click, Shift+Click, marquee)",
    "• Spawn/destroy animations with TileFX system",
    "• Selection rectangle across entire scrollable container",
    "• Virtualization for efficient rendering of large datasets",
    "• Marching ants selection borders",
    "• Context menus and double-click behaviors",
    "• Custom behaviors (inline editing, state toggles, etc.)",
    "• Integration with Panel for scrolling and layout",
  }

  for _, feature in ipairs(features) do
    ImGui.TextColored(ctx, hexrgb("#94A3B8"), feature)
  end

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  ImGui.TextColored(ctx, hexrgb("#F59E0B"), "📚 Real Examples:")
  ImGui.Spacing(ctx)
  ImGui.BulletText(ctx, "Region_Playlist - Dual grids with drag & drop between them")
  ImGui.BulletText(ctx, "ThemeAdjuster - Package tiles with conflict indicators")
  ImGui.BulletText(ctx, "demos/demo.lua - Full package grid implementation")

  ImGui.Dummy(ctx, 1, 20)
end

return M
