-- @noindex
-- ReArkitekt/gui/widgets/tools/color_picker_window.lua
-- Floating color picker window for live batch recoloring
-- Opens as a draggable, always-on-top window with hue wheel picker
-- Changes apply instantly to selected items as you adjust the color

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('rearkitekt.core.colors')

local M = {}

-- State for each picker instance
local instances = {}

--- Create or get a color picker instance
--- @param id string Unique identifier for this picker
--- @return table Instance state
local function get_instance(id)
  if not instances[id] then
    instances[id] = {
      is_open = false,
      current_color = 0xFF0000FF,  -- Default red
      backup_color = nil,
      first_open = true,
    }
  end
  return instances[id]
end

--- Open the color picker window
--- @param id string Unique identifier for this picker
--- @param initial_color number Optional initial color (RGBA)
function M.open(id, initial_color)
  local inst = get_instance(id)
  inst.is_open = true
  if initial_color then
    inst.current_color = initial_color
    inst.backup_color = initial_color
  end
  inst.first_open = true
end

--- Close the color picker window
--- @param id string Unique identifier for this picker
function M.close(id)
  local inst = get_instance(id)
  inst.is_open = false
end

--- Check if the color picker is open
--- @param id string Unique identifier for this picker
--- @return boolean
function M.is_open(id)
  local inst = get_instance(id)
  return inst.is_open
end

--- Render the color picker contents (without window wrapper)
--- @param ctx userdata ImGui context
--- @param id string Unique identifier for this picker
--- @param on_change function Callback when color changes
--- @return boolean changed Whether color was changed this frame
local function render_picker_contents(ctx, id, on_change)
  local inst = get_instance(id)
  local changed = false

  -- Get cursor position before drawing
  local cx, cy = ImGui.GetCursorScreenPos(ctx)

  -- Color picker configuration
  local picker_flags = ImGui.ColorEditFlags_PickerHueWheel |
                       ImGui.ColorEditFlags_NoSidePreview |
                       ImGui.ColorEditFlags_NoSmallPreview |
                       ImGui.ColorEditFlags_NoAlpha |
                       ImGui.ColorEditFlags_NoInputs |
                       ImGui.ColorEditFlags_NoLabel

  -- Convert our RGBA to ImGui's ARGB format
  local argb_color = Colors.rgba_to_argb(inst.current_color)

  -- Draw the color picker (hue wheel + triangle) - native ImGui for smooth gradients
  local rv, new_argb_color = ImGui.ColorPicker4(ctx, '##picker_' .. id, argb_color, picker_flags)

  -- Draw custom black borders on top
  local draw_list = ImGui.GetWindowDrawList(ctx)
  local size = 195  -- ImGui's default picker size
  local wheel_thickness = size * 0.08
  local wheel_r_outer = size * 0.50
  local wheel_r_inner = wheel_r_outer - wheel_thickness
  local center_x = cx + size * 0.5
  local center_y = cy + size * 0.5

  -- Draw black circles for wheel borders
  local col_black = 0xFF000000
  ImGui.DrawList_AddCircle(draw_list, center_x, center_y, wheel_r_outer, col_black, 64, 2.0)
  ImGui.DrawList_AddCircle(draw_list, center_x, center_y, wheel_r_inner, col_black, 64, 2.0)

  -- Track color changes during dragging, but only apply on mouse release
  if rv then
    -- Convert ImGui's ARGB back to our RGBA format
    local new_rgba = Colors.argb_to_rgba(new_argb_color)
    inst.current_color = new_rgba
    changed = true

    -- Store that we have a pending change
    inst.pending_change = true
  end

  -- Apply color only when mouse button is released
  if inst.pending_change and ImGui.IsMouseReleased(ctx, 0) then
    inst.pending_change = false

    if on_change then
      on_change(inst.current_color)
    end
  end

  -- Show hex value
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  local hex_str = string.format("#%06X", (inst.current_color >> 8) & 0xFFFFFF)
  ImGui.Text(ctx, "Color: " .. hex_str)

  return changed
end

--- Render the color picker as a floating window
--- @param ctx userdata ImGui context
--- @param id string Unique identifier for this picker
--- @param config table Configuration { on_change = function(color), title = string }
--- @return boolean changed Whether color was changed this frame
function M.render(ctx, id, config)
  config = config or {}
  local inst = get_instance(id)

  if not inst.is_open then
    return false
  end

  local title = config.title or "Color Picker"
  local on_change = config.on_change

  -- Window flags: always on top, auto-resize, with close button
  local window_flags = ImGui.WindowFlags_AlwaysAutoResize |
                       ImGui.WindowFlags_NoCollapse |
                       ImGui.WindowFlags_TopMost

  -- Set initial window position (center of screen) on first open
  if inst.first_open then
    local viewport = ImGui.GetMainViewport(ctx)
    local display_w, display_h = ImGui.Viewport_GetSize(viewport)
    ImGui.SetNextWindowPos(ctx, display_w * 0.5, display_h * 0.5, ImGui.Cond_Appearing, 0.5, 0.5)
    inst.first_open = false
  end

  -- Begin window
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 12)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 4)

  local visible, open = ImGui.Begin(ctx, title .. "##" .. id, true, window_flags)

  ImGui.PopStyleVar(ctx, 2)

  -- Update open state from window close button
  if not open then
    inst.is_open = false
    ImGui.End(ctx)
    return false
  end

  if not visible then
    ImGui.End(ctx)
    return false
  end

  -- Render the picker contents
  local changed = render_picker_contents(ctx, id, on_change)

  -- Close button at bottom
  ImGui.Spacing(ctx)
  local button_w = ImGui.GetContentRegionAvail(ctx)
  if ImGui.Button(ctx, "Close", button_w, 0) then
    inst.is_open = false
  end

  ImGui.End(ctx)

  return changed
end

--- Get the current color value
--- @param id string Unique identifier for this picker
--- @return number Current color (RGBA)
function M.get_color(id)
  local inst = get_instance(id)
  return inst.current_color
end

--- Set the current color value (without triggering callback)
--- @param id string Unique identifier for this picker
--- @param color number Color to set (RGBA)
function M.set_color(id, color)
  local inst = get_instance(id)
  inst.current_color = color
end

--- Render the color picker inline (embedded in a panel)
--- @param ctx userdata ImGui context
--- @param id string Unique identifier for this picker
--- @param config table Configuration { on_change = function(color), on_close = function(), initial_color = number, size = number }
--- @return boolean changed Whether color was changed this frame
function M.render_inline(ctx, id, config)
  config = config or {}
  local inst = get_instance(id)
  local on_change = config.on_change
  local on_close = config.on_close
  local size = config.size or 195

  -- Set initial color if provided
  if config.initial_color and inst.first_open then
    inst.current_color = config.initial_color
    inst.first_open = false
  end

  -- Get cursor position before drawing
  local cx, cy = ImGui.GetCursorScreenPos(ctx)

  -- Color picker configuration
  local picker_flags = ImGui.ColorEditFlags_PickerHueWheel |
                       ImGui.ColorEditFlags_NoSidePreview |
                       ImGui.ColorEditFlags_NoSmallPreview |
                       ImGui.ColorEditFlags_NoAlpha |
                       ImGui.ColorEditFlags_NoInputs |
                       ImGui.ColorEditFlags_NoLabel

  -- Convert to ARGB for ImGui
  local argb_color = Colors.rgba_to_argb(inst.current_color)

  -- Draw native ImGui picker (smooth GPU-interpolated gradients)
  local rv, new_argb_color = ImGui.ColorPicker4(ctx, '##picker_inline_' .. id, argb_color, picker_flags)

  -- Draw custom black borders on top
  local draw_list = ImGui.GetWindowDrawList(ctx)
  local wheel_thickness = size * 0.08
  local wheel_r_outer = size * 0.50
  local wheel_r_inner = wheel_r_outer - wheel_thickness
  local center_x = cx + size * 0.5
  local center_y = cy + size * 0.5

  -- Draw black circles for wheel borders (thicker, more visible)
  local col_black = 0xFF000000
  ImGui.DrawList_AddCircle(draw_list, center_x, center_y, wheel_r_outer, col_black, 64, 2.5)
  ImGui.DrawList_AddCircle(draw_list, center_x, center_y, wheel_r_inner, col_black, 64, 2.5)

  if rv then
    inst.current_color = Colors.argb_to_rgba(new_argb_color)
    inst.pending_change = true
  end

  -- Apply color only when mouse button is released
  if inst.pending_change and ImGui.IsMouseReleased(ctx, 0) then
    inst.pending_change = false
    if on_change then
      on_change(inst.current_color)
    end
  end

  return rv
end

--- Initialize inline picker (call this to show it)
--- @param id string Unique identifier for this picker
--- @param initial_color number Optional initial color (RGBA)
function M.show_inline(id, initial_color)
  local inst = get_instance(id)
  inst.first_open = true
  if initial_color then
    inst.current_color = initial_color
  end
end

return M
