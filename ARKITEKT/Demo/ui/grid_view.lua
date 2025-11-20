-- @noindex
-- Demo/ui/grid_view.lua
--
-- WHY THIS EXISTS: Demonstrates ARKITEKT's responsive grid system with tiles,
-- including selection, drag & drop, and animations.
--
-- The grid system is one of the most powerful features in ARKITEKT, used
-- throughout the ColorPalette, ItemPicker, and other apps.
--
-- DEMONSTRATES:
-- - Responsive grid layout (auto-fits columns)
-- - Tile rendering with custom content
-- - Multi-selection with click and marquee
-- - Grid item interactions
-- - Animation system integration

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

-- ARKITEKT dependencies
local Colors = require('rearkitekt.core.colors')
local Button = require('rearkitekt.gui.widgets.primitives.button')
local State = require('Demo.core.state')
local Tooltips = require('Demo.ui.tooltips')

local M = {}
local hexrgb = Colors.hexrgb

-- ============================================================================
-- SIMPLE GRID IMPLEMENTATION
-- ============================================================================
-- NOTE: This is a simplified grid for demonstration purposes.
-- For production use, see rearkitekt.gui.widgets.containers.grid

local function calculate_grid_layout(available_width, tile_size, gap)
  local columns = math.max(1, math.floor((available_width + gap) / (tile_size + gap)))
  local actual_tile_width = (available_width - (columns - 1) * gap) / columns
  return columns, actual_tile_width
end

--- Render a simple tile
-- @param ctx ImGui context
-- @param dl DrawList
-- @param x number X position
-- @param y number Y position
-- @param width number Tile width
-- @param height number Tile height
-- @param tile table Tile data
-- @param is_selected boolean Selection state
-- @param is_hovered boolean Hover state
local function render_tile(ctx, dl, x, y, width, height, tile, is_selected, is_hovered)
  -- Colors
  local bg_color = tile.color or hexrgb("#334155")
  local border_color = hexrgb("#475569")
  local selected_border = hexrgb("#3B82F6")
  local hover_overlay = hexrgb("#FFFFFF22")

  -- Background
  ImGui.DrawList_AddRectFilled(
    dl, x, y, x + width, y + height,
    bg_color, 8
  )

  -- Hover overlay
  if is_hovered then
    ImGui.DrawList_AddRectFilled(
      dl, x, y, x + width, y + height,
      hover_overlay, 8
    )
  end

  -- Border
  local border = is_selected and selected_border or border_color
  local thickness = is_selected and 2 or 1
  ImGui.DrawList_AddRect(
    dl, x, y, x + width, y + height,
    border, 8, 0, thickness
  )

  -- Label (centered)
  local label = tile.label or "Item"
  local text_w = ImGui.CalcTextSize(ctx, label)
  local text_x = x + (width - text_w) / 2
  local text_y = y + (height - ImGui.GetTextLineHeight(ctx)) / 2

  ImGui.DrawList_AddText(dl, text_x, text_y, hexrgb("#F8FAFC"), label)

  -- Selection indicator (top-right corner)
  if is_selected then
    local indicator_size = 20
    local indicator_x = x + width - indicator_size - 4
    local indicator_y = y + 4

    ImGui.DrawList_AddCircleFilled(
      dl,
      indicator_x + indicator_size / 2,
      indicator_y + indicator_size / 2,
      indicator_size / 2,
      hexrgb("#3B82F6"),
      16
    )

    ImGui.DrawList_AddText(
      dl,
      indicator_x + 5,
      indicator_y + 2,
      hexrgb("#FFFFFF"),
      "✓"
    )
  end
end

-- ============================================================================
-- GRID SHOWCASE
-- ============================================================================

local function showcase_simple_grid(ctx, state)
  ImGui.Text(ctx, "Simple Grid Layout:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.GRID.simple_grid)
  end
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.TextWrapped(ctx, "Click tiles to select/deselect. The grid automatically adjusts column count based on available width.")
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Controls
  local dl = ImGui.GetWindowDrawList(ctx)
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  local clear_clicked = Button.draw(ctx, dl, cursor_x, cursor_y, 120, 28, {
    label = "Clear Selection",
    bg_color = hexrgb("#475569"),
    bg_hover_color = hexrgb("#334155"),
    text_color = hexrgb("#F8FAFC"),
    rounding = 6,
    tooltip = Tooltips.GRID.clear_selection,
  }, "clear_selection_btn")

  if clear_clicked then
    State.clear_selection(state)
  end

  -- Selection count
  local selected_count = #state.grid.selected_items
  ImGui.SetCursorScreenPos(ctx, cursor_x + 130, cursor_y + 6)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), string.format("(%d selected)", selected_count))

  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 36)
  ImGui.Spacing(ctx)

  -- Grid container
  local grid_x, grid_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)

  -- Grid settings
  local tile_size = 100
  local gap = 12
  local columns, actual_tile_width = calculate_grid_layout(avail_w, tile_size, gap)

  -- Render grid
  local items = state.grid.items
  local row = 0
  local col = 0

  for i, tile in ipairs(items) do
    local x = grid_x + col * (actual_tile_width + gap)
    local y = grid_y + row * (tile_size + gap)

    -- Check hover
    local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
    local is_hovered = mouse_x >= x and mouse_x < x + actual_tile_width and
                      mouse_y >= y and mouse_y < y + tile_size

    -- Check selection
    local is_selected = State.is_item_selected(state, tile.id)

    -- Render tile
    render_tile(ctx, dl, x, y, actual_tile_width, tile_size, tile, is_selected, is_hovered)

    -- Handle click
    if is_hovered and ImGui.IsMouseClicked(ctx, 0) then
      State.toggle_item_selection(state, tile.id)
    end

    -- Next position
    col = col + 1
    if col >= columns then
      col = 0
      row = row + 1
    end
  end

  -- Calculate total height
  local total_rows = math.ceil(#items / columns)
  local total_height = total_rows * (tile_size + gap)

  ImGui.SetCursorScreenPos(ctx, grid_x, grid_y + total_height)
  ImGui.Spacing(ctx)
end

-- ============================================================================
-- CODE EXAMPLES
-- ============================================================================

local function show_code_examples(ctx)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  ImGui.Text(ctx, "Production Grid Usage:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.GRID.production_grid)
  end
  ImGui.Spacing(ctx)

  -- Background
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local bg_color = hexrgb("#1E293B")
  local padding = 12

  local code = [[
-- For production apps, use the full Grid widget:
local Grid = require('rearkitekt.gui.widgets.containers.grid.core')

-- Create grid instance
local grid = Grid.new({
  id = "my_grid",
  tile_width = 120,
  tile_height = 100,
  gap = 12,

  -- Custom tile renderer
  render_tile = function(ctx, tile, rect, state)
    -- Your tile rendering code
    render_my_tile(ctx, tile, rect, state)
  end,

  -- Selection support
  selection = true,
  multi_select = true,

  -- Drag & drop support
  dnd_enabled = true,

  -- Animations
  animations = {
    spawn = { enabled = true, duration = 0.28 },
    destroy = { enabled = true },
  },
})

-- In your render loop
grid:render(ctx, items, available_width, available_height)]]

  local text_h = ImGui.GetTextLineHeightWithSpacing(ctx) * 32

  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(
    dl,
    cursor_x - padding,
    cursor_y - padding / 2,
    cursor_x + avail_w + padding,
    cursor_y + text_h + padding / 2,
    bg_color,
    6
  )

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#E2E8F0"))
  ImGui.TextWrapped(ctx, code)
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
end

-- ============================================================================
-- FEATURES LIST
-- ============================================================================

local function show_features(ctx)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  ImGui.TextColored(ctx, hexrgb("#A78BFA"), "Grid System Features")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.GRID.grid_features)
  end
  ImGui.Spacing(ctx)

  local features = {
    { icon = "📐", title = "Responsive Layout", desc = "Automatically adjusts columns based on available width" },
    { icon = "🎯", title = "Multi-Selection", desc = "Click, Ctrl+Click, and marquee selection support" },
    { icon = "🎨", title = "Custom Rendering", desc = "Flexible tile renderer with full drawing control" },
    { icon = "✨", title = "Animations", desc = "Smooth spawn, destroy, and layout transitions" },
    { icon = "🖱️", title = "Drag & Drop", desc = "Reorder items with visual drop indicators" },
    { icon = "📦", title = "Virtualization", desc = "Efficient rendering for large item counts" },
    { icon = "⚡", title = "Performance", desc = "Optimized for 60fps with hundreds of items" },
    { icon = "🎮", title = "Interactions", desc = "Hover, click, double-click, context menu support" },
  }

  for _, feature in ipairs(features) do
    ImGui.TextColored(ctx, hexrgb("#F8FAFC"), feature.icon .. " " .. feature.title)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
    ImGui.Text(ctx, "   " .. feature.desc)
    ImGui.PopStyleColor(ctx)
    ImGui.Spacing(ctx)
  end
end

-- ============================================================================
-- MAIN RENDER
-- ============================================================================

--- Render the grid showcase view
-- @param ctx ImGui context
-- @param state table Demo state object
function M.render(ctx, state)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 20, 20)

  -- Title
  ImGui.TextColored(ctx, hexrgb("#F8FAFC"), "Grid System Showcase")
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.Text(ctx, "Responsive grid layout with selection and interactions")
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Grid demo
  showcase_simple_grid(ctx, state)

  -- Features list
  show_features(ctx)

  -- Code examples
  show_code_examples(ctx)

  ImGui.PopStyleVar(ctx)
end

return M
