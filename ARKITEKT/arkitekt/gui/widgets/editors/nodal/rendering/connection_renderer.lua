-- @noindex
-- Arkitekt/gui/widgets/nodal/rendering/connection_renderer.lua
-- Connection rendering with Manhattan routing

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local Draw = require('arkitekt.gui.draw')
local Colors = require('arkitekt.core.colors')
local Connection = require('arkitekt.gui.widgets.editors.nodal.core.connection')

local M = {}
local hexrgb = Colors.hexrgb

function M.render(ctx, connection, nodes, config)
  local dl = ImGui.GetWindowDrawList(ctx)
  
  local points = Connection.get_manhattan_points(connection, nodes, config)
  if not points or #points < 4 then
    return
  end
  
  local thickness = config.connection.thickness
  if connection.hovered then
    thickness = thickness * config.connection.hover_thickness_mult
  end
  
  -- Draw Manhattan path (series of line segments)
  M.render_manhattan_path(dl, points, connection.color, thickness, connection.type == "trigger", config)
  
  if connection.animated then
    M.render_animated_dot_manhattan(dl, points, connection.color, config)
  end
  
  if connection.event_name then
    M.render_connection_label_manhattan(ctx, dl, connection, points, config)
  end
end

function M.render_manhattan_path(dl, points, color, thickness, is_trigger, config)
  if is_trigger then
    -- Draw dashed lines for triggers
    for i = 1, #points - 2, 2 do
      local x1, y1 = points[i], points[i + 1]
      local x2, y2 = points[i + 2], points[i + 3]
      M.render_dashed_line(dl, x1, y1, x2, y2, color, thickness, config)
    end
  else
    -- Draw solid lines for sequential
    for i = 1, #points - 2, 2 do
      local x1, y1 = points[i], points[i + 1]
      local x2, y2 = points[i + 2], points[i + 3]
      ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, color, thickness)
    end
  end
  
  -- Draw rounded corners at connection points
  M.render_corner_rounds(dl, points, color, thickness)
end

function M.render_corner_rounds(dl, points, color, radius)
  -- Draw small circles at corner points to smooth transitions
  radius = radius or 2
  for i = 3, #points - 2, 2 do
    local x, y = points[i], points[i + 1]
    ImGui.DrawList_AddCircleFilled(dl, x, y, radius, color)
  end
end

function M.render_dashed_line(dl, x1, y1, x2, y2, color, thickness, config)
  local dash_length = config.connection.dash_length or 8
  local gap_length = config.connection.dash_gap or 6
  
  local dx = x2 - x1
  local dy = y2 - y1
  local length = math.sqrt(dx * dx + dy * dy)
  
  if length < 0.001 then return end
  
  local dir_x = dx / length
  local dir_y = dy / length
  
  local cycle_length = dash_length + gap_length
  local num_cycles = math.floor(length / cycle_length)
  
  local pos = 0
  for i = 0, num_cycles do
    local dash_start = pos
    local dash_end = math.min(pos + dash_length, length)
    
    if dash_end > dash_start then
      local sx = x1 + dir_x * dash_start
      local sy = y1 + dir_y * dash_start
      local ex = x1 + dir_x * dash_end
      local ey = y1 + dir_y * dash_end
      
      ImGui.DrawList_AddLine(dl, sx, sy, ex, ey, color, thickness)
    end
    
    pos = pos + cycle_length
  end
end

function M.render_animated_dot_manhattan(dl, points, color, config)
  if #points < 4 then return end
  
  -- Calculate total path length
  local total_length = 0
  local segment_lengths = {}
  
  for i = 1, #points - 2, 2 do
    local x1, y1 = points[i], points[i + 1]
    local x2, y2 = points[i + 2], points[i + 3]
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    segment_lengths[#segment_lengths + 1] = length
    total_length = total_length + length
  end
  
  if total_length < 0.001 then return end
  
  -- Calculate position along path
  local time = reaper.time_precise()
  local t = ((time * (config.connection.animation_speed or 20)) % total_length) / total_length
  
  local target_distance = t * total_length
  local accumulated = 0
  
  for i = 1, #segment_lengths do
    local seg_len = segment_lengths[i]
    if accumulated + seg_len >= target_distance then
      -- Dot is on this segment
      local seg_t = (target_distance - accumulated) / seg_len
      local idx = (i - 1) * 2 + 1
      local x1, y1 = points[idx], points[idx + 1]
      local x2, y2 = points[idx + 2], points[idx + 3]
      
      local px = x1 + (x2 - x1) * seg_t
      local py = y1 + (y2 - y1) * seg_t
      
      ImGui.DrawList_AddCircleFilled(dl, px, py, config.connection.animation_dot_size or 6, color)
      return
    end
    accumulated = accumulated + seg_len
  end
end

function M.render_connection_label_manhattan(ctx, dl, connection, points, config)
  if #points < 4 then return end
  
  -- Place label at midpoint of path
  local total_length = 0
  local segment_info = {}
  
  for i = 1, #points - 2, 2 do
    local x1, y1 = points[i], points[i + 1]
    local x2, y2 = points[i + 2], points[i + 3]
    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    segment_info[#segment_info + 1] = {x1 = x1, y1 = y1, x2 = x2, y2 = y2, length = length}
    total_length = total_length + length
  end
  
  local mid_distance = total_length / 2
  local accumulated = 0
  
  for _, seg in ipairs(segment_info) do
    if accumulated + seg.length >= mid_distance then
      local seg_t = (mid_distance - accumulated) / seg.length
      local mid_x = seg.x1 + (seg.x2 - seg.x1) * seg_t
      local mid_y = seg.y1 + (seg.y2 - seg.y1) * seg_t
      
      local label = connection.event_name
      local text_w, text_h = ImGui.CalcTextSize(ctx, label)
      
      local padding = config.connection.label_bg_padding or 6
      local bg_x1 = mid_x - text_w / 2 - padding
      local bg_y1 = mid_y - text_h / 2 - padding
      local bg_x2 = mid_x + text_w / 2 + padding
      local bg_y2 = mid_y + text_h / 2 + padding
      
      ImGui.DrawList_AddRectFilled(dl, bg_x1, bg_y1, bg_x2, bg_y2, 
        config.colors.connection_label_bg or hexrgb("#1A1A1AEE"), 
        config.connection.label_bg_rounding or 4)
      
      ImGui.DrawList_AddRect(dl, bg_x1, bg_y1, bg_x2, bg_y2, connection.color, 
        config.connection.label_bg_rounding or 4, 0, 1.0)
      
      Draw.text(dl, mid_x - text_w / 2, mid_y - text_h / 2, config.colors.text.port_label, label)
      return
    end
    accumulated = accumulated + seg.length
  end
end

function M.render_drag_connection(ctx, start_x, start_y, end_x, end_y, color, config)
  local dl = ImGui.GetWindowDrawList(ctx)
  
  -- Simple Manhattan routing for drag preview using config values
  local horizontal_offset = config.connection.manhattan_horizontal_offset or 40
  local approach_offset = config.connection.manhattan_approach_offset or 20
  
  local points = {
    start_x, start_y,
    start_x + horizontal_offset, start_y,
    start_x + horizontal_offset, end_y - approach_offset,
    end_x, end_y - approach_offset,
    end_x, end_y,
  }
  
  M.render_manhattan_path(dl, points, color, config.connection.thickness, true, config)
end

return M