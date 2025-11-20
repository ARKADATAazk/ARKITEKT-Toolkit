-- @noindex
-- Demo/ui/primitives_view.lua
--
-- WHY THIS EXISTS: Demonstrates ARKITEKT's primitive UI components like buttons,
-- checkboxes, text rendering, and basic drawing primitives.
--
-- This is the "getting started" view showing the simplest building blocks.
--
-- DEMONSTRATES:
-- - Button widget with states (normal, hover, active)
-- - Checkbox widget with toggle functionality
-- - Text rendering and formatting
-- - Basic drawing primitives (rectangles, circles, lines)
-- - Color manipulation with the Colors module
-- - Spacing and layout basics

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

-- ARKITEKT dependencies
local Button = require('rearkitekt.gui.widgets.primitives.button')
local Checkbox = require('rearkitekt.gui.widgets.primitives.checkbox')
local Colors = require('rearkitekt.core.colors')
local Tooltips = require('Demo.ui.tooltips')

local M = {}
local hexrgb = Colors.hexrgb

-- ============================================================================
-- HELPER: Section Header
-- ============================================================================

--- Draw a section header with title and description
-- @param ctx ImGui context
-- @param title string Section title
-- @param description string Section description
local function draw_section_header(ctx, title, description)
  -- Title (Shell already sets fonts, just use text functions)
  ImGui.TextColored(ctx, hexrgb("#A78BFA"), title)

  -- Description
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.TextWrapped(ctx, description)
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
end

-- ============================================================================
-- HELPER: Code Display
-- ============================================================================

--- Display code snippet in monospace font
-- @param ctx ImGui context
-- @param code string Code to display
local function draw_code_snippet(ctx, code)
  local bg_color = hexrgb("#1E293B")
  local text_color = hexrgb("#E2E8F0")

  -- Background
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local _, newline_count = code:gsub("\n", "\n")
  local text_h = ImGui.GetTextLineHeightWithSpacing(ctx) * (newline_count + 1)
  local padding = 8

  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(
    dl,
    cursor_x - padding,
    cursor_y - padding / 2,
    cursor_x + avail_w + padding,
    cursor_y + text_h + padding / 2,
    bg_color,
    4
  )

  -- Code text
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
  ImGui.TextWrapped(ctx, code)
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
end

-- ============================================================================
-- SHOWCASE: Buttons
-- ============================================================================

local function showcase_buttons(ctx, state)
  draw_section_header(
    ctx,
    "🔘 Buttons",
    "Interactive button component with hover and click states. Buttons support custom colors, icons, tooltips, and callbacks."
  )

  local dl = ImGui.GetWindowDrawList(ctx)
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  -- Example 1: Basic Button
  ImGui.Text(ctx, "Basic button with click counter:")
  ImGui.Spacing(ctx)

  local btn_clicked = Button.draw_at_cursor(ctx, {
    label = "Click Me! (" .. state.primitives.button_click_count .. ")",
    height = 32,
    tooltip = Tooltips.PRIMITIVES.button_basic,
  }, "demo_btn_1")

  if btn_clicked then
    state.primitives.button_click_count = state.primitives.button_click_count + 1
  end

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Example 2: Colored Buttons
  ImGui.Text(ctx, "Buttons with custom colors:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.PRIMITIVES.button_colored)
  end
  ImGui.Spacing(ctx)

  cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  -- Success button
  Button.draw(ctx, dl, cursor_x, cursor_y, 100, 28, {
    label = "Success",
    bg_color = hexrgb("#10B981"),
    bg_hover_color = hexrgb("#059669"),
    text_color = hexrgb("#FFFFFF"),
    rounding = 6,
  }, "btn_success")

  -- Warning button
  Button.draw(ctx, dl, cursor_x + 110, cursor_y, 100, 28, {
    label = "Warning",
    bg_color = hexrgb("#F59E0B"),
    bg_hover_color = hexrgb("#D97706"),
    text_color = hexrgb("#FFFFFF"),
    rounding = 6,
  }, "btn_warning")

  -- Danger button
  Button.draw(ctx, dl, cursor_x + 220, cursor_y, 100, 28, {
    label = "Danger",
    bg_color = hexrgb("#EF4444"),
    bg_hover_color = hexrgb("#DC2626"),
    text_color = hexrgb("#FFFFFF"),
    rounding = 6,
  }, "btn_danger")

  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 32)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Code example
  ImGui.Text(ctx, "Usage:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.CODE.button_example)
  end
  draw_code_snippet(ctx, [[
local Button = require('rearkitekt.gui.widgets.primitives.button')

local clicked = Button.draw_at_cursor(ctx, {
  label = "Click Me!",
  height = 32,
  tooltip = "Helpful tooltip text",
  bg_color = 0x3B82F6FF,
  on_click = function() print("Clicked!") end
}, "unique_button_id")]])

  ImGui.Separator(ctx)
end

-- ============================================================================
-- SHOWCASE: Checkboxes
-- ============================================================================

local function showcase_checkboxes(ctx, state)
  draw_section_header(
    ctx,
    "☑️  Checkboxes",
    "Toggle widgets for binary states. Support animations and custom styling."
  )

  -- Basic checkbox
  ImGui.Text(ctx, "Basic checkbox:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.PRIMITIVES.checkbox_basic)
  end
  ImGui.Spacing(ctx)

  local cb_clicked = Checkbox.draw_at_cursor(
    ctx,
    "Enable feature",
    state.primitives.checkbox_state,
    {},
    "demo_cb_1"
  )

  if cb_clicked then
    state.primitives.checkbox_state = not state.primitives.checkbox_state
  end

  ImGui.Text(ctx, "State: " .. (state.primitives.checkbox_state and "Checked" or "Unchecked"))

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Code example
  ImGui.Text(ctx, "Usage:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.CODE.checkbox_example)
  end
  draw_code_snippet(ctx, [[
local Checkbox = require('rearkitekt.gui.widgets.primitives.checkbox')

local clicked = Checkbox.draw_at_cursor(
  ctx,
  "Enable feature",    -- label
  current_state,       -- is_checked
  {},                  -- config (optional)
  "checkbox_id"        -- unique id
)

if clicked then
  current_state = not current_state
end]])

  ImGui.Separator(ctx)
end

-- ============================================================================
-- SHOWCASE: Text and Typography
-- ============================================================================

local function showcase_text(ctx, state)
  draw_section_header(
    ctx,
    "📝 Text and Typography",
    "Various text rendering options including colors, sizes, and formatting."
  )

  -- Different text colors
  ImGui.Text(ctx, "Colored text:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.PRIMITIVES.text_colored)
  end
  ImGui.Spacing(ctx)

  ImGui.TextColored(ctx, hexrgb("#EF4444"), "• Red text (errors, warnings)")
  ImGui.TextColored(ctx, hexrgb("#10B981"), "• Green text (success, confirmation)")
  ImGui.TextColored(ctx, hexrgb("#3B82F6"), "• Blue text (information, links)")
  ImGui.TextColored(ctx, hexrgb("#A78BFA"), "• Purple text (highlights, special)")
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "• Gray text (secondary, muted)")

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Wrapped text
  ImGui.Text(ctx, "Text wrapping:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.PRIMITIVES.text_wrapped)
  end
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.PushTextWrapPos(ctx, ImGui.GetCursorPosX(ctx) + 400)
  ImGui.TextWrapped(ctx, "This is a long paragraph that demonstrates text wrapping. The text will automatically wrap to the next line when it reaches the boundary. This is useful for descriptions, help text, and documentation.")
  ImGui.PopTextWrapPos(ctx)
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Code example
  ImGui.Text(ctx, "Usage:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.CODE.text_example)
  end
  draw_code_snippet(ctx, [[
-- Simple text
ImGui.Text(ctx, "Hello World")

-- Colored text
local Colors = require('rearkitekt.core.colors')
ImGui.TextColored(ctx, Colors.hexrgb("#3B82F6"), "Blue text")

-- Wrapped text
ImGui.PushTextWrapPos(ctx, ImGui.GetCursorPosX(ctx) + max_width)
ImGui.TextWrapped(ctx, "Long text that will wrap...")
ImGui.PopTextWrapPos(ctx)]])

  ImGui.Separator(ctx)
end

-- ============================================================================
-- SHOWCASE: Drawing Primitives
-- ============================================================================

local function showcase_drawing_primitives(ctx, state)
  draw_section_header(
    ctx,
    "🎨 Drawing Primitives",
    "Low-level drawing functions for custom graphics: rectangles, circles, lines, and paths."
  )

  local dl = ImGui.GetWindowDrawList(ctx)
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  ImGui.Text(ctx, "Basic shapes:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.PRIMITIVES.drawing_primitives)
  end
  ImGui.Spacing(ctx)

  cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  -- Rectangles
  ImGui.DrawList_AddRectFilled(
    dl,
    cursor_x,
    cursor_y,
    cursor_x + 80,
    cursor_y + 60,
    hexrgb("#3B82F6"),
    8
  )
  ImGui.DrawList_AddText(dl, cursor_x + 15, cursor_y + 22, hexrgb("#FFFFFF"), "Filled")

  -- Outlined rectangle
  ImGui.DrawList_AddRect(
    dl,
    cursor_x + 100,
    cursor_y,
    cursor_x + 180,
    cursor_y + 60,
    hexrgb("#10B981"),
    8,
    0,
    2
  )
  ImGui.DrawList_AddText(dl, cursor_x + 110, cursor_y + 22, hexrgb("#10B981"), "Outline")

  -- Circle
  ImGui.DrawList_AddCircleFilled(
    dl,
    cursor_x + 230,
    cursor_y + 30,
    30,
    hexrgb("#F59E0B"),
    32
  )
  ImGui.DrawList_AddText(dl, cursor_x + 210, cursor_y + 22, hexrgb("#1E293B"), "Circle")

  -- Line
  ImGui.DrawList_AddLine(
    dl,
    cursor_x + 280,
    cursor_y + 10,
    cursor_x + 360,
    cursor_y + 50,
    hexrgb("#EF4444"),
    3
  )
  ImGui.DrawList_AddText(dl, cursor_x + 300, cursor_y + 5, hexrgb("#EF4444"), "Line")

  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 70)
  ImGui.Spacing(ctx)

  -- Code example
  ImGui.Text(ctx, "Usage:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.CODE.drawing_example)
  end
  draw_code_snippet(ctx, [[
local dl = ImGui.GetWindowDrawList(ctx)
local Colors = require('rearkitekt.core.colors')
local hexrgb = Colors.hexrgb

-- Filled rectangle
ImGui.DrawList_AddRectFilled(
  dl, x1, y1, x2, y2,
  hexrgb("#3B82F6"),  -- Color
  8                    -- Corner rounding
)

-- Outlined rectangle
ImGui.DrawList_AddRect(
  dl, x1, y1, x2, y2,
  hexrgb("#10B981"),   -- Color
  8,                   -- Corner rounding
  0,                   -- Flags
  2                    -- Thickness
)

-- Filled circle
ImGui.DrawList_AddCircleFilled(
  dl, center_x, center_y,
  radius,
  hexrgb("#F59E0B"),   -- Color
  32                   -- Segments (smoothness)
)

-- Line
ImGui.DrawList_AddLine(
  dl, x1, y1, x2, y2,
  hexrgb("#EF4444"),   -- Color
  3                    -- Thickness
)]])

  ImGui.Separator(ctx)
end

-- ============================================================================
-- SHOWCASE: Color Utilities
-- ============================================================================

local function showcase_color_utilities(ctx, state)
  draw_section_header(
    ctx,
    "🌈 Color Utilities",
    "ARKITEKT's color module provides hex conversion, brightness/saturation adjustments, and color mixing."
  )

  local dl = ImGui.GetWindowDrawList(ctx)
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  ImGui.Text(ctx, "Base color:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.PRIMITIVES.color_utilities)
  end
  local base_color = state.primitives.color_value

  -- Show base color
  cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddRectFilled(
    dl,
    cursor_x,
    cursor_y,
    cursor_x + 100,
    cursor_y + 40,
    base_color,
    6
  )
  ImGui.SetCursorScreenPos(ctx, cursor_x + 110, cursor_y + 10)
  ImGui.Text(ctx, string.format("0x%08X", base_color))

  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 50)
  ImGui.Spacing(ctx)

  -- Brightness variations
  ImGui.Text(ctx, "Brightness variations:")
  ImGui.Spacing(ctx)

  cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  local brightness_levels = { 0.5, 0.75, 1.0, 1.25, 1.5 }
  for i, brightness in ipairs(brightness_levels) do
    local adjusted = Colors.adjust_brightness(base_color, brightness)
    local x = cursor_x + (i - 1) * 75

    ImGui.DrawList_AddRectFilled(
      dl, x, cursor_y, x + 60, cursor_y + 40,
      adjusted, 6
    )
    ImGui.DrawList_AddText(
      dl, x + 15, cursor_y + 45,
      hexrgb("#94A3B8"),
      string.format("×%.2f", brightness)
    )
  end

  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 70)
  ImGui.Spacing(ctx)

  -- Saturation variations
  ImGui.Text(ctx, "Saturation variations:")
  ImGui.Spacing(ctx)

  cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

  local saturation_levels = { -1.0, -0.5, 0.0, 0.5, 1.0 }
  for i, saturation in ipairs(saturation_levels) do
    local adjusted
    if saturation < 0 then
      adjusted = Colors.desaturate(base_color, -saturation)
    else
      adjusted = Colors.saturate(base_color, saturation)
    end

    local x = cursor_x + (i - 1) * 75

    ImGui.DrawList_AddRectFilled(
      dl, x, cursor_y, x + 60, cursor_y + 40,
      adjusted, 6
    )
    ImGui.DrawList_AddText(
      dl, x + 10, cursor_y + 45,
      hexrgb("#94A3B8"),
      string.format("%+.1f", saturation)
    )
  end

  ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 70)
  ImGui.Spacing(ctx)

  -- Code example
  ImGui.Text(ctx, "Usage:")
  ImGui.SameLine(ctx, 0, 8)
  ImGui.TextColored(ctx, hexrgb("#94A3B8"), "(?)")
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, Tooltips.CODE.color_example)
  end
  draw_code_snippet(ctx, [[
local Colors = require('rearkitekt.core.colors')

-- Convert hex string to color
local color = Colors.hexrgb("#3B82F6")

-- Adjust brightness
local brighter = Colors.adjust_brightness(color, 1.5)
local darker = Colors.adjust_brightness(color, 0.5)

-- Adjust saturation
local saturated = Colors.saturate(color, 0.5)
local desaturated = Colors.desaturate(color, 0.5)

-- Adjust alpha
local semi_transparent = Colors.with_alpha(color, 128)

-- Lerp between colors
local mixed = Colors.lerp(color1, color2, 0.5)]])

  ImGui.Separator(ctx)
end

-- ============================================================================
-- MAIN RENDER
-- ============================================================================

--- Render the primitives showcase view
-- @param ctx ImGui context
-- @param state table Demo state object
function M.render(ctx, state)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 20, 20)

  -- Title (Shell already sets fonts)
  ImGui.TextColored(ctx, hexrgb("#F8FAFC"), "Primitives Showcase")

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.Text(ctx, "Learn the basic building blocks of ARKITEKT interfaces")
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Showcases
  showcase_buttons(ctx, state)
  showcase_checkboxes(ctx, state)
  showcase_text(ctx, state)
  showcase_drawing_primitives(ctx, state)
  showcase_color_utilities(ctx, state)

  ImGui.PopStyleVar(ctx)
end

return M
