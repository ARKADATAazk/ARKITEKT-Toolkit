-- @noindex
-- Arkitekt/app/window.lua
-- FIXED: Smooth ease-in-out curve + click-through during fade-out
-- ADDED: Profiler support via titlebar

local ImGui = require('arkitekt.platform.imgui')
local Config = require('arkitekt.core.config')
local Constants = require('arkitekt.defs.app')
local Typography = require('arkitekt.defs.typography')
local Timing = require('arkitekt.defs.timing')
local Logger = require('arkitekt.debug.logger')

local M = {}
local hexrgb

local Hub = nil
do
  local ok, mod = pcall(require, 'arkitekt.app.hub')
  if ok then Hub = mod end
end

local Draw = nil
do
  local ok, mod = pcall(require, 'arkitekt.gui.draw.primitives')
  if ok then Draw = mod end
end

local Colors = nil
do
  local ok, mod = pcall(require, 'arkitekt.core.colors')
  if ok then
    Colors = mod
    hexrgb = Colors.hexrgb
  end
end

local CloseButton = nil
do
  local ok, mod = pcall(require, 'arkitekt.gui.widgets.primitives.close_button')
  if ok then CloseButton = mod end
end

local Theme = nil
do
  local ok, mod = pcall(require, 'arkitekt.core.theme')
  if ok then Theme = mod end
end

local WF_None = 0

local function floor(n) return (n + 0.5) // 1 end

local function smootherstep(t)
  t = math.max(0.0, math.min(1.0, t))
  return t * t * t * (t * (t * 6 - 15) + 10)
end

local function create_alpha_tracker(duration)
  return {
    current = 0.0,
    target = 0.0,
    duration = duration or Timing.FADE.normal,
    elapsed = 0.0,
    set_target = function(self, t) 
      self.target = t 
      self.elapsed = 0.0
    end,
    update = function(self, dt)
      if math.abs(self.target - self.current) < 0.001 then
        self.current = self.target
        return
      end
      
      self.elapsed = self.elapsed + dt
      local t = math.max(0.0, math.min(1.0, self.elapsed / self.duration))
      local smoothed = smootherstep(t)
      
      self.current = self.current + (self.target - self.current) * smoothed
      
      if self.elapsed >= self.duration then
        self.current = self.target
      end
    end,
    value = function(self) 
      return math.max(0.0, math.min(1.0, self.current))
    end,
    is_complete = function(self)
      return math.abs(self.target - self.current) < 0.001
    end
  }
end

function M.new(opts)
  -- Merge user opts with framework defaults
  local config = Config.deepMerge(Constants.WINDOW, opts or {})

  -- Deep merge fullscreen config
  local fullscreen_config = Config.deepMerge(Constants.WINDOW.fullscreen, config.fullscreen or {})
  local is_fullscreen = fullscreen_config.enabled or false

  -- Apply typography constants for font sizes if not explicitly provided
  if not opts or not opts.title_font_size then
    config.title_font_size = Typography.SIZE.lg
  end
  if not opts or not opts.version_font_size then
    config.version_font_size = Typography.SIZE.md
  end
  if not opts or not opts.titlebar_pad_v then
    config.titlebar_pad_v = Constants.TITLEBAR.pad_v
  end

  -- ============================================================================
  -- IMGUI FLAGS: Use flag builder with presets or custom flags
  -- ============================================================================
  local base_flags = WF_None

  -- If user provided custom flags, use them directly
  if config.imgui_flags ~= nil then
    base_flags = Constants.build_imgui_flags(ImGui, config.imgui_flags)
  -- LEGACY_COMPAT: Remove in v2.0 - Use imgui_flags instead of flags
  elseif config.flags then
    base_flags = config.flags
  end

  -- ============================================================================
  -- CHROME CONFIGURATION: Determine component visibility
  -- ============================================================================
  -- Priority: explicit opts > chrome preset > defaults
  local chrome = {}

  -- If a chrome preset is specified, start with that
  if config.chrome and Constants.CHROME[config.chrome] then
    chrome = Config.deepMerge(Constants.CHROME[config.chrome], {})
  else
    -- Start with empty chrome config (all features opt-in)
    chrome = {
      show_titlebar = nil,
      show_statusbar = nil,
      show_icon = nil,
      show_version = nil,
      enable_maximize = nil,
    }
  end

  -- LEGACY_COMPAT: Remove in v2.0 - Use chrome preset or chrome.{option} instead
  if opts.show_titlebar ~= nil then chrome.show_titlebar = opts.show_titlebar end
  if opts.show_status_bar ~= nil then chrome.show_statusbar = opts.show_status_bar end
  if opts.show_statusbar ~= nil then chrome.show_statusbar = opts.show_statusbar end
  if opts.show_icon ~= nil then chrome.show_icon = opts.show_icon end
  if opts.show_version ~= nil then chrome.show_version = opts.show_version end
  if opts.enable_maximize ~= nil then chrome.enable_maximize = opts.enable_maximize end

  -- Fallback to TITLEBAR defaults if still nil
  if chrome.show_titlebar == nil then chrome.show_titlebar = true end
  if chrome.show_statusbar == nil then chrome.show_statusbar = true end
  if chrome.show_icon == nil then chrome.show_icon = Constants.TITLEBAR.show_icon end
  if chrome.show_version == nil then chrome.show_version = true end
  if chrome.enable_maximize == nil then chrome.enable_maximize = Constants.TITLEBAR.enable_maximize end

  local win = {
    settings        = config.settings,
    title           = config.title,
    version         = config.version,
    flags           = base_flags,
    topmost         = config.topmost or false,

    content_padding = config.content_padding,
    titlebar_pad_h  = config.titlebar_pad_h,
    titlebar_pad_v  = config.titlebar_pad_v,
    title_font      = config.title_font,
    title_font_size = config.title_font_size,
    version_font    = config.version_font,
    version_font_size = config.version_font_size,
    version_color   = config.version_color,

    initial_pos     = config.initial_pos,
    initial_size    = config.initial_size,
    min_size        = config.min_size,

    bg_color_floating = config.bg_color_floating,
    bg_color_docked   = config.bg_color_docked,

    -- Chrome configuration
    chrome          = chrome,

    status_bar      = nil,
    tabs            = nil,
    active_tab      = nil,

    fullscreen = {
      enabled = is_fullscreen,
      use_viewport = fullscreen_config.use_viewport,
      fade_in_duration = fullscreen_config.fade_in_duration or Timing.FADE.normal,
      fade_out_duration = fullscreen_config.fade_out_duration or Timing.FADE.normal,
      scrim_enabled = fullscreen_config.scrim_enabled,
      scrim_color = fullscreen_config.scrim_color or Constants.OVERLAY.SCRIM_COLOR,
      scrim_opacity = fullscreen_config.scrim_opacity or Constants.OVERLAY.SCRIM_OPACITY,
      window_bg_override = fullscreen_config.window_bg_override,
      window_opacity = fullscreen_config.window_opacity,
      alpha = create_alpha_tracker(fullscreen_config.fade_in_duration or Timing.FADE.normal),
      close_requested = false,
      is_closing = false,
      show_close_button = fullscreen_config.show_close_button ~= false,
      close_on_background_click = fullscreen_config.close_on_background_click ~= false,
      close_on_background_left_click = fullscreen_config.close_on_background_left_click == true,
      close_button = nil,
      background_clicked = false,
    },

    titlebar_opts   = {
      height          = config.titlebar_height or Constants.TITLEBAR.height,
      pad_h           = config.titlebar_pad_h or Constants.TITLEBAR.pad_h,
      pad_v           = config.titlebar_pad_v or Constants.TITLEBAR.pad_v,
      button_width    = config.titlebar_button_width or Constants.TITLEBAR.button_width,
      button_spacing  = config.titlebar_button_spacing or Constants.TITLEBAR.button_spacing,
      button_style    = config.titlebar_button_style or Constants.TITLEBAR.button_style,
      separator       = config.titlebar_separator,
      bg_color        = config.titlebar_bg_color,
      bg_color_active = config.titlebar_bg_color_active,
      text_color      = config.titlebar_text_color,
      enable_maximize = chrome.enable_maximize,
      title_font      = config.title_font,
      title_font_size = config.title_font_size,
      version_font    = config.version_font,
      version_font_size = config.version_font_size,
      version_color   = config.version_color,
      branding_font   = config.branding_font,
      branding_font_size = config.branding_font_size,
      branding_text   = config.branding_text,
      branding_opacity = config.branding_opacity,
      branding_color  = config.branding_color,
      show_icon       = chrome.show_icon,
      show_version    = chrome.show_version,
      icon_size       = config.icon_size,
      icon_spacing    = config.icon_spacing,
      icon_color      = config.icon_color,
      icon_draw       = config.icon_draw,
    },

    _is_maximized   = false,
    _pre_max_pos    = nil,
    _pre_max_size   = nil,
    _max_viewport   = nil,
    _pending_maximize = false,
    _pending_restore  = false,

    _saved_pos      = nil,
    _saved_size     = nil,
    _pos_size_set   = false,
    _pos_size_frames = 0,  -- Track frames since first pos/size set (prevents tab flicker)
    _body_open      = false,
    _begun          = false,
    _titlebar       = nil,
    _was_docked     = false,
    _bg_color_pushed = false,
    _fullscreen_scrim_pushed = false,

    _last_frame_time = nil,
    _current_ctx = nil,

    overlay         = nil,

    show_imgui_metrics = false,
  }

  -- Apply additional flags for fullscreen mode if needed
  if is_fullscreen then
    if fullscreen_config.hide_titlebar and ImGui.WindowFlags_NoTitleBar then
      win.flags = win.flags | ImGui.WindowFlags_NoTitleBar
    end
    if fullscreen_config.no_resize and ImGui.WindowFlags_NoResize then
      win.flags = win.flags | ImGui.WindowFlags_NoResize
    end
    if fullscreen_config.no_move and ImGui.WindowFlags_NoMove then
      win.flags = win.flags | ImGui.WindowFlags_NoMove
    end
    if fullscreen_config.no_collapse and ImGui.WindowFlags_NoCollapse then
      win.flags = win.flags | ImGui.WindowFlags_NoCollapse
    end
    if fullscreen_config.no_scrollbar and ImGui.WindowFlags_NoScrollbar then
      win.flags = win.flags | ImGui.WindowFlags_NoScrollbar
    end
    if fullscreen_config.no_scroll_with_mouse and ImGui.WindowFlags_NoScrollWithMouse then
      win.flags = win.flags | ImGui.WindowFlags_NoScrollWithMouse
    end
    if ImGui.WindowFlags_NoBackground then
      win.flags = win.flags | ImGui.WindowFlags_NoBackground
    end

    win.fullscreen.alpha:set_target(1.0)
  end

  if win.settings then
    win._saved_pos  = win.settings:get("window.pos",  nil)
    win._saved_size = win.settings:get("window.size", nil)
    win._is_maximized = win.settings:get("window.maximized", false)

    -- Load pre-maximize position/size if available (for proper un-maximize)
    if win._is_maximized then
      win._pre_max_pos  = win.settings:get("window.pre_max_pos",  nil)
      win._pre_max_size = win.settings:get("window.pre_max_size", nil)
    end
  end

  -- ============================================================================
  -- CHROME COMPONENT CREATION: Status bar, tabs, titlebar
  -- ============================================================================
  if not is_fullscreen then
    -- Status bar (only if enabled in chrome config)
    if win.chrome.show_statusbar then
      local ok, StatusBar = pcall(require, 'arkitekt.app.chrome.status_bar')
      if ok and StatusBar and StatusBar.new then
        win.status_bar = StatusBar.new({
          height = Constants.STATUS_BAR.height + Constants.STATUS_BAR.compensation,
          get_status = opts.get_status_func or function() return { text = "READY", color = hexrgb("#41E0A3") } end,
          style = opts.style and { palette = opts.style.palette } or nil
        })
      end
    end

    -- Tabs (independent of chrome config)
    if opts.tabs then
      local ok, Menutabs = pcall(require, 'arkitekt.gui.widgets.navigation.menutabs')
      if ok and Menutabs and Menutabs.new then
        win.tabs = Menutabs.new(opts.tabs)
        win.active_tab = win.tabs.active
      end
    end

    -- Titlebar (only if enabled in chrome config)
    if win.chrome.show_titlebar then
      do
        local ok, Titlebar = pcall(require, 'arkitekt.app.chrome.titlebar')
        if ok and Titlebar and Titlebar.new then
          win.titlebar_opts.title = win.title
          win.titlebar_opts.version = win.version
          win.titlebar_opts.separator = opts.tabs and false or opts.titlebar_separator
          win.titlebar_opts.on_close = function()
            win._should_close = true
          end
          win.titlebar_opts.on_maximize = function()
            win:_maximize_requested()
          end
          win.titlebar_opts.on_icon_click = function(shift_clicked)
            if shift_clicked then
              win.show_imgui_metrics = not win.show_imgui_metrics
            else
              local script_path = debug.getinfo(1, "S").source
              if script_path:sub(1, 1) == "@" then
                script_path = script_path:sub(2)
              end

              local base_dir = script_path:match("(.+[/\\])")
              local hub_path = base_dir .. "../../ARKITEKT.lua"
              hub_path = hub_path:gsub("[/\\]+", "/"):gsub("/+", "/")
              while hub_path:match("[^/]+/%.%./") do
                hub_path = hub_path:gsub("[^/]+/%.%./", "")
              end
              hub_path = hub_path:gsub("/", "\\")

              if reaper.file_exists(hub_path) then
                local sanitized = hub_path:gsub("[^%w]", "")
                local cmd_name = "_RS" .. sanitized
                local cmd_id = reaper.NamedCommandLookup(cmd_name)

                if not cmd_id or cmd_id == 0 then
                  cmd_id = reaper.AddRemoveReaScript(true, 0, hub_path, true)
                end

                if cmd_id and cmd_id ~= 0 then
                  reaper.Main_OnCommand(cmd_id, 0)
                end
              else
                Logger.warn("GUI", "Hub not found: %s", hub_path)
              end
            end
          end

          win._titlebar = Titlebar.new(win.titlebar_opts)
          win._titlebar:set_maximized(win._is_maximized)
        end
      end
    end
  end

  do
    local ok, OverlayManager = pcall(require, 'arkitekt.gui.widgets.overlays.overlay.manager')
    if ok and OverlayManager and OverlayManager.new then
      win.overlay = OverlayManager.new()
    end
  end

  if is_fullscreen and win.fullscreen.show_close_button and CloseButton then
    local btn_opts = fullscreen_config.close_button or {}
    win.fullscreen.close_button = CloseButton.new({
      size = btn_opts.size or Constants.OVERLAY.CLOSE_BUTTON_SIZE,
      margin = btn_opts.margin or Constants.OVERLAY.CLOSE_BUTTON_MARGIN,
      proximity_distance = fullscreen_config.close_button_proximity or Constants.OVERLAY.CLOSE_BUTTON_PROXIMITY,
      bg_color = btn_opts.bg_color or Constants.OVERLAY.CLOSE_BUTTON_BG_COLOR,
      bg_opacity = btn_opts.bg_opacity or Constants.OVERLAY.CLOSE_BUTTON_BG_OPACITY,
      bg_opacity_hover = btn_opts.bg_opacity_hover or Constants.OVERLAY.CLOSE_BUTTON_BG_OPACITY_HOVER,
      icon_color = btn_opts.icon_color or Constants.OVERLAY.CLOSE_BUTTON_ICON_COLOR,
      hover_color = btn_opts.hover_color or Constants.OVERLAY.CLOSE_BUTTON_HOVER_COLOR,
      active_color = btn_opts.active_color or Constants.OVERLAY.CLOSE_BUTTON_ACTIVE_COLOR,
      on_click = function()
        win:request_close()
      end,
    })
  end

  function win:set_title(s)
    self.title = tostring(s or self.title)
    if self._titlebar then
      self._titlebar:set_title(self.title)
    end
  end
  
  function win:set_version(v)
    self.version = v and tostring(v) or nil
    if self._titlebar then
      self._titlebar:set_version(self.version)
    end
  end
  
  function win:set_version_color(color)
    self.version_color = color
    if self._titlebar then
      self._titlebar:set_version_color(color)
    end
  end
  
  function win:set_title_font(font)
    self.title_font = font
    if self._titlebar then
      self._titlebar.title_font = font
    end
  end

  function win:get_active_tab()
    return self.active_tab
  end

  function win:request_close()
    if self.fullscreen.enabled then
      self.fullscreen.close_requested = true
      self.fullscreen.is_closing = true
      self.fullscreen.alpha:set_target(0.0)
    else
      self._should_close = true
    end
  end

  function win:_maximize_requested()
    if ImGui.IsWindowDocked then
      if self._current_ctx and ImGui.IsWindowDocked(self._current_ctx) then
        return
      end
    end
    self._pending_maximize = true
  end

  function win:_toggle_maximize()
    if not self._current_ctx then return end
    local ctx = self._current_ctx
    
    if self._is_maximized then
      self._is_maximized = false
      self._pending_restore = true
    else
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      self._pre_max_pos = { x = floor(wx), y = floor(wy) }
      self._pre_max_size = { w = floor(ww), h = floor(wh) }
      
      local js_success = false
      if reaper.JS_Window_GetViewportFromRect then
        local left, top, right, bottom = reaper.JS_Window_GetViewportFromRect(
          wx, wy, wx + ww, wy + wh, true
        )
        if left and right and top and bottom then
          self._max_viewport = { 
            x = left, 
            y = top, 
            w = right - left, 
            h = bottom - top 
          }
          js_success = true
        end
      end
      
      if not js_success then
        local monitor_width = 1920
        local monitor_height = 1080
        local taskbar_offset = 40
        local monitor_index = math.floor((self._pre_max_pos.x + monitor_width / 2) / monitor_width)
        local monitor_left = monitor_index * monitor_width
        local monitor_top = 0
        
        self._max_viewport = { 
          x = monitor_left, 
          y = monitor_top,
          w = monitor_width, 
          h = monitor_height - taskbar_offset 
        }
      end
      
      self._is_maximized = true
    end
    
    if self._titlebar then
      self._titlebar:set_maximized(self._is_maximized)
    end

    if self.settings then
      self.settings:set("window.maximized", self._is_maximized)

      -- Save/clear pre-maximize position based on state
      if self._is_maximized and self._pre_max_pos and self._pre_max_size then
        -- Save pre-maximize position so un-maximize works after relaunch
        self.settings:set("window.pre_max_pos", self._pre_max_pos)
        self.settings:set("window.pre_max_size", self._pre_max_size)
      elseif not self._is_maximized then
        -- Clear pre-maximize position when un-maximizing
        self.settings:set("window.pre_max_pos", nil)
        self.settings:set("window.pre_max_size", nil)
      end
    end
  end

  function win:_apply_geometry(ctx)
    if self.fullscreen.enabled then
      local x, y, w, h
      
      if self.fullscreen.use_viewport then
        local viewport = ImGui.GetMainViewport(ctx)
        x, y = ImGui.Viewport_GetPos(viewport)
        w, h = ImGui.Viewport_GetSize(viewport)
      else
        local parent_x, parent_y = ImGui.GetWindowPos(ctx)
        local parent_w, parent_h = ImGui.GetWindowSize(ctx)
        x = parent_x
        y = parent_y
        w = parent_w
        h = parent_h
      end
      
      ImGui.SetNextWindowPos(ctx, x, y, ImGui.Cond_Always)
      ImGui.SetNextWindowSize(ctx, w, h, ImGui.Cond_Always)
      self._pos_size_set = true
      
    elseif self._is_maximized and self._max_viewport then
      if self._max_viewport.x and self._max_viewport.y then
        ImGui.SetNextWindowPos(ctx, self._max_viewport.x, self._max_viewport.y, ImGui.Cond_Always)
      end
      ImGui.SetNextWindowSize(ctx, self._max_viewport.w, self._max_viewport.h, ImGui.Cond_Always)
      self._pos_size_set = true
    elseif self._is_maximized and not self._max_viewport then
      -- Maximized on launch but no viewport calculated yet - calculate it now
      local pos = self._pre_max_pos or self._saved_pos or self.initial_pos
      if pos and pos.x and pos.y then
        local js_success = false
        if reaper.JS_Window_GetViewportFromRect then
          -- Use the pre-maximize position to find the correct monitor
          local left, top, right, bottom = reaper.JS_Window_GetViewportFromRect(
            pos.x, pos.y, pos.x + 100, pos.y + 100, true
          )
          if left and right and top and bottom then
            self._max_viewport = {
              x = left,
              y = top,
              w = right - left,
              h = bottom - top
            }
            js_success = true
          end
        end

        if not js_success then
          -- Fallback viewport calculation
          local monitor_width = 1920
          local monitor_height = 1080
          local taskbar_offset = 40
          local monitor_index = math.floor((pos.x + monitor_width / 2) / monitor_width)
          local monitor_left = monitor_index * monitor_width
          local monitor_top = 0

          self._max_viewport = {
            x = monitor_left,
            y = monitor_top,
            w = monitor_width,
            h = monitor_height - taskbar_offset
          }
        end

        -- Now apply the maximized geometry
        if self._max_viewport.x and self._max_viewport.y then
          ImGui.SetNextWindowPos(ctx, self._max_viewport.x, self._max_viewport.y, ImGui.Cond_Always)
        end
        ImGui.SetNextWindowSize(ctx, self._max_viewport.w, self._max_viewport.h, ImGui.Cond_Always)
        self._pos_size_set = true
      end
    elseif self._pending_restore and self._pre_max_pos then
      ImGui.SetNextWindowPos(ctx, self._pre_max_pos.x, self._pre_max_pos.y, ImGui.Cond_Always)
      ImGui.SetNextWindowSize(ctx, self._pre_max_size.w, self._pre_max_size.h, ImGui.Cond_Always)
      self._pending_restore = false
      self._pos_size_set = true
    elseif not self._pos_size_set or self._pos_size_frames < 3 then
      -- Force position/size for first 3 frames to prevent flicker with tabs
      local pos  = self._saved_pos  or self.initial_pos
      local size = self._saved_size or self.initial_size
      if pos  and pos.x  and pos.y  then ImGui.SetNextWindowPos(ctx,  pos.x,  pos.y, ImGui.Cond_Always) end
      if size and size.w and size.h then ImGui.SetNextWindowSize(ctx, size.w, size.h, ImGui.Cond_Always) end
      self._pos_size_set = true
      self._pos_size_frames = self._pos_size_frames + 1
    end
    
    if not self.fullscreen.enabled then
      if ImGui.SetNextWindowSizeConstraints and self.min_size then
        ImGui.SetNextWindowSizeConstraints(ctx, self.min_size.w, self.min_size.h, 99999, 99999)
      end
    end
  end

  function win:_save_geometry(ctx)
    if not self.settings then return end
    if self._is_maximized then return end
    if self.fullscreen.enabled then return end

    -- Don't save position/size when docked - those values are controlled by the dock
    if self._was_docked then return end

    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local pos  = { x = floor(wx), y = floor(wy) }
    local size = { w = floor(ww), h = floor(wh) }

    if (not self._saved_pos) or pos.x ~= self._saved_pos.x or pos.y ~= self._saved_pos.y then
      self._saved_pos = pos
      self.settings:set("window.pos", pos)
    end
    if (not self._saved_size) or size.w ~= self._saved_size.w or size.h ~= self._saved_size.h then
      self._saved_size = size
      self.settings:set("window.size", size)
    end
  end

  function win:Begin(ctx)
    self._body_open = false
    self._should_close = false
    self._current_ctx = ctx

    if self.fullscreen.enabled then
      local current_time = reaper.time_precise()
      local dt = 1/60
      if self._last_frame_time then
        dt = current_time - self._last_frame_time
        dt = math.max(0.001, math.min(dt, 0.1))
      end
      self._last_frame_time = current_time
      
      self.fullscreen.alpha:update(dt)
      
      if self.fullscreen.is_closing and self.fullscreen.alpha:is_complete() then
        self._should_close = true
      end
    end
    
    self:_apply_geometry(ctx)

    if self.status_bar and self.status_bar.apply_pending_resize then
      self.status_bar.apply_pending_resize(ctx)
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
    
    if self.fullscreen.enabled then
      if self.fullscreen.window_bg_override then
        local alpha_val = self.fullscreen.alpha:value()
        local bg_alpha = (255 * alpha_val + 0.5) // 1
        local bg_color = Colors and Colors.with_alpha(
          self.fullscreen.window_bg_override, 
          bg_alpha
        ) or self.fullscreen.window_bg_override
        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_color)
        self._fullscreen_scrim_pushed = true
      end
    else
      -- Use docked or floating background color
      -- (When "Adapt on docking" is enabled, the full theme is applied on dock transition)
      local bg_color = self._was_docked and self.bg_color_docked or self.bg_color_floating
      if bg_color then
        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_color)
        self._bg_color_pushed = true
      end
    end

    local window_flags = self.flags
    if self.fullscreen.enabled and self.fullscreen.is_closing and ImGui.WindowFlags_NoInputs then
      window_flags = window_flags | ImGui.WindowFlags_NoInputs
    end

    -- Keep window on top if topmost is set
    if self.topmost and ImGui.WindowFlags_TopMost then
      window_flags = window_flags | ImGui.WindowFlags_TopMost
    end

    local visible, open = ImGui.Begin(ctx, self.title .. "##main", true, window_flags)
    self._begun = true

    if visible then
      if self.fullscreen.enabled then
        local wx, wy = ImGui.GetWindowPos(ctx)
        local ww, wh = ImGui.GetWindowSize(ctx)
        
        self.fullscreen.background_clicked = false
        
        if self.fullscreen.scrim_enabled and Draw and Colors then
          local dl = ImGui.GetWindowDrawList(ctx)
          
          local alpha_val = self.fullscreen.alpha:value()
          local scrim_opacity = self.fullscreen.scrim_opacity * alpha_val
          local scrim_alpha = (255 * scrim_opacity + 0.5) // 1
          local scrim_color = Colors.with_alpha(self.fullscreen.scrim_color, scrim_alpha)
          
          Draw.rect_filled(dl, wx, wy, wx + ww, wy + wh, scrim_color, 0)
        end
        
        if not self.fullscreen.is_closing then
          ImGui.SetCursorScreenPos(ctx, wx, wy)
          ImGui.InvisibleButton(ctx, "##fullscreen_background", ww, wh)
          
          if self.fullscreen.close_on_background_click and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then
            self.fullscreen.background_clicked = true
          end
          
          if self.fullscreen.close_on_background_left_click and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) then
            self.fullscreen.background_clicked = true
          end
        end
        
        if self.fullscreen.close_button and self.fullscreen.close_button.update and not self.fullscreen.is_closing then
          local bounds = {x = wx, y = wy, w = ww, h = wh}
          local dt = self._last_frame_time and (reaper.time_precise() - self._last_frame_time) or 1/60
          self.fullscreen.close_button:update(ctx, bounds, dt)
        end
      else
        if ImGui.IsWindowDocked then
          local is_docked = ImGui.IsWindowDocked(ctx)
          -- Check if we just transitioned to docked state
          if is_docked and not self._was_docked then
            -- Apply REAPER theme without offset when docking (if enabled)
            if Theme and Theme.is_dock_adapt_enabled and Theme.is_dock_adapt_enabled() then
              Theme.sync_with_reaper_no_offset()
            end
          end
          self._was_docked = is_docked
        end
        
        if self._pending_maximize then
          self:_toggle_maximize()
          self._pending_maximize = false
        end
        
        local titlebar_rendered = false
        if self._titlebar and not self._was_docked then
          local win_w, _ = ImGui.GetWindowSize(ctx)
          local keep_open = self._titlebar:render(ctx, win_w)
          if not keep_open then
            self._should_close = true
          end
          titlebar_rendered = true
        end
        
        if self.tabs then
          if titlebar_rendered then
            local cursor_x = ImGui.GetCursorPosX(ctx)
            ImGui.SetCursorPos(ctx, cursor_x, self.titlebar_opts.height)
          end
          local active, index = self.tabs:draw(ctx)
          self.active_tab = active
        end
        
        self:_save_geometry(ctx)
      end
    end

    ImGui.PopStyleVar(ctx)
    
    if self._should_close then
      open = false
    end
    
    return visible, open
  end

  function win:BeginBody(ctx)
    if self._body_open then return false end
    
    local status_h = 0
    if not self.fullscreen.enabled then
      status_h = (self.status_bar and not self._was_docked and self.status_bar.height) or 0
    end
    local body_h = -status_h

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, self.content_padding, self.content_padding)
    local child_flags = ImGui.ChildFlags_AlwaysUseWindowPadding or 0
    local window_flags = ImGui.WindowFlags_NoScrollbar
    
    local success = ImGui.BeginChild(ctx, "##body", 0, body_h, child_flags, window_flags)
    self._body_open = true
    return success
  end

  function win:EndBody(ctx)
    if not self._body_open then return end
    ImGui.EndChild(ctx)
    ImGui.PopStyleVar(ctx)
    self._body_open = false
  end

  function win:BeginTabs(_) return true end
  function win:EndTabs(_) end

  function win:End(ctx)
    if not self.fullscreen.enabled then
      if self.status_bar and self.status_bar.render and not self._was_docked then
        ImGui.SetCursorPosX(ctx, 0)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 0, 0)
        do
          local sf = self.version_font or self.title_font
          local ss = (self.version_font_size or Typography.SIZE.md)
          if sf and ss and ss > 0 then
            ImGui.PushFont(ctx, sf, ss)
            self.status_bar.render(ctx)
            ImGui.PopFont(ctx)
          else
            self.status_bar.render(ctx)
          end
        end
        ImGui.PopStyleVar(ctx)
      end
    end

    if self.overlay and self.overlay.render then
      local titlebar_h = 0
      local statusbar_h = 0
      
      if not self.fullscreen.enabled then
        titlebar_h = (self._titlebar and not self._was_docked) and self.titlebar_opts.height or 0
        statusbar_h = (self.status_bar and not self._was_docked) and self.status_bar.height or 0
      end
      
      self.overlay:set_ui_bounds(titlebar_h, statusbar_h, self._was_docked or self.fullscreen.enabled)
      
      local dt = 1/60
      self.overlay:render(ctx, dt)
    end
    
    if self.fullscreen.enabled and self.fullscreen.close_button and self.fullscreen.close_button.render and not self.fullscreen.is_closing then
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      local dl = ImGui.GetWindowDrawList(ctx)
      local bounds = {x = wx, y = wy, w = ww, h = wh, dl = dl}
      self.fullscreen.close_button:render(ctx, bounds, dl)
    end
    
    if self.fullscreen.enabled and self.fullscreen.background_clicked and not self.fullscreen.is_closing then
      self:request_close()
    end
    
    if self.show_imgui_metrics and ImGui.ShowMetricsWindow then
      self.show_imgui_metrics = ImGui.ShowMetricsWindow(ctx, true)
    end

    -- Ensure body child window is closed before ending main window
    if self._body_open then
      ImGui.EndChild(ctx)
      ImGui.PopStyleVar(ctx)
      self._body_open = false
    end

    if self._begun then
      ImGui.End(ctx)
      self._begun = false
    end
    
    if self._fullscreen_scrim_pushed then
      ImGui.PopStyleColor(ctx)
      self._fullscreen_scrim_pushed = false
    end
    
    if self._bg_color_pushed then
      ImGui.PopStyleColor(ctx)
      self._bg_color_pushed = false
    end
  end

  return win
end

return M