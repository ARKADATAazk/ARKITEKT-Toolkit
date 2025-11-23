-- @noindex
-- ReArkitekt/app/titlebar.lua
-- MODIFIED: Stylized titlebar with centered "AZK" branding
-- ADDED: Context menu on right-click icon (Hub, Metrics, Debug Console, Profiler)
-- REMOVED: Keyboard shortcuts and tooltips for cleaner interface
-- UPDATED: ImGui 0.10 font size handling

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Colors = require('arkitekt.core.colors')
local Config = require('arkitekt.core.config')
local Constants = require('arkitekt.defs.app')
local Typography = require('arkitekt.defs.typography')
local ContextMenu = require('arkitekt.gui.widgets.overlays.context_menu')

local M = {}
local hexrgb = Colors.hexrgb

local Icon = nil
do
  local ok, mod = pcall(require, 'arkitekt.app.assets.icon')
  if ok then Icon = mod end
end

-- Format version string: extract numbers and dots, prepend "v"
local function format_version(version)
  if not version or version == "" then return nil end

  -- Extract only numbers and dots
  local clean = version:gsub("[^%d%.]", "")

  -- Remove leading/trailing dots
  clean = clean:gsub("^%.+", ""):gsub("%.+$", "")

  if clean == "" then return nil end

  return "v" .. clean
end

function M.new(opts)
  -- Merge user opts with framework defaults
  local config = Config.deepMerge(Constants.TITLEBAR, opts or {})

  -- Apply typography constants for font sizes
  if not opts or not opts.title_font_size then
    config.title_font_size = Typography.SIZE.lg
  end
  if not opts or not opts.version_font_size then
    config.version_font_size = Typography.SIZE.md
  end

  local titlebar = {
    -- Text content
    title           = config.title or "Window",
    version         = format_version(config.version),

    -- Fonts
    title_font      = config.title_font,
    title_font_size = config.title_font_size,
    version_font    = config.version_font,
    version_font_size = config.version_font_size,
    branding_font   = config.branding_font,
    branding_font_size = config.branding_font_size,
    branding_text   = config.branding_text,
    branding_opacity = config.branding_opacity,
    branding_color  = config.branding_color,

    -- Layout (from merged config)
    height          = config.height,
    pad_h           = config.pad_h,
    pad_v           = config.pad_v,
    button_width    = config.button_width,
    button_spacing  = config.button_spacing,
    button_style    = config.button_style,
    separator       = config.separator ~= false,

    -- Colors
    bg_color        = config.bg_color,
    bg_color_active = config.bg_color_active,
    text_color      = config.text_color,
    version_color   = config.version_color,
    version_spacing = config.version_spacing,

    -- Icon
    show_icon       = config.show_icon ~= false,
    icon_size       = config.icon_size,
    icon_spacing    = config.icon_spacing,
    icon_color      = config.icon_color,
    icon_draw       = config.icon_draw,
    icon_image      = nil,  -- Will be loaded on first draw

    -- State
    enable_maximize = config.enable_maximize ~= false,
    is_maximized    = false,

    -- Callbacks
    on_close        = config.on_close,
    on_maximize     = config.on_maximize,
    on_icon_click   = config.on_icon_click,
  }
  
  function titlebar:_truncate_text(ctx, text, max_width, font, font_size)
    if not text then return "" end

    if font then ImGui.PushFont(ctx, font, font_size) end
    local text_w = ImGui.CalcTextSize(ctx, text)
    if font then ImGui.PopFont(ctx) end
    
    if text_w <= max_width then
      return text
    end

    local ellipsis = "..."
    if font then ImGui.PushFont(ctx, font, font_size) end
    local ellipsis_w = ImGui.CalcTextSize(ctx, ellipsis)
    if font then ImGui.PopFont(ctx) end

    if max_width < ellipsis_w then
      return ""
    end

    for i = #text, 1, -1 do
      local sub = text:sub(1, i)
      if font then ImGui.PushFont(ctx, font, font_size) end
      local sub_w = ImGui.CalcTextSize(ctx, sub)
      if font then ImGui.PopFont(ctx) end
      
      if sub_w + ellipsis_w <= max_width then
        return sub .. ellipsis
      end
    end

    return ellipsis
  end

  function titlebar:_draw_icon(ctx, x, y, color)
    -- Custom icon draw function takes priority
    if self.icon_draw then
      self.icon_draw(ctx, x, y, self.icon_size, color)
      return
    end

    -- Try PNG image first (load once and cache, DPI-aware)
    if Icon and Icon.load_image and Icon.draw_png then
      if not self.icon_image then
        local dpi = ImGui.GetWindowDpiScale(ctx) or 1.0
        self.icon_image = Icon.load_image(ctx, "ARKITEKT", dpi)
      end
      if self.icon_image and Icon.draw_png(ctx, x, y, self.icon_size, self.icon_image) then
        return
      end
    end

    -- Fall back to vector drawing
    if Icon and Icon.draw_arkitekt then
      Icon.draw_arkitekt(ctx, x, y, self.icon_size, color)
    else
      -- Ultimate fallback: simple circle
      local draw_list = ImGui.GetWindowDrawList(ctx)
      local dpi = ImGui.GetWindowDpiScale(ctx)
      local r = (self.icon_size * 0.5) * dpi
      ImGui.DrawList_AddCircleFilled(draw_list, x + r, y + r, r, color)
    end
  end
  
  function titlebar:set_title(title)
    self.title = tostring(title or self.title)
  end
  
  function titlebar:set_version(version)
    self.version = format_version(version)
  end
  
  function titlebar:set_maximized(state)
    self.is_maximized = state
  end
  
  function titlebar:set_icon_visible(visible)
    self.show_icon = visible
  end
  
  function titlebar:set_icon_color(color)
    self.icon_color = color
  end
  
  function titlebar:set_version_color(color)
    self.version_color = color
  end
  
  function titlebar:render(ctx, win_w)
    if not win_w or win_w <= 0 or not self.height or self.height <= 0 then
      return true
    end
    
    local is_focused = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootWindow)
    
    local bg_color = self.bg_color
    if not bg_color then
      bg_color = is_focused 
        and (self.bg_color_active or ImGui.GetColor(ctx, ImGui.Col_TitleBgActive))
        or ImGui.GetColor(ctx, ImGui.Col_TitleBg)
    end
    
    local text_color = self.text_color or ImGui.GetColor(ctx, ImGui.Col_Text)
    local version_color = self.version_color or Constants.TITLEBAR.version_color
    
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 0, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, self.button_spacing, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, bg_color)
    
    local titlebar_flags = ImGui.ChildFlags_None
    local window_flags = ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoScrollWithMouse
    
    local child_visible = ImGui.BeginChild(ctx, "##titlebar", win_w, self.height, titlebar_flags, window_flags)
    
    local clicked_maximize = false
    local clicked_close = false
    local icon_clicked = false
    local icon_shift_clicked = false
    
    if child_visible then
      local content_h = ImGui.GetTextLineHeight(ctx)
      local y_center = (self.height - content_h) * 0.5 
      
      ImGui.SetCursorPos(ctx, self.pad_h, y_center)
      
      local title_x_offset = 0
      if self.show_icon then
        local win_x, win_y = ImGui.GetWindowPos(ctx)
        local native_icon_size = 22  -- Native PNG size
        local icon_x = win_x + self.pad_h - 12  -- Move icon 12px left
        local icon_y = win_y + (self.height - native_icon_size) * 0.5
        local icon_color = self.icon_color or text_color

        ImGui.SetCursorPos(ctx, self.pad_h - 12, (self.height - native_icon_size) * 0.5)  -- Move icon 12px left
        ImGui.InvisibleButton(ctx, "##icon_button", native_icon_size, native_icon_size)

        local icon_hovered = ImGui.IsItemHovered(ctx)
        local icon_left_clicked = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left)
        local icon_right_clicked = ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)

        -- Left click triggers normal icon click
        if icon_left_clicked then
          icon_clicked = true
        end

        -- Right click opens context menu
        if icon_right_clicked then
          ImGui.OpenPopup(ctx, "##icon_context_menu")
        end

        local draw_color = icon_color
        if icon_hovered then
          local r = (draw_color >> 24) & 0xFF
          local g = (draw_color >> 16) & 0xFF
          local b = (draw_color >> 8) & 0xFF
          local a = draw_color & 0xFF
          r = math.min(255, r + 30)
          g = math.min(255, g + 30)
          b = math.min(255, b + 30)
          draw_color = (r << 24) | (g << 16) | (b << 8) | a
        end

        self:_draw_icon(ctx, icon_x, icon_y, draw_color)

        -- Context menu on right-click
        if ContextMenu.begin(ctx, "##icon_context_menu") then
          if ContextMenu.item(ctx, "Open Hub") then
            icon_clicked = true
          end

          if ContextMenu.item(ctx, "Show Metrics") then
            icon_shift_clicked = true
          end

          ContextMenu.separator(ctx)

          if ContextMenu.item(ctx, "Debug Console") then
            local ok, ConsoleWindow = pcall(require, 'arkitekt.debug.console_window')
            if ok and ConsoleWindow and ConsoleWindow.launch then
              ConsoleWindow.launch()
            end
          end

          if ContextMenu.item(ctx, "Lua Profiler") then
            -- Trigger profiler (originally CTRL+SHIFT+ALT+CLICK)
            -- You can add profiler launch logic here if needed
          end

          ContextMenu.end_menu(ctx)
        end

        title_x_offset = native_icon_size + self.icon_spacing - 10  -- Title stays at -10px
        ImGui.SetCursorPos(ctx, self.pad_h + title_x_offset, y_center)
      end
      
      local num_buttons = 1 + (self.enable_maximize and 1 or 0)
      local total_button_width = (self.button_width * num_buttons) + (self.button_spacing * (num_buttons - 1))
      
      local title_start_x = ImGui.GetCursorPosX(ctx)
      local available_width = (win_w - total_button_width) - title_start_x - self.pad_h
      
      if self.version and self.version ~= "" then
        if self.title_font then ImGui.PushFont(ctx, self.title_font, self.title_font_size) end
        local title_w = ImGui.CalcTextSize(ctx, self.title)
        local title_h = ImGui.GetTextLineHeight(ctx)
        if self.title_font then ImGui.PopFont(ctx) end
        
        local version_font = self.version_font
        if version_font then ImGui.PushFont(ctx, version_font, self.version_font_size) end
        local version_w = ImGui.CalcTextSize(ctx, self.version)
        local version_h = ImGui.GetTextLineHeight(ctx)
        if version_font then ImGui.PopFont(ctx) end
        
        local total_w = title_w + self.version_spacing + version_w
        
        if total_w <= available_width then
          local base_y = ImGui.GetCursorPosY(ctx)
          
          if self.title_font then ImGui.PushFont(ctx, self.title_font, self.title_font_size) end
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
          ImGui.Text(ctx, self.title)
          ImGui.PopStyleColor(ctx)
          if self.title_font then ImGui.PopFont(ctx) end

          ImGui.SameLine(ctx, 0, self.version_spacing - 10)  -- Move version 10px left
          
          local height_diff = title_h - version_h
          if height_diff ~= 0 then
            ImGui.SetCursorPosY(ctx, base_y + height_diff - 1)
          end
          
          if version_font then ImGui.PushFont(ctx, version_font, self.version_font_size) end
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, version_color)
          ImGui.Text(ctx, self.version)
          ImGui.PopStyleColor(ctx)
          if version_font then ImGui.PopFont(ctx) end
        else
          if self.title_font then ImGui.PushFont(ctx, self.title_font, self.title_font_size) end
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
          local display_title = self:_truncate_text(ctx, self.title .. " " .. self.version, available_width, self.title_font, self.title_font_size)
          ImGui.Text(ctx, display_title)
          ImGui.PopStyleColor(ctx)
          if self.title_font then ImGui.PopFont(ctx) end
        end
      else
        if self.title_font then ImGui.PushFont(ctx, self.title_font, self.title_font_size) end
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
        local display_title = self:_truncate_text(ctx, self.title, available_width, self.title_font, self.title_font_size)
        ImGui.Text(ctx, display_title)
        ImGui.PopStyleColor(ctx)
        if self.title_font then ImGui.PopFont(ctx) end
      end

      -- Draw branding text in center of titlebar
      if self.branding_text then
        local branding_text = self.branding_text
        local branding_font = self.branding_font or self.title_font
        local branding_font_size = self.branding_font_size or self.title_font_size
        local branding_opacity = self.branding_opacity or 0.15
        local branding_color = self.branding_color or text_color

        -- Calculate text size with proper ImGui 0.10 API
        if branding_font then ImGui.PushFont(ctx, branding_font, branding_font_size) end
        local branding_text_w, branding_text_h = ImGui.CalcTextSize(ctx, branding_text)
        if branding_font then ImGui.PopFont(ctx) end

        local branding_x = (win_w - branding_text_w) * 0.5
        local branding_y = (self.height - branding_text_h) * 0.5

        -- Render branding text with custom font at configured opacity and color
        if branding_font then ImGui.PushFont(ctx, branding_font, branding_font_size) end
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, branding_opacity)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, branding_color)
        ImGui.SetCursorPos(ctx, branding_x, branding_y)
        ImGui.Text(ctx, branding_text)
        ImGui.PopStyleColor(ctx)
        ImGui.PopStyleVar(ctx)
        if branding_font then ImGui.PopFont(ctx) end
      end

      ImGui.SetCursorPos(ctx, win_w - total_button_width, 0)
      
      if self.button_style == "filled" then
        clicked_maximize, clicked_close = self:_draw_buttons_filled(ctx)
      else
        clicked_maximize, clicked_close = self:_draw_buttons_minimal(ctx, bg_color)
      end
    end
    
    ImGui.EndChild(ctx)
    ImGui.PopStyleColor(ctx)
    ImGui.PopStyleVar(ctx, 2)
    
    if self.separator then
      ImGui.Separator(ctx)
    end
    
    if (icon_clicked or icon_shift_clicked) and self.on_icon_click then
      self.on_icon_click(icon_shift_clicked)
    end
    
    if clicked_maximize and self.on_maximize then
      self.on_maximize()
    end
    
    if clicked_close then
      if self.on_close then
        self.on_close()
        return true
      else
        return false
      end
    end
    
    return true
  end

  function titlebar:_draw_button_icon(ctx, min_x, min_y, max_x, max_y, icon_type, color, button_bg_color)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local dpi = ImGui.GetWindowDpiScale(ctx)
    local thickness = math.max(1, math.floor(1.0 * dpi))

    local h = max_y - min_y
    local w = max_x - min_x
    
    local v_padding = math.floor(h * 0.35)
    local iy1 = min_y + v_padding
    local iy2 = max_y - v_padding

    local icon_h = iy2 - iy1
    
    local square_size = icon_h
    if square_size % 2 == 1 then
        square_size = square_size - 1
    end
    
    local center_x = min_x + (w / 2)
    local half_size = square_size / 2
    local ix1 = math.floor(center_x - half_size)
    local ix2 = ix1 + square_size

    if icon_type == 'maximize' then
        ImGui.DrawList_AddRect(draw_list, ix1, iy1, ix2, iy2, color, 0, 0, thickness)

    elseif icon_type == 'restore' then
        local small_offset = math.floor((ix2 - ix1) * 0.25)
        local bx1, by1 = ix1 + small_offset, iy1
        local bx2, by2 = ix2, iy2 - small_offset
        ImGui.DrawList_AddRect(draw_list, bx1, by1, bx2, by2, color, 0, 0, thickness)
        
        local fx1, fy1 = ix1, iy1 + small_offset
        local fx2, fy2 = ix2 - small_offset, iy2
        ImGui.DrawList_AddRectFilled(draw_list, fx1, fy1, fx2, fy2, button_bg_color)
        ImGui.DrawList_AddRect(draw_list, fx1, fy1, fx2, fy2, color, 0, 0, thickness)

    elseif icon_type == 'close' then
        ImGui.DrawList_AddLine(draw_list, ix1, iy1, ix2, iy2, color, thickness)
        ImGui.DrawList_AddLine(draw_list, ix1, iy2, ix2, iy1, color, thickness)
    end
  end

  function titlebar:_draw_buttons_minimal(ctx, bg_color)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)

    local clicked_maximize = false
    local clicked_close = false
    local icon_color = ImGui.GetColor(ctx, ImGui.Col_Text)

    if self.enable_maximize then
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, Constants.TITLEBAR.button_maximize_normal)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, Constants.TITLEBAR.button_maximize_hovered)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, Constants.TITLEBAR.button_maximize_active)

      if ImGui.Button(ctx, "##max", self.button_width, self.height) then
        clicked_maximize = true
      end
      
      local is_hovered = ImGui.IsItemHovered(ctx)
      local is_active = ImGui.IsItemActive(ctx)
      
      local current_button_bg
      if is_active then
        current_button_bg = Constants.TITLEBAR.button_maximize_active
      elseif is_hovered then
        current_button_bg = Constants.TITLEBAR.button_maximize_hovered
      else
        current_button_bg = bg_color
      end
      
      local min_x, min_y = ImGui.GetItemRectMin(ctx)
      local max_x, max_y = ImGui.GetItemRectMax(ctx)
      local icon_type = self.is_maximized and "restore" or "maximize"
      self:_draw_button_icon(ctx, min_x, min_y, max_x, max_y, icon_type, icon_color, current_button_bg)

      ImGui.PopStyleColor(ctx, 3)

      if is_hovered then
        ImGui.SetTooltip(ctx, self.is_maximized and "Restore" or "Maximize")
      end

      ImGui.SameLine(ctx)
    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Button, Constants.TITLEBAR.button_close_normal)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, Constants.TITLEBAR.button_close_hovered)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, Constants.TITLEBAR.button_close_active)

    if ImGui.Button(ctx, "##close", self.button_width, self.height) then
      clicked_close = true
    end

    local is_hovered = ImGui.IsItemHovered(ctx)
    local is_active = ImGui.IsItemActive(ctx)

    local current_button_bg
    if is_active then
      current_button_bg = Constants.TITLEBAR.button_close_active
    elseif is_hovered then
      current_button_bg = Constants.TITLEBAR.button_close_hovered
    else
      current_button_bg = bg_color
    end

    local min_x, min_y = ImGui.GetItemRectMin(ctx)
    local max_x, max_y = ImGui.GetItemRectMax(ctx)
    self:_draw_button_icon(ctx, min_x, min_y, max_x, max_y, "close", icon_color, current_button_bg)
    
    ImGui.PopStyleColor(ctx, 3)
    ImGui.PopStyleVar(ctx, 3)

    if is_hovered then
      ImGui.SetTooltip(ctx, "Close")
    end

    return clicked_maximize, clicked_close
  end

  function titlebar:_draw_buttons_filled(ctx)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)
    
    local clicked_maximize = false
    local clicked_close = false
    
    if self.enable_maximize then
      local icon = self.is_maximized and "⊡" or "▢"

      ImGui.PushStyleColor(ctx, ImGui.Col_Button, Constants.TITLEBAR.button_maximize_filled_normal)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, Constants.TITLEBAR.button_maximize_filled_hovered)
      ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, Constants.TITLEBAR.button_maximize_filled_active)
      
      if ImGui.Button(ctx, icon .. "##max", self.button_width, self.height) then
        clicked_maximize = true
      end
      
      ImGui.PopStyleColor(ctx, 3)
      
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, self.is_maximized and "Restore" or "Maximize")
      end
      
      ImGui.SameLine(ctx)
    end
    
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, Constants.TITLEBAR.button_close_filled_normal)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, Constants.TITLEBAR.button_close_filled_hovered)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, Constants.TITLEBAR.button_close_filled_active)
    
    if ImGui.Button(ctx, "X##close", self.button_width, self.height) then
      clicked_close = true
    end
    
    ImGui.PopStyleColor(ctx, 3)
    ImGui.PopStyleVar(ctx, 3)
    
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Close")
    end
    
    return clicked_maximize, clicked_close
  end
  
  return titlebar
end

return M
