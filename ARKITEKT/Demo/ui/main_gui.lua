-- @noindex
-- Demo/ui/main_gui.lua
--
-- WHY THIS EXISTS: Main UI orchestrator for the ARKITEKT demo app.
-- Manages the tab navigation and renders the appropriate view.
--
-- This demonstrates how to structure a multi-view application using
-- native ImGui tabs. (For more advanced panel usage with custom headers,
-- see the ColorPalette or Region_Playlist apps.)

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

-- Demo views
local WelcomeView = require('Demo.ui.welcome_view')
local PrimitivesView = require('Demo.ui.primitives_view')
local GridView = require('Demo.ui.grid_view')

local M = {}

-- ============================================================================
-- MAIN RENDER
-- ============================================================================

--- Render the main demo UI
-- @param ctx ImGui context
-- @param state table Demo state object
-- @param available_width number Available width for rendering
-- @param available_height number Available height for rendering
function M.render(ctx, state, available_width, available_height)
  -- NOTE: Tab styling is handled by the style module passed to Shell.run()
  -- No need to manually style tabs here.

  -- Begin tab bar
  if ImGui.BeginTabBar(ctx, "##demo_tabs", ImGui.TabBarFlags_None) then
    -- Welcome tab
    if ImGui.BeginTabItem(ctx, "👋 Welcome") then
      -- Content area for this tab
      ImGui.BeginChild(ctx, "##welcome_content")
      WelcomeView.render(ctx, state)
      ImGui.EndChild(ctx)
      ImGui.EndTabItem(ctx)
    end

    -- Primitives tab
    if ImGui.BeginTabItem(ctx, "🔘 Primitives") then
      ImGui.BeginChild(ctx, "##primitives_content")
      PrimitivesView.render(ctx, state)
      ImGui.EndChild(ctx)
      ImGui.EndTabItem(ctx)
    end

    -- Grid tab
    if ImGui.BeginTabItem(ctx, "📦 Grid System") then
      ImGui.BeginChild(ctx, "##grid_content")
      GridView.render(ctx, state)
      ImGui.EndChild(ctx)
      ImGui.EndTabItem(ctx)
    end

    ImGui.EndTabBar(ctx)
  end
end

return M
