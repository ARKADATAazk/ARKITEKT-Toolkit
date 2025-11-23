-- @noindex
-- ReArkitekt/gui/style/imgui_defaults.lua
-- ImGui theme overrides and base styling
-- This provides fallback styling for native ImGui widgets when custom components aren't used

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')

local M = {}
local hexrgb = Colors.hexrgb
local style_color_stack = {}

-- ImGui-specific color palette
-- These are primarily for native ImGui widgets (buttons, sliders, etc.)
-- For custom components, use gui/style/defaults.lua M.COLORS instead
local C = {
  white         = hexrgb("#FFFFFF"),
  black         = hexrgb("#000000"),
  teal          = hexrgb("#41E0A3FF"),
  teal_dark     = hexrgb("#008F6FCC"),
  red           = hexrgb("#E04141FF"),
  yellow        = hexrgb("#E0B341FF"),
  grey_84       = hexrgb("#D6D6D6FF"),
  grey_60       = hexrgb("#999999FF"),
  grey_52       = hexrgb("#858585FF"),
  grey_48       = hexrgb("#7A7A7AFF"),
  grey_40       = hexrgb("#666666FF"),
  grey_35       = hexrgb("#595959FF"),
  grey_31       = hexrgb("#4F4F4FFF"),
  grey_30       = hexrgb("#4D4D4DFF"),
  grey_27       = hexrgb("#454545FF"),
  grey_25       = hexrgb("#404040FF"),
  grey_20       = hexrgb("#333333FF"),
  grey_18       = hexrgb("#2E2E2EFF"),
  grey_15       = hexrgb("#262626FF"),
  grey_14       = hexrgb("#242424FF"),
  grey_10       = hexrgb("#1A1A1AFF"),
  grey_09       = hexrgb("#171717FF"),
  grey_08       = hexrgb("#141414FF"),
  grey_07       = hexrgb("#121212FF"),
  grey_06       = hexrgb("#0F0F0FFF"),
  grey_05       = hexrgb("#0B0B0BFF"),
  border_strong = hexrgb("#000000FF"),
  border_soft   = hexrgb("#000000DD"),
  scroll_bg     = hexrgb("#05050587"),
  tree_lines    = hexrgb("#6E6E8080"),
}

function M.with_alpha(col, a)
  return (col & 0xFFFFFF00) | (a & 0xFF)
end

M.palette = C

function M.PushMyStyle(ctx, opts)
  opts = opts or {}
  local push_window_bg = (opts.window_bg ~= false)
  local push_modal_dim_bg = (opts.modal_dim_bg ~= false)

  local color_pushes = 0
  local function push_color(...)
    ImGui.PushStyleColor(ctx, ...)
    color_pushes = color_pushes + 1
  end

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_DisabledAlpha, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowMinSize, 32, 32)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowTitleAlign, 0, 0.5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 4, 2)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing, 4, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_IndentSpacing, 22)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_CellPadding, 4, 2)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarSize, 12)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 30)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_TabRounding, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_TabBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_TabBarBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_TableAngledHeadersAngle, 0.401426)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0.5, 0.51)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_SeparatorTextBorderSize, 3)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_SeparatorTextAlign, 0, 0.5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_SeparatorTextPadding, 20, 3)

  local A = M.with_alpha
  push_color(ImGui.Col_Text, C.white)
  push_color(ImGui.Col_TextDisabled, hexrgb("#848484FF"))
  if push_window_bg then
    push_color(ImGui.Col_WindowBg, opts.window_bg_color or C.grey_14)
  end
  push_color(ImGui.Col_ChildBg, hexrgb("#0D0D0D00"))
  push_color(ImGui.Col_PopupBg, A(C.grey_08, 0xF0))
  push_color(ImGui.Col_Border, hexrgb("#000000ff"))
  push_color(ImGui.Col_BorderShadow, hexrgb("#00000000"))
  push_color(ImGui.Col_FrameBg, A(C.grey_06, 0x8A))
  push_color(ImGui.Col_FrameBgHovered, A(C.grey_08, 0x66))
  push_color(ImGui.Col_FrameBgActive, A(C.grey_18, 0xAB))
  push_color(ImGui.Col_TitleBg, C.grey_06)
  push_color(ImGui.Col_TitleBgActive, C.grey_08)
  push_color(ImGui.Col_TitleBgCollapsed, hexrgb("#00000082"))
  push_color(ImGui.Col_MenuBarBg, C.grey_14)
  push_color(ImGui.Col_ScrollbarBg, hexrgb("#00000000"))
  push_color(ImGui.Col_ScrollbarGrab, hexrgb("#4A4A4AFF"))
  push_color(ImGui.Col_ScrollbarGrabHovered, hexrgb("#5A5A5AFF"))
  push_color(ImGui.Col_ScrollbarGrabActive, hexrgb("#6A6A6AFF"))
  push_color(ImGui.Col_CheckMark, hexrgb("#7b7b7bff"))
  push_color(ImGui.Col_SliderGrab, hexrgb("#444444ff"))
  push_color(ImGui.Col_SliderGrabActive, hexrgb("#6c6c6cff"))
  push_color(ImGui.Col_Button, A(C.grey_05, 0x66))
  push_color(ImGui.Col_ButtonHovered, C.grey_20)
  push_color(ImGui.Col_ButtonActive, C.grey_18)
  push_color(ImGui.Col_Header, hexrgb("#0000004F"))
  push_color(ImGui.Col_HeaderHovered, hexrgb("#313131ff"))
  push_color(ImGui.Col_HeaderActive, hexrgb("#393939ff"))
  push_color(ImGui.Col_Separator, hexrgb("#00000000"))
  push_color(ImGui.Col_SeparatorHovered, hexrgb("#00000000"))
  push_color(ImGui.Col_SeparatorActive, hexrgb("#00000000"))
  push_color(ImGui.Col_ResizeGrip, C.grey_18)
  push_color(ImGui.Col_ResizeGripHovered, C.grey_18)
  push_color(ImGui.Col_ResizeGripActive, C.grey_20)
  push_color(ImGui.Col_TabHovered, hexrgb("#42FA8FCC"))
  push_color(ImGui.Col_Tab, hexrgb("#000000DC"))
  --ImGui.PushStyleColor(ctx, ImGui.Col_TabActive, C.grey_08)
  --ImGui.PushStyleColor(ctx, ImGui.Col_TabUnfocused, hexrgb("#11261FF8"))
  --ImGui.PushStyleColor(ctx, ImGui.Col_TabUnfocusedActive, hexrgb("#236C42FF"))
  push_color(ImGui.Col_DockingPreview, hexrgb("#42FAAAB3"))
  push_color(ImGui.Col_DockingEmptyBg, C.grey_20)
  push_color(ImGui.Col_PlotLines, hexrgb("#000000ff"))
  push_color(ImGui.Col_PlotLinesHovered, hexrgb("#FF6E59FF"))
  push_color(ImGui.Col_PlotHistogram, hexrgb("#E6B300FF"))
  push_color(ImGui.Col_PlotHistogramHovered, hexrgb("#FF9900FF"))
  push_color(ImGui.Col_TableHeaderBg, C.grey_05)
  push_color(ImGui.Col_TableBorderStrong, C.border_strong)
  push_color(ImGui.Col_TableBorderLight, C.grey_07)
  push_color(ImGui.Col_TableRowBg, hexrgb("#0000000A"))
  push_color(ImGui.Col_TableRowBgAlt, hexrgb("#B0B0B00F"))
  push_color(ImGui.Col_TextSelectedBg, hexrgb("#53535366"))
  push_color(ImGui.Col_DragDropTarget, hexrgb("#989898e6"))
  push_color(ImGui.Col_NavWindowingHighlight, hexrgb("#979797b3"))
  push_color(ImGui.Col_NavWindowingDimBg, hexrgb("#CCCCCC33"))
  if push_modal_dim_bg then
    push_color(ImGui.Col_ModalWindowDimBg, hexrgb("#CCCCCC59"))
  end

  table.insert(style_color_stack, color_pushes)
end

function M.PopMyStyle(ctx)
  local color_pushes = table.remove(style_color_stack) or 0
  if color_pushes > 0 then
    ImGui.PopStyleColor(ctx, color_pushes)
  end
  ImGui.PopStyleVar(ctx, 31)
end

return M
