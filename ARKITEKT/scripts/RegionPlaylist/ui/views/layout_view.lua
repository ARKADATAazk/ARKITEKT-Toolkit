-- @noindex
-- RegionPlaylist/ui/views/layout_view.lua
-- Layout view handling horizontal and vertical split layouts

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local SeparatorView = require('rearkitekt.gui.widgets.primitives.separator')

-- Performance: Localize math functions for hot path (30% faster in loops)
local max = math.max
local min = math.min

local M = {}

local LayoutView = {}
LayoutView.__index = LayoutView

function M.new(config, state_module)
  return setmetatable({
    config = config,
    state = state_module,
    separator_view = SeparatorView.new(),
  }, LayoutView)
end

function LayoutView:get_filtered_active_items(playlist)
  local filter = self.state.active_search_filter or ""
  
  if filter == "" then
    return playlist.items
  end
  
  local filtered = {}
  local filter_lower = filter:lower()
  
  for _, item in ipairs(playlist.items) do
    if item.type == "playlist" then
      local playlist_data = self.state.get_playlist_by_id(item.playlist_id)
      local name_lower = playlist_data and playlist_data.name:lower() or ""
      if name_lower:find(filter_lower, 1, true) then
        filtered[#filtered + 1] = item
      end
    else
      local region = self.state.get_region_by_rid(item.rid)
      if region then
        local name_lower = region.name:lower()
        if name_lower:find(filter_lower, 1, true) then
          filtered[#filtered + 1] = item
        end
      end
    end
  end
  
  return filtered
end

function LayoutView:draw(ctx, region_tiles, shell_state)
  local pl = self.state.get_active_playlist()
  local filtered_active_items = self:get_filtered_active_items(pl)
  local display_playlist = {
    id = pl.id,
    name = pl.name,
    items = filtered_active_items,
  }

  local pool_data
  local pool_mode = self.state.get_pool_mode()
  if pool_mode == "playlists" then
    pool_data = self.state.get_playlists_for_pool()
  elseif pool_mode == "mixed" then
    pool_data = self.state.get_mixed_pool_sorted()
  else
    pool_data = self.state.get_filtered_pool_regions()
  end

  if self.state.get_layout_mode() == 'horizontal' then
    self:draw_horizontal(ctx, region_tiles, display_playlist, pool_data, shell_state)
  else
    self:draw_vertical(ctx, region_tiles, display_playlist, pool_data, shell_state)
  end
end

function LayoutView:draw_horizontal(ctx, region_tiles, display_playlist, pool_data, shell_state)
  local content_w, content_h = ImGui.GetContentRegionAvail(ctx)

  local separator_config = self.config.SEPARATOR.horizontal
  local min_active_height = separator_config.min_active_height
  local min_pool_height = separator_config.min_pool_height
  local separator_gap = separator_config.gap

  local min_total_height = min_active_height + min_pool_height + separator_gap

  local active_height, pool_height

  if content_h < min_total_height then
    local ratio = content_h / min_total_height
    active_height = (min_active_height * ratio)//1
    pool_height = content_h - active_height - separator_gap

    if active_height < 50 then active_height = 50 end
    if pool_height < 50 then pool_height = 50 end

    pool_height = max(1, content_h - active_height - separator_gap)
  else
    active_height = self.state.get_separator_position_horizontal()
    active_height = max(min_active_height, min(active_height, content_h - min_pool_height - separator_gap))
    pool_height = content_h - active_height - separator_gap
  end

  active_height = max(1, active_height)
  pool_height = max(1, pool_height)

  local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

  local sep_thickness = separator_config.thickness
  local sep_y = start_y + active_height + separator_gap/2
  local mx, my = ImGui.GetMousePos(ctx)
  local over_sep_h = (mx >= start_x and mx < start_x + content_w and my >= sep_y - sep_thickness/2 and my < sep_y + sep_thickness/2)
  local block_input = self.separator_view:is_dragging() or (over_sep_h and ImGui.IsMouseDown(ctx, 0))

  if region_tiles.active_grid then region_tiles.active_grid.block_all_input = block_input end
  if region_tiles.pool_grid then region_tiles.pool_grid.block_all_input = block_input end

  region_tiles:draw_active(ctx, display_playlist, active_height, shell_state)
  
  local separator_y = sep_y
  local action, value = self.separator_view:draw_horizontal(ctx, start_x, separator_y, content_w, content_h, separator_config)
  
  if action == "reset" then
    self.state.set_separator_position_horizontal(separator_config.default_position)
    self.state.persist_ui_prefs()
  elseif action == "drag" and content_h >= min_total_height then
    local new_active_height = value - start_y - separator_gap/2
    new_active_height = max(min_active_height, min(new_active_height, content_h - min_pool_height - separator_gap))
    self.state.set_separator_position_horizontal(new_active_height)
    self.state.persist_ui_prefs()
  end
  
  ImGui.SetCursorScreenPos(ctx, start_x, start_y + active_height + separator_gap)

  region_tiles:draw_pool(ctx, pool_data, pool_height, shell_state)
  
  if not self.separator_view:is_dragging() and not (over_sep_h and ImGui.IsMouseDown(ctx, 0)) then
    if region_tiles.active_grid then region_tiles.active_grid.block_all_input = false end
    if region_tiles.pool_grid then region_tiles.pool_grid.block_all_input = false end
  end
end

function LayoutView:draw_vertical(ctx, region_tiles, display_playlist, pool_data, shell_state)
  local content_w, content_h = ImGui.GetContentRegionAvail(ctx)

  local separator_config = self.config.SEPARATOR.vertical
  local min_active_width = separator_config.min_active_width
  local min_pool_width = separator_config.min_pool_width
  local separator_gap = separator_config.gap

  local min_total_width = min_active_width + min_pool_width + separator_gap

  local active_width, pool_width

  if content_w < min_total_width then
    local ratio = content_w / min_total_width
    active_width = (min_active_width * ratio)//1
    pool_width = content_w - active_width - separator_gap

    if active_width < 50 then active_width = 50 end
    if pool_width < 50 then pool_width = 50 end

    pool_width = max(1, content_w - active_width - separator_gap)
  else
    active_width = self.state.get_separator_position_vertical()
    active_width = max(min_active_width, min(active_width, content_w - min_pool_width - separator_gap))
    pool_width = content_w - active_width - separator_gap
  end

  active_width = max(1, active_width)
  pool_width = max(1, pool_width)

  local start_cursor_x, start_cursor_y = ImGui.GetCursorScreenPos(ctx)

  local sep_thickness = separator_config.thickness
  local sep_x = start_cursor_x + active_width + separator_gap/2
  local mx, my = ImGui.GetMousePos(ctx)
  local over_sep_v = (mx >= sep_x - sep_thickness/2 and mx < sep_x + sep_thickness/2 and my >= start_cursor_y and my < start_cursor_y + content_h)
  local block_input = self.separator_view:is_dragging() or (over_sep_v and ImGui.IsMouseDown(ctx, 0))

  if region_tiles.active_grid then region_tiles.active_grid.block_all_input = block_input end
  if region_tiles.pool_grid then region_tiles.pool_grid.block_all_input = block_input end

  -- Ensure content_h is valid to prevent BeginChild/EndChild errors
  local safe_content_h = math.max(1, content_h or 1)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 0, 0)

  -- Wrap in pcall to ensure PopStyleVar is always called
  local success, error_msg = pcall(function()
    if ImGui.BeginChild(ctx, "##left_column", active_width, safe_content_h, ImGui.ChildFlags_None, 0) then
      region_tiles:draw_active(ctx, display_playlist, safe_content_h, shell_state)
      ImGui.EndChild(ctx)
    end
  end)

  ImGui.PopStyleVar(ctx)

  if not success and error_msg then
    reaper.ShowConsoleMsg("Layout error (left column): " .. tostring(error_msg) .. "\n")
  end
  
  local separator_x = sep_x
  local action, value = self.separator_view:draw_vertical(ctx, separator_x, start_cursor_y, content_w, content_h, separator_config)
  
  if action == "reset" then
    self.state.set_separator_position_vertical(separator_config.default_position)
    self.state.persist_ui_prefs()
  elseif action == "drag" and content_w >= min_total_width then
    local new_active_width = value - start_cursor_x - separator_gap/2
    new_active_width = max(min_active_width, min(new_active_width, content_w - min_pool_width - separator_gap))
    self.state.set_separator_position_vertical(new_active_width)
    self.state.persist_ui_prefs()
  end
  
  if not self.separator_view:is_dragging() and not (over_sep_v and ImGui.IsMouseDown(ctx, 0)) then
    if region_tiles.active_grid then region_tiles.active_grid.block_all_input = false end
    if region_tiles.pool_grid then region_tiles.pool_grid.block_all_input = false end
  end
  
  ImGui.SetCursorScreenPos(ctx, start_cursor_x + active_width + separator_gap, start_cursor_y)

  -- Ensure content_h is valid to prevent BeginChild/EndChild errors
  local safe_content_h = math.max(1, content_h or 1)

  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 0, 0)

  -- Wrap in pcall to ensure PopStyleVar is always called
  local success, error_msg = pcall(function()
    if ImGui.BeginChild(ctx, "##right_column", pool_width, safe_content_h, ImGui.ChildFlags_None, 0) then
      region_tiles:draw_pool(ctx, pool_data, safe_content_h, shell_state)
      ImGui.EndChild(ctx)
    end
  end)

  ImGui.PopStyleVar(ctx)

  if not success and error_msg then
    reaper.ShowConsoleMsg("Layout error (right column): " .. tostring(error_msg) .. "\n")
  end
end

return M
