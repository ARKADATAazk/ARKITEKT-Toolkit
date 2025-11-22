-- @noindex
-- ReArkitekt/app/shell.lua
-- MODIFIED: Made font loading robust against older configuration files.
-- ADDED: Support for titlebar_version size override (uses regular font family)
-- ADDED: Integrated Lua profiler support via global config flag
-- ADDED: Support for show_icon option to disable titlebar icon
-- UPDATED: ImGui 0.10 font size handling

-- Note: package.path for ImGui is set up in bootstrap.lua
local ImGui   = require 'imgui' '0.10'
local Config = require('rearkitekt.core.config')
local Constants = require('rearkitekt.defs.app')
local Typography = require('rearkitekt.defs.typography')
local Runtime = require('rearkitekt.app.runtime.runtime')
local Window  = require('rearkitekt.app.chrome.window.window')

local M = {}

local function load_fonts(ctx, font_cfg)
  font_cfg = Config.deepMerge({
    default        = Typography.SIZE.md,
    title          = Typography.SIZE.md,
    version        = Typography.SIZE.sm,
    titlebar_version = Typography.SIZE.xs,
    monospace      = Typography.SEMANTIC.code,
    time_display   = nil,
    icons          = nil,
    family_regular = Typography.FAMILY.regular,
    family_bold    = Typography.FAMILY.bold,
    family_mono    = Typography.FAMILY.mono,
    family_icons   = 'remixicon.ttf',
  }, font_cfg or {})

  local SEP      = package.config:sub(1,1)
  local src      = debug.getinfo(1, 'S').source:sub(2)
  local this_dir = src:match('(.*'..SEP..')') or ('.'..SEP)
  -- Go up TWO levels: runtime/ -> app/ -> rearkitekt/
  local parent   = this_dir:match('^(.*'..SEP..')[^'..SEP..']*'..SEP..'$') or this_dir  -- app/
  parent = parent:match('^(.*'..SEP..')[^'..SEP..']*'..SEP..'$') or parent  -- rearkitekt/
  local fontsdir = parent .. 'fonts' .. SEP

  local R = fontsdir .. font_cfg.family_regular
  local B = fontsdir .. font_cfg.family_bold
  local M = fontsdir .. font_cfg.family_mono
  local I = fontsdir .. font_cfg.family_icons
  local O = fontsdir .. 'Orbitron-Bold.ttf'  -- Orbitron for branding

  local function exists(p) local f = io.open(p, 'rb'); if f then f:close(); return true end end

  -- Track attached fonts to avoid double-attaching when fonts fallback to same object
  local attached = {}
  local function attach_once(font)
    if font and not attached[font] then
      ImGui.Attach(ctx, font)
      attached[font] = true
    end
  end

  -- Use ImGui's built-in fallback font instead of Inter TTF files
  local default_font   = ImGui.CreateFont('sans-serif', 0)
  local title_font     = ImGui.CreateFont('sans-serif', 0)
  local version_font   = ImGui.CreateFont('sans-serif', 0)

  -- Keep loading specific fonts from TTF files
  local monospace_font = exists(M) and ImGui.CreateFontFromFile(M, 0, 0)
                                or default_font

  -- Load Orbitron for branding text
  local orbitron_size = font_cfg.orbitron or Constants.TITLEBAR.branding_font_size
  local orbitron_font = exists(O) and ImGui.CreateFontFromFile(O, 0, 0) or nil

  local time_display_font = nil
  if font_cfg.time_display then
    time_display_font = ImGui.CreateFont('sans-serif', 0)
    attach_once(time_display_font)
  end

  local titlebar_version_font = nil
  local titlebar_version_size = font_cfg.titlebar_version or font_cfg.version
  if font_cfg.titlebar_version then
    titlebar_version_font = ImGui.CreateFont('sans-serif', 0)
    attach_once(titlebar_version_font)
  end

  local icons_font = nil
  if font_cfg.icons then
    icons_font = exists(I) and ImGui.CreateFontFromFile(I, 0, 0) or default_font
    attach_once(icons_font)
  end

  attach_once(default_font)
  attach_once(title_font)
  attach_once(version_font)
  attach_once(monospace_font)
  attach_once(orbitron_font)

  return {
    default = default_font,
    default_size = font_cfg.default,
    title = title_font,
    title_size = font_cfg.title,
    version = version_font,
    version_size = font_cfg.version,
    monospace = monospace_font,
    monospace_size = font_cfg.monospace,
    titlebar_version = titlebar_version_font,
    titlebar_version_size = titlebar_version_size,
    time_display = time_display_font,
    time_display_size = font_cfg.time_display,
    icons = icons_font,
    icons_size = font_cfg.icons,
    orbitron = orbitron_font,
    orbitron_size = orbitron_size,
  }
end

function M.run(opts)
  -- Merge user opts with framework defaults
  local config = Config.deepMerge(Constants.WINDOW, opts or {})

  local title    = config.title
  local version  = config.version
  local draw_fn  = config.draw or function(ctx) ImGui.Text(ctx, 'No draw function provided') end
  local style    = config.style
  local settings = config.settings
  local raw_content = (config.raw_content == true)
  local enable_profiling = config.enable_profiling ~= false

  local show_icon = config.window and config.window.show_icon
  if show_icon == nil then
    show_icon = config.show_icon
  end

  local ctx   = ImGui.CreateContext(title)
  local fonts = load_fonts(ctx, config.fonts or config.font_sizes)

  local window = Window.new({
    fullscreen      = config.fullscreen,
    title           = title,
    version         = version,
    title_font      = fonts.title,
    title_font_size = fonts.title_size,
    version_font    = fonts.titlebar_version or fonts.version,
    version_font_size = fonts.titlebar_version_size or fonts.version_size,
    version_color   = config.version_color,
    branding_font   = fonts.orbitron,  -- Pass custom font for branding text
    branding_font_size = fonts.orbitron_size,
    branding_text   = Constants.TITLEBAR.branding_text,
    branding_opacity = Constants.TITLEBAR.branding_opacity,
    branding_color  = Constants.TITLEBAR.branding_color,
    settings        = settings and settings:sub('ui') or nil,
    initial_pos     = config.initial_pos,
    initial_size    = config.initial_size,
    min_size        = config.min_size,
    show_status_bar = config.show_status_bar,
    show_titlebar   = config.show_titlebar,
    show_icon       = show_icon,
    get_status_func = config.get_status_func,
    status_bar_height = Constants.STATUS_BAR.height,
    content_padding = config.content_padding,
    titlebar_pad_h  = config.titlebar_pad_h,
    titlebar_pad_v  = config.titlebar_pad_v,
    flags           = config.flags,
    style           = style,
    tabs            = config.tabs,
    bg_color_floating = config.bg_color_floating,
    bg_color_docked   = config.bg_color_docked,
  })


  if config.overlay then
    window.overlay = config.overlay
  end

  local state = {
    window   = window,
    settings = settings,
    fonts    = fonts,
    style    = style,
    overlay  = opts.overlay,
    profiling = {
      enabled = enable_profiling,
      frame_start = 0,
      draw_time = 0,
      total_time = 0,
    }
  }

  local function draw_with_profiling(ctx, state)
    if enable_profiling and window.start_timer then
      window:start_timer("draw")
    end
    
    local result = draw_fn(ctx, state)
    
    if enable_profiling and window.end_timer then
      state.profiling.draw_time = window:end_timer("draw")
    end
    
    return result
  end

  local runtime = Runtime.new({
    title = title,
    ctx   = ctx,

    on_frame = function(ctx)
      if enable_profiling then
        state.profiling.frame_start = reaper.time_precise()
      end
      
      if style and style.PushMyStyle then 
        if enable_profiling and window.start_timer then
          window:start_timer("style_push")
        end
        style.PushMyStyle(ctx)
        if enable_profiling and window.end_timer then
          window:end_timer("style_push")
        end
      end

      ImGui.PushFont(ctx, fonts.default, fonts.default_size)

      local visible, open = window:Begin(ctx)
      if visible then
        if raw_content then
          draw_with_profiling(ctx, state)
        else
          if window:BeginBody(ctx) then
            draw_with_profiling(ctx, state)
            window:EndBody(ctx)
          end
        end
      end
      window:End(ctx)

      ImGui.PopFont(ctx)
      
      if style and style.PopMyStyle then 
        if enable_profiling and window.start_timer then
          window:start_timer("style_pop")
        end
        style.PopMyStyle(ctx)
        if enable_profiling and window.end_timer then
          window:end_timer("style_pop")
        end
      end

      if settings and settings.maybe_flush then 
        if enable_profiling and window.start_timer then
          window:start_timer("settings_flush")
        end
        settings:maybe_flush()
        if enable_profiling and window.end_timer then
          window:end_timer("settings_flush")
        end
      end
      
      if enable_profiling then
        state.profiling.total_time = (reaper.time_precise() - state.profiling.frame_start) * 1000
        if window.profiling then
          window.profiling.custom_timers["total_frame"] = state.profiling.total_time
        end
      end
      
      return open ~= false
    end,

    on_destroy = function()
      if settings and settings.flush then settings:flush() end
      if opts.on_close then opts.on_close() end
    end,
  })

  state.start_timer = function(name)
    if window.start_timer then
      window:start_timer(name)
    end
  end
  
  state.end_timer = function(name)
    if window.end_timer then
      return window:end_timer(name)
    end
    return 0
  end
  
  state.toggle_profiling = function()
    if window.toggle_profiling then
      window:toggle_profiling()
    end
  end
  
  state.get_profiling_data = function()
    if window.profiling then
      return window.profiling
    end
    return nil
  end

  runtime:start()
  return runtime
end

return M
