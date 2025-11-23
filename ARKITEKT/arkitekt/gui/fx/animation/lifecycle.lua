-- @noindex
-- ReArkitekt/gui/fx/animation/lifecycle.lua
-- Spawn and destroy animations for UI elements
-- Merged from spawn.lua and destroy.lua for better organization

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Easing = require('arkitekt.gui.fx.animation.easing')
local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

-- =============================================================================
-- SpawnTracker: Spawn animation that affects layout
-- Tiles push each other as they expand
-- =============================================================================
-- Usage:
--   local spawner = Lifecycle.SpawnTracker.new({duration = 0.28})
--   spawner:spawn(id, target_rect)
--   if spawner:is_spawning(id) then
--     local factor = spawner:get_width_factor(id)  -- 0.0 to 1.0
--   end

local SpawnTracker = {}
SpawnTracker.__index = SpawnTracker

function SpawnTracker.new(config)
  config = config or {}

  return setmetatable({
    spawning = {},
    duration = config.duration or 0.28,
  }, SpawnTracker)
end

function SpawnTracker:spawn(id, target_rect)
  self.spawning[id] = {
    start_time = reaper.time_precise(),
    target = {target_rect[1], target_rect[2], target_rect[3], target_rect[4]},
  }
end

function SpawnTracker:is_spawning(id)
  return self.spawning[id] ~= nil
end

function SpawnTracker:get_width_factor(id)
  local spawn = self.spawning[id]
  if not spawn then return 1.0 end

  local now = reaper.time_precise()
  local elapsed = now - spawn.start_time
  local t = math.min(1.0, elapsed / self.duration)

  t = Easing.smoothstep(t)

  if t >= 1.0 then
    self.spawning[id] = nil
    return 1.0
  end

  return t
end

function SpawnTracker:clear()
  self.spawning = {}
end

function SpawnTracker:remove(id)
  self.spawning[id] = nil
end

-- =============================================================================
-- DestroyAnim: Destroy animation with red flash and smooth dissolve
-- =============================================================================
-- Usage:
--   local destroyer = Lifecycle.DestroyAnim.new({duration = 0.10})
--   destroyer:destroy(key, rect)
--   destroyer:update(dt)
--   destroyer:render(ctx, dl, key, base_rect, base_color, rounding)

local DestroyAnim = {}
DestroyAnim.__index = DestroyAnim

function DestroyAnim.new(opts)
  opts = opts or {}

  return setmetatable({
    duration = opts.duration or 0.10,
    destroying = {},
    on_complete = opts.on_complete,
  }, DestroyAnim)
end

function DestroyAnim:destroy(key, rect)
  if not key or not rect then return end

  self.destroying[key] = {
    elapsed = 0,
    rect = {rect[1], rect[2], rect[3], rect[4]},
  }
end

function DestroyAnim:is_destroying(key)
  return self.destroying[key] ~= nil
end

function DestroyAnim:update(dt)
  dt = dt or 0.016

  local completed = {}

  for key, anim in pairs(self.destroying) do
    anim.elapsed = anim.elapsed + dt

    if anim.elapsed >= self.duration then
      completed[#completed + 1] = key
    end
  end

  for _, key in ipairs(completed) do
    self.destroying[key] = nil
    if self.on_complete then
      self.on_complete(key)
    end
  end
end

function DestroyAnim:get_factor(key)
  local anim = self.destroying[key]
  if not anim then return 0 end

  local t = math.min(1, anim.elapsed / self.duration)
  return Easing.ease_out_quad(t)
end

function DestroyAnim:render(ctx, dl, key, base_rect, base_color, rounding)
  local anim = self.destroying[key]
  if not anim then return false end

  local t = math.min(1, anim.elapsed / self.duration)
  local rect = anim.rect

  local x1, y1, x2, y2 = rect[1], rect[2], rect[3], rect[4]
  local cx = (x1 + x2) * 0.5
  local cy = (y1 + y2) * 0.5
  local w = x2 - x1
  local h = y2 - y1

  local zoom_factor = 1.0 + t * 0.08
  local new_w = w * zoom_factor
  local new_h = h * zoom_factor

  local nx1 = cx - new_w * 0.5
  local ny1 = cy - new_h * 0.5
  local nx2 = cx + new_w * 0.5
  local ny2 = cy + new_h * 0.5

  local target_red = hexrgb("#AA333388")

  local r1 = (base_color >> 24) & 0xFF
  local g1 = (base_color >> 16) & 0xFF
  local b1 = (base_color >> 8) & 0xFF
  local a1 = base_color & 0xFF

  local r2 = (target_red >> 24) & 0xFF
  local g2 = (target_red >> 16) & 0xFF
  local b2 = (target_red >> 8) & 0xFF

  local red_factor = math.min(1, t * 3)

  local r = (r1 + (r2 - r1) * red_factor)//1
  local g = (g1 + (g2 - g1) * red_factor)//1
  local b = (b1 + (b2 - b1) * red_factor)//1
  local a = (a1 * (1 - Easing.ease_out_quad(t) * 0.9))//1

  local flash_color = (r << 24) | (g << 16) | (b << 8) | a

  ImGui.DrawList_AddRectFilled(dl, nx1, ny1, nx2, ny2, flash_color, rounding)

  local blur_intensity = Easing.ease_out_quad(t)
  local blur_layers = (blur_intensity * 3)//1 + 1
  for i = 1, blur_layers do
    local offset = i * 1.5 * blur_intensity
    local blur_alpha = (a * 0.2 / blur_layers)//1
    local blur_color = (r << 24) | (g << 16) | (b << 8) | blur_alpha

    ImGui.DrawList_AddRectFilled(dl,
      nx1 - offset, ny1 - offset,
      nx2 + offset, ny2 + offset,
      blur_color, rounding + offset * 0.3)
  end

  local cross_alpha = (255 * (1 - Easing.ease_out_quad(t)))//1
  local cross_color = (hexrgb("#FF4444") & 0xFFFFFF00) | cross_alpha
  local cross_thickness = 2.5

  local cross_size = 20
  local cross_half = cross_size * 0.5
  ImGui.DrawList_AddLine(dl,
    cx - cross_half, cy - cross_half,
    cx + cross_half, cy + cross_half,
    cross_color, cross_thickness)
  ImGui.DrawList_AddLine(dl,
    cx + cross_half, cy - cross_half,
    cx - cross_half, cy + cross_half,
    cross_color, cross_thickness)

  return true
end

function DestroyAnim:clear()
  self.destroying = {}
end

function DestroyAnim:remove(key)
  self.destroying[key] = nil
end

-- Export both animation types
M.SpawnTracker = SpawnTracker
M.DestroyAnim = DestroyAnim

return M
