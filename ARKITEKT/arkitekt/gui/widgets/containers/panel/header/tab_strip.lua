-- @noindex
-- Arkitekt/gui/widgets/panel/header/tab_strip.lua
-- Clean, modular tab strip with improved animation control

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local ContextMenu = require('arkitekt.gui.widgets.overlays.context_menu')
local Chip = require('arkitekt.gui.widgets.data.chip')
local Style = require('arkitekt.gui.style')
local InteractionBlocking = require('arkitekt.gui.utils.interaction_blocking')

local Colors = require('arkitekt.core.colors')
local ColorPickerMenu = require('arkitekt.gui.widgets.menus.color_picker_menu')

local hexrgb = Colors.hexrgb

local M = {}

local TAB_SLIDE_SPEED = 15.0
local DRAG_THRESHOLD = 3.0

-- Dynamic color lookup function for theme reactivity
-- Called each frame to get fresh colors from Style.COLORS
local function get_tab_colors()
  local C = Style.COLORS
  return {
    bg_color = C.BG_BASE,
    bg_hover_color = C.BG_HOVER,
    bg_active_color = C.BG_ACTIVE,
    border_outer_color = C.BORDER_OUTER,
    border_inner_color = C.BORDER_INNER,
    border_hover_color = C.BORDER_HOVER,
    border_active_color = C.BORDER_FOCUS,
    text_color = C.TEXT_DIMMED,
    text_hover_color = C.TEXT_HOVER,
    text_active_color = C.TEXT_ACTIVE,
  }
end

local function get_corner_flags(corner_rounding)
  if not corner_rounding then
    return 0
  end
  
  local flags = 0
  if corner_rounding.round_top_left then
    flags = flags | ImGui.DrawFlags_RoundCornersTopLeft
  end
  if corner_rounding.round_top_right then
    flags = flags | ImGui.DrawFlags_RoundCornersTopRight
  end
  
  return flags
end

local function calculate_tab_width(ctx, label, config, has_chip)
  local text_w = ImGui.CalcTextSize(ctx, label)
  local chip_width = has_chip and 20 or 0
  local min_width = config.min_width or 50  -- Reduced from 60 to 50
  local max_width = config.max_width or 180
  local padding_x = config.padding_x or 5

  local ideal_width = text_w + padding_x * 2 + chip_width
  return math.min(max_width, math.max(min_width, ideal_width))
end

local function calculate_responsive_tab_widths(ctx, tabs, config, available_width, should_extend)
  local min_width = config.min_width or 50  -- Soft minimum (only for very small text)
  local max_width = config.max_width or 180
  local padding_x = config.padding_x or 5
  local spacing = config.spacing or 0

  if #tabs == 0 then return {} end

  -- Calculate natural/ideal widths for all tabs
  local natural_widths = {}
  local min_text_widths = {}  -- Minimum width needed to show text without truncation
  local total_natural = 0
  local total_spacing = 0

  for i, tab in ipairs(tabs) do
    local has_chip = tab.chip_color ~= nil
    local text_w = ImGui.CalcTextSize(ctx, tab.label or "Tab")

    -- Calculate width based on actual rendering:
    -- Left: padding_x - 3 (text offset)
    -- Right: 6 (comfortable margin to inner border)
    -- Chip: 12 actual space (not 20)
    local left_margin = math.max(0, padding_x - 3)
    local right_margin = 6
    local actual_chip_space = has_chip and 12 or 0
    local actual_text_width = math.floor(text_w + left_margin + right_margin + actual_chip_space + 0.5)

    -- Apply very small floor (20px) to prevent microscopic tabs
    min_text_widths[i] = math.max(20, actual_text_width)

    -- Natural width: use actual text width, cap at max only
    local natural = min_text_widths[i]
    natural = math.min(max_width, natural)  -- Hard cap at max
    natural = math.floor(natural + 0.5)     -- Round to whole pixels

    natural_widths[i] = natural
    total_natural = total_natural + natural

    if i < #tabs then
      local effective_spacing = (spacing == 0 and -1 or spacing)
      total_spacing = total_spacing + effective_spacing
    end
  end

  local total_with_spacing = total_natural + total_spacing

  -- STAGE 1: Always expand tabs with clipped text (independent of should_extend)
  if total_with_spacing < available_width then
    local extra_space = available_width - total_with_spacing

    -- Identify which tabs have clipped text (actual text exceeds current width)
    local clipped_tabs = {}
    local total_deficit = 0
    for i, tab in ipairs(tabs) do
      -- Check if this tab's text was clamped by max_width
      if min_text_widths[i] > natural_widths[i] then
        local deficit = math.min(min_text_widths[i] - natural_widths[i], extra_space)
        clipped_tabs[i] = deficit
        total_deficit = total_deficit + deficit
      end
    end

    -- Distribute extra space only to clipped tabs, proportionally
    if total_deficit > 0 and next(clipped_tabs) then
      local space_to_distribute = math.min(extra_space, total_deficit)

      for i, deficit in pairs(clipped_tabs) do
        local proportion = deficit / total_deficit
        local extra = math.floor(space_to_distribute * proportion + 0.5)
        -- Allow exceeding max_width to show full text
        natural_widths[i] = natural_widths[i] + extra
      end

      -- Recalculate total after expanding clipped tabs
      total_with_spacing = 0
      for i = 1, #tabs do
        total_with_spacing = total_with_spacing + natural_widths[i]
        if i < #tabs then
          local effective_spacing = (spacing == 0 and -1 or spacing)
          total_with_spacing = total_with_spacing + effective_spacing
        end
      end
    end
  end

  -- STAGE 2: If should_extend (80% threshold), distribute remaining space evenly to all tabs
  if should_extend and total_with_spacing < available_width then
    local extra_space = available_width - total_with_spacing
    local base_per_tab = math.floor(extra_space / #tabs)
    local remainder = extra_space - (base_per_tab * #tabs)

    for i = 1, #tabs do
      natural_widths[i] = natural_widths[i] + base_per_tab
      -- Distribute remainder pixels to first N tabs (ensures exact fill)
      if i <= remainder then
        natural_widths[i] = natural_widths[i] + 1
      end
    end
  end

  return natural_widths, min_text_widths
end

local function init_tab_positions(state, tabs, start_x, ctx, config, available_width, should_extend)
  if not state.tab_positions then
    state.tab_positions = {}
  end

  if not state.tab_animation_enabled then
    state.tab_animation_enabled = {}
  end

  -- Use cached widths if available, otherwise calculate
  local tab_widths
  if state._cached_tab_widths then
    tab_widths = state._cached_tab_widths
  else
    tab_widths, _ = calculate_responsive_tab_widths(ctx, tabs, config, available_width, should_extend)
  end

  local cursor_x = start_x
  local spacing = config.spacing or 0

  for i, tab in ipairs(tabs) do
    if not state.tab_positions[tab.id] then
      local tab_width = tab_widths[i] or calculate_tab_width(ctx, tab.label or "Tab", config, tab.chip_color ~= nil)

      state.tab_positions[tab.id] = {
        current_x = cursor_x,
        target_x = cursor_x,
      }

      state.tab_animation_enabled[tab.id] = false

      local effective_spacing = spacing
      if i < #tabs and spacing == 0 then
        effective_spacing = -1
      end

      cursor_x = cursor_x + tab_width + effective_spacing
    end
  end
end

local function update_tab_positions(ctx, state, config, tabs, start_x, available_width, should_extend)
  local spacing = config.spacing or 0
  local dt = ImGui.GetDeltaTime(ctx)
  local cursor_x = start_x

  -- Use cached widths if available, otherwise calculate
  local tab_widths
  if state._cached_tab_widths then
    tab_widths = state._cached_tab_widths
  else
    tab_widths, _ = calculate_responsive_tab_widths(ctx, tabs, config, available_width, should_extend)
  end

  -- First pass: calculate all new targets and detect if this is a uniform shift (window move)
  local new_targets = {}
  local deltas = {}
  local is_uniform_shift = true
  local first_delta = nil

  for i, tab in ipairs(tabs) do
    local tab_width = tab_widths[i] or calculate_tab_width(ctx, tab.label or "Tab", config, tab.chip_color ~= nil)
    local pos = state.tab_positions[tab.id]

    if not pos then
      pos = { current_x = cursor_x, target_x = cursor_x }
      state.tab_positions[tab.id] = pos
      state.tab_animation_enabled[tab.id] = false
    end

    new_targets[tab.id] = cursor_x
    local delta = cursor_x - pos.target_x
    deltas[tab.id] = delta

    -- Check if all tabs are shifting by the same amount (window drag)
    if first_delta == nil then
      first_delta = delta
    elseif math.abs(delta - first_delta) > 0.1 then
      is_uniform_shift = false
    end

    local effective_spacing = spacing
    if i < #tabs and spacing == 0 then
      effective_spacing = -1
    end

    cursor_x = cursor_x + tab_width + effective_spacing
  end
  
  -- Second pass: update positions, snap instantly if uniform shift (window move)
  for i, tab in ipairs(tabs) do
    local pos = state.tab_positions[tab.id]
    local new_target = new_targets[tab.id]
    local delta = deltas[tab.id]

    if is_uniform_shift and math.abs(delta) > 0.01 then
      -- Window is being dragged: snap all tabs instantly, no animation
      pos.current_x = new_target
      pos.target_x = new_target
      state.tab_animation_enabled[tab.id] = false
    else
      -- Individual tab repositioning (reorder): use smooth animation
      if math.abs(new_target - pos.target_x) > 0.5 then
        state.tab_animation_enabled[tab.id] = true
      end

      pos.target_x = new_target

      if state.tab_animation_enabled[tab.id] then
        local diff = pos.target_x - pos.current_x
        if math.abs(diff) > 0.5 then
          local move = diff * TAB_SLIDE_SPEED * dt
          pos.current_x = pos.current_x + move
        else
          pos.current_x = pos.target_x
          state.tab_animation_enabled[tab.id] = false
        end
      else
        pos.current_x = pos.target_x
      end
    end
  end
end

local function enable_animation_for_affected_tabs(state, tabs, affected_index)
  if not state.tab_animation_enabled then
    state.tab_animation_enabled = {}
  end
  
  for i = affected_index, #tabs do
    local tab = tabs[i]
    if tab then
      state.tab_animation_enabled[tab.id] = true
    end
  end
end

local function draw_plus_button(ctx, dl, x, y, width, height, config, unique_id, corner_rounding)
  local btn_cfg = config.plus_button or {}

  -- Apply dynamic colors from theme
  for k, v in pairs(get_tab_colors()) do
    if btn_cfg[k] == nil then btn_cfg[k] = v end
  end
  
  local is_hovered = InteractionBlocking.is_mouse_hovering_rect_unblocked(ctx, x, y, x + width, y + height)
  local is_active = ImGui.IsMouseDown(ctx, 0) and is_hovered

  local bg_color = btn_cfg.bg_color
  local border_inner = btn_cfg.border_inner_color
  local icon_color = btn_cfg.text_color

  if is_active then
    bg_color = btn_cfg.bg_active_color
    border_inner = btn_cfg.border_active_color or btn_cfg.border_hover_color
    icon_color = btn_cfg.text_active_color or btn_cfg.text_hover_color
  elseif is_hovered then
    bg_color = btn_cfg.bg_hover_color
    border_inner = btn_cfg.border_hover_color
    icon_color = btn_cfg.text_hover_color
  end

  local rounding = corner_rounding and corner_rounding.rounding or 4
  local inner_rounding = math.max(0, rounding - 2)
  local corner_flags = get_corner_flags(corner_rounding)
  
  ImGui.DrawList_AddRectFilled(dl, x, y, x + width, y + height, bg_color, inner_rounding, corner_flags)
  
  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + width - 1, y + height - 1, border_inner, inner_rounding, corner_flags, 1)
  
  ImGui.DrawList_AddRect(dl, x, y, x + width, y + height, btn_cfg.border_outer_color or config.border_outer_color, inner_rounding, corner_flags, 1)

  local center_x = x + width * 0.5
  local center_y = y + height * 0.5  -- Lowered by 1px (removed -1)
  local cross_size = 7
  local cross_thickness = 1
  
  ImGui.DrawList_AddRectFilled(dl, 
    center_x - cross_size * 0.5, center_y - cross_thickness * 0.5,
    center_x + cross_size * 0.5, center_y + cross_thickness * 0.5,
    icon_color)
  
  ImGui.DrawList_AddRectFilled(dl,
    center_x - cross_thickness * 0.5, center_y - cross_size * 0.5,
    center_x + cross_thickness * 0.5, center_y + cross_size * 0.5,
    icon_color)

  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, "##plus_" .. unique_id, width, height)

  return clicked, width
end

local function draw_overflow_button(ctx, dl, x, y, width, height, config, hidden_count, unique_id, corner_rounding)
  local btn_cfg = config.overflow_button or {}

  -- Apply dynamic colors from theme
  for k, v in pairs(get_tab_colors()) do
    if btn_cfg[k] == nil then btn_cfg[k] = v end
  end

  -- Use vertical ellipsis (⋮) when no overflow, count when overflow exists
  local display_text = (hidden_count > 0) and tostring(hidden_count) or "⋮"

  local is_hovered = InteractionBlocking.is_mouse_hovering_rect_unblocked(ctx, x, y, x + width, y + height)
  local is_active = ImGui.IsMouseDown(ctx, 0) and is_hovered

  local bg_color = btn_cfg.bg_color
  local border_inner = btn_cfg.border_inner_color
  local text_color = btn_cfg.text_color

  if is_active then
    bg_color = btn_cfg.bg_active_color
    border_inner = btn_cfg.border_active_color or btn_cfg.border_hover_color
    text_color = btn_cfg.text_active_color or btn_cfg.text_hover_color
  elseif is_hovered then
    bg_color = btn_cfg.bg_hover_color
    border_inner = btn_cfg.border_hover_color
    text_color = btn_cfg.text_hover_color
  end

  local rounding = corner_rounding and corner_rounding.rounding or 4
  local inner_rounding = math.max(0, rounding - 2)
  local corner_flags = get_corner_flags(corner_rounding)

  ImGui.DrawList_AddRectFilled(dl, x, y, x + width, y + height, bg_color, inner_rounding, corner_flags)

  ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + width - 1, y + height - 1, border_inner, inner_rounding, corner_flags, 1)

  ImGui.DrawList_AddRect(dl, x, y, x + width, y + height, btn_cfg.border_outer_color or config.border_outer_color, inner_rounding, corner_flags, 1)

  local text_w = ImGui.CalcTextSize(ctx, display_text)
  local text_x = x + (width - text_w) * 0.5
  local text_y = y + (height - ImGui.GetTextLineHeight(ctx)) * 0.5
  ImGui.DrawList_AddText(dl, text_x, text_y, text_color, display_text)

  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicked = ImGui.InvisibleButton(ctx, "##overflow_" .. unique_id, width, height)

  return clicked
end

local function draw_track(ctx, dl, x, y, width, height, config, corner_rounding)
  local track_cfg = config.track
  if not track_cfg or not track_cfg.enabled then return end
  
  local track_x = x - track_cfg.extend_left
  local track_y = y - track_cfg.extend_top
  local track_width = width + track_cfg.extend_left + track_cfg.extend_right
  local track_height = height + track_cfg.extend_top + track_cfg.extend_bottom
  
  local rounding = corner_rounding and corner_rounding.rounding or (track_cfg.rounding or 6)
  local corner_flags = get_corner_flags(corner_rounding)
  
  -- Dynamic colors from Style.COLORS for theme reactivity
  ImGui.DrawList_AddRectFilled(
    dl,
    track_x, track_y,
    track_x + track_width, track_y + track_height,
    track_cfg.bg_color or Style.COLORS.BG_PANEL,
    rounding,
    corner_flags
  )

  if track_cfg.border_thickness and track_cfg.border_thickness > 0 then
    ImGui.DrawList_AddRect(
      dl,
      track_x, track_y,
      track_x + track_width, track_y + track_height,
      track_cfg.border_color or Style.COLORS.BORDER_OUTER,
      rounding,
      corner_flags,
      track_cfg.border_thickness
    )
  end
end

-- Check if currently editing a tab inline
local function is_editing_inline(state)
  return state.editing_state and state.editing_state.active
end

-- Start inline editing for a tab
local function start_inline_edit(state, id, initial_text)
  state.editing_state = {
    active = true,
    id = id,
    text = initial_text or "",
    focus_next_frame = true,
    frames_active = 0,
  }
end

-- Stop inline editing (commit or cancel)
local function stop_inline_edit(state, commit, config)
  if not state.editing_state or not state.editing_state.active then return end

  local id = state.editing_state.id
  local new_text = state.editing_state.text

  state.editing_state = nil

  if commit and config.on_tab_rename then
    config.on_tab_rename(id, new_text)
  end
end

-- Handle inline editing input for tabs
local function handle_inline_edit_input(ctx, dl, state, id, x, y, width, height, chip_color)
  if not state.editing_state or state.editing_state.id ~= id then
    return false  -- Not editing this tab
  end

  local edit_state = state.editing_state

  -- Increment frame counter
  edit_state.frames_active = (edit_state.frames_active or 0) + 1

  -- Calculate text line dimensions
  local text_height = ImGui.GetTextLineHeight(ctx)

  -- Calculate vertical position (vertically centered)
  local y_pos = y + (height - text_height) / 2

  -- Input field bounds
  local padding_x = 6
  local padding_y = 1
  local input_x1 = x + padding_x
  local input_y1 = y_pos - padding_y
  local input_x2 = x + width - padding_x
  local input_y2 = y_pos + text_height + padding_y

  -- Draw custom backdrop
  local bg_color
  if chip_color then
    -- Create darker version of chip color for backdrop
    bg_color = Colors.adjust_brightness(chip_color, 0.15)
    bg_color = Colors.with_opacity(bg_color, 0.88)
  else
    bg_color = hexrgb("#1A1A1AE0")
  end

  -- Draw backdrop with rounded corners
  ImGui.DrawList_AddRectFilled(dl, input_x1, input_y1, input_x2, input_y2, bg_color, 2, 0)

  -- Position and size the input field
  ImGui.SetCursorScreenPos(ctx, input_x1 + 4, y_pos - 1)
  ImGui.SetNextItemWidth(ctx, input_x2 - input_x1 - 8)

  -- Focus input on first frame
  if edit_state.focus_next_frame then
    ImGui.SetKeyboardFocusHere(ctx)
    edit_state.focus_next_frame = false
  end

  -- Calculate text and selection colors
  local text_color, selection_color
  if chip_color then
    text_color = Colors.adjust_brightness(chip_color, 1.8)
    selection_color = Colors.adjust_brightness(chip_color, 0.8)
    selection_color = Colors.with_opacity(selection_color, 0.67)
  else
    text_color = hexrgb("#FFFFFFDD")
    selection_color = hexrgb("#4444AAAA")
  end

  -- Style the input field to be transparent
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, hexrgb("#00000000"))
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
  ImGui.PushStyleColor(ctx, ImGui.Col_TextSelectedBg, selection_color)

  -- Draw input field
  local changed, new_text = ImGui.InputText(
    ctx,
    "##tab_inline_edit_" .. id,
    edit_state.text,
    ImGui.InputTextFlags_AutoSelectAll
  )

  ImGui.PopStyleColor(ctx, 6)

  if changed then
    edit_state.text = new_text
  end

  -- Track if item is hovered
  local is_item_hovered = ImGui.IsItemHovered(ctx)
  local is_active = ImGui.IsItemActive(ctx)

  -- Check for Enter (commit) or Escape (cancel)
  local enter_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
  local escape_pressed = ImGui.IsKeyPressed(ctx, ImGui.Key_Escape)

  if enter_pressed then
    return true, true  -- editing_active, should_commit
  elseif escape_pressed then
    return true, false  -- editing_active, should_cancel
  elseif ImGui.IsMouseClicked(ctx, 0) and edit_state.frames_active > 2 and not is_item_hovered and not is_active then
    -- Cancel if clicked outside
    return true, false  -- editing_active, should_cancel
  end

  return true, nil  -- Still editing, no action
end

local function draw_tab(ctx, dl, tab_data, is_active, tab_index, x, y, width, height, state, config, unique_id, animator, corner_rounding)
  -- Apply dynamic colors from theme
  for k, v in pairs(get_tab_colors()) do
    if config[k] == nil then config[k] = v end
  end

  local label = tab_data.label or "Tab"
  local id = tab_data.id
  local chip_color = tab_data.chip_color
  local has_chip = chip_color ~= nil
  
  local is_spawning = animator and animator:is_spawning(id)
  local is_destroying = animator and animator:is_destroying(id)
  
  local render_x, render_y, render_w, render_h = x, y, width, height
  local alpha_factor = 1.0
  
  if is_spawning and animator.get_spawn_factor then
    local spawn_factor = animator:get_spawn_factor(id)
    local target_w = width * spawn_factor
    local offset_x = (width - target_w) * 0.5
    render_x = x + offset_x
    render_w = target_w
    alpha_factor = spawn_factor
  elseif is_destroying and animator.get_destroy_factor then
    local destroy_factor = animator:get_destroy_factor(id)
    local scale = 1.0 - destroy_factor
    local new_w = width * scale
    local new_h = height * scale
    local offset_x = (width - new_w) * 0.5
    local offset_y = (height - new_h) * 0.5
    render_x = x + offset_x
    render_y = y + offset_y
    render_w = new_w
    render_h = new_h
    alpha_factor = 1.0 - destroy_factor
  end

  local is_hovered = InteractionBlocking.is_mouse_hovering_rect_unblocked(ctx, render_x, render_y, render_x + render_w, render_y + render_h)
  local is_pressed = ImGui.IsMouseDown(ctx, 0) and is_hovered and not state.dragging_tab

  local apply_alpha = function(color, factor)
    local a = color & 0xFF
    local new_a = math.floor(a * factor)
    return (color & 0xFFFFFF00) | new_a
  end

  local bg_color = config.bg_color
  local border_inner = config.border_inner_color
  local text_color = config.text_color
  
  if is_active then
    bg_color = config.bg_active_color
    border_inner = config.border_active_color
    text_color = config.text_active_color
  elseif is_pressed then
    bg_color = config.bg_active_color
    border_inner = config.border_hover_color
    text_color = config.text_hover_color
  elseif is_hovered then
    bg_color = config.bg_hover_color
    border_inner = config.border_hover_color
    text_color = config.text_hover_color
  end
  
  bg_color = apply_alpha(bg_color, alpha_factor)
  local border_outer = apply_alpha(config.border_outer_color, alpha_factor)
  border_inner = apply_alpha(border_inner, alpha_factor)
  text_color = apply_alpha(text_color, alpha_factor)

  local rounding = corner_rounding and corner_rounding.rounding or 0
  local inner_rounding = math.max(0, rounding - 2)
  local corner_flags = get_corner_flags(corner_rounding)

  ImGui.DrawList_AddRectFilled(dl, render_x, render_y, render_x + render_w, render_y + render_h, 
                                bg_color, inner_rounding, corner_flags)
  
  ImGui.DrawList_AddRect(dl, render_x + 1, render_y + 1, render_x + render_w - 1, render_y + render_h - 1, 
                         border_inner, inner_rounding, corner_flags, 1)
  
  ImGui.DrawList_AddRect(dl, render_x, render_y, render_x + render_w, render_y + render_h, 
                         border_outer, inner_rounding, corner_flags, 1)

  -- Check if currently editing this tab
  local is_being_edited = is_editing_inline(state) and state.editing_state.id == id

  -- Render label and chip OR inline editor
  if is_being_edited then
    -- Handle inline editing input
    local edit_result, edit_action = handle_inline_edit_input(ctx, dl, state, id, render_x, render_y, render_w, render_h, chip_color)

    if edit_action == true then
      -- Commit
      stop_inline_edit(state, true, config)
    elseif edit_action == false then
      -- Cancel
      stop_inline_edit(state, false, config)
    end
  else
    -- Render normal label and chip
    local content_x = render_x + (config.padding_x or 5)

    if has_chip then
      local chip_x = content_x + 2
      local chip_y = render_y + render_h * 0.5

      Chip.draw(ctx, {
        style = Chip.STYLE.INDICATOR,
        color = chip_color,
        draw_list = dl,
        x = chip_x,
        y = chip_y,
        radius = config.chip_radius or 4,
        is_selected = is_active,
        is_hovered = is_hovered,
        show_glow = is_active or is_hovered,
        glow_layers = 2,
        alpha_factor = alpha_factor,
      })

      content_x = content_x + 12
    end

    local text_w, text_h = ImGui.CalcTextSize(ctx, label)
    local text_x = content_x - 3
    local text_y = render_y + (render_h - text_h) * 0.5

    -- Extend text rendering to 2px from edge (inner border)
    local text_max_w = render_x + render_w - text_x - 2
    if text_w > text_max_w then
      ImGui.DrawList_PushClipRect(dl, text_x, render_y,
                                  render_x + render_w - 2, render_y + render_h, true)
      ImGui.DrawList_AddText(dl, text_x, text_y, text_color, label)
      ImGui.DrawList_PopClipRect(dl)
    else
      ImGui.DrawList_AddText(dl, text_x, text_y, text_color, label)
    end
  end

  ImGui.SetCursorScreenPos(ctx, render_x, render_y)
  ImGui.InvisibleButton(ctx, "##tab_" .. id .. "_" .. unique_id, render_w, render_h)

  local clicked = ImGui.IsItemClicked(ctx, 0)
  local double_clicked = ImGui.IsItemClicked(ctx, 0) and ImGui.IsMouseDoubleClicked(ctx, 0)
  local right_clicked = ImGui.IsItemClicked(ctx, 1)

  -- Double-click to start inline editing (if not currently editing)
  if double_clicked and not is_editing_inline(state) then
    start_inline_edit(state, id, label)
    clicked = false  -- Don't trigger tab selection when starting edit
  end

  -- Check for Alt+click to delete
  local alt_held = ImGui.IsKeyDown(ctx, ImGui.Key_LeftAlt) or ImGui.IsKeyDown(ctx, ImGui.Key_RightAlt)

  if ImGui.IsItemActive(ctx) and not state.dragging_tab and not is_being_edited then
    local drag_delta_x, drag_delta_y = ImGui.GetMouseDragDelta(ctx, 0)
    local drag_distance = math.sqrt(drag_delta_x * drag_delta_x + drag_delta_y * drag_delta_y)
    
    if drag_distance > DRAG_THRESHOLD and ImGui.IsMouseDragging(ctx, 0) then
      local mx = ImGui.GetMousePos(ctx)
      state.dragging_tab = {
        id = id,
        index = tab_index,
        offset_x = mx - render_x,
        original_index = tab_index,
      }
    end
  end

  local delete_requested = false

  -- Alt+click to delete
  if clicked and alt_held then
    delete_requested = true
    clicked = false  -- Don't trigger tab selection when deleting
  end

  if right_clicked then
    ImGui.OpenPopup(ctx, "##tab_context_" .. id .. "_" .. unique_id)
  end

  if ContextMenu.begin(ctx, "##tab_context_" .. id .. "_" .. unique_id, config.context_menu) then
    if ContextMenu.item(ctx, "Duplicate Playlist", config.context_menu) then
      if config.on_tab_duplicate then
        config.on_tab_duplicate(id)
      end
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.Separator(ctx)

    if ContextMenu.item(ctx, "Delete Playlist", config.context_menu) then
      delete_requested = true
    end

    -- Color picker using centralized widget
    ColorPickerMenu.render(ctx, {
      current_color = chip_color,
      icon_font = config.icon_font,  -- Pass icon font for selection indicator
      icon_font_size = config.icon_font_size or 12,
      on_select = function(color_int, color_hex, color_name)
        if config.on_tab_color_change then
          config.on_tab_color_change(id, color_int or false)
        end
      end,
    })

    ContextMenu.end_menu(ctx)
  end

  return clicked, delete_requested
end

local function calculate_visible_tabs(ctx, tabs, config, available_width)
  local visible_indices = {}
  local current_width = 0
  local spacing = config.spacing or 0

  for i, tab in ipairs(tabs) do
    local has_chip = tab.chip_color ~= nil
    local tab_width = calculate_tab_width(ctx, tab.label or "Tab", config, has_chip)
    local effective_spacing = (i > 1) and spacing or 0
    if i > 1 and i <= #tabs and spacing == 0 then
      effective_spacing = -1
    end
    local needed = tab_width + effective_spacing

    if current_width + needed <= available_width then
      visible_indices[#visible_indices + 1] = i
      current_width = current_width + needed
    else
      break
    end
  end

  local overflow_count = #tabs - #visible_indices

  return visible_indices, overflow_count, current_width
end

local function handle_drag_reorder(ctx, state, tabs, config, tabs_start_x, available_width, should_extend, overflow_x)
  if not state.dragging_tab then return end
  if not ImGui.IsMouseDragging(ctx, 0) then return end

  local mx = ImGui.GetMousePos(ctx)

  -- Use cached widths if available, otherwise calculate
  local tab_widths
  if state._cached_tab_widths then
    tab_widths = state._cached_tab_widths
  else
    tab_widths, _ = calculate_responsive_tab_widths(ctx, tabs, config, available_width, should_extend)
  end

  local dragged_tab = tabs[state.dragging_tab.index]
  local dragged_width = tab_widths[state.dragging_tab.index] or calculate_tab_width(ctx, dragged_tab.label or "Tab", config, dragged_tab.chip_color ~= nil)
  local spacing = config.spacing or 0

  -- Clamp drag position to stay within bounds
  local unclamped_drag_left = mx - state.dragging_tab.offset_x
  local min_x = tabs_start_x
  local max_x = overflow_x and (overflow_x - dragged_width) or (tabs_start_x + available_width - dragged_width)
  local drag_left = math.max(min_x, math.min(max_x, unclamped_drag_left))
  local drag_right = drag_left + dragged_width

  -- Store clamped position for use in draw loop
  state.dragging_tab.clamped_x = drag_left

  local positions = {}
  local current_x = tabs_start_x

  for i = 1, #tabs do
    local tab = tabs[i]
    local tab_w = tab_widths[i] or calculate_tab_width(ctx, tab.label or "Tab", config, tab.chip_color ~= nil)

    positions[i] = {
      index = i,
      left = current_x,
      center = current_x + tab_w * 0.5,
      right = current_x + tab_w,
      width = tab_w,
    }

    local effective_spacing = spacing
    if i < #tabs and spacing == 0 then
      effective_spacing = -1
    end

    current_x = current_x + tab_w + effective_spacing
  end
  
  local current_index = state.dragging_tab.index
  local target_index = current_index
  
  if current_index > 1 then
    local left_neighbor = positions[current_index - 1]
    if drag_left < left_neighbor.center then
      target_index = current_index - 1
    end
  end
  
  if current_index < #tabs then
    local right_neighbor = positions[current_index + 1]
    if drag_right > right_neighbor.center then
      target_index = current_index + 1
    end
  end
  
  if target_index ~= state.dragging_tab.index then
    local dragged_tab_data = table.remove(tabs, state.dragging_tab.index)
    table.insert(tabs, target_index, dragged_tab_data)
    
    local min_affected = math.min(state.dragging_tab.index, target_index)
    local max_affected = math.max(state.dragging_tab.index, target_index)
    
    for i = min_affected, max_affected do
      if tabs[i] then
        state.tab_animation_enabled[tabs[i].id] = true
      end
    end
    
    state.dragging_tab.index = target_index
  end
end

local function finalize_drag(ctx, state, config, tabs, tabs_start_x, overflow_x, responsive_widths)
  if not state.dragging_tab then return end

  if not ImGui.IsMouseDown(ctx, 0) then
    local mx = ImGui.GetMousePos(ctx)
    if state.tab_positions and state.tab_positions[state.dragging_tab.id] then
      local dragged_tab_w = responsive_widths and responsive_widths[state.dragging_tab.index] or 50
      local unclamped_x = mx - state.dragging_tab.offset_x
      -- Clamp final position between plus button and overflow button
      local min_x = tabs_start_x
      local max_x = overflow_x - dragged_tab_w
      state.tab_positions[state.dragging_tab.id].current_x = math.max(min_x, math.min(max_x, unclamped_x))
    end
    
    if config.on_tab_reorder and state.dragging_tab.original_index ~= state.dragging_tab.index then
      config.on_tab_reorder(state.dragging_tab.original_index, state.dragging_tab.index)
    end
    
    state.dragging_tab = nil
  end
end

function M.draw(ctx, dl, x, y, available_width, height, config, state)
  config = config or {}
  state = state or {}
  
  local element_id = state.id or "tabstrip"
  local unique_id = string.format("%s_%s", tostring(state._panel_id or "unknown"), element_id)
  
  local tabs = state.tabs or {}
  local active_tab_id = state.active_tab_id
  local animator = state.tab_animator
  local corner_rounding = config.corner_rounding
  
  if animator and animator.update then
    animator:update()
  end

  local plus_cfg = config.plus_button or {}
  local plus_width = plus_cfg.width or 23
  local spacing = config.spacing or 0

  local tabs_start_x = x + plus_width
  if spacing > 0 then
    tabs_start_x = tabs_start_x + spacing
  else
    tabs_start_x = tabs_start_x - 1
  end

  -- Calculate available space for tabs (without overflow button initially)
  local tabs_max_width = available_width - plus_width
  if spacing > 0 then
    tabs_max_width = tabs_max_width - spacing
  else
    tabs_max_width = tabs_max_width + 1
  end

  -- Calculate natural tab widths without any constraints (no extension yet)
  local natural_widths, min_text_widths = calculate_responsive_tab_widths(ctx, tabs, config, tabs_max_width, false)

  -- Calculate total natural width of tabs
  local total_tabs_natural = 0
  for i = 1, #tabs do
    total_tabs_natural = total_tabs_natural + natural_widths[i]
    if i < #tabs then
      total_tabs_natural = total_tabs_natural + (spacing == 0 and -1 or spacing)
    end
  end

  -- Determine overflow button width
  local overflow_cfg = config.overflow_button or { min_width = 21, padding_x = 8 }
  local overflow_width = overflow_cfg.min_width or 21

  -- Calculate what percentage of available width the tabs + overflow would use
  local usage_ratio = (total_tabs_natural + overflow_width + (spacing == 0 and -1 or spacing)) / tabs_max_width

  -- Determine overflow button positioning strategy
  -- Push to edge when tabs use >= 75% of available space
  -- This ensures overflow button snaps to corner before creating awkward gaps
  local overflow_at_edge = (usage_ratio >= 0.75)

  local tabs_available_width
  if overflow_at_edge then
    -- Push overflow to edge, give tabs all remaining space with border overlap
    tabs_available_width = tabs_max_width - overflow_width + 1  -- +1 for border overlap with overflow
  else
    -- Natural flow: overflow sits after tabs
    tabs_available_width = tabs_max_width
  end

  -- Calculate widths - only expand when overflow is at edge (crowded state)
  local final_tab_widths, min_text_widths
  if overflow_at_edge then
    final_tab_widths, min_text_widths = calculate_responsive_tab_widths(ctx, tabs, config, tabs_available_width, true)
  else
    final_tab_widths, min_text_widths = calculate_responsive_tab_widths(ctx, tabs, config, tabs_available_width, false)
  end

  -- Calculate visible tabs - always use final_tab_widths (includes Stage 1 expansion)
  local visible_indices, overflow_count, tabs_width
  if final_tab_widths then
    -- Use expanded widths to determine visibility
    visible_indices = {}
    local current_width = 0
    local spacing_val = config.spacing or 0
    local total_buffer = 10  -- Allow up to 10px total buffer space

    for i, tab in ipairs(tabs) do
      local tab_width = final_tab_widths[i]
      local effective_spacing = (i > 1) and spacing_val or 0
      if i > 1 and i <= #tabs and spacing_val == 0 then
        effective_spacing = -1
      end
      local needed = tab_width + effective_spacing

      -- Special case: if this is the ONLY tab (first tab and no others added yet),
      -- always make it fit by constraining to available width
      if i == 1 and #tabs == 1 then
        visible_indices[#visible_indices + 1] = i
        -- Constrain single tab to available width
        local max_single_tab_width = tabs_available_width
        final_tab_widths[i] = math.min(tab_width, max_single_tab_width)
        current_width = final_tab_widths[i]
      -- Allow tabs to fit with buffer space
      elseif current_width + needed <= tabs_available_width + total_buffer then
        visible_indices[#visible_indices + 1] = i
        current_width = current_width + needed
      else
        break
      end
    end

    overflow_count = #tabs - #visible_indices
    tabs_width = current_width

    -- Only re-extend to fill when at 80% threshold (overflow_at_edge)
    if overflow_at_edge then
      if overflow_count > 0 and #visible_indices > 0 then
        -- Not all tabs fit - re-extend only visible tabs to fill space
        local visible_tabs = {}
        for _, idx in ipairs(visible_indices) do
          visible_tabs[#visible_tabs + 1] = tabs[idx]
        end

        -- Re-calculate widths for only visible tabs to fill the entire available width
        local visible_widths, visible_min_widths = calculate_responsive_tab_widths(ctx, visible_tabs, config, tabs_available_width, true)

        -- Verify total and adjust last tab if needed to ensure exact fill
        local verify_total = 0
        for i = 1, #visible_widths do
          verify_total = verify_total + visible_widths[i]
          if i < #visible_widths then
            verify_total = verify_total + (spacing_val == 0 and -1 or spacing_val)
          end
        end

        -- If there's any rounding error, adjust the last visible tab
        local diff = tabs_available_width - verify_total
        if diff ~= 0 and #visible_widths > 0 then
          visible_widths[#visible_widths] = visible_widths[#visible_widths] + diff
        end

        -- Map visible widths back to original tab indices
        local remapped_widths = {}
        for i, idx in ipairs(visible_indices) do
          remapped_widths[idx] = visible_widths[i]
        end
        final_tab_widths = remapped_widths

        tabs_width = tabs_available_width  -- Exact width
      elseif overflow_count == 0 and #visible_indices > 0 then
        -- All tabs fit at 80% threshold - fill to edge exactly
        local verify_total = 0
        for i, idx in ipairs(visible_indices) do
          verify_total = verify_total + final_tab_widths[idx]
          if i < #visible_indices then
            verify_total = verify_total + (spacing_val == 0 and -1 or spacing_val)
          end
        end

        -- Adjust last tab to fill exactly
        local diff = tabs_available_width - verify_total
        if diff ~= 0 and #visible_indices > 0 then
          local last_idx = visible_indices[#visible_indices]
          final_tab_widths[last_idx] = final_tab_widths[last_idx] + diff
        end

        tabs_width = tabs_available_width  -- Exact width
      end
    end
  else
    visible_indices, overflow_count, tabs_width = calculate_visible_tabs(
      ctx, tabs, config, tabs_available_width
    )
  end

  -- Store final adjusted widths in cache for use by position functions
  state._cached_tab_widths = final_tab_widths
  state._cached_should_extend = overflow_at_edge

  init_tab_positions(state, tabs, tabs_start_x, ctx, config, tabs_available_width, overflow_at_edge)

  -- Recalculate overflow button width based on content
  if overflow_count > 0 then
    local count_text = tostring(overflow_count)
    local text_w = ImGui.CalcTextSize(ctx, count_text)
    overflow_width = math.max(overflow_cfg.min_width or 21, text_w + (overflow_cfg.padding_x or 8) * 2)
  end

  -- Calculate total width
  local tabs_total_width
  if overflow_at_edge then
    -- Overflow at edge: total is full available width
    tabs_total_width = tabs_max_width
  else
    -- Natural flow: tabs + overflow
    tabs_total_width = tabs_width + overflow_width
    if spacing > 0 then
      tabs_total_width = tabs_total_width + spacing
    else
      tabs_total_width = tabs_total_width - 1
    end
  end

  if config.track and config.track.enabled then
    local track_start_x = x
    if not config.track.include_plus_button then
      track_start_x = tabs_start_x
    end

    draw_track(ctx, dl, track_start_x, y,
               tabs_start_x - track_start_x + tabs_total_width,
               height, config, corner_rounding)
  end

  local plus_corner = corner_rounding and {
    round_top_left = corner_rounding.round_top_left,
    round_top_right = false,
    rounding = corner_rounding.rounding,
  } or nil

  local plus_clicked, _ = draw_plus_button(ctx, dl, x, y, plus_width, height, config, unique_id, plus_corner)

  if plus_clicked and config.on_tab_create then
    config.on_tab_create()
  end

  -- Calculate responsive widths for drawing (needed for drag clamping)
  local responsive_widths
  if overflow_at_edge and final_tab_widths then
    -- Create a full table with all widths for drawing
    responsive_widths = {}
    for i = 1, #tabs do
      responsive_widths[i] = final_tab_widths[i] or calculate_tab_width(ctx, tabs[i].label or "Tab", config, tabs[i].chip_color ~= nil)
    end
  else
    local widths, min_widths = calculate_responsive_tab_widths(ctx, tabs, config, tabs_available_width, overflow_at_edge)
    responsive_widths = widths
  end

  -- Calculate overflow button position (needed for drag clamping)
  local overflow_x
  if overflow_at_edge then
    -- Position at the right edge (aligned with corner, no offset)
    overflow_x = x + available_width - overflow_width
  else
    -- Position right after tabs (natural flow with border overlap)
    overflow_x = tabs_start_x + tabs_width
    if spacing > 0 then
      overflow_x = overflow_x + spacing
    else
      overflow_x = overflow_x - 1  -- Border overlap
    end
  end

  -- Handle tab dragging (with calculated bounds for clamping)
  handle_drag_reorder(ctx, state, tabs, config, tabs_start_x, tabs_available_width, overflow_at_edge, overflow_x)
  finalize_drag(ctx, state, config, tabs, tabs_start_x, overflow_x, responsive_widths)
  update_tab_positions(ctx, state, config, tabs, tabs_start_x, tabs_available_width, overflow_at_edge)

  local clicked_tab_id = nil
  local id_to_delete = nil

  -- Apply clipping to prevent tabs from overflowing panel bounds
  ImGui.DrawList_PushClipRect(dl, x, y, x + available_width, y + height, true)

  for i, tab_data in ipairs(tabs) do
    local is_visible = false
    local is_last_visible = false
    for idx, vis_idx in ipairs(visible_indices) do
      if vis_idx == i then
        is_visible = true
        is_last_visible = (idx == #visible_indices)
        break
      end
    end

    if is_visible then
      local pos = state.tab_positions[tab_data.id]
      if pos then
        local tab_w = responsive_widths[i] or calculate_tab_width(ctx, tab_data.label or "Tab", config, tab_data.chip_color ~= nil)
        -- Snap to whole pixels for crisp rendering during animation
        local tab_x = math.floor(pos.current_x + 0.5)

        if state.dragging_tab and state.dragging_tab.id == tab_data.id then
          -- Use pre-clamped position from handle_drag_reorder
          if state.dragging_tab.clamped_x then
            tab_x = math.floor(state.dragging_tab.clamped_x + 0.5)
          else
            -- Fallback if clamped_x not set (shouldn't happen)
            local mx = ImGui.GetMousePos(ctx)
            local unclamped_x = mx - state.dragging_tab.offset_x
            local min_x = tabs_start_x
            local max_x = overflow_x - tab_w
            tab_x = math.floor(math.max(min_x, math.min(max_x, unclamped_x)) + 0.5)
          end
        end

        -- Calculate actual render width to ensure border overlap with next tab/overflow
        local render_width = tab_w
        local next_visible_idx = nil
        for j = i + 1, #tabs do
          for _, vis_idx in ipairs(visible_indices) do
            if vis_idx == j then
              next_visible_idx = j
              break
            end
          end
          if next_visible_idx then break end
        end

        -- If there's a next visible tab, extend width to overlap its border
        if next_visible_idx then
          local next_pos = state.tab_positions[tabs[next_visible_idx].id]
          if next_pos then
            local next_x = math.floor(next_pos.current_x + 0.5)
            if state.dragging_tab and state.dragging_tab.id == tabs[next_visible_idx].id then
              -- Use pre-clamped position from handle_drag_reorder
              if state.dragging_tab.clamped_x then
                next_x = math.floor(state.dragging_tab.clamped_x + 0.5)
              else
                -- Fallback if clamped_x not set (shouldn't happen)
                local mx = ImGui.GetMousePos(ctx)
                local next_tab_w = responsive_widths[next_visible_idx] or calculate_tab_width(ctx, tabs[next_visible_idx].label or "Tab", config, tabs[next_visible_idx].chip_color ~= nil)
                local unclamped_x = mx - state.dragging_tab.offset_x
                local min_x = tabs_start_x
                local max_x = overflow_x - next_tab_w
                next_x = math.floor(math.max(min_x, math.min(max_x, unclamped_x)) + 0.5)
              end
            end

            -- Extend this tab's width to reach the next tab (with 1px overlap)
            local distance_to_next = next_x - tab_x
            render_width = math.max(tab_w, distance_to_next + 1)  -- Ensure never smaller than tab_w
          end
        elseif is_last_visible then
          -- Last visible tab - extend to overflow button (with overlap)
          local target_x = overflow_x
          local distance_to_target = target_x - tab_x
          render_width = distance_to_target + 1  -- +1 for border overlap
        end

        -- Ensure render_width is always positive and at least 1px
        render_width = math.max(1, render_width)
        render_width = math.floor(render_width + 0.5)

        local is_active = (tab_data.id == active_tab_id)
        local clicked, delete_requested = draw_tab(
          ctx, dl, tab_data, is_active,
          i, tab_x, y, render_width, height,
          state, config, unique_id, animator, nil
        )

        if clicked and not (state.dragging_tab or ImGui.IsMouseDragging(ctx, 0)) then
          clicked_tab_id = tab_data.id
        end

        if delete_requested then
          id_to_delete = tab_data.id
        end
      end
    end
  end

  -- Draw overflow/menu button (overflow_x already calculated before tab loop)
  local overflow_corner = corner_rounding and {
    round_top_left = false,
    round_top_right = corner_rounding.round_top_right,
    rounding = corner_rounding.rounding,
  } or nil

  local overflow_clicked = draw_overflow_button(
    ctx, dl, overflow_x, y, overflow_width, height,
    config, overflow_count, unique_id, overflow_corner
  )

  if overflow_clicked and config.on_overflow_clicked then
    config.on_overflow_clicked()
  end

  -- Draw clip edge borders when content overflows
  local panel_right = x + available_width
  if tabs_start_x + tabs_width > panel_right or (overflow_at_edge and overflow_x + overflow_width > panel_right) then
    local border_color = 0x000000FF
    ImGui.DrawList_AddLine(dl, panel_right, y, panel_right, y + height, border_color, 1)
  end

  ImGui.DrawList_PopClipRect(dl)

  if clicked_tab_id and config.on_tab_change then
    config.on_tab_change(clicked_tab_id)
  end

  if id_to_delete and #tabs > 1 then
    for i, tab in ipairs(tabs) do
      if tab.id == id_to_delete then
        enable_animation_for_affected_tabs(state, tabs, i + 1)
        break
      end
    end
    
    if animator then
      animator:destroy(id_to_delete)
      state.pending_delete_id = id_to_delete
      
      if id_to_delete == active_tab_id and config.on_tab_change then
        for i, tab in ipairs(tabs) do
          if tab.id ~= id_to_delete then
            config.on_tab_change(tab.id)
            break
          end
        end
      end
    else
      if id_to_delete == active_tab_id and config.on_tab_change then
        for i, tab in ipairs(tabs) do
          if tab.id ~= id_to_delete then
            config.on_tab_change(tab.id)
            break
          end
        end
      end
      
      if config.on_tab_delete then
        config.on_tab_delete(id_to_delete)
      end
    end
  end

  if state.pending_delete_id and animator then
    if not animator:is_destroying(state.pending_delete_id) then
      if config.on_tab_delete then
        config.on_tab_delete(state.pending_delete_id)
      end
      state.pending_delete_id = nil
    end
  end

  return plus_width + (spacing > 0 and spacing or -1) + tabs_total_width
end

function M.measure(ctx, config, state)
  state = state or {}
  config = config or {}
  
  local plus_width = (config.plus_button and config.plus_button.width) or 23
  local spacing = config.spacing or 0
  
  local tabs = state.tabs or {}
  
  if #tabs == 0 then
    return plus_width
  end
  
  local total = plus_width
  if spacing > 0 then
    total = total + spacing
  else
    total = total - 1
  end
  
  for i, tab in ipairs(tabs) do
    local has_chip = tab.chip_color ~= nil
    local tab_w = calculate_tab_width(ctx, tab.label or "Tab", config, has_chip)
    total = total + tab_w
    
    local effective_spacing = spacing
    if i < #tabs and spacing == 0 then
      effective_spacing = -1
    end
    
    if i < #tabs then
      total = total + effective_spacing
    end
  end
  
  return total
end

return M