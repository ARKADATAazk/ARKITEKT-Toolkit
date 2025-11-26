-- @noindex
-- Arkitekt/gui/widgets/close_button.lua
-- Floating close button that appears on hover in top-right corner

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local Draw = require('arkitekt.gui.draw')
local Colors = require('arkitekt.core.colors')

local M = {}
local hexrgb = Colors.hexrgb

local function create_alpha_tracker(speed)
  return {
    current = 0.0,
    target = 0.0,
    speed = speed or 12.0,
    set_target = function(self, t) 
      self.target = t 
    end,
    update = function(self, dt)
      local diff = self.target - self.current
      if math.abs(diff) < 0.005 then
        self.current = self.target
      else
        local alpha = 1.0 - math.exp(-self.speed * dt)
        self.current = self.current + diff * alpha
      end
    end,
    value = function(self) 
      return math.max(0.0, math.min(1.0, self.current))
    end
  }
end

function M.new(opts)
  opts = opts or {}
  
  local button = {
    size = opts.size or 32,
    margin = opts.margin or 16,
    proximity_distance = opts.proximity_distance or 150,
    
    bg_color = opts.bg_color or hexrgb("#000000"),
    bg_opacity = opts.bg_opacity or 0.6,
    bg_opacity_hover = opts.bg_opacity_hover or 0.8,
    
    icon_color = opts.icon_color or hexrgb("#FFFFFF"),
    icon_opacity = opts.icon_opacity or 0.8,
    
    hover_color = opts.hover_color or hexrgb("#FF4444"),
    active_color = opts.active_color or hexrgb("#FF0000"),
    
    alpha = create_alpha_tracker(12.0),
    hover_alpha = create_alpha_tracker(16.0),
    
    on_click = opts.on_click,
  }
  
  function button:update(ctx, bounds, dt)
    dt = dt or (1/60)
    
    local mx, my = ImGui.GetMousePos(ctx)
    local button_x = bounds.x + bounds.w - self.margin - self.size
    local button_y = bounds.y + self.margin
    
    local dx = mx - (button_x + self.size/2)
    local dy = my - (button_y + self.size/2)
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance < self.proximity_distance then
      self.alpha:set_target(1.0)
    else
      self.alpha:set_target(0.0)
    end
    
    self.alpha:update(dt)
    self.hover_alpha:update(dt)
  end
  
  function button:render(ctx, bounds, dl)
    local alpha = self.alpha:value()
    if alpha < 0.01 then return false end
    
    local button_x = bounds.x + bounds.w - self.margin - self.size
    local button_y = bounds.y + self.margin
    
    ImGui.SetCursorScreenPos(ctx, button_x, button_y)
    
    local is_hovered = false
    local clicked = false
    
    if alpha > 0.8 then
      if ImGui.InvisibleButton(ctx, "##close_button", self.size, self.size) then
        clicked = true
      end
      is_hovered = ImGui.IsItemHovered(ctx)
    end
    
    if is_hovered then
      self.hover_alpha:set_target(1.0)
    else
      self.hover_alpha:set_target(0.0)
    end
    
    local hover_alpha = self.hover_alpha:value()
    
    local bg_opacity = self.bg_opacity + (self.bg_opacity_hover - self.bg_opacity) * hover_alpha
    local bg_color = Colors.with_alpha(self.bg_color, (255 * bg_opacity * alpha) // 1)
    
    local corner_radius = self.size / 2
    Draw.rect_filled(dl, button_x, button_y, button_x + self.size, button_y + self.size, bg_color, corner_radius)
    
    local icon_color = self.icon_color
    if hover_alpha > 0.5 then
      icon_color = self.hover_color
    end
    if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) and is_hovered then
      icon_color = self.active_color
    end
    
    local final_icon_color = Colors.with_alpha(icon_color, (255 * self.icon_opacity * alpha) // 1)
    
    local center_x = button_x + self.size / 2
    local center_y = button_y + self.size / 2
    local cross_size = self.size * 0.35
    local thickness = 2.0
    
    Draw.line(dl, 
      center_x - cross_size, center_y - cross_size,
      center_x + cross_size, center_y + cross_size,
      final_icon_color, thickness)
    Draw.line(dl, 
      center_x + cross_size, center_y - cross_size,
      center_x - cross_size, center_y + cross_size,
      final_icon_color, thickness)
    
    if clicked and self.on_click then
      self.on_click()
    end
    
    return clicked
  end
  
  return button
end

return M