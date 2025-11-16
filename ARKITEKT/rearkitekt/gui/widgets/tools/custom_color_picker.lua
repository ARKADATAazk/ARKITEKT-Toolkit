-- @noindex
-- ReArkitekt/gui/widgets/tools/custom_color_picker.lua
-- Custom color picker with smooth GPU-interpolated gradients
-- Uses rendering techniques from tile renderer for quality

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('rearkitekt.core.colors')

local M = {}

-- Convert HSV to RGB
local function hsv_to_rgb(h, s, v)
  local c = v * s
  local x = c * (1 - math.abs((h * 6) % 2 - 1))
  local m = v - c

  local r, g, b
  if h < 1/6 then
    r, g, b = c, x, 0
  elseif h < 2/6 then
    r, g, b = x, c, 0
  elseif h < 3/6 then
    r, g, b = 0, c, x
  elseif h < 4/6 then
    r, g, b = 0, x, c
  elseif h < 5/6 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end

  return (r + m) * 255, (g + m) * 255, (b + m) * 255
end

-- Convert RGB to HSV
local function rgb_to_hsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local max_c = math.max(r, g, b)
  local min_c = math.min(r, g, b)
  local delta = max_c - min_c

  local h = 0
  if delta ~= 0 then
    if max_c == r then
      h = ((g - b) / delta) % 6
    elseif max_c == g then
      h = (b - r) / delta + 2
    else
      h = (r - g) / delta + 4
    end
    h = h / 6
  end

  local s = (max_c == 0) and 0 or (delta / max_c)
  local v = max_c

  return h, s, v
end

-- Rotate point around origin
local function rotate_point(x, y, cos_a, sin_a)
  return x * cos_a - y * sin_a, x * sin_a + y * cos_a
end

-- Check if point is in triangle
local function point_in_triangle(px, py, ax, ay, bx, by, cx, cy)
  local v0x, v0y = cx - ax, cy - ay
  local v1x, v1y = bx - ax, by - ay
  local v2x, v2y = px - ax, py - ay

  local dot00 = v0x * v0x + v0y * v0y
  local dot01 = v0x * v1x + v0y * v1y
  local dot02 = v0x * v2x + v0y * v2y
  local dot11 = v1x * v1x + v1y * v1y
  local dot12 = v1x * v2x + v1y * v2y

  local denom = dot00 * dot11 - dot01 * dot01
  if math.abs(denom) < 0.0001 then return false end

  local inv_denom = 1 / denom
  local u = (dot11 * dot02 - dot01 * dot12) * inv_denom
  local v = (dot00 * dot12 - dot01 * dot02) * inv_denom

  return (u >= 0) and (v >= 0) and (u + v <= 1)
end

-- Get barycentric coordinates
local function get_barycentric(px, py, ax, ay, bx, by, cx, cy)
  local v0x, v0y = bx - ax, by - ay
  local v1x, v1y = cx - ax, cy - ay
  local v2x, v2y = px - ax, py - ay

  local d00 = v0x * v0x + v0y * v0y
  local d01 = v0x * v1x + v0y * v1y
  local d11 = v1x * v1x + v1y * v1y
  local d20 = v2x * v0x + v2y * v0y
  local d21 = v2x * v1x + v2y * v1y

  local denom = d00 * d11 - d01 * d01
  if math.abs(denom) < 0.0001 then return 0, 0, 0 end

  local inv_denom = 1 / denom
  local v = (d11 * d20 - d01 * d21) * inv_denom
  local w = (d00 * d21 - d01 * d20) * inv_denom
  local u = 1 - v - w

  return u, v, w
end

-- Closest point on triangle
local function closest_point_on_triangle(px, py, ax, ay, bx, by, cx, cy)
  local function closest_on_segment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    return ax + t * dx, ay + t * dy
  end

  local c1x, c1y = closest_on_segment(px, py, ax, ay, bx, by)
  local c2x, c2y = closest_on_segment(px, py, bx, by, cx, cy)
  local c3x, c3y = closest_on_segment(px, py, cx, cy, ax, ay)

  local d1 = (px - c1x)^2 + (py - c1y)^2
  local d2 = (px - c2x)^2 + (py - c2y)^2
  local d3 = (px - c3x)^2 + (py - c3y)^2

  if d1 <= d2 and d1 <= d3 then
    return c1x, c1y
  elseif d2 <= d3 then
    return c2x, c2y
  else
    return c3x, c3y
  end
end

--- Render custom color picker with smooth gradients
--- @param ctx userdata ImGui context
--- @param size number Size of the picker
--- @param h number Hue (0-1)
--- @param s number Saturation (0-1)
--- @param v number Value (0-1)
--- @return boolean changed, number h, number s, number v
function M.render(ctx, size, h, s, v)
  local changed = false
  local value_changed_h = false
  local value_changed_sv = false

  local draw_list = ImGui.GetWindowDrawList(ctx)
  local cx, cy = ImGui.GetCursorScreenPos(ctx)

  -- Geometry
  local wheel_thickness = size * 0.08
  local wheel_r_outer = size * 0.50
  local wheel_r_inner = wheel_r_outer - wheel_thickness
  local center_x = cx + size * 0.5
  local center_y = cy + size * 0.5

  -- Triangle geometry
  local triangle_r = wheel_r_inner - math.floor(size * 0.027)
  local triangle_pa_x, triangle_pa_y = triangle_r, 0  -- Hue point
  local triangle_pb_x, triangle_pb_y = triangle_r * -0.5, triangle_r * -0.866025  -- Black point
  local triangle_pc_x, triangle_pc_y = triangle_r * -0.5, triangle_r * 0.866025   -- White point

  local col_white = 0xFFFFFFFF
  local col_black = 0xFF000000

  -- === RENDER HUE WHEEL ===
  local num_segments = 64
  for i = 0, num_segments - 1 do
    local angle1 = (i / num_segments) * 2 * math.pi
    local angle2 = ((i + 1) / num_segments) * 2 * math.pi

    local hue1 = i / num_segments
    local hue2 = (i + 1) / num_segments

    local r1, g1, b1 = hsv_to_rgb(hue1, 1, 1)
    local r2, g2, b2 = hsv_to_rgb(hue2, 1, 1)

    local color1 = ImGui.ColorConvertDouble4ToU32(r1/255, g1/255, b1/255, 1)
    local color2 = ImGui.ColorConvertDouble4ToU32(r2/255, g2/255, b2/255, 1)

    -- Quad for smooth gradient
    local x1_out = center_x + math.cos(angle1) * wheel_r_outer
    local y1_out = center_y + math.sin(angle1) * wheel_r_outer
    local x2_out = center_x + math.cos(angle2) * wheel_r_outer
    local y2_out = center_y + math.sin(angle2) * wheel_r_outer
    local x1_in = center_x + math.cos(angle1) * wheel_r_inner
    local y1_in = center_y + math.sin(angle1) * wheel_r_inner
    local x2_in = center_x + math.cos(angle2) * wheel_r_inner
    local y2_in = center_y + math.sin(angle2) * wheel_r_inner

    -- Use AddRectFilledMultiColor for smooth GPU interpolation (like tile renderer)
    ImGui.DrawList_AddQuadFilled(draw_list, x1_out, y1_out, x2_out, y2_out, x2_in, y2_in, x1_in, y1_in, color1)
  end

  -- === RENDER SV TRIANGLE ===
  local cos_hue_angle = math.cos(h * 2 * math.pi)
  local sin_hue_angle = math.sin(h * 2 * math.pi)

  local tra_x = center_x + cos_hue_angle * triangle_pa_x - sin_hue_angle * triangle_pa_y
  local tra_y = center_y + sin_hue_angle * triangle_pa_x + cos_hue_angle * triangle_pa_y
  local trb_x = center_x + cos_hue_angle * triangle_pb_x - sin_hue_angle * triangle_pb_y
  local trb_y = center_y + sin_hue_angle * triangle_pb_x + cos_hue_angle * triangle_pb_y
  local trc_x = center_x + cos_hue_angle * triangle_pc_x - sin_hue_angle * triangle_pc_y
  local trc_y = center_y + sin_hue_angle * triangle_pc_x + cos_hue_angle * triangle_pc_y

  -- Get pure hue color
  local r_hue, g_hue, b_hue = hsv_to_rgb(h, 1, 1)
  local hue_color32 = ImGui.ColorConvertDouble4ToU32(r_hue/255, g_hue/255, b_hue/255, 1)

  -- Draw triangle with smooth GPU gradients using AddRectFilledMultiColor
  -- Each horizontal strip has 4-corner vertex colors interpolated by GPU
  local num_strips = 200

  for i = 0, num_strips - 1 do
    local t1 = i / num_strips
    local t2 = (i + 1) / num_strips

    -- Left edge points (hue → black)
    local left1_x = tra_x + (trb_x - tra_x) * t1
    local left1_y = tra_y + (trb_y - tra_y) * t1
    local left2_x = tra_x + (trb_x - tra_x) * t2
    local left2_y = tra_y + (trb_y - tra_y) * t2

    -- Right edge points (hue → white)
    local right1_x = tra_x + (trc_x - tra_x) * t1
    local right1_y = tra_y + (trc_y - tra_y) * t1
    local right2_x = tra_x + (trc_x - tra_x) * t2
    local right2_y = tra_y + (trc_y - tra_y) * t2

    -- Calculate corner colors in HSV space for accuracy
    -- Left edge: hue with V decreasing (towards black)
    local left1_r, left1_g, left1_b = hsv_to_rgb(h, 1, 1 - t1)
    local left2_r, left2_g, left2_b = hsv_to_rgb(h, 1, 1 - t2)

    -- Right edge: hue with S decreasing (towards white)
    local right1_r, right1_g, right1_b = hsv_to_rgb(h, 1 - t1, 1)
    local right2_r, right2_g, right2_b = hsv_to_rgb(h, 1 - t2, 1)

    local left1_col = ImGui.ColorConvertDouble4ToU32(left1_r/255, left1_g/255, left1_b/255, 1)
    local left2_col = ImGui.ColorConvertDouble4ToU32(left2_r/255, left2_g/255, left2_b/255, 1)
    local right1_col = ImGui.ColorConvertDouble4ToU32(right1_r/255, right1_g/255, right1_b/255, 1)
    local right2_col = ImGui.ColorConvertDouble4ToU32(right2_r/255, right2_g/255, right2_b/255, 1)

    -- Draw horizontal strip with 4-corner gradient (GPU interpolates!)
    -- Find bounding rectangle for this trapezoid strip
    local min_x = math.min(left1_x, left2_x, right1_x, right2_x)
    local min_y = math.min(left1_y, left2_y, right1_y, right2_y)
    local max_x = math.max(left1_x, left2_x, right1_x, right2_x)
    local max_y = math.max(left1_y, left2_y, right1_y, right2_y)

    -- AddRectFilledMultiColor: top-left, top-right, bottom-right, bottom-left
    ImGui.DrawList_AddRectFilledMultiColor(draw_list,
      min_x, min_y, max_x, max_y,
      left1_col, right1_col, right2_col, left2_col)
  end

  -- THICK black borders for visibility
  ImGui.DrawList_AddCircle(draw_list, center_x, center_y, wheel_r_outer, col_black, 64, 3.0)
  ImGui.DrawList_AddCircle(draw_list, center_x, center_y, wheel_r_inner, col_black, 64, 3.0)

  -- Triangle border using PathStroke
  ImGui.DrawList_PathClear(draw_list)
  ImGui.DrawList_PathLineTo(draw_list, tra_x, tra_y)
  ImGui.DrawList_PathLineTo(draw_list, trb_x, trb_y)
  ImGui.DrawList_PathLineTo(draw_list, trc_x, trc_y)
  ImGui.DrawList_PathStroke(draw_list, col_black, ImGui.DrawFlags_Closed, 3.0)

  -- === CURSORS ===
  local hue_cursor_pos_x = center_x + cos_hue_angle * (wheel_r_inner + wheel_r_outer) * 0.5
  local hue_cursor_pos_y = center_y + sin_hue_angle * (wheel_r_inner + wheel_r_outer) * 0.5
  local hue_cursor_rad = value_changed_h and (wheel_thickness * 0.65) or (wheel_thickness * 0.55)

  ImGui.DrawList_AddCircleFilled(draw_list, hue_cursor_pos_x, hue_cursor_pos_y, hue_cursor_rad, hue_color32, 32)
  ImGui.DrawList_AddCircle(draw_list, hue_cursor_pos_x, hue_cursor_pos_y, hue_cursor_rad + 1, 0xFF808080, 32, 2)
  ImGui.DrawList_AddCircle(draw_list, hue_cursor_pos_x, hue_cursor_pos_y, hue_cursor_rad, col_white, 32, 2)

  local sv_cursor_x = trc_x + (tra_x - trc_x) * s + (trb_x - trc_x) * (1 - v)
  local sv_cursor_y = trc_y + (tra_y - trc_y) * s + (trb_y - trc_y) * (1 - v)
  local sv_cursor_rad = value_changed_sv and (wheel_thickness * 0.55) or (wheel_thickness * 0.40)

  local r_cur, g_cur, b_cur = hsv_to_rgb(h, s, v)
  local user_col32 = ImGui.ColorConvertDouble4ToU32(r_cur/255, g_cur/255, b_cur/255, 1)

  ImGui.DrawList_AddCircleFilled(draw_list, sv_cursor_x, sv_cursor_y, sv_cursor_rad, user_col32, 32)
  ImGui.DrawList_AddCircle(draw_list, sv_cursor_x, sv_cursor_y, sv_cursor_rad + 1, 0xFF808080, 32, 2)
  ImGui.DrawList_AddCircle(draw_list, sv_cursor_x, sv_cursor_y, sv_cursor_rad, col_white, 32, 2)

  -- === INTERACTION ===
  ImGui.SetCursorScreenPos(ctx, cx, cy)
  ImGui.InvisibleButton(ctx, "##picker_wheel", size, size)

  if ImGui.IsItemActive(ctx) then
    local mx, my = ImGui.GetMousePos(ctx)
    local initial_mx, initial_my = ImGui.GetMouseClickedPos(ctx, 0)

    local dx = initial_mx - center_x
    local dy = initial_my - center_y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Hue wheel interaction
    if dist >= (wheel_r_inner - 1) and dist <= (wheel_r_outer + 1) then
      local current_dx = mx - center_x
      local current_dy = my - center_y
      h = math.atan(current_dy, current_dx) / math.pi * 0.5
      if h < 0 then h = h + 1 end
      changed = true
      value_changed_h = true
    end

    -- Triangle interaction
    local cos_neg = math.cos(-h * 2 * math.pi)
    local sin_neg = math.sin(-h * 2 * math.pi)
    local initial_off_x = initial_mx - center_x
    local initial_off_y = initial_my - center_y
    local initial_unrot_x, initial_unrot_y = rotate_point(initial_off_x, initial_off_y, cos_neg, sin_neg)

    if point_in_triangle(initial_unrot_x, initial_unrot_y,
                         triangle_pa_x, triangle_pa_y,
                         triangle_pb_x, triangle_pb_y,
                         triangle_pc_x, triangle_pc_y) then
      local current_off_x = mx - center_x
      local current_off_y = my - center_y
      local current_unrot_x, current_unrot_y = rotate_point(current_off_x, current_off_y, cos_neg, sin_neg)

      if not point_in_triangle(current_unrot_x, current_unrot_y,
                               triangle_pa_x, triangle_pa_y,
                               triangle_pb_x, triangle_pb_y,
                               triangle_pc_x, triangle_pc_y) then
        current_unrot_x, current_unrot_y = closest_point_on_triangle(
          current_unrot_x, current_unrot_y,
          triangle_pa_x, triangle_pa_y,
          triangle_pb_x, triangle_pb_y,
          triangle_pc_x, triangle_pc_y)
      end

      local uu, vv, ww = get_barycentric(
        current_unrot_x, current_unrot_y,
        triangle_pa_x, triangle_pa_y,
        triangle_pb_x, triangle_pb_y,
        triangle_pc_x, triangle_pc_y)

      v = math.max(0.0001, math.min(1, 1 - vv))
      s = math.max(0.0001, math.min(1, uu / v))
      changed = true
      value_changed_sv = true
    end
  end

  return changed, h, s, v
end

return M
