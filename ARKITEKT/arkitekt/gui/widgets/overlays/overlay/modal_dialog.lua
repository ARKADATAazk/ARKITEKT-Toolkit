-- @noindex
-- ReArkitekt/gui/widgets/overlay/modal_dialog.lua
-- Unified modal dialog system using overlay system like overflow modal

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Sheet = require('arkitekt.gui.widgets.overlays.overlay.sheet')
local Button = require('arkitekt.gui.widgets.primitives.button')
local Style = require('arkitekt.gui.style.defaults')
local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

-- Default modal configuration
local DEFAULTS = {
  width = 0.45,          -- Percentage of window width
  height = 0.25,         -- Percentage of window height

  -- Modal box styling (square, no gradients, double borders)
  bg_color = hexrgb("#1A1A1AFF"),         -- Dark background
  border_outer = hexrgb("#000000DD"),     -- Black outer border
  border_inner = hexrgb("#404040FF"),     -- Gray inner border

  -- Title styling
  title_bg = hexrgb("#1E1E1EFF"),         -- Title bar background
  title_text = hexrgb("#CCCCCCFF"),       -- Title text color
  title_height = 32,                      -- Title bar height

  -- Content padding
  padding_x = 16,
  padding_y = 12,

  -- Button area
  button_area_height = 50,
  button_width = 120,
  button_spacing = 10,
}

-- Helper: Draw simple square modal box content
local function draw_modal_content(ctx, dl, x, y, width, height, title, content_fn)
  -- Draw title bar if title provided
  local title_offset = 0
  if title and title ~= "" then
    title_offset = DEFAULTS.title_height

    ImGui.DrawList_AddRectFilled(
      dl, x, y, x + width, y + DEFAULTS.title_height,
      DEFAULTS.title_bg, 0
    )

    -- Draw title separator line
    ImGui.DrawList_AddLine(
      dl, x, y + DEFAULTS.title_height,
      x + width, y + DEFAULTS.title_height,
      DEFAULTS.border_inner, 1
    )

    -- Draw title text
    local title_x = x + DEFAULTS.padding_x
    local title_y = y + (DEFAULTS.title_height - ImGui.GetTextLineHeight(ctx)) * 0.5
    ImGui.DrawList_AddText(dl, title_x, title_y, DEFAULTS.title_text, title)
  end

  -- Draw content
  if content_fn then
    content_fn(ctx, dl, x, y + title_offset, width, height - title_offset)
  end
end

-- Helper: Draw text input field
local function draw_text_input(ctx, x, y, width, height, unique_id, text, placeholder)
  local bg_color = Style.SEARCH_INPUT_COLORS.bg
  local border_inner = Style.SEARCH_INPUT_COLORS.border_inner
  local border_outer = Style.SEARCH_INPUT_COLORS.border_outer

  local dl = ImGui.GetWindowDrawList(ctx)

  -- Background
  ImGui.DrawList_AddRectFilled(dl, x, y, x + width, y + height, bg_color, 0)

  -- Inner border
  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + width - 1, y + height - 1, border_inner, 0, 0, 1)

  -- Outer border
  ImGui.DrawList_AddRect(dl, x, y, x + width, y + height, border_outer, 0, 0, 1)

  -- Draw input field
  ImGui.SetCursorScreenPos(ctx, x + 8, y + (height - ImGui.GetTextLineHeight(ctx)) * 0.5 - 2)
  ImGui.PushItemWidth(ctx, width - 16)

  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, Style.SEARCH_INPUT_COLORS.text)

  local changed, new_text = ImGui.InputTextWithHint(
    ctx,
    "##" .. unique_id,
    placeholder or "",
    text,
    ImGui.InputTextFlags_None
  )

  local is_focused = ImGui.IsItemActive(ctx)

  ImGui.PopStyleColor(ctx, 5)
  ImGui.PopItemWidth(ctx)

  return changed, new_text, is_focused
end

-- ============================================================================
-- MESSAGE DIALOG
-- ============================================================================

-- Track modal state
local message_modal_open = {}

function M.show_message(ctx, window, title, message, opts)
  opts = opts or {}
  local id = opts.id or "##message_dialog"
  local button_label = opts.button_label or "OK"
  local on_close = opts.on_close

  if not window or not window.overlay then
    return false
  end

  if not message_modal_open[id] then
    message_modal_open[id] = true

    window.overlay:push({
      id = id,
      close_on_scrim = true,
      esc_to_close = true,
      on_close = function()
        message_modal_open[id] = nil
        if on_close then on_close() end
      end,
      render = function(ctx, alpha, bounds)
        Sheet.render(ctx, alpha, bounds, function(ctx, w, h, a)
          -- Message text (Sheet now handles padding)
          ImGui.PushTextWrapPos(ctx, w)
          ImGui.Text(ctx, message)
          ImGui.PopTextWrapPos(ctx)

          -- Bottom button
          ImGui.Dummy(ctx, 0, 10)
          ImGui.Separator(ctx)
          ImGui.Dummy(ctx, 0, 8)

          local button_w = DEFAULTS.button_width
          local start_x = (w - button_w) * 0.5

          ImGui.SetCursorPosX(ctx, start_x)
          if ImGui.Button(ctx, button_label, button_w, 28) then
            window.overlay:pop(id)
            message_modal_open[id] = nil
            if on_close then on_close() end
          end
        end, {
          title = title,
          width = opts.width or DEFAULTS.width,
          height = opts.height or DEFAULTS.height
        })
      end
    })
  end

  return true
end

-- ============================================================================
-- CONFIRMATION DIALOG
-- ============================================================================

local confirm_modal_open = {}

function M.show_confirm(ctx, window, title, message, opts)
  opts = opts or {}
  local id = opts.id or "##confirm_dialog"
  local confirm_label = opts.confirm_label or "OK"
  local cancel_label = opts.cancel_label or "Cancel"
  local on_confirm = opts.on_confirm
  local on_cancel = opts.on_cancel

  if not window or not window.overlay then
    return false
  end

  if not confirm_modal_open[id] then
    confirm_modal_open[id] = true

    window.overlay:push({
      id = id,
      close_on_scrim = true,
      esc_to_close = true,
      on_close = function()
        confirm_modal_open[id] = nil
        if on_cancel then on_cancel() end
      end,
      render = function(ctx, alpha, bounds)
        Sheet.render(ctx, alpha, bounds, function(ctx, w, h, a)
          -- Message text (Sheet now handles padding)
          ImGui.PushTextWrapPos(ctx, w)
          ImGui.Text(ctx, message)
          ImGui.PopTextWrapPos(ctx)

          -- Bottom buttons
          ImGui.Dummy(ctx, 0, 10)
          ImGui.Separator(ctx)
          ImGui.Dummy(ctx, 0, 8)

          local button_w = DEFAULTS.button_width
          local total_w = button_w * 2 + DEFAULTS.button_spacing
          local start_x = (w - total_w) * 0.5

          ImGui.SetCursorPosX(ctx, start_x)
          if ImGui.Button(ctx, cancel_label, button_w, 28) then
            window.overlay:pop(id)
            confirm_modal_open[id] = nil
            if on_cancel then on_cancel() end
          end

          ImGui.SameLine(ctx, 0, DEFAULTS.button_spacing)
          if ImGui.Button(ctx, confirm_label, button_w, 28) then
            window.overlay:pop(id)
            confirm_modal_open[id] = nil
            if on_confirm then on_confirm() end
          end
        end, {
          title = title,
          width = opts.width or DEFAULTS.width,
          height = opts.height or DEFAULTS.height
        })
      end
    })
  end

  return true
end

-- ============================================================================
-- TEXT INPUT DIALOG
-- ============================================================================

local input_modal_open = {}
local input_state = {}

function M.show_input(ctx, window, title, initial_text, opts)
  opts = opts or {}
  local id = opts.id or "##input_dialog"
  local placeholder = opts.placeholder or ""
  local confirm_label = opts.confirm_label or "OK"
  local cancel_label = opts.cancel_label or "Cancel"
  local on_confirm = opts.on_confirm
  local on_cancel = opts.on_cancel

  if not window or not window.overlay then
    return false
  end

  -- Initialize state
  if not input_state[id] then
    input_state[id] = {
      text = initial_text or "",
      first_frame = true,
    }
  end

  if not input_modal_open[id] then
    input_modal_open[id] = true

    window.overlay:push({
      id = id,
      close_on_scrim = false,  -- Don't close on scrim for input (might lose data)
      esc_to_close = true,
      on_close = function()
        input_modal_open[id] = nil
        input_state[id] = nil
        if on_cancel then on_cancel() end
      end,
      render = function(ctx, alpha, bounds)
        Sheet.render(ctx, alpha, bounds, function(ctx, w, h, a)
          local state = input_state[id]

          if not state then
            return
          end

          -- Input field (Sheet now handles padding)
          ImGui.Dummy(ctx, 0, 4)
          ImGui.SetNextItemWidth(ctx, w)

          ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, Style.SEARCH_INPUT_COLORS.bg)
          ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, Style.SEARCH_INPUT_COLORS.bg_hover)
          ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, Style.SEARCH_INPUT_COLORS.bg_active)
          ImGui.PushStyleColor(ctx, ImGui.Col_Border, Style.SEARCH_INPUT_COLORS.border_outer)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, Style.SEARCH_INPUT_COLORS.text)

          local changed, new_text = ImGui.InputTextWithHint(
            ctx,
            "##" .. id .. "_input",
            placeholder,
            state.text,
            ImGui.InputTextFlags_None
          )

          if changed then
            state.text = new_text
          end

          -- Auto-focus on first frame
          if state.first_frame then
            ImGui.SetKeyboardFocusHere(ctx, -1)
            state.first_frame = false
          end

          ImGui.PopStyleColor(ctx, 5)

          -- Bottom buttons
          ImGui.Dummy(ctx, 0, 10)
          ImGui.Separator(ctx)
          ImGui.Dummy(ctx, 0, 8)

          local button_w = DEFAULTS.button_width
          local total_w = button_w * 2 + DEFAULTS.button_spacing
          local start_x = (w - total_w) * 0.5

          ImGui.SetCursorPosX(ctx, start_x)
          if ImGui.Button(ctx, cancel_label, button_w, 28) then
            window.overlay:pop(id)
            input_modal_open[id] = nil
            input_state[id] = nil
            if on_cancel then on_cancel() end
          end

          ImGui.SameLine(ctx, 0, DEFAULTS.button_spacing)
          if ImGui.Button(ctx, confirm_label, button_w, 28) then
            if state.text and state.text ~= "" then
              local result = state.text
              window.overlay:pop(id)
              input_modal_open[id] = nil
              input_state[id] = nil
              if on_confirm then on_confirm(result) end
            end
          end
        end, {
          title = title,
          width = opts.width or DEFAULTS.width,
          height = opts.height or 0.3
        })
      end
    })
  end

  return true
end

return M
