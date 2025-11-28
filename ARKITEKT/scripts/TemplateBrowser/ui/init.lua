-- @noindex
-- TemplateBrowser/ui/init.lua
-- Main GUI with three-panel layout

local ImGui = require('arkitekt.platform.imgui')
local Ark = require('arkitekt')

-- Domain services
local TemplateOps = require('TemplateBrowser.domain.template.operations')
local FileOps = require('TemplateBrowser.data.file_ops')
local FXQueue = require('TemplateBrowser.domain.fx.queue')
local Scanner = require('TemplateBrowser.domain.template.scanner')
local FuzzySearch = require('TemplateBrowser.domain.search.fuzzy')

-- UI components
local TileAnim = require('arkitekt.gui.animation.tile_animator')
local TemplateGridFactory = require('TemplateBrowser.ui.tiles.factory')
local GridCallbacks = require('TemplateBrowser.ui.tiles.grid_callbacks')
local TemplateContainerConfig = require('TemplateBrowser.ui.config.template')
local RecentPanelConfig = require('TemplateBrowser.ui.config.recent')
local LeftPanelConfig = require('TemplateBrowser.ui.config.left_panel')
local ConveniencePanelConfig = require('TemplateBrowser.ui.config.convenience')
local InfoPanelConfig = require('TemplateBrowser.ui.config.info')
local Shortcuts = require('TemplateBrowser.ui.shortcuts')

-- Layout constants
local Layout = require('TemplateBrowser.defs.constants')

-- Import view modules
local LeftPanelView = require('TemplateBrowser.ui.views.left_panel_view')
local ConveniencePanelView = require('TemplateBrowser.ui.views.convenience_panel_view')
local TemplatePanelView = require('TemplateBrowser.ui.views.template_panel_view')
local InfoPanelView = require('TemplateBrowser.ui.views.info_panel_view')
local TemplateModalsView = require('TemplateBrowser.ui.views.template_modals_view')
local StatusBar = require('TemplateBrowser.ui.status')

local M = {}
local GUI = {}
GUI.__index = GUI

function M.new(config, state, scanner)
  local self = setmetatable({
    config = config,
    state = state,
    scanner = scanner,
    initialized = false,
    template_animator = TileAnim.new(16.0),  -- Animation speed
    template_grid = nil,  -- Initialized in initialize_once
    quick_access_grid = nil,  -- Initialized in initialize_once
    fonts = nil,  -- Set from shell_state in draw()
    template_container = nil,  -- Initialized in initialize_once
    recent_container = nil,  -- Initialized in initialize_once
    left_panel_container = nil,  -- Initialized in initialize_once
    convenience_panel_container = nil,  -- Initialized in initialize_once
    info_container = nil,  -- Initialized in initialize_once
  }, GUI)

  return self
end

function GUI:initialize_once(ctx, is_overlay_mode)
  if self.initialized then return end
  self.ctx = ctx
  self.is_overlay_mode = is_overlay_mode or false

  -- Create template grid with unified callbacks
  local main_grid_callbacks = GridCallbacks.create(
    self,
    function() return self.state.filtered_templates end,
    { is_quick_access = false }
  )

  self.template_grid = TemplateGridFactory.create(
    function() return self.state.filtered_templates end,
    self.state.metadata,
    self.template_animator,
    function()
      return self.state.template_view_mode == "list"
        and self.state.list_tile_width
        or self.state.grid_tile_width
    end,
    function() return self.state.template_view_mode end,
    main_grid_callbacks.on_select,
    main_grid_callbacks.on_double_click,
    main_grid_callbacks.on_right_click,
    main_grid_callbacks.on_star_click,
    main_grid_callbacks.on_tag_drop,
    self
  )

  -- Get quick access templates helper
  local function get_quick_access_templates()
    local templates
    if self.state.quick_access_mode == "favorites" then
      -- Get favorites
      if not self.state.metadata or not self.state.metadata.virtual_folders then
        return {}
      end
      local favorites = self.state.metadata.virtual_folders["__FAVORITES__"]
      if not favorites or not favorites.template_refs then
        return {}
      end
      templates = {}
      for _, ref_uuid in ipairs(favorites.template_refs) do
        for _, tmpl in ipairs(self.state.templates) do
          if tmpl.uuid == ref_uuid then
            templates[#templates + 1] = tmpl
            break
          end
        end
      end
    elseif self.state.quick_access_mode == "inbox" then
      -- Get templates in _Inbox folder
      templates = {}
      for _, tmpl in ipairs(self.state.templates) do
        if tmpl.relative_path == "_Inbox" then
          templates[#templates + 1] = tmpl
        end
      end
    elseif self.state.quick_access_mode == "most_used" then
      -- Get most used
      local usage_list = {}
      for _, tmpl in ipairs(self.state.templates) do
        local metadata = self.state.metadata and self.state.metadata.templates[tmpl.uuid]
        local usage_count = metadata and metadata.usage_count or 0
        if usage_count > 0 then
          usage_list[#usage_list + 1] = {template = tmpl, usage_count = usage_count}
        end
      end
      table.sort(usage_list, function(a, b) return a.usage_count > b.usage_count end)
      templates = {}
      for i = 1, math.min(100, #usage_list) do
        templates[#templates + 1] = usage_list[i].template
      end
    else
      -- Get recents
      local recent = {}
      for _, tmpl in ipairs(self.state.templates) do
        local metadata = self.state.metadata and self.state.metadata.templates[tmpl.uuid]
        if metadata and metadata.last_used then
          recent[#recent + 1] = {template = tmpl, last_used = metadata.last_used}
        end
      end
      table.sort(recent, function(a, b) return a.last_used > b.last_used end)
      templates = {}
      for i = 1, math.min(100, #recent) do
        templates[#templates + 1] = recent[i].template
      end
    end

    -- Apply search filter (fuzzy match)
    local search_query = self.state.quick_access_search or ""
    if search_query ~= "" then
      local filtered = {}
      for _, tmpl in ipairs(templates) do
        local score = FuzzySearch.score(search_query, tmpl.name)
        if score > 0 then
          tmpl._fuzzy_score = score
          filtered[#filtered + 1] = tmpl
        end
      end
      -- Sort by fuzzy score when searching
      table.sort(filtered, function(a, b)
        local a_score = a._fuzzy_score or 0
        local b_score = b._fuzzy_score or 0
        if a_score ~= b_score then
          return a_score > b_score
        end
        return a.name:lower() < b.name:lower()
      end)
      templates = filtered
    else
      -- Apply sort only when not searching
      local sort_mode = self.state.quick_access_sort or "alphabetical"
      if sort_mode == "alphabetical" then
        table.sort(templates, function(a, b) return a.name:lower() < b.name:lower() end)
      elseif sort_mode == "color" then
        table.sort(templates, function(a, b)
          local a_color = (self.state.metadata and self.state.metadata.templates[a.uuid] and self.state.metadata.templates[a.uuid].color) or 0
          local b_color = (self.state.metadata and self.state.metadata.templates[b.uuid] and self.state.metadata.templates[b.uuid].color) or 0
          return a_color < b_color
        end)
      end
    end

    return templates
  end

  -- Create quick access grid with unified callbacks
  local quick_access_callbacks = GridCallbacks.create(
    self,
    get_quick_access_templates,
    { is_quick_access = true }
  )

  self.quick_access_grid = TemplateGridFactory.create(
    get_quick_access_templates,
    self.state.metadata,
    self.template_animator,
    function()
      return self.state.quick_access_view_mode == "list"
        and self.state.list_tile_width
        or self.state.grid_tile_width
    end,
    function() return self.state.quick_access_view_mode end,
    quick_access_callbacks.on_select,
    quick_access_callbacks.on_double_click,
    quick_access_callbacks.on_right_click,
    quick_access_callbacks.on_star_click,
    quick_access_callbacks.on_tag_drop,
    self
  )

  -- Create template container with header controls
  local container_config = TemplateContainerConfig.create({
    get_template_count = function()
      return #self.state.filtered_templates
    end,
    get_search_query = function()
      return self.state.search_query
    end,
    on_search_changed = function(new_query)
      self.state.search_query = new_query
      
      Scanner.filter_templates(self.state)
    end,
    get_sort_mode = function()
      return self.state.sort_mode
    end,
    on_sort_changed = function(new_mode)
      self.state.sort_mode = new_mode
      
      Scanner.filter_templates(self.state)
    end,
    get_filter_items = function()
      local items = {}

      -- Add active tag filters
      if self.state.metadata and self.state.metadata.tags then
        for tag_name, _ in pairs(self.state.filter_tags) do
          local tag_data = self.state.metadata.tags[tag_name]
          if tag_data then
            items[#items + 1] = {
              id = "tag:" .. tag_name,
              label = tag_name,
              color = tag_data.color,
            }
          end
        end
      end

      -- Add active FX filters
      for fx_name, _ in pairs(self.state.filter_fx) do
        items[#items + 1] = {
          id = "fx:" .. fx_name,
          label = fx_name,
          color = 0x888888,  -- Gray for FX
        }
      end

      return items
    end,
    on_filter_remove = function(filter_id)
      -- Parse filter ID to determine type
      local filter_type, filter_name = filter_id:match("^(%w+):(.+)$")

      if filter_type == "tag" then
        -- Remove tag filter
        self.state.filter_tags[filter_name] = nil
      elseif filter_type == "fx" then
        -- Remove FX filter
        self.state.filter_fx[filter_name] = nil
      end

      -- Re-filter templates
      
      Scanner.filter_templates(self.state)
    end,
    get_view_mode_label = function()
      return (self.state.template_view_mode == "grid") and "Grid" or "List"
    end,
    on_view_toggle = function()
      self.state.template_view_mode = (self.state.template_view_mode == "grid") and "list" or "grid"
    end,
  }, self.is_overlay_mode)  -- Pass overlay mode to use transparent backgrounds

  self.template_container = Ark.Panel.new({
    id = "templates_container",
    config = container_config,
  })

  -- Create quick access panel container (recent/favorites/most used)
  local recent_config = RecentPanelConfig.create({
    get_quick_access_mode = function()
      return self.state.quick_access_mode or "recents"
    end,
    on_quick_access_mode_changed = function(new_mode)
      self.state.quick_access_mode = new_mode
    end,
    get_search_query = function()
      return self.state.quick_access_search or ""
    end,
    on_search_changed = function(new_query)
      self.state.quick_access_search = new_query
    end,
    get_sort_mode = function()
      return self.state.quick_access_sort or "alphabetical"
    end,
    on_sort_changed = function(new_mode)
      self.state.quick_access_sort = new_mode
    end,
    get_view_mode_label = function()
      return (self.state.quick_access_view_mode == "grid") and "Grid" or "List"
    end,
    on_view_toggle = function()
      self.state.quick_access_view_mode = (self.state.quick_access_view_mode == "grid") and "list" or "grid"
    end,
  }, self.is_overlay_mode)

  self.recent_container = Ark.Panel.new({
    id = "recent_container",
    config = recent_config,
  })

  -- Create left panel container (Directory/VSTs/Tags tabs)
  local left_panel_config = LeftPanelConfig.create({
    get_active_tab = function()
      return self.state.left_panel_tab or "directory"
    end,
    on_tab_change = function(tab_id)
      self.state.left_panel_tab = tab_id
    end,
  }, self.is_overlay_mode)

  self.left_panel_container = Ark.Panel.new({
    id = "left_panel_container",
    config = left_panel_config,
  })

  -- Create convenience panel container (Tags/VSTs mini tabs for quick access)
  local convenience_panel_config = ConveniencePanelConfig.create({
    get_active_tab = function()
      return self.state.convenience_panel_tab or "tags"
    end,
    on_tab_change = function(tab_id)
      self.state.convenience_panel_tab = tab_id
    end,
  }, self.is_overlay_mode)

  self.convenience_panel_container = Ark.Panel.new({
    id = "convenience_panel_container",
    config = convenience_panel_config,
  })

  -- Create info panel container (template details & tags)
  local info_panel_config = InfoPanelConfig.create({}, self.is_overlay_mode)

  self.info_container = Ark.Panel.new({
    id = "info_panel_container",
    config = info_panel_config,
  })

  self.initialized = true
end

function GUI:draw(ctx, shell_state)
  local is_overlay_mode = shell_state.is_overlay_mode == true
  self:initialize_once(ctx, is_overlay_mode)

  -- Store fonts reference for grid tiles
  self.fonts = shell_state.fonts

  -- Show loading screen while scanning templates
  if not self.state.scan_complete then
    local window_width, window_height = ImGui.GetWindowSize(ctx)

    -- Guard against NaN/inf from window size (can happen on first frame)
    if window_width ~= window_width or window_width == math.huge or window_width == -math.huge or window_width <= 0 then
      window_width = 800  -- Fallback width
    end
    if window_height ~= window_height or window_height == math.huge or window_height == -math.huge or window_height <= 0 then
      window_height = 600  -- Fallback height
    end

    -- Title text
    local text = self.state.scan_in_progress and "Scanning templates..." or "Initializing..."
    local text_width = ImGui.CalcTextSize(ctx, text)
    ImGui.SetCursorPosX(ctx, (window_width - text_width) * 0.5)
    ImGui.SetCursorPosY(ctx, window_height * 0.5 - 30)
    ImGui.Text(ctx, text)

    -- Progress bar and percentage (only during actual scanning)
    if self.state.scan_in_progress then
      local progress = self.state.scan_progress or 0

      -- Guard against NaN/inf
      if progress ~= progress or progress == math.huge or progress == -math.huge then
        progress = 0
      end

      -- Clamp to 0-1 range
      progress = math.max(0, math.min(1, progress))

      local bar_width = 300

      -- Progress bar using new widget
      Ark.ProgressBar.draw(ctx, {
        x = (window_width - bar_width) * 0.5,
        y = window_height * 0.5,
        width = bar_width,
        height = 4,
        progress = progress,
        advance = "none",
      })

      -- Percentage text (use math.floor to ensure integer)
      local percent_text = string.format("%d%%", math.floor(progress * 100))
      local percent_width = ImGui.CalcTextSize(ctx, percent_text)
      ImGui.SetCursorPosX(ctx, (window_width - percent_width) * 0.5)
      ImGui.SetCursorPosY(ctx, window_height * 0.5 + 10)
      ImGui.Text(ctx, percent_text)
    end

    return  -- Don't render main UI until scan is complete
  end

  -- Process background FX parsing queue
  FXQueue.process_batch(self.state, Layout.FX_QUEUE.BATCH_SIZE)

  -- Process conflict resolution if user made a choice
  if self.state.conflict_resolution and self.state.conflict_pending then
    local conflict = self.state.conflict_pending
    local resolution = self.state.conflict_resolution

    if resolution ~= "cancel" and conflict.operation == "move" then
      local success_count = 0
      local total_count = #conflict.templates
      local target_node = conflict.target_folder

      for _, tmpl in ipairs(conflict.templates) do
        local success, new_path, conflict_detected = FileOps.move_template(tmpl.path, target_node.full_path, resolution)
        if success then
          success_count = success_count + 1
        else
          self.state.set_status("Failed to move template: " .. tmpl.name, "error")
        end
      end

      -- Rescan if any succeeded
      if success_count > 0 then
        
        Scanner.scan_templates(self.state)

        -- Success message
        if total_count > 1 then
          self.state.set_status("Moved " .. success_count .. " of " .. total_count .. " templates to " .. target_node.name, "success")
        else
          self.state.set_status("Moved " .. conflict.templates[1].name .. " to " .. target_node.name, "success")
        end
      end
    end

    -- Clear conflict state
    self.state.conflict_pending = nil
    self.state.conflict_resolution = nil
  end

  -- Handle keyboard shortcuts (but not while editing markdown)
  local is_editing_markdown = false
  if self.state.selected_template then
    local notes_field_id = "template_notes_" .. self.state.selected_template.uuid
    is_editing_markdown = Ark.MarkdownField.is_editing(notes_field_id)
  end

  local action = Shortcuts.check_shortcuts(ctx)
  if action and not is_editing_markdown then
    if action == "undo" then
      self.state.undo_manager:undo()
    elseif action == "redo" then
      self.state.undo_manager:redo()
    elseif action == "rename_template" then
      if self.state.selected_template then
        self.state.renaming_item = self.state.selected_template
        self.state.renaming_type = "template"
        self.state.rename_buffer = self.state.selected_template.name
      end
    elseif action == "archive_template" then
      if self.state.selected_template then
        local success, archive_path = FileOps.delete_template(self.state.selected_template.path)
        if success then
          self.state.set_status("Archived: " .. self.state.selected_template.name, "success")
          -- Rescan templates
          
          Scanner.scan_templates(self.state)
          self.state.selected_template = nil
        else
          self.state.set_status("Failed to archive template", "error")
        end
      end
    elseif action == "apply_template" then
      if self.state.selected_template then
        TemplateOps.apply_to_selected_track(self.state.selected_template.path, self.state.selected_template.uuid, self.state)
      end
    elseif action == "insert_template" then
      if self.state.selected_template then
        TemplateOps.insert_as_new_track(self.state.selected_template.path, self.state.selected_template.uuid, self.state)
      end
    elseif action == "save_template" then
      -- Open save template modal
      self.state.saving_template = true
    elseif action == "focus_search" then
      -- Focus search box (will be handled by container)
      self.state.focus_search = true
    elseif action == "navigate_left" or action == "navigate_right" or
           action == "navigate_up" or action == "navigate_down" then
      -- Grid navigation (will be handled by grid widget)
      self.state.grid_navigation = action
    end
  end

  -- Get overlay alpha for animations
  local is_overlay_mode = shell_state.is_overlay_mode == true
  local overlay = shell_state.overlay

  local overlay_alpha = 1.0
  if is_overlay_mode and overlay and overlay.alpha then
    overlay_alpha = overlay.alpha:value()
  end
  self.state.overlay_alpha = overlay_alpha

  -- Get screen dimensions
  local SCREEN_W, SCREEN_H
  if is_overlay_mode and shell_state.overlay_state then
    -- Overlay mode: bounds already account for multi-monitor via overlay manager's JS API
    SCREEN_W = shell_state.overlay_state.width
    SCREEN_H = shell_state.overlay_state.height
  else
    -- Normal window mode: use viewport
    local viewport = ImGui.GetMainViewport(ctx)
    SCREEN_W, SCREEN_H = ImGui.Viewport_GetSize(viewport)
  end

  -- Title (moved up for tighter layout)
  local title_y_offset = -15  -- TODO: Move to Layout.TITLE.Y_OFFSET when added
  ImGui.PushFont(ctx, shell_state.fonts.title, shell_state.fonts.title_size)
  local title = "Template Browser"
  local title_w = ImGui.CalcTextSize(ctx, title)
  local title_y = ImGui.GetCursorPosY(ctx) + title_y_offset
  ImGui.SetCursorPos(ctx, (SCREEN_W - title_w) * 0.5, title_y)
  ImGui.Text(ctx, title)
  ImGui.PopFont(ctx)

  -- FX parsing progress indicator
  if not FXQueue.is_complete(self.state) then
    local status = FXQueue.get_status(self.state)
    local progress = FXQueue.get_progress(self.state)

    local status_y = title_y + 25
    local status_w = ImGui.CalcTextSize(ctx, status)

    ImGui.SetCursorPos(ctx, (SCREEN_W - status_w) * 0.5, status_y)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, Ark.Colors.hexrgb("#B3B3B3"))
    ImGui.Text(ctx, status)
    ImGui.PopStyleColor(ctx)

    -- Small progress bar
    local bar_width = 200
    local bar_height = 3
    ImGui.SetCursorPos(ctx, (SCREEN_W - bar_width) * 0.5, status_y + 18)
    ImGui.PushStyleColor(ctx, ImGui.Col_PlotHistogram, self.config.COLORS.selected_bg)
    ImGui.ProgressBar(ctx, progress, bar_width, bar_height, "")
    ImGui.PopStyleColor(ctx)
  end

  -- Adjust spacing after title
  ImGui.SetCursorPosY(ctx, title_y + 30)

  -- Padding (from layout constants)
  local padding_left = Layout.PADDING.PANEL
  local padding_right = Layout.PADDING.PANEL
  local padding_bottom = Layout.PADDING.PANEL
  local status_bar_height = Layout.STATUS_BAR.HEIGHT

  local cursor_y = ImGui.GetCursorPosY(ctx)
  local content_width = SCREEN_W - padding_left - padding_right
  local panel_height = SCREEN_H - cursor_y - padding_bottom - status_bar_height

  -- Get window's screen position for coordinate conversion
  -- The cursor is currently at (0, cursor_y) in window coords
  local cursor_screen_x, cursor_screen_y = ImGui.GetCursorScreenPos(ctx)
  -- Window's top-left corner in screen coords
  local window_screen_x = cursor_screen_x
  local window_screen_y = cursor_screen_y - cursor_y

  -- Draggable separator configuration (from layout constants)
  local separator_thickness = Layout.SEPARATOR.THICKNESS
  local min_panel_width = Layout.SEPARATOR.MIN_PANEL_WIDTH

  -- Calculate positions based on ratios within content area (window-relative)
  local sep1_x_local = padding_left + (content_width * self.state.separator1_ratio)
  local sep2_x_local = padding_left + (content_width * self.state.separator2_ratio)

  -- Convert to screen coordinates for separator
  local sep1_x_screen = window_screen_x + sep1_x_local
  local sep2_x_screen = window_screen_x + sep2_x_local
  local content_y_screen = window_screen_y + cursor_y

  -- Handle separator 1 dragging
  local sep1_result = Ark.Splitter.draw(ctx, {
    id = "template_sep1",
    x = sep1_x_screen,
    y = content_y_screen,
    height = panel_height,
    orientation = "vertical",
    thickness = separator_thickness,
  })
  if sep1_result.action == "drag" then
    -- Convert back to window coordinates
    local sep1_new_x = sep1_result.position - window_screen_x
    -- Clamp to valid range within content area
    local min_x = padding_left + min_panel_width
    local max_x = SCREEN_W - padding_right - min_panel_width * 2 - separator_thickness * 2
    sep1_new_x = math.max(min_x, math.min(sep1_new_x, max_x))
    self.state.separator1_ratio = (sep1_new_x - padding_left) / content_width
    sep1_x_local = sep1_new_x
    sep1_x_screen = window_screen_x + sep1_x_local
  elseif sep1_result.action == "reset" then
    self.state.separator1_ratio = self.config.FOLDERS_PANEL_WIDTH_RATIO
    sep1_x_local = padding_left + (content_width * self.state.separator1_ratio)
    sep1_x_screen = window_screen_x + sep1_x_local
  end

  -- Handle separator 2 dragging
  local sep2_result = Ark.Splitter.draw(ctx, {
    id = "template_sep2",
    x = sep2_x_screen,
    y = content_y_screen,
    height = panel_height,
    orientation = "vertical",
    thickness = separator_thickness,
  })
  if sep2_result.action == "drag" then
    -- Convert back to window coordinates
    local sep2_new_x = sep2_result.position - window_screen_x
    -- Clamp to valid range
    local min_x = sep1_x_local + separator_thickness + min_panel_width
    local max_x = SCREEN_W - padding_right - min_panel_width
    sep2_new_x = math.max(min_x, math.min(sep2_new_x, max_x))
    self.state.separator2_ratio = (sep2_new_x - padding_left) / content_width
    sep2_x_local = sep2_new_x
    sep2_x_screen = window_screen_x + sep2_x_local
  elseif sep2_result.action == "reset" then
    self.state.separator2_ratio = self.state.separator1_ratio + self.config.TEMPLATES_PANEL_WIDTH_RATIO
    sep2_x_local = padding_left + (content_width * self.state.separator2_ratio)
    sep2_x_screen = window_screen_x + sep2_x_local
  end

  -- Calculate panel widths (accounting for separator thickness)
  local left_column_width = sep1_x_local - padding_left - separator_thickness / 2
  local template_width = sep2_x_local - sep1_x_local - separator_thickness
  local info_width = SCREEN_W - padding_right - sep2_x_local - separator_thickness / 2

  -- Draw panels with padding using view modules
  -- Left column: Tabbed panel (DIRECTORY / VSTS / TAGS)
  ImGui.SetCursorPos(ctx, padding_left, cursor_y)
  LeftPanelView.draw_left_panel(ctx, self, left_column_width, panel_height)

  -- Middle panel: Templates
  ImGui.SetCursorPos(ctx, sep1_x_local + separator_thickness / 2, cursor_y)
  TemplatePanelView.draw_template_panel(ctx, self, template_width, panel_height)

  -- Right panel: Info & Tag Assignment
  ImGui.SetCursorPos(ctx, sep2_x_local + separator_thickness / 2, cursor_y)
  InfoPanelView.draw_info_panel(ctx, self, info_width, panel_height)

  -- Context menus and modals (must be drawn outside panels)
  TemplateModalsView.draw_template_context_menu(ctx, self.state)
  TemplateModalsView.draw_tag_context_menu(ctx, self.state)
  TemplateModalsView.draw_vst_context_menu(ctx, self.state)
  TemplateModalsView.draw_template_rename_modal(ctx, self.state)
  TemplateModalsView.draw_save_template_modal(ctx, self.state)
  TemplateModalsView.draw_conflict_resolution_modal(ctx, self.state)

  -- Status bar at the bottom
  
  local status_bar_y = SCREEN_H - padding_bottom - status_bar_height
  ImGui.SetCursorPos(ctx, padding_left, status_bar_y)
  StatusBar.draw(ctx, self.state, content_width, status_bar_height)

  -- Handle exit
  if self.state.exit or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    if is_overlay_mode then
      if overlay and overlay.close then
        overlay:close()
      end
    else
      if shell_state.window and shell_state.window.request_close then
        shell_state.window:request_close()
      end
    end
  end
end

return M
