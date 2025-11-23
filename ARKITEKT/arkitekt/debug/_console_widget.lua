-- @noindex
-- arkitekt/debug/_console_widget.lua
-- Console widget implementation with ColoredTextView

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Logger = require('arkitekt.debug.logger')
local Panel = require('arkitekt.gui.widgets.containers.panel')
local Config = require('arkitekt.gui.widgets.containers.panel.defaults')
local ColoredTextView = require('arkitekt.gui.widgets.text.colored_text_view')
local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb


local M = {}

local function hexrgb(hex)
  if hex:sub(1, 1) == "#" then hex = hex:sub(2) end
  local h = tonumber(hex, 16)
  if not h then return Colors.hexrgb("#FFFFFF") end
  return (#hex == 8) and h or ((h << 8) | 0xFF)
end

local COLORS = {
  teal = hexrgb("#41E0A3FF"),
  red = hexrgb("#E04141FF"),
  yellow = hexrgb("#E0B341FF"),
  grey_84 = hexrgb("#D6D6D6FF"),
  grey_60 = hexrgb("#999999FF"),
  grey_52 = hexrgb("#858585FF"),
  grey_40 = hexrgb("#666666FF"),
  grey_20 = hexrgb("#333333FF"),
  grey_18 = hexrgb("#2E2E2EFF"),
  grey_14 = hexrgb("#242424FF"),
  grey_10 = hexrgb("#1A1A1AFF"),
  grey_08 = hexrgb("#141414FF"),
}

local CATEGORY_COLORS = {
  ENGINE = COLORS.teal,
  GUI = COLORS.grey_84,
  STATE = hexrgb("#FFD700FF"),
  BRIDGE = COLORS.yellow,
  STORAGE = hexrgb("#CD853FFF"),
  TRANSITIONS = hexrgb("#00CED1FF"),
  TRANSPORT = hexrgb("#4682B4FF"),
  PLAYLIST = hexrgb("#9370DBFF"),
  REGION = hexrgb("#20B2AAFF"),
  COORDINATOR = hexrgb("#FF69B4FF"),
  WIDGET = hexrgb("#87CEEBFF"),
  CONTROLLER = hexrgb("#98FB98FF"),
  QUANTIZE = hexrgb("#DDA0DDFF"),
  PLAYBACK = hexrgb("#F0E68CFF"),
  SEQUENCER = hexrgb("#ADD8E6FF"),
  UNDO = hexrgb("#F5DEB3FF"),
  SYSTEM = COLORS.grey_84,
  CONSOLE = COLORS.grey_60,
}

local LEVEL_COLORS = {
  INFO = COLORS.teal,
  DEBUG = COLORS.grey_60,
  WARN = COLORS.yellow,
  ERROR = COLORS.red,
  PROFILE = COLORS.grey_52,
}

local function get_entry_color(entry)
  if CATEGORY_COLORS[entry.category] then
    return CATEGORY_COLORS[entry.category]
  elseif LEVEL_COLORS[entry.level] then
    return LEVEL_COLORS[entry.level]
  else
    return COLORS.grey_60
  end
end

function M.new(config)
  config = config or {}
  
  local console = {
    filter_category = "All",
    search_text = "",
    paused = false,
    
    last_frame_time = 0,
    fps = 60,
    frame_time_ms = 16.7,
    
    scroll_pos = 0,
    scroll_max = 0,
    user_scrolled_up = false,
    
    panel = nil,
    text_view = ColoredTextView.new(),
    last_entry_count = 0,
  }
  
  local panel_config = {
    bg_color = hexrgb("#0D0D0DFF"),
    border_color = hexrgb("#000000DD"),
    border_thickness = 1,
    rounding = 8,
    padding = 8,
    
    scroll = {
      flags = 0,
      bg_color = hexrgb("#00000000"),
    },
    
    background_pattern = {
      enabled = false,
    },
    
    header = {
      enabled = true,
      height = 30,
      
      elements = {
        {
          id = "clear_btn",
          type = "button",
          spacing_before = 0,
          config = {
            id = "clear",
            label = "Clear",
            width = 50,
            on_click = function()
              Logger.clear()
              console.text_view:set_lines({})
              console.last_entry_count = 0
            end,
          },
        },
        {
          id = "export_btn",
          type = "button",
          spacing_before = 0,
          config = {
            id = "export",
            label = "Export",
            width = 55,
            on_click = function()
              local entries = Logger.get_entries()
              local export_text = ""
              for _, entry in ipairs(entries) do
                local h = math.floor(entry.time / 3600) % 24
                local m = math.floor(entry.time / 60) % 60
                local s = entry.time % 60
                local time_str = string.format("%02d:%02d:%06.3f", h, m, s)
                export_text = export_text .. string.format("[%s] [%s] %s: %s\n",
                  time_str, entry.level, entry.category, entry.message)
              end
              reaper.CF_SetClipboard(export_text)
              Logger.info("CONSOLE", "Exported to clipboard")
            end,
          },
        },
        {
          id = "copy_btn",
          type = "button",
          spacing_before = 0,
          config = {
            id = "copy",
            label = "Copy",
            width = 50,
            on_click = function()
              if console.text_view:copy() then
                Logger.info("CONSOLE", "Selection copied to clipboard")
              else
                Logger.warn("CONSOLE", "No selection to copy")
              end
            end,
          },
        },
        {
          id = "sep1",
          type = "separator",
          width = 12,
          spacing_before = 0,
        },
        {
          id = "filter",
          type = "dropdown_field",
          width = 90,
          spacing_before = 0,
          config = {
            options = {
              { value = "All", label = "All" },
              { value = "INFO", label = "INFO" },
              { value = "DEBUG", label = "DEBUG" },
              { value = "WARN", label = "WARN" },
              { value = "ERROR", label = "ERROR" },
              { value = "PROFILE", label = "PROFILE" },
            },
            on_change = function(value)
              console.filter_category = value
              console:update_text_view()
            end,
          },
        },
        {
          id = "search",
          type = "search_field",
          width = 180,
          spacing_before = 0,
          config = {
            placeholder = "Search...",
            on_change = function(text)
              console.search_text = text
              console:update_text_view()
            end,
          },
        },
        {
          id = "spacer",
          type = "separator",
          flex = 1,
          spacing_before = 0,
        },
        {
          id = "pause_btn",
          type = "button",
          spacing_before = 0,
          config = {
            id = "pause",
            label = "Pause",
            width = 52,
            on_click = function()
              console.paused = not console.paused
            end,
            custom_draw = function(ctx, dl, x, y, width, height, is_hovered, is_active, text_color)
              local label = console.paused and "Resume" or "Pause"
              local text_w = ImGui.CalcTextSize(ctx, label)
              local text_x = x + (width - text_w) * 0.5
              local text_y = y + (height - ImGui.GetTextLineHeight(ctx)) * 0.5
              
              local indicator_x = x + 8
              local indicator_y = y + height * 0.5
              local indicator_color = console.paused and COLORS.yellow or COLORS.teal
              ImGui.DrawList_AddCircleFilled(dl, indicator_x, indicator_y, 3, indicator_color)
              
              ImGui.DrawList_AddText(dl, text_x + 8, text_y, text_color, label)
            end,
          },
        },
      },
    },
  }
  
  console.panel = Panel.new({
    id = "debug_console_panel",
    config = panel_config,
  })
  
  -- Convert log entries to colored text view format (without icons)
  function console:update_text_view()
    local entries = Logger.get_entries()
    local lines = {}
    
    for _, entry in ipairs(entries) do
      -- Apply filters
      local show = true
      if self.filter_category ~= "All" and entry.level ~= self.filter_category then
        show = false
      end
      if self.search_text ~= "" then
        local search_lower = self.search_text:lower()
        local text = (entry.message .. entry.category):lower()
        if not text:find(search_lower, 1, true) then
          show = false
        end
      end
      
      if show then
        local color = get_entry_color(entry)
        
        local msg_str = entry.message
        if entry.data then
          msg_str = msg_str .. " {...}"
        end
        
        -- Create line with colored segments (no icons)
        table.insert(lines, {
          segments = {
            {text = msg_str, color = color}
          }
        })
      end
    end
    
    self.text_view:set_lines(lines)
  end
  
  function console:update()
    local current_time = reaper.time_precise()
    if self.last_frame_time > 0 then
      local delta = current_time - self.last_frame_time
      self.frame_time_ms = delta * 1000
      self.fps = math.floor(1.0 / delta + 0.5)
    end
    self.last_frame_time = current_time
    
    -- Update text view if logs changed
    local current_count = Logger.get_count()
    if not self.paused and current_count ~= self.last_entry_count then
      self:update_text_view()
      self.last_entry_count = current_count
    end
  end
  
  local function draw_stats_overlay(ctx, w, h)
    local dl = ImGui.GetWindowDrawList(ctx)
    local sx, sy = ImGui.GetCursorScreenPos(ctx)
    
    -- Stats panel in top right
    local stats_w = 200
    local stats_h = 60
    local padding = 12
    local stats_x = sx + w - stats_w - padding
    local stats_y = sy + padding
    
    -- Background with slight transparency
    local bg_color = hexrgb("#1A1A1AE6")
    local border_color = hexrgb("#333333FF")
    ImGui.DrawList_AddRectFilled(dl, stats_x, stats_y, stats_x + stats_w, stats_y + stats_h, bg_color, 6, 0)
    ImGui.DrawList_AddRect(dl, stats_x, stats_y, stats_x + stats_w, stats_y + stats_h, border_color, 6, 0, 1.0)
    
    -- FPS
    local fps_str = string.format("FPS: %d", console.fps)
    local fps_color = console.fps >= 60 and COLORS.teal or (console.fps >= 30 and COLORS.yellow or COLORS.red)
    ImGui.DrawList_AddText(dl, stats_x + 12, stats_y + 8, fps_color, fps_str)
    
    -- Frame time
    local frame_str = string.format("%.1fms", console.frame_time_ms)
    ImGui.DrawList_AddText(dl, stats_x + 12, stats_y + 26, COLORS.grey_60, frame_str)
    
    -- Log count
    local count_str = string.format("%d / %d logs", Logger.get_count(), Logger.get_max())
    ImGui.DrawList_AddText(dl, stats_x + 12, stats_y + 44, COLORS.grey_60, count_str)
  end
  
  function console:render(ctx)
    self:update()
    
    local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
    
    if self.panel:begin_draw(ctx) then
      self.text_view:render(ctx, avail_w, avail_h)
    end
    self.panel:end_draw(ctx)
    
    -- Draw stats overlay in top right
    draw_stats_overlay(ctx, avail_w, avail_h)
  end
  
  -- Initialize with current logs
  console:update_text_view()
  
  return console
end

return M
