-- @noindex
-- ReArkitekt/gui/utils/interaction_blocking.lua
-- Centralized utility for checking if user interactions should be blocked
-- due to popups, modals, or overlay managers being active

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local M = {}

-- Cached overlay manager reference (loaded once on first use)
local OverlayManager = nil
local overlay_manager_loaded = false

local function get_overlay_manager()
  if not overlay_manager_loaded then
    pcall(function()
      OverlayManager = require('arkitekt.gui.widgets.overlays.overlay.manager')
    end)
    overlay_manager_loaded = true
  end
  return OverlayManager
end

--- Check if any interaction should be blocked due to popups/modals/overlays
-- @param ctx ImGui context
-- @param custom_blocking boolean|nil Optional custom blocking condition
-- @param ignore_modal boolean|nil If true, bypasses modal/overlay blocking (for critical UI like close buttons)
-- @return boolean true if interaction should be blocked
function M.should_block_interaction(ctx, custom_blocking, ignore_modal)
  -- Check custom blocking first
  if custom_blocking then
    return true
  end

  -- Allow priority interactions (window controls, etc.) to bypass modal blocking
  if ignore_modal then
    return false
  end

  -- Check overlay manager (prevents one-frame delay on overlay open)
  local overlay_mgr = get_overlay_manager()
  if overlay_mgr and overlay_mgr.has_active_overlays() then
    return true
  end

  -- Check if any ImGui popup is open
  if ImGui.IsPopupOpen(ctx, '', ImGui.PopupFlags_AnyPopupId) then
    return true
  end

  return false
end

--- Wrapper for IsMouseHoveringRect that respects popup/overlay blocking
-- @param ctx ImGui context
-- @param x1 number Left X coordinate
-- @param y1 number Top Y coordinate
-- @param x2 number Right X coordinate
-- @param y2 number Bottom Y coordinate
-- @param custom_blocking boolean|nil Optional custom blocking condition
-- @param ignore_modal boolean|nil If true, bypasses modal/overlay blocking (for critical UI like close buttons)
-- @return boolean true if mouse is hovering rect AND not blocked
function M.is_mouse_hovering_rect_unblocked(ctx, x1, y1, x2, y2, custom_blocking, ignore_modal)
  if M.should_block_interaction(ctx, custom_blocking, ignore_modal) then
    return false
  end

  return ImGui.IsMouseHoveringRect(ctx, x1, y1, x2, y2)
end

return M
