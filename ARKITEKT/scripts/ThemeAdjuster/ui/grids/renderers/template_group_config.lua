-- @noindex
-- ThemeAdjuster/ui/grids/renderers/template_group_config.lua
-- Configuration UI for template groups in the templates grid

local ImGui = require 'imgui' '0.10'
local Colors = require('rearkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

-- Configuration state storage
M._group_config_open = M._group_config_open or {}
M._group_config_state = M._group_config_state or {}

--- Opens the configuration dialog for a template group
--- @param group_id string - The group ID to configure
--- @param view table - The AdditionalView instance
function M.open_config(group_id, view)
  local group = nil
  for _, g in ipairs(view.template_groups) do
    if g.id == group_id then
      group = g
      break
    end
  end

  if not group then return end

  M._group_config_open[group_id] = true
  M._group_config_state[group_id] = {
    name = group.name or "",
    color = group.color or "#888888",
    -- Load first template's config as group defaults
    preset_config = M.load_group_preset_config(group, view),
  }
end

--- Loads the preset configuration from the group's templates
--- @param group table - The group data
--- @param view table - The AdditionalView instance
--- @return table - Preset configuration state
function M.load_group_preset_config(group, view)
  -- Collect all unique parameters from all templates in the group
  local all_params = {}
  local param_order = {}  -- To preserve order

  for _, template_id in ipairs(group.template_ids or {}) do
    local template = view.templates[template_id]
    if template and template.params then
      for _, param_name in ipairs(template.params) do
        if not all_params[param_name] then
          all_params[param_name] = true
          table.insert(param_order, param_name)
        end
      end
    end
  end

  -- Load existing presets from group (stored by apply_group_config)
  local presets = {}
  if group.presets then
    -- Group has full preset configuration saved
    presets = group.presets
  else
    -- Fallback: try loading from first template (backward compatibility)
    local first_template_id = group.template_ids and group.template_ids[1]
    if first_template_id then
      local first_template = view.templates[first_template_id]
      if first_template and first_template.config and first_template.config.presets then
        -- Convert old format to new format if needed
        for _, preset in ipairs(first_template.config.presets) do
          local new_preset = {
            label = preset.label or "Unnamed",
            values = {}
          }

          -- If old format (single value), apply to all params
          if preset.value then
            for _, param_name in ipairs(param_order) do
              new_preset.values[param_name] = preset.value
            end
          else
            -- New format already
            new_preset.values = preset.values or {}
          end

          table.insert(presets, new_preset)
        end
      end
    end
  end

  return {
    type = "preset_spinner",
    presets = presets,
    param_order = param_order,  -- Track parameter column order
  }
end

--- Renders all open group configuration dialogs
--- @param ctx ImGui context
--- @param view table - The AdditionalView instance
function M.render_config_dialogs(ctx, view)
  for group_id, is_open in pairs(M._group_config_open) do
    if is_open then
      local state = M._group_config_state[group_id]
      if not state then
        M._group_config_open[group_id] = false
        goto continue
      end

      -- Find the group
      local group = nil
      for _, g in ipairs(view.template_groups) do
        if g.id == group_id then
          group = g
          break
        end
      end

      if not group then
        M._group_config_open[group_id] = false
        goto continue
      end

      -- Modal window
      local modal_w, modal_h = 650, 600
      ImGui.SetNextWindowSize(ctx, modal_w, modal_h, ImGui.Cond_Appearing)

      local flags = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoDocking
      local visible, open = ImGui.Begin(ctx, "Group Configuration: " .. (state.name ~= "" and state.name or "Unnamed Group"), true, flags)

      if visible then
        -- Group name
        ImGui.Text(ctx, "Group Name:")
        ImGui.SetNextItemWidth(ctx, 300)
        local changed_name, new_name = ImGui.InputText(ctx, "##group_name", state.name)
        if changed_name then
          state.name = new_name
        end

        ImGui.Dummy(ctx, 0, 8)

        -- Group color picker
        ImGui.Text(ctx, "Group Color:")
        ImGui.SameLine(ctx)

        -- Convert hex to ImGui color format (0xRRGGBB)
        local color_int = M.hex_to_color_int(state.color)

        -- Color button that opens the picker
        local changed_color, new_color_int = ImGui.ColorEdit3(ctx, "##group_color", color_int,
          ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_PickerHueWheel)
        if changed_color then
          state.color = M.color_int_to_hex(new_color_int)
        end

        -- Show hex color text
        ImGui.SameLine(ctx)
        ImGui.TextDisabled(ctx, state.color)

        ImGui.Dummy(ctx, 0, 12)
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 0, 8)

        -- Template list in this group
        ImGui.Text(ctx, string.format("Templates in this group: %d", #(group.template_ids or {})))
        ImGui.Dummy(ctx, 0, 4)

        if ImGui.BeginChild(ctx, "group_templates_list", 0, 100) then
          for _, template_id in ipairs(group.template_ids or {}) do
            local template = view.templates[template_id]
            if template then
              local param_names = table.concat(template.params or {}, ", ")
              ImGui.BulletText(ctx, param_names)
            end
          end
          ImGui.EndChild(ctx)
        end

        ImGui.Dummy(ctx, 0, 12)
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 0, 8)

        -- Preset configuration section
        ImGui.Text(ctx, "Preset Configuration:")
        ImGui.TextWrapped(ctx, "Configure presets for all templates in this group. Each parameter gets its own column.")
        ImGui.Dummy(ctx, 0, 8)

        -- Preset configuration (render for all templates in group)
        M.render_preset_config(ctx, state, view)

        -- Bottom buttons
        ImGui.Dummy(ctx, 0, 12)
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 0, 8)

        if ImGui.Button(ctx, "Apply", 180, 28) then
          -- Apply configuration to the group and all its templates
          M.apply_group_config(group, state, view)
          M._group_config_open[group_id] = false
        end

        ImGui.SameLine(ctx, 0, 8)
        if ImGui.Button(ctx, "Cancel", 100, 28) then
          M._group_config_open[group_id] = false
        end

        ImGui.End(ctx)
      end

      if not open then
        M._group_config_open[group_id] = false
      end

      ::continue::
    end
  end
end

--- Render preset spinner configuration with parameter columns
function M.render_preset_config(ctx, state, view)
  ImGui.Separator(ctx)
  ImGui.Dummy(ctx, 0, 8)

  ImGui.Text(ctx, "Presets (each row = spinner enum):")
  ImGui.Dummy(ctx, 0, 4)

  local param_order = state.preset_config.param_order or {}
  local num_params = #param_order

  -- Calculate number of columns: # + Label + one per parameter
  local num_columns = 2 + num_params

  -- Table for presets
  local table_flags = ImGui.TableFlags_Borders |
                      ImGui.TableFlags_RowBg |
                      ImGui.TableFlags_ScrollY |
                      ImGui.TableFlags_ScrollX |
                      ImGui.TableFlags_SizingFixedFit

  if ImGui.BeginTable(ctx, "group_preset_table", num_columns, table_flags, 0, 180) then
    -- Setup columns
    ImGui.TableSetupColumn(ctx, "#", ImGui.TableColumnFlags_WidthFixed, 30)
    ImGui.TableSetupColumn(ctx, "Label", ImGui.TableColumnFlags_WidthFixed, 120)

    -- Add column for each parameter
    for _, param_name in ipairs(param_order) do
      -- Use full parameter name
      ImGui.TableSetupColumn(ctx, param_name, ImGui.TableColumnFlags_WidthFixed, 150)
    end

    ImGui.TableSetupScrollFreeze(ctx, 2, 1)  -- Freeze first 2 columns and header
    ImGui.TableHeadersRow(ctx)

    -- Render preset rows
    local to_remove = nil
    for i, preset in ipairs(state.preset_config.presets) do
      ImGui.TableNextRow(ctx)
      ImGui.PushID(ctx, i)

      -- Column 0: Index with remove button
      ImGui.TableSetColumnIndex(ctx, 0)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.Text(ctx, tostring(i))
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "Right-click to remove")
      end

      -- Right-click to remove
      if ImGui.BeginPopupContextItem(ctx, "preset_ctx_" .. i) then
        if ImGui.MenuItem(ctx, "Remove") then
          to_remove = i
        end
        ImGui.EndPopup(ctx)
      end

      -- Column 1: Label input
      ImGui.TableSetColumnIndex(ctx, 1)
      ImGui.SetNextItemWidth(ctx, -1)
      local changed_label, new_label = ImGui.InputText(ctx, "##label", preset.label or "")
      if changed_label then
        preset.label = new_label
      end

      -- Columns 2+: Parameter value controls
      for col_idx, param_name in ipairs(param_order) do
        ImGui.TableSetColumnIndex(ctx, 1 + col_idx)

        -- Get parameter info
        local param = view:get_param_by_name(param_name)
        if param then
          -- Initialize value if not set
          if preset.values[param_name] == nil then
            preset.values[param_name] = param.default or param.min or 0
          end

          -- Render control based on parameter type
          ImGui.SetNextItemWidth(ctx, -1)
          local changed = false
          local new_value = preset.values[param_name]

          if param.type == "toggle" then
            -- Checkbox for boolean
            local is_checked = (preset.values[param_name] ~= 0)
            local rv, new_checked = ImGui.Checkbox(ctx, "##" .. param_name, is_checked)
            if rv then
              changed = true
              new_value = new_checked and 1 or 0
            end

          elseif param.type == "spinner" then
            -- Combo box for enum
            local current_idx = math.floor(preset.values[param_name] - param.min + 1)
            local values = {}
            for v = param.min, param.max do
              table.insert(values, tostring(v))
            end

            local rv, new_idx = ImGui.Combo(ctx, "##" .. param_name, current_idx, table.concat(values, "\0") .. "\0")
            if rv then
              changed = true
              new_value = param.min + (new_idx - 1)
            end

          else
            -- InputDouble for int/float/slider
            local rv, new_val = ImGui.InputDouble(ctx, "##" .. param_name, preset.values[param_name])
            if rv then
              changed = true
              new_value = new_val
              -- Clamp to min/max
              if param.min and new_value < param.min then new_value = param.min end
              if param.max and new_value > param.max then new_value = param.max end
            end
          end

          if changed then
            preset.values[param_name] = new_value
          end
        end
      end

      ImGui.PopID(ctx)
    end

    -- Handle removal
    if to_remove then
      table.remove(state.preset_config.presets, to_remove)
    end

    ImGui.EndTable(ctx)
  end

  ImGui.Dummy(ctx, 0, 8)
  if ImGui.Button(ctx, "Add Preset", 120, 0) then
    -- Create new preset with default values for all parameters
    local new_preset = {
      label = "New Preset",
      values = {}
    }

    for _, param_name in ipairs(param_order) do
      local param = view:get_param_by_name(param_name)
      if param then
        new_preset.values[param_name] = param.default or param.min or 0
      end
    end

    table.insert(state.preset_config.presets, new_preset)
  end

  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "(Right-click row # to remove)")
end

--- Initialize default presets for a group (deprecated - now handled in load_group_preset_config)
function M.initialize_default_presets(state, group, view)
  -- Legacy function - no longer used
end

--- Apply group configuration to all templates in the group
function M.apply_group_config(group, state, view)
  -- Update group properties
  group.name = state.name
  group.color = state.color

  -- Store the FULL preset configuration on the group itself
  -- This is needed for the group macro control in Additional Parameters
  group.presets = state.preset_config.presets

  -- Also apply configuration to all templates in the group (for individual template usage)
  for _, template_id in ipairs(group.template_ids or {}) do
    local template = view.templates[template_id]
    if template then
      -- Update template type
      template.type = "preset_spinner"

      -- Convert multi-parameter preset format to per-template format
      -- Each template gets presets with values only for its own parameters
      template.config = {
        presets = {}
      }

      for _, preset in ipairs(state.preset_config.presets) do
        -- For each preset, extract only the values for this template's parameters
        local template_preset = {
          label = preset.label,
          values = {}
        }

        -- Copy values for parameters that belong to this template
        for _, param_name in ipairs(template.params or {}) do
          if preset.values[param_name] ~= nil then
            template_preset.values[param_name] = preset.values[param_name]
          end
        end

        table.insert(template.config.presets, template_preset)
      end
    end
  end

  -- Save changes
  view:save_templates()
end

--- Convert hex color string to ImGui color integer (0xRRGGBB)
function M.hex_to_color_int(hex)
  hex = hex:gsub("#", "")
  return tonumber(hex, 16)
end

--- Convert ImGui color integer (0xRRGGBB) to hex color string
function M.color_int_to_hex(color_int)
  return string.format("#%06X", color_int & 0xFFFFFF)
end

return M
