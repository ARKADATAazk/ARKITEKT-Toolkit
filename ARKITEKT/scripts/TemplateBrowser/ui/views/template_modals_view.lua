-- @noindex
-- TemplateBrowser/ui/views/template_modals_view.lua
-- Template Browser modals and context menus

local ImGui = require('arkitekt.platform.imgui')
local Ark = require('arkitekt')
local FileOps = require('TemplateBrowser.data.file_ops')
local Chip = require('arkitekt.gui.widgets.data.chip')
local ColorDefs = require('arkitekt.defs.colors')
local UI = require('TemplateBrowser.ui.config.constants')

local M = {}

-- Color preset palette from centralized colors
local PRESET_COLORS = {}
for i, color in ipairs(ColorDefs.PALETTE) do
  PRESET_COLORS[i] = Ark.Colors.hexrgb(color.hex)
end

-- Draw template context menu (color picker)
function M.draw_template_context_menu(ctx, state)
  -- Context menu with color picker (MUST be outside BeginChild for popups to work)
  if state.context_menu_template then
    ImGui.OpenPopup(ctx, "template_color_picker")
  end

  if ImGui.BeginPopup(ctx, "template_color_picker") then
    local tmpl = state.context_menu_template
    if tmpl then
      ImGui.Text(ctx, "Set Template Color")
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- Get template metadata
      local tmpl_metadata = state.metadata and state.metadata.templates[tmpl.uuid]
      local current_color = tmpl_metadata and tmpl_metadata.chip_color or nil

      -- Draw 4x4 color grid
      local grid_cols = UI.COLOR_PICKER.GRID_COLS
      local chip_size = UI.COLOR_PICKER.CHIP_SIZE
      local chip_radius = chip_size / 2

      for idx, color in ipairs(PRESET_COLORS) do
        local col_idx = (idx - 1) % grid_cols

        if col_idx > 0 then
          ImGui.SameLine(ctx)
        end

        -- Position for color button
        local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

        -- Clickable area
        if ImGui.InvisibleButton(ctx, "##color_" .. idx, chip_size, chip_size) then
          -- Set color
          if tmpl_metadata then
            tmpl_metadata.chip_color = color
            local Persistence = require('TemplateBrowser.data.storage')
            Persistence.save_metadata(state.metadata)
          end
          state.context_menu_template = nil
          ImGui.CloseCurrentPopup(ctx)
        end

        local is_hovered = ImGui.IsItemHovered(ctx)
        local is_this_color = (current_color == color)

        -- Draw chip
        local chip_x = start_x + chip_radius
        local chip_y = start_y + chip_radius
        Chip.draw(ctx, {
          style = Chip.STYLE.INDICATOR,
          x = chip_x,
          y = chip_y,
          radius = chip_radius - 2,
          color = color,
          is_selected = is_this_color,
          is_hovered = is_hovered,
          show_glow = is_this_color or is_hovered,
          glow_layers = is_this_color and 6 or 3,
        })
      end

      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- Remove color button
      if Ark.Button.draw_at_cursor(ctx, {
        label = "Remove Color",
        width = -1,
        height = UI.BUTTON.HEIGHT_DEFAULT
      }, "remove_color") then
        if tmpl_metadata then
          tmpl_metadata.chip_color = nil
          local Persistence = require('TemplateBrowser.data.storage')
          Persistence.save_metadata(state.metadata)
        end
        state.context_menu_template = nil
        ImGui.CloseCurrentPopup(ctx)
      end

      -- Add "Remove from Virtual Folder" button if viewing a virtual folder
      if state.selected_folder and state.selected_folder ~= "" and state.metadata then
        local vfolder = state.metadata.virtual_folders and state.metadata.virtual_folders[state.selected_folder]
        if vfolder and tmpl then
          ImGui.Spacing(ctx)
          ImGui.Separator(ctx)
          ImGui.Spacing(ctx)

          if Ark.Button.draw_at_cursor(ctx, {
            label = "Remove from " .. vfolder.name,
            width = -1,
            height = UI.BUTTON.HEIGHT_DEFAULT
          }, "remove_from_vfolder") then
            local Persistence = require('TemplateBrowser.data.storage')

            -- Remove template UUID from virtual folder's template_refs
            if vfolder.template_refs then
              for i, ref_uuid in ipairs(vfolder.template_refs) do
                if ref_uuid == tmpl.uuid then
                  table.remove(vfolder.template_refs, i)
                  break
                end
              end
            end

            -- Save metadata
            Persistence.save_metadata(state.metadata)

            -- Refresh filtered templates
            local Scanner = require('TemplateBrowser.domain.template.scanner')
            Scanner.filter_templates(state)

            state.set_status("Removed " .. tmpl.name .. " from " .. vfolder.name, "success")
            state.context_menu_template = nil
            ImGui.CloseCurrentPopup(ctx)
          end
        end
      end
    end

    ImGui.EndPopup(ctx)
  end
end

-- Draw template rename modal
function M.draw_template_rename_modal(ctx, state)
  -- Rename modal popup (for F2 or Ctrl+double-click)
  if state.renaming_item and state.renaming_type == "template" then
    ImGui.OpenPopup(ctx, "Rename Template")
  end

  if ImGui.BeginPopupModal(ctx, "Rename Template", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    local tmpl = state.renaming_item

    ImGui.Text(ctx, "Current name: " .. (tmpl and tmpl.name or ""))
    ImGui.Spacing(ctx)

    -- Initialize field with current name
    if Ark.InputText.get_text("template_rename_modal") == "" then
      Ark.InputText.set_text("template_rename_modal", state.rename_buffer)
    end

    local changed, new_name = Ark.InputText.draw_at_cursor(ctx, {
      width = UI.FIELD.RENAME_WIDTH,
      height = UI.FIELD.RENAME_HEIGHT,
      text = state.rename_buffer,
    }, "template_rename_modal")

    if changed then
      state.rename_buffer = new_name
    end

    -- Auto-focus input on first frame
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx, -1)
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Buttons
    local ok_clicked = Ark.Button.draw_at_cursor(ctx, {
      label = "OK",
      width = 140,
      height = UI.BUTTON.HEIGHT_DEFAULT
    }, "rename_ok")
    if ok_clicked or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
      if state.rename_buffer ~= "" and state.rename_buffer ~= tmpl.name then
        local old_path = tmpl.path
        local success, new_path = FileOps.rename_template(tmpl.path, state.rename_buffer)
        if success then
          -- Create undo operation
          state.undo_manager:push({
            description = "Rename template: " .. tmpl.name .. " -> " .. state.rename_buffer,
            undo_fn = function()
              local undo_success = FileOps.rename_template(new_path, tmpl.name)
              if undo_success then
                local Scanner = require('TemplateBrowser.domain.template.scanner')
                Scanner.scan_templates(state)
              end
              return undo_success
            end,
            redo_fn = function()
              local redo_success = FileOps.rename_template(old_path, state.rename_buffer)
              if redo_success then
                local Scanner = require('TemplateBrowser.domain.template.scanner')
                Scanner.scan_templates(state)
              end
              return redo_success
            end
          })

          local Scanner = require('TemplateBrowser.domain.template.scanner')
          Scanner.scan_templates(state)
        end
      end
      state.renaming_item = nil
      state.renaming_type = nil
      state.rename_buffer = ""
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.SameLine(ctx)
    local cancel_clicked = Ark.Button.draw_at_cursor(ctx, {
      label = "Cancel",
      width = 140,
      height = UI.BUTTON.HEIGHT_DEFAULT
    }, "rename_cancel")
    if cancel_clicked or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      state.renaming_item = nil
      state.renaming_type = nil
      state.rename_buffer = ""
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

-- Draw tag context menu (color picker)
function M.draw_tag_context_menu(ctx, state)
  -- Context menu with color picker for tags
  if state.context_menu_tag then
    ImGui.OpenPopup(ctx, "tag_color_picker")
  end

  if ImGui.BeginPopup(ctx, "tag_color_picker") then
    local tag_name = state.context_menu_tag
    if tag_name and state.metadata and state.metadata.tags[tag_name] then
      local tag_data = state.metadata.tags[tag_name]

      ImGui.Text(ctx, "Set Tag Color: " .. tag_name)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      local current_color = tag_data.color

      -- Draw color grid
      local grid_cols = UI.COLOR_PICKER.GRID_COLS
      local chip_size = UI.COLOR_PICKER.CHIP_SIZE
      local chip_radius = chip_size / 2

      for idx, color in ipairs(PRESET_COLORS) do
        local col_idx = (idx - 1) % grid_cols

        if col_idx > 0 then
          ImGui.SameLine(ctx)
        end

        local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

        if ImGui.InvisibleButton(ctx, "##tag_color_" .. idx, chip_size, chip_size) then
          tag_data.color = color
          local Persistence = require('TemplateBrowser.data.storage')
          Persistence.save_metadata(state.metadata)
          state.context_menu_tag = nil
          ImGui.CloseCurrentPopup(ctx)
        end

        local is_hovered = ImGui.IsItemHovered(ctx)
        local is_this_color = (current_color == color)

        local chip_x = start_x + chip_radius
        local chip_y = start_y + chip_radius
        Chip.draw(ctx, {
          style = Chip.STYLE.INDICATOR,
          x = chip_x,
          y = chip_y,
          radius = chip_radius - 2,
          color = color,
          is_selected = is_this_color,
          is_hovered = is_hovered,
          show_glow = is_this_color or is_hovered,
          glow_layers = is_this_color and 6 or 3,
        })
      end

      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- Reset to default (dark grey)
      if Ark.Button.draw_at_cursor(ctx, {
        label = "Reset to Default",
        width = -1,
        height = UI.BUTTON.HEIGHT_DEFAULT
      }, "tag_reset_color") then
        tag_data.color = Ark.Colors.hexrgb("#646464")
        local Persistence = require('TemplateBrowser.data.storage')
        Persistence.save_metadata(state.metadata)
        state.context_menu_tag = nil
        ImGui.CloseCurrentPopup(ctx)
      end
    end

    ImGui.EndPopup(ctx)
  end
end

-- Draw VST context menu (color picker)
function M.draw_vst_context_menu(ctx, state)
  -- Context menu with color picker for VSTs
  if state.context_menu_vst then
    ImGui.OpenPopup(ctx, "vst_color_picker")
  end

  if ImGui.BeginPopup(ctx, "vst_color_picker") then
    local vst_name = state.context_menu_vst
    if vst_name then
      ImGui.Text(ctx, "Set VST Color: " .. vst_name)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- Ensure vsts metadata exists
      if not state.metadata.vsts then
        state.metadata.vsts = {}
      end
      if not state.metadata.vsts[vst_name] then
        state.metadata.vsts[vst_name] = {}
      end

      local vst_data = state.metadata.vsts[vst_name]
      local current_color = vst_data.color

      -- Draw color grid
      local grid_cols = UI.COLOR_PICKER.GRID_COLS
      local chip_size = UI.COLOR_PICKER.CHIP_SIZE
      local chip_radius = chip_size / 2

      for idx, color in ipairs(PRESET_COLORS) do
        local col_idx = (idx - 1) % grid_cols

        if col_idx > 0 then
          ImGui.SameLine(ctx)
        end

        local start_x, start_y = ImGui.GetCursorScreenPos(ctx)

        if ImGui.InvisibleButton(ctx, "##vst_color_" .. idx, chip_size, chip_size) then
          vst_data.color = color
          local Persistence = require('TemplateBrowser.data.storage')
          Persistence.save_metadata(state.metadata)
          state.context_menu_vst = nil
          ImGui.CloseCurrentPopup(ctx)
        end

        local is_hovered = ImGui.IsItemHovered(ctx)
        local is_this_color = (current_color == color)

        local chip_x = start_x + chip_radius
        local chip_y = start_y + chip_radius
        Chip.draw(ctx, {
          style = Chip.STYLE.INDICATOR,
          x = chip_x,
          y = chip_y,
          radius = chip_radius - 2,
          color = color,
          is_selected = is_this_color,
          is_hovered = is_hovered,
          show_glow = is_this_color or is_hovered,
          glow_layers = is_this_color and 6 or 3,
        })
      end

      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- Reset to default (dark grey)
      if Ark.Button.draw_at_cursor(ctx, {
        label = "Reset to Default",
        width = -1,
        height = UI.BUTTON.HEIGHT_DEFAULT
      }, "vst_reset_color") then
        vst_data.color = nil
        local Persistence = require('TemplateBrowser.data.storage')
        Persistence.save_metadata(state.metadata)
        state.context_menu_vst = nil
        ImGui.CloseCurrentPopup(ctx)
      end
    end

    ImGui.EndPopup(ctx)
  end
end

-- Draw conflict resolution modal
function M.draw_conflict_resolution_modal(ctx, state)
  -- Show conflict modal when conflict is pending
  if state.conflict_pending then
    ImGui.OpenPopup(ctx, "File Conflict")
  end

  if ImGui.BeginPopupModal(ctx, "File Conflict", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    local conflict = state.conflict_pending

    if conflict then
      ImGui.Text(ctx, "A file with the same name already exists in the target folder.")
      ImGui.Spacing(ctx)

      -- Show conflict details
      if #conflict.templates == 1 then
        ImGui.Text(ctx, string.format("File: %s", conflict.templates[1].name))
      else
        ImGui.Text(ctx, string.format("Files: %d templates", #conflict.templates))
      end

      ImGui.Text(ctx, string.format("Target: %s", conflict.target_folder.name or "Root"))

      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      ImGui.Text(ctx, "What would you like to do?")
      ImGui.Spacing(ctx)

      -- Overwrite button
      local overwrite_clicked = Ark.Button.draw_at_cursor(ctx, {
        label = "Overwrite (Archives existing)",
        width = UI.MODAL.CONFLICT_WIDTH,
        height = UI.BUTTON.HEIGHT_MODAL
      }, "conflict_overwrite")

      if overwrite_clicked then
        state.conflict_resolution = "overwrite"
        ImGui.CloseCurrentPopup(ctx)
      end

      ImGui.Spacing(ctx)

      -- Keep Both button
      local keep_both_clicked = Ark.Button.draw_at_cursor(ctx, {
        label = "Keep Both (Rename new)",
        width = UI.MODAL.CONFLICT_WIDTH,
        height = UI.BUTTON.HEIGHT_MODAL
      }, "conflict_keep_both")

      if keep_both_clicked then
        state.conflict_resolution = "keep_both"
        ImGui.CloseCurrentPopup(ctx)
      end

      ImGui.Spacing(ctx)

      -- Cancel button
      local cancel_clicked = Ark.Button.draw_at_cursor(ctx, {
        label = "Cancel",
        width = UI.MODAL.CONFLICT_WIDTH,
        height = UI.BUTTON.HEIGHT_MODAL
      }, "conflict_cancel")

      if cancel_clicked or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        state.conflict_resolution = "cancel"
        state.conflict_pending = nil  -- Clear pending conflict
        ImGui.CloseCurrentPopup(ctx)
      end
    end

    ImGui.EndPopup(ctx)
  end
end

-- Draw save template modal
function M.draw_save_template_modal(ctx, state)
  -- Save template modal (for Ctrl+S shortcut)
  if state.saving_template then
    ImGui.OpenPopup(ctx, "Save Template")
  end

  if ImGui.BeginPopupModal(ctx, "Save Template", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Save selected track(s) as template")
    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Template name input
    ImGui.Text(ctx, "Template Name:")
    ImGui.SetNextItemWidth(ctx, UI.FIELD.RENAME_WIDTH)

    -- Initialize field if empty
    if Ark.InputText.get_text("save_template_name") == "" and state.save_template_buffer == "" then
      -- Try to get current selected track name as default
      local track = reaper.GetSelectedTrack(0, 0)
      if track then
        local _, track_name = reaper.GetTrackName(track)
        state.save_template_buffer = track_name ~= "" and track_name or "New Template"
        Ark.InputText.set_text("save_template_name", state.save_template_buffer)
      else
        state.save_template_buffer = "New Template"
        Ark.InputText.set_text("save_template_name", state.save_template_buffer)
      end
    end

    local changed, new_name = Ark.InputText.draw_at_cursor(ctx, {
      width = UI.FIELD.RENAME_WIDTH,
      height = UI.FIELD.RENAME_HEIGHT,
      text = state.save_template_buffer,
    }, "save_template_name")

    if changed then
      state.save_template_buffer = new_name
    end

    -- Auto-focus input on first frame
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx, -1)
    end

    ImGui.Spacing(ctx)

    -- Folder path input (optional)
    ImGui.Text(ctx, "Subfolder (optional):")
    ImGui.SetNextItemWidth(ctx, UI.FIELD.RENAME_WIDTH)

    local folder_changed, new_folder = Ark.InputText.draw_at_cursor(ctx, {
      width = UI.FIELD.RENAME_WIDTH,
      height = UI.FIELD.RENAME_HEIGHT,
      text = state.save_template_folder or "",
      placeholder = "e.g., Drums/Kicks",
    }, "save_template_folder")

    if folder_changed then
      state.save_template_folder = new_folder
    end

    ImGui.Spacing(ctx)

    -- Options checkboxes
    ImGui.Text(ctx, "Options:")
    ImGui.Spacing(ctx)

    local include_items_changed, include_items = ImGui.Checkbox(ctx, "Include Media Items", state.save_template_include_items or false)
    if include_items_changed then
      state.save_template_include_items = include_items
    end

    local include_envelopes_changed, include_envelopes = ImGui.Checkbox(ctx, "Include Automation Envelopes",
      state.save_template_include_envelopes == nil and true or state.save_template_include_envelopes)
    if include_envelopes_changed then
      state.save_template_include_envelopes = include_envelopes
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Buttons
    local ok_clicked = Ark.Button.draw_at_cursor(ctx, {
      label = "Save",
      width = 140,
      height = UI.BUTTON.HEIGHT_DEFAULT
    }, "save_template_ok")

    if ok_clicked or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
      if state.save_template_buffer ~= "" then
        local Operations = require('TemplateBrowser.domain.template.operations')
        local success, result = Operations.save_template({
          name = state.save_template_buffer,
          folder = state.save_template_folder,
          include_items = state.save_template_include_items or false,
          include_envelopes = state.save_template_include_envelopes == nil and true or state.save_template_include_envelopes,
        }, state)

        if success then
          -- Rescan templates to show the new one
          local Scanner = require('TemplateBrowser.domain.template.scanner')
          Scanner.scan_templates(state)
        end
      end

      -- Reset state
      state.saving_template = false
      state.save_template_buffer = ""
      state.save_template_folder = ""
      state.save_template_include_items = false
      state.save_template_include_envelopes = true
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.SameLine(ctx)
    local cancel_clicked = Ark.Button.draw_at_cursor(ctx, {
      label = "Cancel",
      width = 140,
      height = UI.BUTTON.HEIGHT_DEFAULT
    }, "save_template_cancel")

    if cancel_clicked or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      -- Reset state
      state.saving_template = false
      state.save_template_buffer = ""
      state.save_template_folder = ""
      state.save_template_include_items = false
      state.save_template_include_envelopes = true
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

return M
