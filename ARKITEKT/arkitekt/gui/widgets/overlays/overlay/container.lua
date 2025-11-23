-- @noindex
-- ReArkitekt/gui/widgets/overlay/container.lua
-- Reusable dark container pattern for non-blocking modals

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

-- Default container styling - simple squares with 1px black border
local DEFAULTS = {
  width = 0.6,           -- Percentage of bounds width
  height = 0.8,          -- Percentage of bounds height
  rounding = 0,          -- Square corners (no rounding)
  bg_color = hexrgb("#1e1e1e"),  -- Slightly lighter dark background
  bg_opacity = 1.0,
  border_color = hexrgb("#000000"),  -- Black border
  border_opacity = 1.0,
  border_thickness = 1,  -- 1 pixel border
  padding = 20,          -- Internal padding for content spacing
}

-- Render a dark container with content
-- Usage in overlay render callback:
--   Container.render(ctx, alpha, bounds, function(ctx, content_w, content_h)
--     -- Your content here
--   end, { width = 0.5, height = 0.6 })
function M.render(ctx, alpha, bounds, content_fn, opts)
  opts = opts or {}

  -- Merge with defaults (use inverted ternary to handle false values correctly)
  local config = {}
  for k, v in pairs(DEFAULTS) do
    config[k] = opts[k] == nil and v or opts[k]
  end

  -- Calculate container dimensions
  local w = math.floor(bounds.w * config.width)
  local h = math.floor(bounds.h * config.height)
  local x = math.floor(bounds.x + (bounds.w - w) * 0.5)
  local y = math.floor(bounds.y + (bounds.h - h) * 0.5)
  local r = config.rounding

  -- Create child window for container (renders above scrim)
  ImGui.SetCursorScreenPos(ctx, x, y)

  -- Use built-in WindowPadding instead of manual cursor positioning
  -- This ensures all ImGui elements respect the padding automatically
  local padding = config.padding
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, padding, padding)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, r)

  -- Dark background color for child
  local bg_color = Colors.with_alpha(config.bg_color, math.floor(255 * config.bg_opacity * alpha))
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, bg_color)

  -- CRITICAL: AlwaysUseWindowPadding flag ensures WindowPadding style var is applied
  -- Without this flag, child windows ignore WindowPadding by default
  local child_flags = ImGui.ChildFlags_AlwaysUseWindowPadding or 0
  local window_flags = 0  -- Allow scrolling
  ImGui.BeginChild(ctx, '##modal_container', w, h, child_flags, window_flags)

  -- Draw simple 1px black border
  local dl = ImGui.GetWindowDrawList(ctx)
  local border_color = Colors.with_alpha(config.border_color, math.floor(255 * config.border_opacity * alpha))
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, border_color, r, 0, config.border_thickness)

  ImGui.PopStyleColor(ctx, 1)
  ImGui.PopStyleVar(ctx, 2)

  -- Content dimensions account for padding (applied via WindowPadding)
  local content_w = w - padding * 2
  local content_h = h - padding * 2

  if content_fn then
    content_fn(ctx, content_w, content_h, w, h, alpha, padding)
  end

  ImGui.EndChild(ctx)
end

return M
