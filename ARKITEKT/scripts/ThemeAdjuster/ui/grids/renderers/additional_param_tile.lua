-- @noindex
-- ThemeAdjuster/ui/grids/renderers/additional_param_tile.lua
-- Renders parameter tiles in Additional tab with controls and link mode selector

local ImGui = require 'imgui' '0.10'
local Colors = require('rearkitekt.core.colors')
local Checkbox = require('rearkitekt.gui.widgets.primitives.checkbox')
local Spinner = require('rearkitekt.gui.widgets.primitives.spinner')
local ParameterLinkManager = require('ThemeAdjuster.core.parameter_link_manager')
local hexrgb = Colors.hexrgb

local M = {}

-- Tile dimensions
local TILE_HEIGHT = 60
local TILE_PADDING = 8
local CONTROL_WIDTH = 200

-- Throttle refresh calls during drag
local last_refresh_time = 0
local REFRESH_INTERVAL = 0.1  -- 100ms = 10 fps max

-- Track last set values for preset spinners to avoid recalculating index
M._preset_spinner_states = M._preset_spinner_states or {}  -- keyed by param_name

-- Read/write parameter value from Reaper theme
local function get_param_value(param_index, param_type)
  if not param_index then return param_type == "bool" and 0 or 0.0 end

  local ok, name, desc, value = pcall(reaper.ThemeLayout_GetParameter, param_index)
  if not ok or value == nil then
    -- Default values based on type
    if param_type == "bool" then
      return 0
    elseif param_type == "int" or param_type == "enum" then
      return 0
    else -- float
      return 0.0
    end
  end
  return value
end

local function set_param_value(param_index, value)
  if not param_index then return end
  pcall(reaper.ThemeLayout_SetParameter, param_index, value, true)
end

-- Render a single parameter tile
function M.render(ctx, param, tab_color, shell_state, view)
  -- Check if this is a group control (macro)
  if param.is_group then
    M.render_group(ctx, param, tab_color, shell_state, view)
    return
  end

  local param_name = param.name
  local param_index = param.index
  local param_type = param.type
  local metadata = view.custom_metadata[param_name] or {}

  -- Get current value from Reaper
  local current_value = get_param_value(param_index, param_type)

  -- Get link status
  local is_in_group = ParameterLinkManager.is_in_group(param_name)
  local link_mode = ParameterLinkManager.get_link_mode(param_name)
  local other_params = is_in_group and ParameterLinkManager.get_other_group_params(param_name) or {}

  -- Tile background
  local x1, y1 = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local x2, y2 = x1 + avail_w, y1 + TILE_HEIGHT
  local dl = ImGui.GetWindowDrawList(ctx)

  -- Background with tab color tint
  local function dim_color(color, opacity)
    local r = (color >> 24) & 0xFF
    local g = (color >> 16) & 0xFF
    local b = (color >> 8) & 0xFF
    local a = math.floor(255 * opacity)
    return (r << 24) | (g << 16) | (b << 8) | a
  end

  local bg_color = dim_color(tab_color, 0.12)
  local border_color = dim_color(tab_color, 0.3)

  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg_color, 3)
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, border_color, 3, 0, 1)

  -- Start tile content
  ImGui.SetCursorScreenPos(ctx, x1 + TILE_PADDING, y1 + TILE_PADDING)

  -- TOP ROW: Parameter name + tooltip indicator
  ImGui.PushFont(ctx, shell_state.fonts.bold, 13)
  local display_name = metadata.display_name and metadata.display_name ~= "" and metadata.display_name or param_name
  if #display_name > 35 then
    display_name = display_name:sub(1, 32) .. "..."
  end
  ImGui.Text(ctx, display_name)
  ImGui.PopFont(ctx)

  -- Tooltip with full details
  if ImGui.IsItemHovered(ctx) then
    local tooltip = "Parameter: " .. param_name
    tooltip = tooltip .. "\nType: " .. (param_type or "unknown")
    if metadata.description and metadata.description ~= "" then
      tooltip = tooltip .. "\n" .. metadata.description
    end
    if param.min and param.max then
      tooltip = tooltip .. string.format("\nRange: %.2f - %.2f", param.min, param.max)
    end
    ImGui.SetTooltip(ctx, tooltip)
  end

  -- Linked params indicator (same line, right side)
  if is_in_group and #other_params > 0 then
    ImGui.SameLine(ctx, avail_w - 250)
    local group_color = ParameterLinkManager.get_group_color(param_name) or hexrgb("#4AE290")
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, group_color)
    local linked_text = "Linked: " .. table.concat(other_params, ", ")
    if #linked_text > 30 then
      linked_text = linked_text:sub(1, 27) .. "..."
    end
    ImGui.Text(ctx, linked_text)
    ImGui.PopStyleColor(ctx)

    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Grouped with:\n" .. table.concat(other_params, "\n"))
    end
  end

  -- MIDDLE ROW: Control (slider/checkbox/spinner)
  ImGui.SetCursorScreenPos(ctx, x1 + TILE_PADDING, y1 + TILE_PADDING + 20)

  local value_changed = false
  local was_deactivated = false
  local new_value = current_value
  local control_id = "##" .. param_name

  -- Check if this parameter has a template configured
  local template = nil

  -- First check if param has template_id attached (from group expansion or template assignment)
  if param.template_id and view.templates then
    template = view.templates[param.template_id]
  end

  -- Fall back to assignment lookup for backward compatibility
  if not template then
    local assignment = view:get_assignment_for_param(param.name)
    if assignment then
      -- New system: template_id references view.templates
      if assignment.template_id and view.templates then
        template = view.templates[assignment.template_id]
      -- Old system: inline template (backwards compat)
      elseif assignment.template then
        template = assignment.template
      end
    end
  end

  local presets = template and ((template.config and template.config.presets) or template.presets)
  if template and template.type == "preset_spinner" and presets and #presets > 0 then
    -- Render preset spinner
    local preset_values = {}
    local preset_labels = {}
    for _, preset in ipairs(presets) do
      -- New format: preset.values[param_name] for multi-parameter support
      -- Old format: preset.value for single value (backwards compat)
      local value = preset.values and preset.values[param.name] or preset.value
      if value then
        table.insert(preset_values, value)
        table.insert(preset_labels, preset.label or "Unnamed")
      end
    end

    -- Only render spinner if we have valid preset values
    if #preset_values > 0 then
      -- Get or initialize spinner state
      if not M._preset_spinner_states[param_name] then
        M._preset_spinner_states[param_name] = {
          last_value = current_value,
          current_idx = 1
        }
      end

      local spinner_state = M._preset_spinner_states[param_name]

      -- Only recalculate closest index if the value changed externally (not from our spinner)
      if math.abs(current_value - spinner_state.last_value) > 0.1 then
        -- Value changed externally, find closest preset
        local closest_idx = 1
        local min_diff = math.abs(current_value - preset_values[1])
        for i = 2, #preset_values do
          local diff = math.abs(current_value - preset_values[i])
          if diff < min_diff then
            min_diff = diff
            closest_idx = i
          end
        end
        spinner_state.current_idx = closest_idx
        spinner_state.last_value = current_value
      end

      local changed_spinner, new_idx = Spinner.draw(
        ctx,
        "##preset_spinner_" .. param.name,
        spinner_state.current_idx,
        preset_labels,
        {w = CONTROL_WIDTH, h = 24}
      )

      if changed_spinner then
        new_value = preset_values[new_idx]
        value_changed = true
        was_deactivated = true  -- Spinner changes are immediate

        -- Update state to track this change
        spinner_state.current_idx = new_idx
        spinner_state.last_value = new_value
      end
    else
      -- No valid presets, fall through to default controls
      template = nil
    end

  elseif param_type == "bool" then
    -- Checkbox
    local checked = current_value ~= 0
    if Checkbox.draw_at_cursor(ctx, param_name, checked, nil, "param_" .. param_name) then
      new_value = checked and 0 or 1
      value_changed = true
      was_deactivated = true  -- Immediate
    end
  elseif param_type == "int" or param_type == "enum" then
    -- SliderInt with IsItemActive for continuous updates
    ImGui.SetNextItemWidth(ctx, CONTROL_WIDTH)
    local min_val = param.min or 0
    local max_val = param.max or 100
    local changed, val = ImGui.SliderInt(ctx, control_id, current_value, min_val, max_val)
    local is_active = ImGui.IsItemActive(ctx)

    if changed or is_active then
      new_value = val
      value_changed = true
    end

    if ImGui.IsItemDeactivated(ctx) then
      was_deactivated = true
    end
  else
    -- SliderDouble with IsItemActive (REAPER parameters are integers, so we round)
    ImGui.SetNextItemWidth(ctx, CONTROL_WIDTH)
    local min_val = param.min or 0.0
    local max_val = param.max or 1.0
    local changed, val = ImGui.SliderDouble(ctx, control_id, current_value, min_val, max_val, "%.0f")
    local is_active = ImGui.IsItemActive(ctx)

    if changed or is_active then
      new_value = math.floor(val + 0.5)  -- Round to integer for REAPER
      value_changed = true
    end

    if ImGui.IsItemDeactivated(ctx) then
      was_deactivated = true
    end
  end

  -- BOTTOM ROW: Link mode selector
  ImGui.SetCursorScreenPos(ctx, x1 + TILE_PADDING + CONTROL_WIDTH + 20, y1 + TILE_PADDING + 20)

  -- UNLINKED button
  local is_unlinked = link_mode == ParameterLinkManager.LINK_MODE.UNLINKED
  if is_unlinked then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, hexrgb("#555555"))
  end
  if ImGui.Button(ctx, "UNLINKED##" .. param_name, 80, 20) then
    ParameterLinkManager.set_link_mode(param_name, ParameterLinkManager.LINK_MODE.UNLINKED)
    view:save_assignments()
  end
  if is_unlinked then
    ImGui.PopStyleColor(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "No linking - parameter is independent")
  end

  ImGui.SameLine(ctx, 0, 4)

  -- LINK button
  local is_link = link_mode == ParameterLinkManager.LINK_MODE.LINK
  if is_link then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, hexrgb("#4A90E2"))
  end
  if ImGui.Button(ctx, "LINK##" .. param_name, 60, 20) then
    ParameterLinkManager.set_link_mode(param_name, ParameterLinkManager.LINK_MODE.LINK)
    view:save_assignments()
  end
  if is_link then
    ImGui.PopStyleColor(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "LINK mode - parameters move by same delta")
  end

  ImGui.SameLine(ctx, 0, 4)

  -- SYNC button
  local is_sync = link_mode == ParameterLinkManager.LINK_MODE.SYNC
  if is_sync then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, hexrgb("#4AE290"))
  end
  if ImGui.Button(ctx, "SYNC##" .. param_name, 60, 20) then
    ParameterLinkManager.set_link_mode(param_name, ParameterLinkManager.LINK_MODE.SYNC)
    view:save_assignments()
  end
  if is_sync then
    ImGui.PopStyleColor(ctx)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "SYNC mode - parameter mirrors exact value")
  end

  -- Handle value change and propagation (match library_tile.lua pattern)
  if value_changed then
    local old_value = current_value

    -- Apply to this parameter
    set_param_value(param_index, new_value)

    -- Propagate to linked parameters
    if is_in_group and link_mode ~= ParameterLinkManager.LINK_MODE.UNLINKED then
      local propagations = ParameterLinkManager.propagate_value_change(param_name, old_value, new_value, param)

      -- Apply propagated changes to other parameters
      for _, prop in ipairs(propagations) do
        -- Find the parameter definition for the linked param
        for _, p in ipairs(view.all_params) do
          if p.name == prop.param_name then
            local target_min = p.min or 0
            local target_max = p.max or 100
            local target_range = target_max - target_min
            local target_new_value

            if prop.mode == "sync" then
              -- SYNC: Set to same percentage position in target's range
              target_new_value = target_min + (prop.percent * target_range)
            elseif prop.mode == "link" then
              -- LINK: Use virtual value (can be negative), clamp for REAPER
              target_new_value = prop.virtual_value
            end

            -- Round to integer for REAPER
            target_new_value = math.floor(target_new_value + 0.5)

            -- Clamp to target's range
            local clamped_value = math.max(target_min, math.min(target_max, target_new_value))

            set_param_value(p.index, clamped_value)
            break
          end
        end
      end
    end

    -- Throttled refresh during drag, immediate on release
    local current_time = reaper.time_precise()
    local should_refresh = was_deactivated or ((current_time - last_refresh_time) >= REFRESH_INTERVAL)

    if should_refresh then
      pcall(reaper.ThemeLayout_RefreshAll)
      last_refresh_time = current_time
    end
  end

  -- Move cursor to next tile position
  ImGui.SetCursorScreenPos(ctx, x1, y2 + 4)
  ImGui.Dummy(ctx, avail_w, 0)
end

-- Render a group control tile (macro that controls multiple parameters at once)
function M.render_group(ctx, group_param, tab_color, shell_state, view)
  local group_id = group_param.group_id
  local group_name = group_param.display_name

  -- Find the group
  local group = nil
  for _, g in ipairs(view.template_groups) do
    if g.id == group_id then
      group = g
      break
    end
  end

  if not group then
    -- Group not found, render placeholder
    ImGui.Text(ctx, "Group not found: " .. group_name)
    return
  end

  -- Get presets from the group itself (stored by apply_group_config)
  local presets = group.presets

  if not presets or #presets == 0 then
    -- No presets configured
    ImGui.Text(ctx, group_name .. " (no presets)")
    return
  end

  -- Tile background
  local x1, y1 = ImGui.GetCursorScreenPos(ctx)
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local x2, y2 = x1 + avail_w, y1 + TILE_HEIGHT
  local dl = ImGui.GetWindowDrawList(ctx)

  -- Background with tab color tint
  local function dim_color(color, opacity)
    local r = (color >> 24) & 0xFF
    local g = (color >> 16) & 0xFF
    local b = (color >> 8) & 0xFF
    local a = math.floor(255 * opacity)
    return (r << 24) | (g << 16) | (b << 8) | a
  end

  local bg_color = dim_color(tab_color, 0.12)
  local border_color = dim_color(tab_color, 0.3)

  ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg_color, 3)
  ImGui.DrawList_AddRect(dl, x1, y1, x2, y2, border_color, 3, 0, 1)

  -- Start tile content
  ImGui.SetCursorScreenPos(ctx, x1 + TILE_PADDING, y1 + TILE_PADDING)

  -- TOP ROW: Group name
  ImGui.PushFont(ctx, shell_state.fonts.bold, 13)
  local display_name = group_name
  if #display_name > 35 then
    display_name = display_name:sub(1, 32) .. "..."
  end
  ImGui.Text(ctx, display_name)
  ImGui.PopFont(ctx)

  -- Tooltip with group info
  if ImGui.IsItemHovered(ctx) then
    local tooltip = "Group: " .. group_name
    tooltip = tooltip .. "\nTemplates: " .. #(group.template_ids or {})
    tooltip = tooltip .. "\nPresets: " .. #presets
    ImGui.SetTooltip(ctx, tooltip)
  end

  -- MIDDLE ROW: Preset spinner
  ImGui.SetCursorScreenPos(ctx, x1 + TILE_PADDING, y1 + TILE_PADDING + 20)

  -- Build preset labels
  local preset_labels = {}
  for _, preset in ipairs(presets) do
    table.insert(preset_labels, preset.label or "Unnamed")
  end

  -- Track spinner state
  if not M._preset_spinner_states[group_id] then
    M._preset_spinner_states[group_id] = {
      current_idx = 1
    }
  end

  local spinner_state = M._preset_spinner_states[group_id]

  local changed_spinner, new_idx = Spinner.draw(
    ctx,
    "##group_spinner_" .. group_id,
    spinner_state.current_idx,
    preset_labels,
    {w = CONTROL_WIDTH, h = 24}
  )

  if changed_spinner then
    spinner_state.current_idx = new_idx
    local selected_preset = presets[new_idx]

    -- Apply all preset values to all parameters in the group
    if selected_preset and selected_preset.values then
      for _, template_id in ipairs(group.template_ids or {}) do
        local template = view.templates[template_id]
        if template then
          for _, param_name in ipairs(template.params or {}) do
            local value = selected_preset.values[param_name]
            if value ~= nil then
              -- Find parameter and set its value
              for _, p in ipairs(view.all_params) do
                if p.name == param_name then
                  set_param_value(p.index, value)
                  break
                end
              end
            end
          end
        end
      end

      -- Refresh the theme
      pcall(reaper.ThemeLayout_RefreshAll)
    end
  end

  -- Move cursor to next tile position
  ImGui.SetCursorScreenPos(ctx, x1, y2 + 4)
  ImGui.Dummy(ctx, avail_w, 0)
end

return M
