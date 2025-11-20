-- @noindex
-- Demo/ui/welcome_view.lua
--
-- WHY THIS EXISTS: Welcome screen that introduces the ARKITEKT Demo and provides
-- an overview of what can be learned from each section.
--
-- This is the landing page that helps users navigate the demo effectively.

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local Colors = require('rearkitekt.core.colors')

local M = {}
local hexrgb = Colors.hexrgb

-- ============================================================================
-- MAIN RENDER
-- ============================================================================

--- Render the welcome view
-- @param ctx ImGui context
-- @param state table Demo state object
function M.render(ctx, state)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 30, 30)

  -- Hero section
  local cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)

  -- Background accent
  local dl = ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(
    dl,
    cursor_x - 30,
    cursor_y - 30,
    cursor_x + avail_w + 30,
    cursor_y + 120,
    hexrgb("#1E293B"),
    0
  )

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Title (Shell already sets default font, no need to push)
  ImGui.TextColored(ctx, hexrgb("#F8FAFC"), "ARKITEKT Framework Demo")

  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.PushTextWrapPos(ctx, ImGui.GetCursorPosX(ctx) + avail_w - 60)
  ImGui.TextWrapped(ctx, "Welcome to the ARKITEKT demo! This interactive showcase demonstrates the core features of the ARKITEKT framework for building professional REAPER interfaces with ImGui.")
  ImGui.PopTextWrapPos(ctx)
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- What you'll learn section
  ImGui.TextColored(ctx, hexrgb("#A78BFA"), "📚 What You'll Learn")
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  local sections = {
    {
      title = "Primitives",
      icon = "🔘",
      description = "Start here to learn the basic building blocks: buttons, checkboxes, text rendering, drawing shapes, and color utilities. Perfect for beginners.",
      color = hexrgb("#3B82F6"),
    },
    {
      title = "Grid System",
      icon = "📦",
      description = "Explore the powerful grid layout system with responsive columns, multi-selection, and custom tile rendering. Essential for any browsing interface.",
      color = hexrgb("#10B981"),
    },
    {
      title = "Coming Soon",
      icon = "🚧",
      description = "More showcases coming: panels & tabs, animations, overlays & modals, and complete application patterns.",
      color = hexrgb("#94A3B8"),
    },
  }

  for i, section in ipairs(sections) do
    -- Section card
    cursor_x, cursor_y = ImGui.GetCursorScreenPos(ctx)

    -- Card background
    ImGui.DrawList_AddRectFilled(
      dl,
      cursor_x - 15,
      cursor_y - 10,
      cursor_x + avail_w - 15,
      cursor_y + 85,
      hexrgb("#334155"),
      8
    )

    -- Accent border
    ImGui.DrawList_AddRect(
      dl,
      cursor_x - 15,
      cursor_y - 10,
      cursor_x + avail_w - 15,
      cursor_y + 85,
      section.color,
      8,
      0,
      2
    )

    -- Icon and title
    ImGui.Text(ctx, section.icon)
    ImGui.SameLine(ctx, 0, 8)
    ImGui.TextColored(ctx, hexrgb("#F8FAFC"), section.title)

    ImGui.Spacing(ctx)

    -- Description
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#CBD5E1"))
    ImGui.PushTextWrapPos(ctx, ImGui.GetCursorPosX(ctx) + avail_w - 45)
    ImGui.TextWrapped(ctx, section.description)
    ImGui.PopTextWrapPos(ctx)
    ImGui.PopStyleColor(ctx)

    ImGui.SetCursorScreenPos(ctx, cursor_x, cursor_y + 95)
    ImGui.Spacing(ctx)
  end

  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- Getting started
  ImGui.TextColored(ctx, hexrgb("#A78BFA"), "🚀 Getting Started")
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
  ImGui.Text(ctx, "1. Navigate through tabs at the top to explore different features")
  ImGui.Text(ctx, "2. Interact with examples to see how they work")
  ImGui.Text(ctx, "3. Read code snippets to learn the API")
  ImGui.Text(ctx, "4. Use these patterns in your own REAPER scripts")
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  -- About ARKITEKT
  ImGui.TextColored(ctx, hexrgb("#A78BFA"), "💡 About ARKITEKT")
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#CBD5E1"))
  ImGui.PushTextWrapPos(ctx, ImGui.GetCursorPosX(ctx) + avail_w - 30)
  ImGui.TextWrapped(ctx, "ARKITEKT is a comprehensive ImGui framework for REAPER that provides:")
  ImGui.PopTextWrapPos(ctx)
  ImGui.PopStyleColor(ctx)

  ImGui.Spacing(ctx)

  local features = {
    "✨ Clean, consistent UI components",
    "🎨 Powerful color and theme system",
    "📦 Responsive grid layouts",
    "🎬 Smooth animations and transitions",
    "🔧 Modular, reusable architecture",
    "📚 Well-documented APIs",
    "⚡ High-performance rendering",
    "🤝 Easy to extend and customize",
  }

  for _, feature in ipairs(features) do
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#94A3B8"))
    ImGui.Text(ctx, feature)
    ImGui.PopStyleColor(ctx)
  end

  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, hexrgb("#64748B"))
  ImGui.Text(ctx, "Use the tabs above to start exploring!")
  ImGui.PopStyleColor(ctx)

  ImGui.PopStyleVar(ctx)
end

return M
