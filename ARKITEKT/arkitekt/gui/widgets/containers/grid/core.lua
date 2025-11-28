-- @noindex
-- Arkitekt/gui/widgets/grid/core.lua
-- Main grid orchestrator - composes rendering, animation, and input modules
-- UPDATED: Now handles extended input areas (padding zones)
-- FIXED: Tiles outside grid bounds are no longer interactive or rendered
-- FIXED: Respects parent panel scrollable bounds
-- API_MATCHING: Added ImGui-style Ark.Grid(ctx, opts) API with hidden state

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local LayoutGrid = require('arkitekt.gui.widgets.containers.grid.layout')
local Tracks = require('arkitekt.gui.animation.tracks')
local RectTrack = Tracks.RectTrack
local Colors = require('arkitekt.core.colors')
local Selection  = require('arkitekt.gui.interaction.selection')
local SelRect    = require('arkitekt.gui.widgets.data.selection_rectangle')
local Draw       = require('arkitekt.gui.draw.primitives')
local Dnd = require('arkitekt.gui.interaction.drag_visual')
local DragIndicator = Dnd.DragIndicator
local DropIndicator = Dnd.DropIndicator
local Rendering  = require('arkitekt.gui.widgets.containers.grid.rendering')
local Animation  = require('arkitekt.gui.widgets.containers.grid.animation')
local Input      = require('arkitekt.gui.widgets.containers.grid.input')
local DnDState   = require('arkitekt.gui.widgets.containers.grid.dnd_state')
local DropZones  = require('arkitekt.gui.widgets.containers.grid.drop_zones')

local M = {}
local hexrgb = Colors.hexrgb

-- ============================================================================
-- HIDDEN STATE REGISTRY (ImGui-style API)
-- ============================================================================
-- Stores Grid instances keyed by ID, with access tracking for automatic cleanup

local _grid_state = {
  instances = {},      -- Grid instances by ID
  access_times = {},   -- Last access time per ID
  frame_ids = {},      -- IDs used this frame (for duplicate detection)
  last_frame = 0,      -- Last frame number for frame_ids reset
}

local STALE_THRESHOLD = 30.0  -- Remove instances not accessed for 30 seconds

-- Debug mode: warn about duplicate IDs
local DEBUG = true

--- Clean up stale grid instances
local function cleanup_stale_instances()
  local now = reaper.time_precise()
  for id, last_access in pairs(_grid_state.access_times) do
    if now - last_access > STALE_THRESHOLD then
      _grid_state.instances[id] = nil
      _grid_state.access_times[id] = nil
    end
  end
end

--- Reset frame tracking (call at start of each frame)
local function reset_frame_tracking()
  local frame = ImGui.GetFrameCount and ImGui.GetFrameCount() or reaper.time_precise()
  if frame ~= _grid_state.last_frame then
    _grid_state.frame_ids = {}
    _grid_state.last_frame = frame
    -- Periodic cleanup every few seconds
    if math.random() < 0.01 then
      cleanup_stale_instances()
    end
  end
end

local DEFAULTS = {
  layout = { speed = 14.0, snap_epsilon = 0.5 },
  drag = { threshold = 6 },
  
  spawn = {
    enabled = true,
    duration = 0.28,
  },
  
  destroy = {
    enabled = true,
  },
  
  marquee = {
    drag_threshold = 3,
    fill_color = hexrgb("#FFFFFF22"),
    fill_color_add = hexrgb("#FFFFFF33"),
    stroke_color = hexrgb("#FFFFFF"),
    stroke_thickness = 1,
    rounding = 0,
  },

  dim = {
    fill_color = hexrgb("#00000088"),
    stroke_color = hexrgb("#FFFFFF33"),
    stroke_thickness = 1.5,
    rounding = 6,
  },
  
  drop = {
    line = {
      width = 2,
      color = hexrgb("#42E896"),
      glow_width = 12,
      glow_color = hexrgb("#42E89633"),
    },
    caps = {
      width = 8,
      height = 3,
      color = hexrgb("#42E896"),
      rounding = 0,
      glow_size = 3,
      glow_color = hexrgb("#42E89644"),
    },
    pulse_speed = 2.5,
  },
  
  wheel = {
    step = 1,
  },
  
  tile_helpers = {
    hover_shadow = {
      enabled = true,
      max_offset = 2,
      max_alpha = 20,
    },
    selection = {
      ant_speed = 20,
      ant_dash = 8,
      ant_gap = 6,
      brightness_factor = 1.5,
      saturation_factor = 0.5,
    },
  },
}

M.TileHelpers = Rendering.TileHelpers

local Grid = {}
Grid.__index = Grid

function M.new(opts)
  opts = opts or {}

  local grid_id = opts.id or "grid"

  local grid
  grid = setmetatable({
    id               = grid_id,
    gap              = opts.gap or 12,
    min_col_w_fn     = type(opts.min_col_w) == "function" and opts.min_col_w or function() return opts.min_col_w or 160 end,
    -- fixed_tile_h_fn: If opts provides function, use it. Otherwise create function that reads from grid.fixed_tile_h
    fixed_tile_h_fn  = type(opts.fixed_tile_h) == "function" and opts.fixed_tile_h or function() return grid.fixed_tile_h end,
    fixed_tile_h     = opts.fixed_tile_h,  -- Keep for backward compatibility with direct assignment
    get_items        = opts.get_items or function() return {} end,
    key              = opts.key or function(item) return tostring(item) end,
    get_exclusion_zones = opts.get_exclusion_zones,

    behaviors        = opts.behaviors or {},
    mouse_behaviors  = opts.mouse_behaviors or {},
    custom_shortcuts = opts.shortcuts or {},
    render_tile      = opts.render_tile or function() end,
    render_overlays  = opts.render_overlays,

    external_drag_check = opts.external_drag_check,
    is_copy_mode_check = opts.is_copy_mode_check,
    accept_external_drops = opts.accept_external_drops or false,
    render_drop_zones = opts.render_drop_zones or true,
    on_external_drop = opts.on_external_drop,
    on_destroy_complete = opts.on_destroy_complete,
    on_click_empty   = opts.on_click_empty,

    extend_input_area = opts.extend_input_area or { left = 0, right = 0, top = 0, bottom = 0 },
    clip_rendering = opts.clip_rendering or false,

    config           = opts.config or DEFAULTS,

    selection        = Selection.new(),
    rect_track       = RectTrack.new(
      opts.layout_speed or DEFAULTS.layout.speed,
      opts.layout_snap or DEFAULTS.layout.snap_epsilon
    ),
    sel_rect         = SelRect.new(),
    animator         = Animation.new({
      spawn = opts.config and opts.config.spawn or DEFAULTS.spawn,
      destroy = opts.config and opts.config.destroy or DEFAULTS.destroy,
      on_destroy_complete = opts.on_destroy_complete,
    }),

    hover_id         = nil,
    prev_hover_id    = nil,
    hover_start_time = nil,
    current_rects    = {},
    drag             = DnDState.new({
      threshold = (opts.config and opts.config.drag and opts.config.drag.threshold) or DEFAULTS.drag.threshold
    }),
    external_drop_target = nil,
    last_window_pos  = nil,
    previous_item_keys = {},

    last_layout_cols = 1,
    grid_bounds = nil,
    visual_bounds = nil,
    panel_clip_bounds = nil,

    -- Cache string IDs for performance (avoid string concatenation every frame)
    _cached_bg_id = "##grid_bg_" .. grid_id,
    _cached_empty_id = "##grid_empty_" .. grid_id,

    -- Virtual list mode for large datasets (1000+ items)
    virtual = opts.virtual or false,
    virtual_buffer_rows = opts.virtual_buffer_rows or 2,  -- Extra rows above/below viewport
  }, Grid)

  grid.animator:set_rect_track(grid.rect_track)

  return grid
end

function Grid:_is_mouse_in_bounds(ctx)
  if not self.visual_bounds then return false end
  local mx, my = ImGui.GetMousePos(ctx)
  return mx >= self.visual_bounds[1] and mx < self.visual_bounds[3] and
         my >= self.visual_bounds[2] and my < self.visual_bounds[4]
end

function Grid:_rect_intersects_bounds(rect, buffer)
  if not self.visual_bounds then return true end
  local gb = self.visual_bounds
  local buff = buffer or 0

  -- Expand bounds by buffer for smoother scrolling (pre-render items about to be visible)
  return not (rect[3] < (gb[1] - buff) or
              rect[1] > (gb[3] + buff) or
              rect[4] < (gb[2] - buff) or
              rect[2] > (gb[4] + buff))
end

function Grid:_find_drop_target(ctx, mx, my, dragged_set, items)
  return DropZones.find_drop_target(mx, my, items, self.key, dragged_set, self.rect_track, self.last_layout_cols == 1, self.visual_bounds)
end

function Grid:_update_external_drop_target(ctx)
  self.external_drop_target = nil
  
  if not self.accept_external_drops then return end
  if not Input.is_external_drag_active(self) then return end
  if not self:_is_mouse_in_bounds(ctx) then return end

  local mx, my = ImGui.GetMousePos(ctx)
  local items = self.get_items()
  
  local target_index, coord, alt1, alt2, orientation = self:_find_drop_target(ctx, mx, my, {}, items)
  
  if target_index and coord then
    self.external_drop_target = {
      index = target_index,
      coord = coord,
      alt1 = alt1,
      alt2 = alt2,
      orientation = orientation,
    }
  end
end

function Grid:_draw_drag_visuals(ctx, dl)
  local mx, my = ImGui.GetMousePos(ctx)
  local dragged_ids = self.drag:get_dragged_ids()
  local dragged_set = DropZones.build_dragged_set(dragged_ids)

  local items = self.get_items()
  local target_index, coord, alt1, alt2, orientation = self:_find_drop_target(ctx, mx, my, dragged_set, items)

  local cfg = self.config

  -- Cache lengths for performance
  local num_items = #items
  local num_dragged = #dragged_ids
  local all_items_dragged = (num_items > 0) and (num_dragged == num_items) or false

  if all_items_dragged then
    self.drag:set_target(nil)
  else
    self.drag:set_target(target_index)
  end

  for i = 1, num_dragged do
    local id = dragged_ids[i]
    local r = self.rect_track:get(id)
    if r then
      local dim_fill = (cfg.dim and cfg.dim.fill_color) or DEFAULTS.dim.fill_color
      local dim_stroke = (cfg.dim and cfg.dim.stroke_color) or DEFAULTS.dim.stroke_color
      local dim_thickness = (cfg.dim and cfg.dim.stroke_thickness) or DEFAULTS.dim.stroke_thickness
      local dim_rounding = (cfg.dim and cfg.dim.rounding) or DEFAULTS.dim.rounding

      ImGui.DrawList_AddRectFilled(dl, r[1], r[2], r[3], r[4], dim_fill, dim_rounding)
      ImGui.DrawList_AddRect(dl, r[1]+0.5, r[2]+0.5, r[3]-0.5, r[4]-0.5, dim_stroke, dim_rounding, 0, dim_thickness)
    end
  end

  if (not all_items_dragged) and target_index and coord and alt1 and alt2 and orientation and self.render_drop_zones then
    local is_copy_mode = self.is_copy_mode_check and self.is_copy_mode_check() or false
    if orientation == 'horizontal' then
      DropIndicator.draw(ctx, dl, cfg.drop or DEFAULTS.drop, is_copy_mode, orientation, alt1, alt2, coord)
    else
      DropIndicator.draw(ctx, dl, cfg.drop or DEFAULTS.drop, is_copy_mode, orientation, coord, alt1, alt2)
    end
  end

  if num_dragged > 0 then
    local fg_dl = ImGui.GetForegroundDrawList(ctx)
    DragIndicator.draw(ctx, fg_dl, mx, my, num_dragged, cfg.ghost or DEFAULTS.ghost)
  end
end

function Grid:_draw_external_drop_visuals(ctx, dl)
  if not self.external_drop_target or not self.render_drop_zones then return end
  
  if not self:_is_mouse_in_bounds(ctx) then return end
  
  local cfg = self.config
  local is_copy_mode = self.is_copy_mode_check and self.is_copy_mode_check() or false
  
  if self.external_drop_target.orientation == 'horizontal' then
    DropIndicator.draw(
      ctx, dl,
      cfg.drop or DEFAULTS.drop,
      is_copy_mode,
      self.external_drop_target.orientation,
      self.external_drop_target.alt1,
      self.external_drop_target.alt2,
      self.external_drop_target.coord
    )
  else
    DropIndicator.draw(
      ctx, dl,
      cfg.drop or DEFAULTS.drop,
      is_copy_mode,
      self.external_drop_target.orientation,
      self.external_drop_target.coord,
      self.external_drop_target.alt1,
      self.external_drop_target.alt2
    )
  end
end

function Grid:_draw_marquee(ctx, dl)
  if not self.sel_rect:is_active() or not self.sel_rect.start_pos then return end

  local x1, y1, x2, y2 = self.sel_rect:aabb_visual()
  if not x1 then return end

  if not self.sel_rect:did_drag() then return end

  local cfg = self.config.marquee or DEFAULTS.marquee
  local fill = (self.sel_rect.mode == "add") and
              (cfg.fill_color_add or DEFAULTS.marquee.fill_color_add) or
              (cfg.fill_color or DEFAULTS.marquee.fill_color)
  local stroke = cfg.stroke_color or DEFAULTS.marquee.stroke_color
  local thickness = cfg.stroke_thickness or DEFAULTS.marquee.stroke_thickness
  local rounding = cfg.rounding or DEFAULTS.marquee.rounding

  -- Clip marquee to visual bounds to prevent bleeding into other panels
  -- Always clip marquee regardless of clip_rendering flag for proper panel isolation
  if self.visual_bounds then
    ImGui.DrawList_PushClipRect(dl, self.visual_bounds[1], self.visual_bounds[2], self.visual_bounds[3], self.visual_bounds[4], true)
  end

  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, fill, rounding)
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, stroke, rounding, 0, thickness)

  if self.visual_bounds then
    ImGui.DrawList_PopClipRect(dl)
  end
end

function Grid:get_drop_target_index()
  if self.external_drop_target then
    return self.external_drop_target.index
  end
  return nil
end

function Grid:mark_spawned(keys)
  self.animator:mark_spawned(keys)
end

function Grid:mark_destroyed(keys)
  self.animator:mark_destroyed(keys)
end

-- Virtual list mode: only calculate layout for visible items
-- Requires fixed_tile_h for accurate height estimation
function Grid:_draw_virtual(ctx, items, num_items)
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  local origin_x, origin_y = ImGui.GetCursorScreenPos(ctx)

  local ext = self.extend_input_area
  local extended_x = origin_x - ext.left
  local extended_y = origin_y - ext.top

  -- Calculate grid parameters
  local min_col_w = self.min_col_w_fn()
  local fixed_tile_h = self.fixed_tile_h_fn and self.fixed_tile_h_fn() or self.fixed_tile_h

  if not fixed_tile_h then
    -- Fall back to regular draw if no fixed height (can't estimate total height)
    return false
  end

  -- Calculate columns
  local cols = math.max(1, (avail_w + self.gap) // (min_col_w + self.gap))
  local tile_w = (avail_w - (cols - 1) * self.gap) / cols
  local row_height = fixed_tile_h + self.gap

  -- Calculate total dimensions
  local total_rows = math.ceil(num_items / cols)
  local total_height = total_rows * row_height + self.gap

  self.last_layout_cols = cols

  -- Handle input
  local keyboard_consumed = false
  local wheel_consumed = false

  if not self.block_all_input then
    keyboard_consumed = Input.handle_shortcuts(self, ctx)
    wheel_consumed = Input.handle_wheel_input(self, ctx, items)
  end

  if wheel_consumed then
    local current_scroll_y = ImGui.GetScrollY(ctx)
    ImGui.SetScrollY(ctx, current_scroll_y)
  end

  -- Calculate visible range
  local scroll_y = ImGui.GetScrollY(ctx)
  local buffer_rows = self.virtual_buffer_rows

  local first_visible_row = math.max(0, (scroll_y / row_height) // 1 - buffer_rows)
  local last_visible_row = math.ceil((scroll_y + avail_h) / row_height) + buffer_rows

  local first_item = math.max(1, first_visible_row * cols + 1)
  local last_item = math.min(num_items, (last_visible_row + 1) * cols)

  -- Update visual bounds
  local extended_w = avail_w + ext.left + ext.right
  local extended_h = math.max(total_height, avail_h) + ext.top + ext.bottom

  if self.panel_clip_bounds then
    self.visual_bounds = self.panel_clip_bounds
  else
    local window_x, window_y = ImGui.GetWindowPos(ctx)
    self.visual_bounds = {
      window_x,
      window_y + 30,
      window_x + avail_w,
      window_y + 30 + avail_h
    }
  end

  self.grid_bounds = {extended_x, extended_y, extended_x + extended_w, extended_y + extended_h}

  -- Mouse interaction detection
  local mx, my = ImGui.GetMousePos(ctx)
  local gb = self.grid_bounds
  local mouse_in_grid = gb and mx >= gb[1] and mx <= gb[3] and my >= gb[2] and my <= gb[4]

  local is_over_ui_element = ImGui.IsAnyItemHovered(ctx) or
                              ImGui.IsPopupOpen(ctx, '', ImGui.PopupFlags_AnyPopupId)
  local allow_background_interaction = not self.disable_background_clicks and not is_over_ui_element

  local bg_clicked = mouse_in_grid and ImGui.IsMouseClicked(ctx, 0) and allow_background_interaction
  local bg_double_clicked = mouse_in_grid and ImGui.IsMouseDoubleClicked(ctx, 0) and allow_background_interaction
  local deferred_marquee_start = false

  if bg_clicked and not Input.is_external_drag_active(self) then
    deferred_marquee_start = true
  end

  -- Marquee selection handling
  local marquee_threshold = (self.config.marquee and self.config.marquee.drag_threshold) or DEFAULTS.marquee.drag_threshold

  if self.sel_rect:is_active() and ImGui.IsMouseDragging(ctx, 0, marquee_threshold) and not Input.is_external_drag_active(self) then
    local mx, my = ImGui.GetMousePos(ctx)
    self.sel_rect:update(mx, my)

    -- Calculate rects for ALL items for marquee selection (necessary evil)
    local x1, y1, x2, y2 = self.sel_rect:aabb()
    if x1 then
      local rect_map = {}
      for i = 1, num_items do
        local item = items[i]
        local row = (i - 1) // cols
        local col = (i - 1) % cols
        local rx = origin_x + col * (tile_w + self.gap)
        local ry = origin_y + self.gap + row * row_height
        rect_map[self.key(item)] = {rx, ry, rx + tile_w, ry + fixed_tile_h}
      end
      self.selection:apply_rect({x1, y1, x2, y2}, rect_map, self.sel_rect.mode)
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end
  end

  if self.sel_rect:is_active() and ImGui.IsMouseReleased(ctx, 0) then
    if not self.sel_rect:did_drag() then
      self.selection:clear()
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end
    self.sel_rect:clear()
  end

  ImGui.SetCursorScreenPos(ctx, origin_x, origin_y)

  self.hover_id = nil
  self.current_rects = {}
  local dl = ImGui.GetWindowDrawList(ctx)

  if self.clip_rendering and self.visual_bounds then
    ImGui.PushClipRect(ctx, self.visual_bounds[1], self.visual_bounds[2], self.visual_bounds[3], self.visual_bounds[4], true)
  end

  local mouse_over_tile = false
  local double_clicked_tile_key = nil

  -- Render only visible items
  for i = first_item, last_item do
    local item = items[i]
    local key = self.key(item)

    -- Calculate rect on-the-fly
    local row = (i - 1) // cols
    local col = (i - 1) % cols
    local rx = origin_x + col * (tile_w + self.gap)
    local ry = origin_y + self.gap + row * row_height
    local rect = {rx, ry, rx + tile_w, ry + fixed_tile_h}

    -- Update rect_track for this item (needed for selection, drag, etc.)
    self.rect_track:teleport(key, rect)

    self.current_rects[key] = {rect[1], rect[2], rect[3], rect[4], item}

    local state = {
      hover    = false,
      selected = self.selection:is_selected(key),
      index    = i,
    }

    local is_hovered = false
    if not self.block_all_input then
      is_hovered = Input.handle_tile_input(self, ctx, item, rect)
    end
    state.hover = is_hovered

    self.render_tile(ctx, rect, item, state, self)

    -- Check for double-click on tile
    if bg_double_clicked and Draw.point_in_rect(mx, my, rect[1], rect[2], rect[3], rect[4]) then
      mouse_over_tile = true
      double_clicked_tile_key = key
    elseif deferred_marquee_start and Draw.point_in_rect(mx, my, rect[1], rect[2], rect[3], rect[4]) then
      mouse_over_tile = true
    end
  end

  if self.clip_rendering then
    ImGui.PopClipRect(ctx)
  end

  -- Handle double-click on tile
  if bg_double_clicked and double_clicked_tile_key and self.behaviors and self.behaviors.double_click then
    self.behaviors.double_click(self, double_clicked_tile_key)
  end

  -- Start marquee selection if click was NOT over a tile
  if deferred_marquee_start and not mouse_over_tile then
    local mx, my = ImGui.GetMousePos(ctx)
    local ctrl = ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl)
    local shift = ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift)
    local mode = (ctrl or shift) and "add" or "replace"

    self.sel_rect:begin(mx, my, mode, ctx)
    if self.on_click_empty then self.on_click_empty() end
  end

  if not self.block_all_input then
    Input.check_start_drag(self, ctx)
  end

  -- Draw drag visuals (simplified for virtual mode - no animation)
  if (not self.block_all_input) and self.drag:is_active() then
    self:_draw_drag_visuals(ctx, dl)
  end

  self:_update_external_drop_target(ctx)

  if Input.is_external_drag_active(self) then
    self:_draw_external_drop_visuals(ctx, dl)

    if self.accept_external_drops and ImGui.IsMouseReleased(ctx, 0) then
      if self.external_drop_target and self.on_external_drop then
        self.on_external_drop(self.external_drop_target.index)
      end
      self.external_drop_target = nil
    end
  end

  -- Handle drag release and reorder
  if self.drag:is_active() and ImGui.IsMouseReleased(ctx, 0) then
    if self.drag:get_target_index() and self.behaviors and self.behaviors.reorder then
      local order = {}
      for i = 1, num_items do
        order[i] = self.key(items[i])
      end

      local dragged_set = DropZones.build_dragged_set(self.drag:get_dragged_ids())

      local filtered_order = {}
      for i = 1, #order do
        local id = order[i]
        if not dragged_set[id] then
          filtered_order[#filtered_order + 1] = id
        end
      end

      local new_order = {}
      local insert_pos = math.min(self.drag:get_target_index(), #filtered_order + 1)

      for i = 1, insert_pos - 1 do
        new_order[#new_order + 1] = filtered_order[i]
      end

      for _, id in ipairs(self.drag:get_dragged_ids()) do
        new_order[#new_order + 1] = id
      end

      for i = insert_pos, #filtered_order do
        new_order[#new_order + 1] = filtered_order[i]
      end

      self.behaviors.reorder(self, new_order)
    end

    local pending = self.drag:release()
    if pending and not Input.is_external_drag_active(self) then
      self.selection:single(pending)
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end
  end

  if not self.drag:is_active() and ImGui.IsMouseReleased(ctx, 0) and not Input.is_external_drag_active(self) then
    if self.drag:has_pending_selection() then
      self.selection:single(self.drag:get_pending_selection())
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end

    self.drag:release()
  end

  self:_draw_marquee(ctx, dl)

  if self.render_overlays then
    self.render_overlays(ctx, self.current_rects)
  end

  -- Hover change detection for auto-preview and other hover-based behaviors
  if self.hover_id ~= self.prev_hover_id then
    if self.behaviors and self.behaviors.on_hover then
      self.behaviors.on_hover(self, self.hover_id, self.prev_hover_id)
    end
    if self.hover_id then
      self.hover_start_time = reaper.time_precise()
    else
      self.hover_start_time = nil
    end
    self.prev_hover_id = self.hover_id
  end

  if self.hover_id and self.hover_start_time and self.behaviors and self.behaviors.on_hover_tick then
    local elapsed = reaper.time_precise() - self.hover_start_time
    self.behaviors.on_hover_tick(self, self.hover_id, elapsed)
  end

  -- Reserve vertical space for scrollbar calculation
  ImGui.SetCursorPosY(ctx, total_height)
  ImGui.Dummy(ctx, 0, 0)

  return true  -- Successfully used virtual mode
end

function Grid:draw(ctx)
  local items = self.get_items()
  -- Cache table length for performance (avoid recalculating #items multiple times)
  local num_items = #items

  -- Use virtual list mode for large datasets when enabled
  if self.virtual and num_items > 0 then
    if self:_draw_virtual(ctx, items, num_items) then
      return
    end
    -- Fall through to regular draw if virtual mode failed (e.g., no fixed_tile_h)
  end

  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  local origin_x, origin_y = ImGui.GetCursorScreenPos(ctx)

  local ext = self.extend_input_area
  local extended_x = origin_x - ext.left
  local extended_y = origin_y - ext.top

  if num_items == 0 then
    -- CRITICAL: Update animations even when grid is empty
    -- so destruction animations can complete properly
    self.animator:update(0.016)

    local extended_w = avail_w + ext.left + ext.right
    local extended_h = avail_h + ext.top + ext.bottom

    if self.panel_clip_bounds then
      self.visual_bounds = self.panel_clip_bounds
    else
      self.visual_bounds = {origin_x, origin_y, origin_x + avail_w, origin_y + avail_h}
    end

    self.grid_bounds = {extended_x, extended_y, extended_x + extended_w, extended_y + extended_h}

    -- No InvisibleButton needed when inside child window
    ImGui.SetCursorScreenPos(ctx, origin_x, origin_y)

    -- Render destruction animations even when grid is empty
    local dl = ImGui.GetWindowDrawList(ctx)
    self.animator:render_destroy_effects(ctx, dl)

    self:_update_external_drop_target(ctx)

    if Input.is_external_drag_active(self) then
      self:_draw_external_drop_visuals(ctx, dl)

      if self.accept_external_drops and ImGui.IsMouseReleased(ctx, 0) then
        if self.external_drop_target and self.on_external_drop then
          self.on_external_drop(self.external_drop_target.index)
        end
        self.external_drop_target = nil
      end
    end

    return
  end

  local keyboard_consumed = false
  local wheel_consumed = false

  if not self.block_all_input then
    keyboard_consumed = Input.handle_shortcuts(self, ctx)
    wheel_consumed = Input.handle_wheel_input(self, ctx, items)
  end
  
  if wheel_consumed then
    local current_scroll_y = ImGui.GetScrollY(ctx)
    ImGui.SetScrollY(ctx, current_scroll_y)
  end

  self.current_rects = {}

  local min_col_w = self.min_col_w_fn()
  -- Support both function (preferred) and static value (backward compat)
  local fixed_tile_h = self.fixed_tile_h_fn and self.fixed_tile_h_fn() or self.fixed_tile_h

  local cols, rows, rects = LayoutGrid.calculate(avail_w, min_col_w, self.gap, num_items, origin_x, origin_y, fixed_tile_h)

  self.last_layout_cols = cols

  local current_keys = {}
  for i, item in ipairs(items) do
    local key = self.key(item)
    current_keys[key] = true
    self.rect_track:to(key, rects[i])
  end

  local new_keys = {}
  for key, _ in pairs(current_keys) do
    if not self.previous_item_keys[key] then
      new_keys[#new_keys + 1] = key
    end
  end
  
  self.animator:handle_spawn(new_keys, self.rect_track)
  self.previous_item_keys = current_keys

  local wx, wy = ImGui.GetWindowPos(ctx)
  local window_moved = false
  if self.last_window_pos then
    if wx ~= self.last_window_pos[1] or wy ~= self.last_window_pos[2] then
      window_moved = true
    end
  end
  self.last_window_pos = {wx, wy}

  if window_moved then
    local rect_map = {}
    for i, item in ipairs(items) do rect_map[self.key(item)] = rects[i] end
    self.rect_track:teleport_all(rect_map)
  else
    self.rect_track:update()
  end
  
  self.animator:update(0.016)

  local tile_h = rects[1] and (rects[1][4] - rects[1][2]) or 100
  local grid_height = rows * (tile_h + self.gap) + self.gap

  local bg_height = math.max(grid_height, avail_h)
  
  local extended_w = avail_w + ext.left + ext.right
  local extended_h = bg_height + ext.top + ext.bottom
  
  if self.panel_clip_bounds then
    self.visual_bounds = self.panel_clip_bounds
  else
    -- CRITICAL FIX: Calculate actual visible viewport in screen space
    -- Use GetCursorStartPos to get the content area start, which stays fixed
    local window_x, window_y = ImGui.GetWindowPos(ctx)
    local scroll_y = ImGui.GetScrollY(ctx)

    -- Content area starts at window position (accounting for title bar/padding automatically)
    -- and extends by the available region size
    local content_start_y = window_y + (origin_y - scroll_y - window_y)

    -- Simpler approach: just use window pos and available region
    -- This gives us the visible viewport in screen space
    self.visual_bounds = {
      window_x,
      window_y + 30,  -- Approximate title bar height
      window_x + avail_w,
      window_y + 30 + avail_h
    }
  end
  
  self.grid_bounds = {extended_x, extended_y, extended_x + extended_w, extended_y + extended_h}

  -- DON'T create InvisibleButton when inside a child window - the child window itself
  -- prevents parent window dragging. InvisibleButton would block widget input.
  ImGui.SetCursorScreenPos(ctx, origin_x, origin_y)

  -- Manual click detection for background clicks and marquee selection
  local mx, my = ImGui.GetMousePos(ctx)
  local gb = self.grid_bounds
  local mouse_in_grid = gb and mx >= gb[1] and mx <= gb[3] and my >= gb[2] and my <= gb[4]

  -- Check if background clicks should be blocked (e.g., when overlays/popups are open)
  -- Also block if mouse is over other UI elements (buttons, widgets, child windows)
  local is_over_ui_element = ImGui.IsAnyItemHovered(ctx) or
                              ImGui.IsPopupOpen(ctx, '', ImGui.PopupFlags_AnyPopupId)
  local allow_background_interaction = not self.disable_background_clicks and not is_over_ui_element

  local bg_clicked = mouse_in_grid and ImGui.IsMouseClicked(ctx, 0) and allow_background_interaction
  local bg_double_clicked = mouse_in_grid and ImGui.IsMouseDoubleClicked(ctx, 0) and allow_background_interaction

  -- We'll check if click is over a tile AFTER rendering
  -- For now, defer marquee selection start until we know
  local mouse_over_tile = false
  local double_clicked_tile_key = nil
  local deferred_marquee_start = false

  -- Don't start marquee yet - wait until after rendering to check if click is over a tile
  if bg_clicked and not Input.is_external_drag_active(self) then
    deferred_marquee_start = true
  end

  local marquee_threshold = (self.config.marquee and self.config.marquee.drag_threshold) or DEFAULTS.marquee.drag_threshold

  -- Marquee selection with left-click drag (SHIFT disables tile drag, enables marquee)
  if self.sel_rect:is_active() and ImGui.IsMouseDragging(ctx, 0, marquee_threshold) and not Input.is_external_drag_active(self) then
    local mx, my = ImGui.GetMousePos(ctx)
    self.sel_rect:update(mx, my)

    -- Auto-scroll when near edges
    if self.visual_bounds then
      local scroll_speed = 15
      local edge_threshold = 30
      local bounds = self.visual_bounds
      
      local scroll_x = ImGui.GetScrollX(ctx)
      local scroll_y = ImGui.GetScrollY(ctx)
      local scroll_max_y = ImGui.GetScrollMaxY(ctx)
      local scroll_max_x = ImGui.GetScrollMaxX(ctx)
      
      -- Vertical scroll
      if my < bounds[2] + edge_threshold and scroll_y > 0 then
        local distance_from_edge = (bounds[2] + edge_threshold) - my
        local scroll_amount = math.min(scroll_speed * (distance_from_edge / edge_threshold), scroll_speed)
        ImGui.SetScrollY(ctx, math.max(0, scroll_y - scroll_amount))
      elseif my > bounds[4] - edge_threshold and scroll_y < scroll_max_y then
        local distance_from_edge = my - (bounds[4] - edge_threshold)
        local scroll_amount = math.min(scroll_speed * (distance_from_edge / edge_threshold), scroll_speed)
        ImGui.SetScrollY(ctx, math.min(scroll_max_y, scroll_y + scroll_amount))
      end
      
      -- Horizontal scroll (if needed)
      if mx < bounds[1] + edge_threshold and scroll_x > 0 then
        local distance_from_edge = (bounds[1] + edge_threshold) - mx
        local scroll_amount = math.min(scroll_speed * (distance_from_edge / edge_threshold), scroll_speed)
        ImGui.SetScrollX(ctx, math.max(0, scroll_x - scroll_amount))
      elseif mx > bounds[3] - edge_threshold and scroll_x < scroll_max_x then
        local distance_from_edge = mx - (bounds[3] - edge_threshold)
        local scroll_amount = math.min(scroll_speed * (distance_from_edge / edge_threshold), scroll_speed)
        ImGui.SetScrollX(ctx, math.min(scroll_max_x, scroll_x + scroll_amount))
      end
    end

    local x1, y1, x2, y2 = self.sel_rect:aabb()
    if x1 then
      local rect_map = {}
      for i = 1, num_items do
        local item = items[i]
        rect_map[self.key(item)] = rects[i]
      end
      self.selection:apply_rect({x1, y1, x2, y2}, rect_map, self.sel_rect.mode)
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end
  end

  -- Finish marquee selection on left-click release
  if self.sel_rect:is_active() and ImGui.IsMouseReleased(ctx, 0) then
    if not self.sel_rect:did_drag() then
      self.selection:clear()
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end
    self.sel_rect:clear()
  end

  ImGui.SetCursorScreenPos(ctx, origin_x, origin_y)

  self.hover_id = nil
  local dl = ImGui.GetWindowDrawList(ctx)
  
  if self.clip_rendering and self.visual_bounds then
    ImGui.PushClipRect(ctx, self.visual_bounds[1], self.visual_bounds[2], self.visual_bounds[3], self.visual_bounds[4], true)
  end

  -- Viewport culling with buffer zone (dynamic based on item count for better performance)
  local VIEWPORT_BUFFER = (num_items > 500) and 100 or 200

  -- CRITICAL OPTIMIZATION: Calculate visible row range to avoid looping through all items
  -- For 1000 items with 10 visible, this reduces loop from 1000 to ~20 items
  local first_item, last_item = 1, num_items
  if self.visual_bounds and rects[1] then
    -- Cache math functions for performance
    local floor = math.floor
    local ceil = math.ceil
    local max = math.max
    local min = math.min

    local tile_h = rects[1][4] - rects[1][2]
    local row_height = tile_h + self.gap

    -- Calculate which rows are visible (with buffer)
    local viewport_top = self.visual_bounds[2] - VIEWPORT_BUFFER
    local viewport_bottom = self.visual_bounds[4] + VIEWPORT_BUFFER

    local first_visible_row = max(0, (viewport_top - origin_y - self.gap) // row_height)
    local last_visible_row = ceil((viewport_bottom - origin_y - self.gap) / row_height)

    -- Convert row range to item indices
    first_item = max(1, first_visible_row * cols + 1)
    last_item = min(num_items, (last_visible_row + 1) * cols)
  end

  for i = first_item, last_item do
    local item = items[i]
    local key = self.key(item)
    local rect = self.rect_track:get(key)

    if rect then
      rect = self.animator:apply_spawn_to_rect(key, rect)

      -- Viewport culling check (should pass for most items in range due to row calculation)
      local is_visible = self:_rect_intersects_bounds(rect, VIEWPORT_BUFFER)

      if not is_visible then
        -- Skip rendering, input, and expensive operations for invisible items
        self.current_rects[key] = {rect[1], rect[2], rect[3], rect[4], item}
        goto continue
      end

      self.current_rects[key] = {rect[1], rect[2], rect[3], rect[4], item}

      local state = {
        hover    = false,
        selected = self.selection:is_selected(key),
        index    = i,
      }

      local is_hovered = false
      if not self.block_all_input then
        is_hovered = Input.handle_tile_input(self, ctx, item, rect)
      end
      state.hover = is_hovered

      self.render_tile(ctx, rect, item, state, self)

      -- ImGui drag-drop source (for external drops)
      if self.drag:is_active() and self.drag_payload_type and self.drag_payload_data then
        -- Check if this tile is one of the dragged tiles
        local is_dragged = false
        for _, dragged_key in ipairs(self.drag.ids or {}) do
          if dragged_key == key then
            is_dragged = true
            break
          end
        end

        -- Create drag source on first dragged tile only
        if is_dragged and key == self.drag.ids[1] then
          if ImGui.BeginDragDropSource(ctx) then
            ImGui.SetDragDropPayload(ctx, self.drag_payload_type, self.drag_payload_data)
            ImGui.Text(ctx, self.drag_label or ("Dragging " .. #self.drag.ids .. " item(s)"))
            ImGui.EndDragDropSource(ctx)
          end
        end
      end

      ::continue::
    end
  end
  
  if self.clip_rendering then
    ImGui.PopClipRect(ctx)
  end

  self.animator:render_destroy_effects(ctx, dl)

  -- NOW check if the deferred click was over a tile (after rendering, so we know where tiles are)
  if deferred_marquee_start or bg_double_clicked then
    local mx, my = ImGui.GetMousePos(ctx)
    for i = 1, num_items do
      local item = items[i]
      local key = self.key(item)
      local r = self.rect_track:get(key)
      if r and Draw.point_in_rect(mx, my, r[1], r[2], r[3], r[4]) then
        mouse_over_tile = true
        if bg_double_clicked then
          double_clicked_tile_key = key
        end
        break
      end
    end
  end

  -- Handle double-click on tile
  if bg_double_clicked and double_clicked_tile_key and self.behaviors and self.behaviors.double_click then
    self.behaviors.double_click(self, double_clicked_tile_key)
  end

  -- NOW start marquee selection if click was NOT over a tile
  if deferred_marquee_start and not mouse_over_tile then
    local mx, my = ImGui.GetMousePos(ctx)
    local ctrl = ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl)
    local shift = ImGui.IsKeyDown(ctx, ImGui.Key_LeftShift) or ImGui.IsKeyDown(ctx, ImGui.Key_RightShift)
    local mode = (ctrl or shift) and "add" or "replace"

    self.sel_rect:begin(mx, my, mode, ctx)
    if self.on_click_empty then self.on_click_empty() end
  end

  if not self.block_all_input then
    Input.check_start_drag(self, ctx)
  end

  if (not self.block_all_input) and self.drag:is_active() then
    self:_draw_drag_visuals(ctx, dl)
  end

  self:_update_external_drop_target(ctx)

  if Input.is_external_drag_active(self) then
    self:_draw_external_drop_visuals(ctx, dl)
    
    if self.accept_external_drops and ImGui.IsMouseReleased(ctx, 0) then
      if self.external_drop_target and self.on_external_drop then
        self.on_external_drop(self.external_drop_target.index)
      end
      self.external_drop_target = nil
    end
  end

  if self.drag:is_active() and ImGui.IsMouseReleased(ctx, 0) then
    if self.drag:get_target_index() and self.behaviors and self.behaviors.reorder then
      local order = {}
      for i = 1, num_items do
        order[i] = self.key(items[i])
      end

      local dragged_set = DropZones.build_dragged_set(self.drag:get_dragged_ids())

      local filtered_order = {}
      local num_order = #order
      for i = 1, num_order do
        local id = order[i]
        if not dragged_set[id] then
          filtered_order[#filtered_order + 1] = id
        end
      end
      
      local new_order = {}
      local insert_pos = math.min(self.drag:get_target_index(), #filtered_order + 1)
      
      for i = 1, insert_pos - 1 do
        new_order[#new_order + 1] = filtered_order[i]
      end
      
      for _, id in ipairs(self.drag:get_dragged_ids()) do
        new_order[#new_order + 1] = id
      end
      
      for i = insert_pos, #filtered_order do
        new_order[#new_order + 1] = filtered_order[i]
      end

      self.behaviors.reorder(self, new_order)
    end

    local pending = self.drag:release()
    if pending and not Input.is_external_drag_active(self) then
      self.selection:single(pending)
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end

    -- Clear ImGui drag payload
    self.drag_payload_type = nil
    self.drag_payload_data = nil
    self.drag_label = nil
  end

  if not self.drag:is_active() and ImGui.IsMouseReleased(ctx, 0) and not Input.is_external_drag_active(self) then
    if self.drag:has_pending_selection() then
      self.selection:single(self.drag:get_pending_selection())
      if self.behaviors and self.behaviors.on_select then
        self.behaviors.on_select(self, self.selection:selected_keys())
      end
    end

    self.drag:release()
  end

  self:_draw_marquee(ctx, dl)

  if self.render_overlays then
    self.render_overlays(ctx, self.current_rects)
  end

  -- Hover change detection for auto-preview and other hover-based behaviors
  if self.hover_id ~= self.prev_hover_id then
    -- Hover changed - call on_hover behavior if defined
    if self.behaviors and self.behaviors.on_hover then
      self.behaviors.on_hover(self, self.hover_id, self.prev_hover_id)
    end
    -- Reset hover timer when hover changes
    if self.hover_id then
      self.hover_start_time = reaper.time_precise()
    else
      self.hover_start_time = nil
    end
    self.prev_hover_id = self.hover_id
  end

  -- Call on_hover_tick for continuous hover tracking (e.g., auto-preview delay)
  if self.hover_id and self.hover_start_time and self.behaviors and self.behaviors.on_hover_tick then
    local elapsed = reaper.time_precise() - self.hover_start_time
    self.behaviors.on_hover_tick(self, self.hover_id, elapsed)
  end

  -- Reserve vertical space for full grid height so scrollbar calculation is correct
  -- Without this, ImGui doesn't know the true content height (due to viewport culling)
  -- and the scrollbar stops short of the bottom tiles
  if self.grid_bounds then
    local origin_y = self.grid_bounds[2] - (self.extend_input_area.top or 0)
    local grid_bottom = self.grid_bounds[4]
    local full_height = grid_bottom - origin_y

    -- Set cursor to reserve the space and add Dummy to expand window boundaries
    ImGui.SetCursorPosY(ctx, full_height)
    ImGui.Dummy(ctx, 0, 0)  -- Required after SetCursorPos to expand window boundaries
  end
end

function Grid:clear()
  self.selection:clear()
  self.rect_track:clear()
  self.sel_rect:clear()
  self.animator:clear()
  self.hover_id = nil
  self.current_rects = {}
  self.drag:clear()
  self.external_drop_target = nil
  self.last_window_pos = nil
  self.previous_item_keys = {}
  self.last_layout_cols = 1
  self.grid_bounds = nil
  self.visual_bounds = nil
  self.panel_clip_bounds = nil
end

-- ============================================================================
-- IMGui-STYLE API: Ark.Grid(ctx, opts)
-- ============================================================================

-- Track deprecation warnings to avoid spamming
local _new_warned = {}

--- @deprecated Use Ark.Grid(ctx, opts) instead
--- Original Grid.new() - kept for backward compatibility
local _original_new = M.new
function M.new(opts)
  opts = opts or {}
  local id = opts.id or "grid"

  -- Warn once per unique call site
  if not _new_warned[id] then
    _new_warned[id] = true
    local info = debug.getinfo(2, "Sl")
    local source = info and info.short_src or "unknown"
    local line = info and info.currentline or 0
    reaper.ShowConsoleMsg(string.format(
      "[ARKITEKT] Grid.new() is deprecated. Use Ark.Grid(ctx, opts) instead.\n  at %s:%d (id='%s')\n",
      source, line, id
    ))
  end

  return _original_new(opts)
end

--- Create a new Grid instance internally (no deprecation warning)
local function _create_grid_instance(opts)
  return _original_new(opts)
end

--- Build result object from grid state
--- @param grid table Grid instance
--- @return table Result object with all state info
local function _build_result(grid)
  local items = grid.get_items()
  local num_items = #items

  -- Selection state
  local selected_keys = grid.selection:selected_keys()
  local selection_changed = grid._selection_changed_this_frame or false

  -- Drag state
  local dragging = grid.drag:is_active()
  local drag_keys = dragging and grid.drag:get_dragged_ids() or {}
  local dropped = grid._drop_occurred_this_frame or false
  local drop_target_key = nil
  local drop_index = grid.drag:get_target_index()

  -- Reorder state
  local reordered = grid._reorder_occurred_this_frame or false
  local new_order = grid._new_order_this_frame

  -- Inline edit state
  local editing_key = grid._editing_key
  local edit_completed = grid._edit_completed_this_frame or false
  local edit_value = grid._edit_value_this_frame

  -- Click tracking
  local clicked_key = grid._clicked_key_this_frame
  local double_clicked_key = grid._double_clicked_key_this_frame
  local right_clicked_key = grid._right_clicked_key_this_frame

  return {
    -- Layout info
    visible_count = grid._visible_count or num_items,
    total_count = num_items,
    columns = grid.last_layout_cols or 1,
    scroll_y = grid._scroll_y or 0,

    -- Selection
    selected_keys = selected_keys,
    selection_changed = selection_changed,
    clicked_key = clicked_key,
    double_clicked_key = double_clicked_key,
    right_clicked_key = right_clicked_key,

    -- Drag
    dragging = dragging,
    drag_keys = drag_keys,
    dropped = dropped,
    drop_target_key = drop_target_key,
    drop_index = drop_index,

    -- Reorder
    reordered = reordered,
    new_order = new_order,

    -- Inline edit
    editing_key = editing_key,
    edit_completed = edit_completed,
    edit_value = edit_value,

    -- Hover
    hovered_key = grid.hover_id,

    -- Internal: access to grid instance for advanced use
    _instance = grid,
  }
end

--- Reset per-frame tracking flags on grid instance
local function _reset_frame_flags(grid)
  grid._selection_changed_this_frame = false
  grid._drop_occurred_this_frame = false
  grid._reorder_occurred_this_frame = false
  grid._new_order_this_frame = nil
  grid._edit_completed_this_frame = false
  grid._edit_value_this_frame = nil
  grid._clicked_key_this_frame = nil
  grid._double_clicked_key_this_frame = nil
  grid._right_clicked_key_this_frame = nil
end

--- Update grid instance with per-frame opts
local function _update_grid_from_opts(grid, opts)
  -- Update items getter
  if opts.items then
    grid.get_items = function() return opts.items end
  end

  -- Update callbacks (these may change per-frame)
  if opts.render then
    grid.render_tile = opts.render
  end

  -- Update feature flags
  if opts.selectable ~= nil then
    grid._selectable = opts.selectable
  end
  if opts.draggable ~= nil then
    grid._draggable = opts.draggable
  end
  if opts.reorderable ~= nil then
    grid._reorderable = opts.reorderable
  end

  -- Update callbacks in behaviors
  if opts.on_select then
    grid.behaviors = grid.behaviors or {}
    local user_on_select = opts.on_select
    grid.behaviors.on_select = function(g, keys)
      grid._selection_changed_this_frame = true
      user_on_select(keys)
    end
  end

  if opts.on_drag_start then
    grid.behaviors = grid.behaviors or {}
    local user_on_drag_start = opts.on_drag_start
    grid.behaviors.drag_start = function(g, keys)
      user_on_drag_start(keys)
    end
  end

  if opts.on_reorder then
    grid.behaviors = grid.behaviors or {}
    local user_on_reorder = opts.on_reorder
    grid.behaviors.reorder = function(g, new_order)
      grid._reorder_occurred_this_frame = true
      grid._new_order_this_frame = new_order
      user_on_reorder(new_order)
    end
  end

  if opts.on_right_click then
    grid.behaviors = grid.behaviors or {}
    local user_on_right_click = opts.on_right_click
    grid.behaviors['click:right'] = function(g, key, selected)
      grid._right_clicked_key_this_frame = key
      user_on_right_click(key, selected)
    end
  end

  if opts.on_double_click then
    grid.behaviors = grid.behaviors or {}
    local user_on_double_click = opts.on_double_click
    grid.behaviors.double_click = function(g, key)
      grid._double_clicked_key_this_frame = key
      user_on_double_click(key)
    end
  end
end

--- ImGui-style Grid API
--- @param ctx userdata ImGui context
--- @param opts table Options table (id required)
--- @return table Result object with selection, drag, reorder state
function M.draw(ctx, opts)
  -- Reset frame tracking
  reset_frame_tracking()

  -- Validate required 'id' field
  if not opts or not opts.id then
    error("Ark.Grid: 'id' field is required. Example: Ark.Grid(ctx, {id = 'my_grid', items = {...}})", 2)
  end

  local id = opts.id

  -- Debug: Check for duplicate IDs in same frame
  if DEBUG and _grid_state.frame_ids[id] then
    local info = debug.getinfo(2, "Sl")
    local source = info and info.short_src or "unknown"
    local line = info and info.currentline or 0
    reaper.ShowConsoleMsg(string.format(
      "[ARKITEKT] Warning: Ark.Grid duplicate ID '%s' in same frame - state will be shared!\n  at %s:%d\n",
      id, source, line
    ))
  end
  _grid_state.frame_ids[id] = true

  -- Get or create grid instance
  local grid = _grid_state.instances[id]
  if not grid then
    -- Create new instance with initial opts
    local create_opts = {
      id = id,
      gap = opts.gap,
      min_col_w = opts.min_col_w or opts.tile_width,
      fixed_tile_h = opts.fixed_tile_h or opts.tile_height,
      key = opts.key,
      render_tile = opts.render,
      get_items = opts.items and function() return opts.items end or function() return {} end,
      behaviors = {},
      config = opts.config,
      extend_input_area = opts.extend_input_area or opts.padding,
      clip_rendering = opts.clip_rendering,
      virtual = opts.virtual,
      virtual_buffer_rows = opts.virtual_buffer_rows,
      accept_external_drops = opts.accept_external_drops,
      external_drag_check = opts.external_drag_check,
      is_copy_mode_check = opts.is_copy_mode_check,
      on_external_drop = opts.on_external_drop,
      on_click_empty = opts.on_click_empty,
      render_overlays = opts.render_overlays,
    }
    grid = _create_grid_instance(create_opts)
    _grid_state.instances[id] = grid
  end

  -- Update access time
  _grid_state.access_times[id] = reaper.time_precise()

  -- Reset per-frame flags
  _reset_frame_flags(grid)

  -- Update instance with current opts
  _update_grid_from_opts(grid, opts)

  -- Draw the grid
  grid:draw(ctx)

  -- Build and return result object
  return _build_result(grid)
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

-- Make module callable: Ark.Grid(ctx, opts) → M.draw(ctx, opts)
return setmetatable(M, {
  __call = function(_, ctx, opts)
    return M.draw(ctx, opts)
  end
})