-- @noindex
-- Arkitekt/gui/widgets/panel/header/layout.lua
-- Layout engine for header elements with corner detection
-- Enhanced with left/right alignment support

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local PanelConfig = require('arkitekt.gui.widgets.containers.panel.defaults')
local ConfigUtil = require('arkitekt.core.config')

local M = {}

-- Component registry - imports from controls/ directly for reusable components
local InputTextModule = require('arkitekt.gui.widgets.primitives.inputtext')
local ComboModule = require('arkitekt.gui.widgets.primitives.combo')

local COMPONENTS = {
  button = require('arkitekt.gui.widgets.primitives.button'),
  checkbox = require('arkitekt.gui.widgets.primitives.checkbox'),
  inputtext = InputTextModule,
  combo = ComboModule,
  tab_strip = require('arkitekt.gui.widgets.containers.panel.header.tab_strip'),
  separator = require('arkitekt.gui.widgets.containers.panel.header.separator'),
  custom = {
    -- Custom element type that accepts a draw callback
    draw = function(ctx, dl, x, y, width, height, config, state)
      if config.on_draw then
        config.on_draw(ctx, dl, x, y, width, height, state)
      end
    end,
  },
}

-- Inline component for filter chip lists
local ChipList = require('arkitekt.gui.widgets.data.chip_list')
local Chip = require('arkitekt.gui.widgets.data.chip')

-- Custom compound element for template browser header with search/sort + filter chips
local InputText = require('arkitekt.gui.widgets.primitives.inputtext')
local Combo = require('arkitekt.gui.widgets.primitives.combo')
local Button = require('arkitekt.gui.widgets.primitives.button')

COMPONENTS.template_header_controls = {
  draw = function(ctx, dl, x, y, width, height, config, state)
    local row1_height = 26
    local row_spacing = 4
    local row2_y = y + row1_height + row_spacing

    -- ROW 1: Template count + Search + Sort
    local cursor_x = x

    -- Template count (120px)
    if config.get_template_count then
      local count = config.get_template_count()
      local label = string.format("%d template%s", count, count == 1 and "" or "s")

      Button.draw(ctx, {
        id = "template_count",
        draw_list = dl,
        x = cursor_x,
        y = y,
        width = 120,
        height = row1_height,
        label = label,
        interactive = false,
        style = {
          bg_color = 0x00000000,  -- Transparent
          text_color = 0xAAAAAAFF,
        },
        panel_state = state,
      })
      cursor_x = cursor_x + 128
    end

    -- Search field (200px, positioned before sort)
    local sort_width = 140
    local search_width = 200
    local search_x = x + width - sort_width - search_width - 8

    if config.get_search_query and config.on_search_changed then
      InputText.search(ctx, {
        x = search_x,
        y = y,
        width = search_width,
        height = row1_height,
        placeholder = "Search templates...",
        get_value = config.get_search_query,
        on_change = config.on_search_changed,
        draw_list = dl,
        panel_state = state,
      })
    end

    -- Sort dropdown (140px, right side)
    if config.get_sort_mode and config.on_sort_changed then
      local sort_x = search_x + search_width + 8
      Combo.draw(ctx, {
        x = sort_x,
        y = y,
        width = sort_width,
        height = row1_height,
        draw_list = dl,
        panel_state = state,
        tooltip = "Sort by",
        tooltip_delay = 0.5,
        enable_sort = false,
        get_value = config.get_sort_mode,
        options = {
          { value = "alphabetical", label = "Alphabetical" },
          { value = "usage", label = "Most Used" },
          { value = "insertion", label = "Recently Added" },
          { value = "color", label = "Color" },
        },
        enable_mousewheel = true,
        on_change = config.on_sort_changed,
      })
    end

    -- ROW 2: Filter chips
    if config.get_filter_items and config.on_filter_remove then
      local items = config.get_filter_items()
      if #items > 0 then
        ImGui.SetCursorScreenPos(ctx, x, row2_y)
        local clicked_id = ChipList.draw(ctx, items, {
          max_width = width,
          chip_height = 18,
          chip_spacing = 4,
          line_spacing = 2,
          use_dot_style = true,
        })

        if clicked_id then
          config.on_filter_remove(clicked_id)
        end
      end
    end

    return width
  end,

  measure = function(ctx, config, state)
    return 0  -- Dynamic width
  end,
}

-- ============================================================================
-- WIDTH CALCULATION
-- ============================================================================

local function calculate_element_width(ctx, element, state)
  local component = COMPONENTS[element.type]
  if not component then return 0 end
  
  if element.width then
    return element.width
  end
  
  if element.flex then
    return nil
  end
  
  if component.measure then
    return component.measure(ctx, element.config or {}, state)
  end
  
  return 0
end

-- ============================================================================
-- LEFT/RIGHT ALIGNMENT
-- ============================================================================

local function separate_by_alignment(elements)
  local left = {}
  local center = {}
  local right = {}
  
  for _, element in ipairs(elements) do
    local align = element.align or "left"
    if align == "right" then
      right[#right + 1] = element
    elseif align == "center" then
      center[#center + 1] = element
    else
      left[#left + 1] = element
    end
  end
  
  return left, center, right
end

local function layout_elements(ctx, elements, available_width, state)
  local layout = {}
  local fixed_total = 0
  local flex_total = 0

  -- Headers enforce no spacing between elements - use separators for gaps
  -- This ensures rounding rules work correctly (elements are always flush)

  for i, element in ipairs(elements) do
    local width = calculate_element_width(ctx, element, state)

    if width then
      fixed_total = fixed_total + width
    else
      flex_total = flex_total + (element.flex or 1)
    end

    layout[i] = {
      element = element,
      fixed_width = width,
      flex = element.flex,
    }
  end

  local remaining = available_width - fixed_total
  local flex_unit = flex_total > 0 and (remaining / flex_total) or 0

  for i, item in ipairs(layout) do
    if not item.fixed_width then
      item.width = math.max(0, item.flex * flex_unit)
    else
      item.width = item.fixed_width
    end
  end

  return layout
end

-- ============================================================================
-- CORNER & SEPARATOR DETECTION
-- ============================================================================

local function is_separator(element_type)
  return element_type == 'separator'
end

local function find_first_non_separator(layout)
  for i = 1, #layout do
    if not is_separator(layout[i].element.type) then
      return i
    end
  end
  return nil
end

local function find_last_non_separator(layout)
  for i = #layout, 1, -1 do
    if not is_separator(layout[i].element.type) then
      return i
    end
  end
  return nil
end

local function find_separator_neighbors(elements, separator_index)
  local left_neighbor = nil
  local right_neighbor = nil
  
  for i = separator_index - 1, 1, -1 do
    if not is_separator(elements[i].element.type) then
      left_neighbor = i
      break
    end
  end
  
  for i = separator_index + 1, #elements do
    if not is_separator(elements[i].element.type) then
      right_neighbor = i
      break
    end
  end
  
  return left_neighbor, right_neighbor
end

local function calculate_corner_rounding(layout, header_rounding, is_bottom, side)
  local rounding_info = {}

  local first_idx = find_first_non_separator(layout)
  local last_idx = find_last_non_separator(layout)

  -- Determine which edges get outer rounding based on side
  -- "full" = both edges, "left" = left edge only, "right" = right edge only
  side = side or "full"
  local use_left_edge = (side == "full" or side == "left")
  local use_right_edge = (side == "full" or side == "right")

  for i, item in ipairs(layout) do
    if is_separator(item.element.type) then
      -- Separators never have rounding
      rounding_info[i] = {
        round_top_left = false,
        round_top_right = false,
        round_bottom_left = false,
        round_bottom_right = false,
      }
    else
      -- Determine if this element is at edges or next to separators
      -- Only apply edge rounding if this side is being used
      local is_first = (i == first_idx) and use_left_edge
      local is_last = (i == last_idx) and use_right_edge

      -- Check if element is adjacent to separators
      local sep_on_left = false
      local sep_on_right = false

      for j = 1, #layout do
        if is_separator(layout[j].element.type) then
          local left_neighbor, right_neighbor = find_separator_neighbors(layout, j)
          if left_neighbor == i then
            sep_on_right = true  -- Separator is to our right
          end
          if right_neighbor == i then
            sep_on_left = true   -- Separator is to our left
          end
        end
      end

      -- Check for rounding_mode override in element config
      -- "top" = force top corners, "bottom" = force bottom corners, nil = auto
      local rounding_mode = item.element.config and item.element.config.rounding_mode

      if rounding_mode == "bottom" then
        -- Force bottom corners (e.g., transport panel buttons)
        rounding_info[i] = {
          round_top_left = false,
          round_top_right = false,
          round_bottom_left = is_first or sep_on_left,
          round_bottom_right = is_last or sep_on_right,
          rounding = header_rounding,
        }
      elseif rounding_mode == "top" then
        -- Force top corners
        rounding_info[i] = {
          round_top_left = is_first or sep_on_left,
          round_top_right = is_last or sep_on_right,
          round_bottom_left = false,
          round_bottom_right = false,
          rounding = header_rounding,
        }
      elseif is_bottom then
        -- Footer: bottom corners for edges, top corners toward separators
        rounding_info[i] = {
          round_top_left = sep_on_left,
          round_top_right = sep_on_right,
          round_bottom_left = is_first and not sep_on_left,
          round_bottom_right = is_last and not sep_on_right,
          rounding = header_rounding,
        }
      else
        -- Header: top corners for edges, bottom corners toward separators
        rounding_info[i] = {
          round_top_left = is_first and not sep_on_left,
          round_top_right = is_last and not sep_on_right,
          round_bottom_left = sep_on_left,
          round_bottom_right = sep_on_right,
          rounding = header_rounding,
        }
      end
    end
  end

  return rounding_info
end

-- ============================================================================
-- ELEMENT STATE MANAGEMENT
-- ============================================================================

local function get_or_create_element_state(state, element)
  if element.type == "tab_strip" then
    local element_state = state[element.id]
    if not element_state then
      element_state = {
        tabs = {},
        active_tab_id = nil,
        tab_positions = {},
        dragging_tab = nil,
        pending_delete_id = nil,
        _tabs_version = 0,
      }
      state[element.id] = element_state
    end
    
    if not element_state.dragging_tab then
      if state.tabs and type(state.tabs) == "table" then
        if element_state.tabs ~= state.tabs then
          element_state.tabs = state.tabs
          element_state._tabs_version = (element_state._tabs_version or 0) + 1
        end
        element_state.active_tab_id = state.active_tab_id
      end
    end
    
    if state.tab_animator then
      element_state.tab_animator = state.tab_animator
    end
    
    element_state.id = element.id
    element_state._panel_id = state.id
    
    return element_state
  else
    local element_state = state[element.id]
    if not element_state then
      element_state = {}
      state[element.id] = element_state
    end
    element_state.id = element.id
    element_state._panel_id = state.id
    
    return element_state
  end
end

-- ============================================================================
-- ELEMENT RENDERING
-- ============================================================================

-- Widgets that use the new standardized opts-based API
local STANDARDIZED_WIDGETS = {
  button = true,
  checkbox = true,
  inputtext = true,
  combo = true,
}

local function render_elements(ctx, dl, x, y, width, height, elements, state, header_rounding, is_bottom, valign, side)
  if not elements or #elements == 0 then
    return 0
  end

  local layout = layout_elements(ctx, elements, width, state)
  local rounding_info = calculate_corner_rounding(layout, header_rounding, is_bottom, side)

  local border_overlap = 1
  local cursor_x = x
  local last_non_sep_idx = find_last_non_separator(layout)

  for i, item in ipairs(layout) do
    local element = item.element
    local element_width = item.width

    -- Apply 1px overlap between adjacent non-separator elements
    if i > 1 then
      local prev_element = layout[i - 1].element
      if prev_element.type ~= 'separator' and element.type ~= 'separator' then
        cursor_x = cursor_x - border_overlap
      end
    end

    if i == last_non_sep_idx and element.type ~= 'separator' then
      local remaining_space = (x + width) - cursor_x
      if remaining_space > element_width then
        element_width = remaining_space
      end
    end

    local component = COMPONENTS[element.type]
    if component and component.draw then
      -- Merge panel ELEMENT_STYLE as fallback (won't override preset colors)
      local style_defaults = PanelConfig.ELEMENT_STYLE[element.type] or {}
      local element_config = ConfigUtil.merge_safe(element.config or {}, style_defaults)

      -- Pass element ID to config for unique identification
      element_config.id = element.id

      if rounding_info[i] then
        element_config.corner_rounding = rounding_info[i]
      end

      -- Update button label from panel current_mode if this is a mode_toggle button
      if element.type == "button" and element.id == "mode_toggle" and state.current_mode then
        if state.current_mode == "regions" then
          element_config.label = "Regions"
        elseif state.current_mode == "playlists" then
          element_config.label = "Playlists"
        elseif state.current_mode == "mixed" then
          element_config.label = "Mixed"
        end
      end

      -- Evaluate function-based labels (for dynamic content)
      if element_config.label and type(element_config.label) == "function" then
        element_config.label = element_config.label(state)
      end

      local element_state = get_or_create_element_state(state, element)

      local used_width

      -- Use new opts-based API for standardized widgets
      if STANDARDIZED_WIDGETS[element.type] then
        -- Build opts table for standardized widget API
        local opts = element_config
        opts.x = cursor_x
        opts.y = y
        opts.width = element_width
        opts.height = height
        opts.draw_list = dl
        opts.panel_state = element_state

        local result = component.draw(ctx, opts)
        used_width = result and result.width or element_width
      else
        -- Use old positional API for non-standardized widgets
        used_width = component.draw(
          ctx, dl,
          cursor_x, y,
          element_width, height,
          element_config,
          element_state
        )
      end

      cursor_x = cursor_x + (used_width or element_width)
    else
      cursor_x = cursor_x + element_width
    end
  end

  return height
end

-- ============================================================================
-- CLIP EDGE BORDER DRAWING
-- ============================================================================

--- Draws visual borders at panel edges where content is being clipped
--- @param dl ImGui draw list
--- @param panel_x number Panel left edge
--- @param panel_y number Panel top edge
--- @param panel_width number Panel width
--- @param panel_height number Panel height
--- @param ... number Content boundaries (left_start, left_end, right_start, right_end)
local function draw_clip_edge_borders(dl, panel_x, panel_y, panel_width, panel_height, ...)
  local bounds = {...}
  local border_color = 0x000000FF  -- Black border for clip edges
  local border_thickness = 1

  local panel_left = panel_x
  local panel_right = panel_x + panel_width

  -- Check if content extends beyond left edge
  if #bounds >= 1 and bounds[1] < panel_left then
    ImGui.DrawList_AddLine(dl, panel_left, panel_y, panel_left, panel_y + panel_height, border_color, border_thickness)
  end

  -- Check if content extends beyond right edge
  local right_bound = #bounds >= 2 and bounds[2] or bounds[1]
  if right_bound > panel_right then
    ImGui.DrawList_AddLine(dl, panel_right, panel_y, panel_right, panel_y + panel_height, border_color, border_thickness)
  end

  -- For dual-side layouts (left + right elements)
  if #bounds >= 4 then
    -- Check left-aligned content overflow
    if bounds[2] > panel_right then
      ImGui.DrawList_AddLine(dl, panel_right, panel_y, panel_right, panel_y + panel_height, border_color, border_thickness)
    end
    -- Check right-aligned content overflow
    if bounds[3] < panel_left then
      ImGui.DrawList_AddLine(dl, panel_left, panel_y, panel_left, panel_y + panel_height, border_color, border_thickness)
    end
  end
end

-- ============================================================================
-- MAIN DRAW FUNCTION
-- ============================================================================

function M.draw(ctx, dl, x, y, width, height, state, config)
  if not config or not config.elements or #config.elements == 0 then
    return 0
  end

  local padding = config.padding or {}
  local padding_left = padding.left or 0
  local padding_right = padding.right or 0

  local content_width = width - padding_left - padding_right
  local content_height = height
  local content_x = x + padding_left
  local content_y = y

  local header_rounding = config.rounding or 8
  local is_bottom = config.position == "bottom"

  -- Apply clipping to prevent header elements from overflowing panel bounds
  ImGui.DrawList_PushClipRect(dl, x, y, x + width, y + height, true)

  -- Separate elements by alignment
  local left_elements, center_elements, right_elements = separate_by_alignment(config.elements)

  -- Handle center elements
  if #center_elements > 0 then
    local center_layout = layout_elements(ctx, center_elements, content_width, state)
    local center_width = 0
    for _, item in ipairs(center_layout) do
      center_width = center_width + item.width
    end

    local valign = config.valign or "top"
    -- Pixel snap center position to prevent blurry borders
    local center_x = math.floor(content_x + (content_width - center_width) / 2 + 0.5)
    render_elements(ctx, dl, center_x, content_y, center_width, content_height, center_elements, state, header_rounding, is_bottom, valign, "full")

    -- Draw clip edge borders if content overflows (use actual rendered width, not allocated content_width)
    draw_clip_edge_borders(dl, x, y, width, height, center_x, center_x + center_width)

    ImGui.DrawList_PopClipRect(dl)
    return height
  end

  if #left_elements > 0 and #right_elements > 0 then
    -- Both left and right elements: calculate available space
    local left_layout = layout_elements(ctx, left_elements, content_width, state)
    local right_layout = layout_elements(ctx, right_elements, content_width, state)

    -- Calculate total width needed
    local left_width = 0
    for _, item in ipairs(left_layout) do
      left_width = left_width + item.width
    end

    local right_width = 0
    for _, item in ipairs(right_layout) do
      right_width = right_width + item.width
    end

    -- Render left-aligned elements (only left edge gets outer rounding)
    render_elements(ctx, dl, content_x, content_y, left_width, content_height, left_elements, state, header_rounding, is_bottom, nil, "left")

    -- Render right-aligned elements (only right edge gets outer rounding)
    local right_x = content_x + content_width - right_width
    render_elements(ctx, dl, right_x, content_y, right_width, content_height, right_elements, state, header_rounding, is_bottom, nil, "right")

    -- Draw clip edge borders if content overflows
    draw_clip_edge_borders(dl, x, y, width, height, content_x, content_x + left_width, right_x, right_x + right_width)

  elseif #right_elements > 0 then
    -- Only right-aligned elements
    local right_layout = layout_elements(ctx, right_elements, content_width, state)
    local right_width = 0
    for _, item in ipairs(right_layout) do
      right_width = right_width + item.width
    end

    local right_x = content_x + content_width - right_width
    render_elements(ctx, dl, right_x, content_y, right_width, content_height, right_elements, state, header_rounding, is_bottom, nil, "full")

    -- Draw clip edge borders if content overflows (use actual rendered width)
    draw_clip_edge_borders(dl, x, y, width, height, right_x, right_x + right_width)

  else
    -- Only left-aligned elements (default)
    -- Calculate actual element widths instead of using allocated content_width
    local left_layout = layout_elements(ctx, left_elements, content_width, state)
    local left_width = 0
    for _, item in ipairs(left_layout) do
      left_width = left_width + item.width
    end

    render_elements(ctx, dl, content_x, content_y, content_width, content_height, left_elements, state, header_rounding, is_bottom, nil, "full")

    -- Draw clip edge borders if content overflows (use actual rendered width, not allocated content_width)
    draw_clip_edge_borders(dl, x, y, width, height, content_x, content_x + left_width)
  end

  -- Always pop clip rect before returning
  ImGui.DrawList_PopClipRect(dl)

  return height
end

return M
