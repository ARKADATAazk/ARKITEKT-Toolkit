-- @noindex
-- ReArkitekt/gui/fx/animation/tracks.lua
-- Animation tracking utilities - single-value and multi-rectangle trackers
-- Merged from track.lua and rect_track.lua for better organization

local Math = require('arkitekt.core.math')

local M = {}

-- =============================================================================
-- Track: Single-value animation track with smooth interpolation
-- =============================================================================
-- Usage:
--   local track = Tracks.Track.new(0, 14.0)  -- initial value, speed
--   track:to(100)                             -- set target
--   track:update(dt)                          -- update in frame loop
--   local val = track:get()                   -- get current value

local Track = {}
Track.__index = Track

function Track.new(initial_value, speed)
  return setmetatable({
    current = initial_value or 0,
    target = initial_value or 0,
    speed = speed or 14.0,
  }, Track)
end

function Track:to(target)
  self.target = target
end

function Track:update(dt)
  dt = dt or 0.016
  self.current = Math.lerp(self.current, self.target, self.speed * dt)
  return self.current
end

function Track:get()
  return self.current
end

function Track:teleport(value)
  self.current = value
  self.target = value
end

function Track:is_animating(epsilon)
  epsilon = epsilon or 0.01
  return math.abs(self.current - self.target) > epsilon
end

function Track:set_speed(speed)
  self.speed = speed
end

-- =============================================================================
-- RectTrack: Multi-rectangle animation tracker with staggered delays
-- and magnetic snapping
-- =============================================================================
-- Usage:
--   local tracker = Tracks.RectTrack.new(14.0)
--   tracker:to(item_id, {x1, y1, x2, y2})
--   tracker:to_with_delay(item_id, rect, 0.05)
--   tracker:update(dt)
--   local current_rect = tracker:get(item_id)

local RectTrack = {}
RectTrack.__index = RectTrack

function RectTrack.new(speed, snap_epsilon, magnetic_threshold, magnetic_multiplier)
  return setmetatable({
    rects = {},
    speed = speed or 14.0,
    snap_eps = snap_epsilon or 0.5,
    magnetic_threshold = magnetic_threshold or 30.0,
    magnetic_multiplier = magnetic_multiplier or 2.5,
  }, RectTrack)
end

function RectTrack:to(id, rect)
  if not self.rects[id] then
    self.rects[id] = {
      current = {rect[1], rect[2], rect[3], rect[4]},
      target = {rect[1], rect[2], rect[3], rect[4]},
      delay = 0,
      settled = true,  -- Start settled if spawning at target position
    }
  else
    local r = self.rects[id]

    -- Check if target actually changed before unsettling
    local target_changed = (r.target[1] ~= rect[1] or r.target[2] ~= rect[2] or
                           r.target[3] ~= rect[3] or r.target[4] ~= rect[4])

    r.target[1] = rect[1]
    r.target[2] = rect[2]
    r.target[3] = rect[3]
    r.target[4] = rect[4]
    r.delay = 0

    -- Only unsettle if target actually changed
    if target_changed then
      r.settled = false
    end
  end
end

function RectTrack:to_with_delay(id, rect, delay)
  delay = delay or 0

  if not self.rects[id] then
    self.rects[id] = {
      current = {rect[1], rect[2], rect[3], rect[4]},
      target = {rect[1], rect[2], rect[3], rect[4]},
      delay = delay,
      settled = (delay == 0),  -- Start settled if no delay
    }
  else
    local r = self.rects[id]

    -- Check if target actually changed before unsettling
    local target_changed = (r.target[1] ~= rect[1] or r.target[2] ~= rect[2] or
                           r.target[3] ~= rect[3] or r.target[4] ~= rect[4])

    r.target[1] = rect[1]
    r.target[2] = rect[2]
    r.target[3] = rect[3]
    r.target[4] = rect[4]
    r.delay = delay

    -- Only unsettle if target actually changed
    if target_changed then
      r.settled = false
    end
  end
end

function RectTrack:update(dt)
  dt = dt or 0.016

  -- Cache math functions for performance
  local sqrt = math.sqrt
  local abs = math.abs

  for id, r in pairs(self.rects) do
    -- CRITICAL OPTIMIZATION: Skip settled items (massive win when idle)
    -- With 1000 items, this reduces update from 1000 iterations to ~0-20
    if r.settled then
      goto continue
    end

    if r.delay and r.delay > 0 then
      r.delay = r.delay - dt
      if r.delay < 0 then r.delay = 0 end
    else
      local dist_sq = 0
      for i = 1, 4 do
        local d = r.target[i] - r.current[i]
        dist_sq = dist_sq + d * d
      end
      local dist = sqrt(dist_sq)

      local effective_speed = self.speed
      if dist < self.magnetic_threshold then
        effective_speed = self.speed * self.magnetic_multiplier
      end

      local all_snapped = true
      for i = 1, 4 do
        r.current[i] = Math.lerp(r.current[i], r.target[i], effective_speed * dt)

        if abs(r.current[i] - r.target[i]) < self.snap_eps then
          r.current[i] = r.target[i]
        else
          all_snapped = false
        end
      end

      -- Mark as settled when all coordinates have snapped
      if all_snapped then
        r.settled = true
      end
    end

    ::continue::
  end
end

function RectTrack:get(id)
  local r = self.rects[id]
  if not r then return nil end
  return {r.current[1], r.current[2], r.current[3], r.current[4]}
end

function RectTrack:teleport(id, rect)
  if not rect then return end
  if not self.rects[id] then
    self.rects[id] = {
      current = {rect[1], rect[2], rect[3], rect[4]},
      target = {rect[1], rect[2], rect[3], rect[4]},
      delay = 0,
      settled = true,
    }
  else
    local r = self.rects[id]
    r.current = {rect[1], rect[2], rect[3], rect[4]}
    r.target = {rect[1], rect[2], rect[3], rect[4]}
    r.delay = 0
    r.settled = true
  end
end

function RectTrack:teleport_all(new_rects)
  self.rects = {}
  for id, rect in pairs(new_rects) do
    self.rects[id] = {
      current = {rect[1], rect[2], rect[3], rect[4]},
      target = {rect[1], rect[2], rect[3], rect[4]},
      delay = 0,
      settled = true,
    }
  end
end

function RectTrack:clear()
  self.rects = {}
end

function RectTrack:remove(id)
  self.rects[id] = nil
end

-- Export both track types
M.Track = Track
M.RectTrack = RectTrack

return M
