-- @noindex
-- arkitekt/gui/widgets/navigation/tree_view.lua
-- TreeView widget with arkitekt styling, inline rename, and folder icons

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Style = require('arkitekt.gui.style')
local Colors = require('arkitekt.core.colors')
local InputText = require('arkitekt.gui.widgets.primitives.inputtext')

local M = {}

-- Performance: Cache table functions for hot path
local concat = table.concat
local remove = table.remove

-- ============================================================================
-- TREE ARROW RENDERING
-- ============================================================================

local function draw_tree_arrow(ctx, dl, x, y, is_open)
  -- Custom arrow to overlay native ImGui arrow for better appearance
  -- Arrow size: 5x5 pixels
  local size = 5

  -- Round to whole pixels for crisp rendering
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1

  -- Slightly darker arrow color for better visibility
  local arrow_color = Colors.hexrgb("#B0B0B0FF")

  if is_open then
    -- Down-pointing triangle (opened folder)
    -- Points: top-left, top-right, bottom-center
    local x1, y1 = x, y
    local x2, y2 = x + size, y
    local x3, y3 = (x + size / 2 + 0.5) // 1, y + size  -- Round center point to whole pixel

    ImGui.DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, arrow_color)
  else
    -- Right-pointing triangle (closed folder)
    -- Points: left-top, left-bottom, right-center
    local x1, y1 = x, y
    local x2, y2 = x, y + size
    local x3, y3 = x + size, y + size / 2  -- Keep fractional for this arrow (was working fine)

    ImGui.DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, arrow_color)
  end
end

-- ============================================================================
-- FOLDER ICON RENDERING
-- ============================================================================

local function draw_folder_icon(ctx, dl, x, y, color)
  -- Folder icon: 13x7 main body with 5x2 tab on top left
  local main_w = 13
  local main_h = 7
  local tab_w = 5
  local tab_h = 2

  -- Round to whole pixels to avoid aliasing
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1

  local icon_color = color or Colors.hexrgb("#888888")

  -- Draw tab (5x2 rectangle on top left)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + tab_w, y + tab_h, icon_color, 0)

  -- Draw main body (13x7 rectangle)
  ImGui.DrawList_AddRectFilled(dl, x, y + tab_h, x + main_w, y + tab_h + main_h, icon_color, 0)

  return main_w + 4  -- Return width including spacing
end

local function draw_file_icon(ctx, dl, x, y, color)
  -- File icon: simple document/page shape (10x12 rectangle with folded corner)
  local main_w = 10
  local main_h = 12
  local fold_size = 3

  -- Round to whole pixels to avoid aliasing
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1

  local icon_color = color or Colors.hexrgb("#888888")

  -- Draw main document body (rectangle with cut corner)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + main_w - fold_size, y + main_h, icon_color, 0)
  ImGui.DrawList_AddRectFilled(dl, x, y + fold_size, x + main_w, y + main_h, icon_color, 0)

  -- Draw folded corner (small triangle in top-right)
  local corner_color = Colors.hexrgb("#555555")
  ImGui.DrawList_AddTriangleFilled(dl,
    x + main_w - fold_size, y + fold_size,  -- Bottom-left of triangle
    x + main_w, y + fold_size,              -- Bottom-right
    x + main_w - fold_size, y,              -- Top-left
    corner_color)

  return main_w + 4  -- Return width including spacing
end

local function draw_virtual_folder_icon(ctx, dl, x, y, color)
  -- Virtual folder icon: hollow folder with dotted outline
  local main_w = 13
  local main_h = 7
  local tab_w = 5
  local tab_h = 2

  -- Round to whole pixels to avoid aliasing
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1

  local icon_color = color or Colors.hexrgb("#888888")

  -- Draw hollow folder outline with thicker lines (2px) for visibility
  -- Tab outline
  ImGui.DrawList_AddRect(dl, x, y, x + tab_w, y + tab_h, icon_color, 0, 0, 2)

  -- Main body outline
  ImGui.DrawList_AddRect(dl, x, y + tab_h, x + main_w, y + tab_h + main_h, icon_color, 0, 0, 2)

  -- Draw small "V" inside to indicate virtual
  local v_color = Colors.with_alpha(icon_color, 0xFF)  -- Full opacity
  local v_x = x + 4
  local v_y = y + tab_h + 2
  local v_size = 4
  -- Left stroke
  ImGui.DrawList_AddLine(dl, v_x, v_y, v_x + v_size/2, v_y + v_size, v_color, 1.5)
  -- Right stroke
  ImGui.DrawList_AddLine(dl, v_x + v_size/2, v_y + v_size, v_x + v_size, v_y, v_color, 1.5)

  return main_w + 4  -- Return width including spacing
end

-- ============================================================================
-- TREE NODE RENDERING
-- ============================================================================

local _node_counter = 0

local function render_tree_node(ctx, node, config, state, depth)
  depth = depth or 0
  _node_counter = _node_counter + 1
  local node_id = node.id or node.path or tostring(_node_counter)

  ImGui.PushID(ctx, node_id)

  -- Determine if node is open
  local is_open = state.open_nodes and state.open_nodes[node_id]
  if is_open == nil then is_open = false end

  -- Check if node is selected (support both single and multi-select)
  local is_selected = false
  if state.selected_nodes then
    is_selected = state.selected_nodes[node_id] ~= nil
  elseif state.selected_node then
    is_selected = state.selected_node == node_id
  end

  -- Check if renaming
  local is_renaming = state.renaming_node == node_id

  -- Check if node has color
  local node_color = node.color

  -- Always draw tree node structure (even when renaming) to maintain proper layout
  -- Normal tree node display

    -- Tree node flags (same as original working implementation)
    local flags = ImGui.TreeNodeFlags_SpanAvailWidth | ImGui.TreeNodeFlags_DrawLinesFull

    -- Only allow expand/collapse by clicking arrow, not the whole item
    flags = flags | ImGui.TreeNodeFlags_OpenOnArrow

    -- DISABLED: Toggle on click behavior (keep for potential future use)
    -- flags = flags | ImGui.TreeNodeFlags_OpenOnDoubleClick  -- Would allow double-click to toggle

    if is_selected then
      flags = flags | ImGui.TreeNodeFlags_Selected
    end

    if not node.children or #node.children == 0 then
      flags = flags | ImGui.TreeNodeFlags_Leaf
    end

    -- Set open state before rendering
    if is_open then
      ImGui.SetNextItemOpen(ctx, true)
    end

    -- If renaming, allow InputText to overlap and take input priority
    if is_renaming then
      ImGui.SetNextItemAllowOverlap(ctx)
    end

    -- Use empty label and draw icon + text manually
    -- TreeNodeEx(ctx, str_id, label, flags) - need all 4 params!
    local node_open = ImGui.TreeNodeEx(ctx, node_id, "", flags)

    -- Get the item rect for the tree node (full width due to SpanAvailWidth flag)
    local tree_item_hovered = not is_renaming and ImGui.IsItemHovered(ctx)
    local tree_item_clicked = not is_renaming and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left)
    local tree_item_right_clicked = not is_renaming and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
    local tree_item_double_clicked = not is_renaming and tree_item_hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
    local tree_toggled = ImGui.IsItemToggledOpen(ctx)

    -- Get item rect for drawing overlays
    local item_min_x, item_min_y = ImGui.GetItemRectMin(ctx)
    local item_max_x, item_max_y = ImGui.GetItemRectMax(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)

    -- Draw hover effect (subtle for all items)
    if tree_item_hovered and not is_selected then
      local hover_color = Colors.hexrgb("#FFFFFF08")  -- 3% opacity white
      ImGui.DrawList_AddRectFilled(dl, item_min_x, item_min_y, item_max_x, item_max_y, hover_color, 0)
    end

    -- Draw selection indicator
    if is_selected then
      local selection_bar_width = 3
      local selection_color = Colors.hexrgb("#FFFFFFFF")  -- White accent bar
      local selection_bg = Colors.hexrgb("#FFFFFF15")  -- Light grey/white background

      -- Draw left edge white accent bar
      ImGui.DrawList_AddRectFilled(dl, item_min_x, item_min_y, item_min_x + selection_bar_width, item_max_y, selection_color, 0)
      -- Draw background
      ImGui.DrawList_AddRectFilled(dl, item_min_x, item_min_y, item_max_x, item_max_y, selection_bg, 0)
    end

    -- Now manually draw the folder icon and text (since label is empty)
    -- Calculate positions (after the arrow/indent)
    local arrow_width = ImGui.GetTreeNodeToLabelSpacing(ctx)
    local icon_x = item_min_x + arrow_width
    local text_y_offset = (ImGui.GetTextLineHeight(ctx) - 9) * 0.5  -- Center icon vertically (9 = tab_h + main_h)
    local icon_y = item_min_y + text_y_offset

    -- Draw custom arrow overlay (only for non-leaf nodes)
    if node.children and #node.children > 0 then
      -- Arrow position: centered in the arrow_width space, slightly to the right of the left edge
      local arrow_x = item_min_x + (arrow_width / 2) - 2.5  -- Center horizontally in arrow space
      local arrow_y = item_min_y + (item_max_y - item_min_y) / 2 - 2.5  -- Center vertically
      -- Round arrow_y to whole pixel to avoid aliasing
      arrow_y = (arrow_y + 0.5) // 1
      draw_tree_arrow(ctx, dl, arrow_x, arrow_y, is_open)
    end

    -- Draw icon (file, virtual folder, or physical folder)
    local icon_width
    if node.is_file then
      icon_width = draw_file_icon(ctx, dl, icon_x, icon_y, node_color)
    elseif node.is_virtual then
      icon_width = draw_virtual_folder_icon(ctx, dl, icon_x, icon_y, node_color)
    else
      icon_width = draw_folder_icon(ctx, dl, icon_x, icon_y, node_color)
    end

    -- Calculate text position
    local text_x = icon_x + icon_width
    local text_y = item_min_y

    -- If renaming, show input field inline instead of text
    if is_renaming then
      -- Save current cursor to restore later
      local saved_cursor_x, saved_cursor_y = ImGui.GetCursorScreenPos(ctx)

      -- Position using absolute screen coordinates
      ImGui.SetCursorScreenPos(ctx, text_x, item_min_y)

      -- Style: lighter background for input field
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, Colors.hexrgb("#FFFFFF15"))
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, Colors.hexrgb("#FFFFFF20"))
      ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, Colors.hexrgb("#FFFFFF25"))

      -- Auto-focus and select all text on first show
      if not state.rename_focus_set then
        ImGui.SetKeyboardFocusHere(ctx, 0)
        state.rename_focus_set = true
      end

      -- Input field width: from text position to right edge minus padding
      ImGui.SetNextItemWidth(ctx, item_max_x - text_x - 8)
      local rv, buf = ImGui.InputText(ctx, "##rename_" .. node_id, state.rename_buffer, ImGui.InputTextFlags_AutoSelectAll)

      if rv then
        state.rename_buffer = buf
      end

      ImGui.PopStyleColor(ctx, 3)

      -- Check input state before restoring cursor
      local input_active = ImGui.IsItemActive(ctx)
      local input_hovered = ImGui.IsItemHovered(ctx)

      -- Restore cursor position to maintain tree layout
      ImGui.SetCursorScreenPos(ctx, saved_cursor_x, saved_cursor_y)

      -- Store input state for global click-away check
      state.rename_input_active = input_active
      state.rename_input_hovered = input_hovered

      -- Commit on Enter
      if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter) then
        if state.rename_buffer ~= "" and state.rename_buffer ~= node.name then
          if config.on_rename then
            config.on_rename(node, state.rename_buffer)
          end
        end
        state.renaming_node = nil
        state.rename_buffer = ""
        state.rename_focus_set = nil
      end

      -- Cancel on Escape or lost focus
      if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        state.renaming_node = nil
        state.rename_buffer = ""
        state.rename_focus_set = nil
      end
    else
      -- Draw text label after icon (normal display)
      -- Use node color for text if available, otherwise white
      local text_color
      if node_color and config.show_colors then
        -- Make text much lighter by lerping toward white (preserves hue)
        text_color = Colors.lerp(node_color, Colors.hexrgb("#FFFFFFFF"), 0.7)  -- 70% toward white
      else
        text_color = Colors.hexrgb("#FFFFFFFF")  -- Default white text
      end
      ImGui.DrawList_AddText(dl, text_x, text_y, text_color, node.name)

      -- Draw template count if available (right-aligned)
      if node.template_count and node.template_count > 0 and config.show_template_count then
        local count_text = "(" .. node.template_count .. ")"
        local count_w = ImGui.CalcTextSize(ctx, count_text)
        local count_x = item_max_x - count_w - 8  -- 8px padding from right edge
        local count_y = item_min_y
        local count_color = Colors.hexrgb("#808080FF")  -- Gray
        ImGui.DrawList_AddText(dl, count_x, count_y, count_color, count_text)
      end
    end

    -- Handle click for selection (but not when renaming)
    if tree_item_clicked and not tree_toggled and not is_renaming then
      local ctrl_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
      local shift_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)

      if config.enable_multi_select and state.selected_nodes then
        -- Multi-select mode
        if shift_down and state.last_clicked_node then
          -- Range selection: select all nodes between last clicked and current
          if not state._flat_node_list then
            state._flat_node_list = {}
          end

          local start_idx, end_idx
          for i, flat_node_id in ipairs(state._flat_node_list) do
            if flat_node_id == state.last_clicked_node then
              start_idx = i
            end
            if flat_node_id == node_id then
              end_idx = i
            end
          end

          if start_idx and end_idx then
            if start_idx > end_idx then
              start_idx, end_idx = end_idx, start_idx
            end

            -- Clear selection if not holding ctrl
            if not ctrl_down then
              state.selected_nodes = {}
            end

            -- Select range
            for i = start_idx, end_idx do
              state.selected_nodes[state._flat_node_list[i]] = true
            end
          end
        elseif ctrl_down then
          -- Toggle selection
          if state.selected_nodes[node_id] then
            state.selected_nodes[node_id] = nil
          else
            state.selected_nodes[node_id] = true
          end
          state.last_clicked_node = node_id
        else
          -- Normal click without modifiers
          -- If clicking on an already-selected item, don't clear the selection
          -- This allows dragging multiple selected items
          if not state.selected_nodes[node_id] then
            -- Only clear selection if clicking on a non-selected item
            state.selected_nodes = {}
          end
          state.selected_nodes[node_id] = true
          state.last_clicked_node = node_id
        end

        if config.on_select then
          config.on_select(node, state.selected_nodes)
        end
      else
        -- Single select mode (backward compatibility)
        state.selected_node = node_id
        if config.on_select then
          config.on_select(node)
        end
      end
    end

    -- Track open state
    if state.open_nodes then
      state.open_nodes[node_id] = node_open
    end

    -- Handle F2 key to start rename when this node is selected
    if is_selected and config.enable_rename and ImGui.IsKeyPressed(ctx, ImGui.Key_F2) and not is_renaming then
      -- Check if this specific node can be renamed
      local can_rename = true
      if config.can_rename then
        can_rename = config.can_rename(node)
      end
      if can_rename then
        state.renaming_node = node_id
        state.rename_buffer = node.name
      end
    end

    -- Handle Delete key to delete folder when selected
    if is_selected and ImGui.IsKeyPressed(ctx, ImGui.Key_Delete) and not is_renaming then
      if config.on_delete then
        config.on_delete(node)
      end
    end

    -- Handle double-click (rename by default if enabled)
    if tree_item_double_clicked and not is_renaming then
      if config.enable_rename then
        -- Check if this specific node can be renamed
        local can_rename = true
        if config.can_rename then
          can_rename = config.can_rename(node)
        end
        if can_rename then
          state.renaming_node = node_id
          state.rename_buffer = node.name
        end
      end
      if config.on_double_click then
        config.on_double_click(node)
      end
    end

    -- Handle right-click context menu (but not when renaming)
    if not is_renaming and config.context_menu_id then
      -- Use OpenPopupOnItemClick for proper right-click handling
      ImGui.OpenPopupOnItemClick(ctx, config.context_menu_id, ImGui.PopupFlags_MouseButtonRight)

      -- Notify callback that this node was right-clicked (for setting state)
      if ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Right) and tree_item_hovered then
        if config.on_right_click then
          config.on_right_click(node)
        end
      end

      -- Render context menu if callback provided
      if config.render_context_menu then
        config.render_context_menu(ctx, node)
      end
    end

    -- Drag-drop source (for dragging folders)
    if config.enable_drag_drop and ImGui.BeginDragDropSource(ctx) then
      -- Support multi-drag: if this node is selected and multi-select is enabled
      local drag_payload = node_id
      local drag_label = "Move: " .. node.name

      if config.enable_multi_select and state.selected_nodes then
        -- Check if this node is selected
        local is_node_selected = state.selected_nodes[node_id] ~= nil

        -- Count selected nodes and collect their IDs
        local selected_ids = {}
        local count = 0
        for id, _ in pairs(state.selected_nodes) do
          count = count + 1
          selected_ids[count] = id
        end

        if is_node_selected and count > 1 then
          -- Encode multiple node IDs (newline-separated)
          drag_payload = concat(selected_ids, "\n")
          drag_label = "Move: " .. count .. " folders"
        end
      end

      ImGui.SetDragDropPayload(ctx, "TREENODE_FOLDER", drag_payload)
      ImGui.Text(ctx, drag_label)
      ImGui.EndDragDropSource(ctx)
    end

    -- Drag-drop target (for receiving folders and templates)
    if config.enable_drag_drop and ImGui.BeginDragDropTarget(ctx) then
      -- Accept folder drops
      local accepted_folder, folder_payload = ImGui.AcceptDragDropPayload(ctx, "TREENODE_FOLDER")
      if accepted_folder and folder_payload and config.on_drop_folder then
        config.on_drop_folder(folder_payload, node)
      end

      -- Accept template drops
      local accepted_template, template_payload = ImGui.AcceptDragDropPayload(ctx, "TEMPLATE")
      if accepted_template and template_payload and config.on_drop_template then
        config.on_drop_template(template_payload, node)
      end

      ImGui.EndDragDropTarget(ctx)
    end

    -- Render children if node is open
    if node_open then
      if node.children and #node.children > 0 then
        for _, child in ipairs(node.children) do
          render_tree_node(ctx, child, config, state, depth + 1)
        end
      end
      ImGui.TreePop(ctx)
    end

  ImGui.PopID(ctx)
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Build flat list of all node IDs (for range selection)
local function build_flat_node_list(nodes, flat_list)
  flat_list = flat_list or {}
  for _, node in ipairs(nodes) do
    _node_counter = _node_counter + 1
    local node_id = node.id or node.path or tostring(_node_counter)
    flat_list[#flat_list + 1] = node_id
    if node.children and #node.children > 0 then
      build_flat_node_list(node.children, flat_list)
    end
  end
  return flat_list
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Draw tree view
-- @param ctx ImGui context
-- @param nodes Table of root nodes: { { id, name, children = {...}, color = 0xRRGGBBAA }, ... }
-- @param state Table with open_nodes, selected_node, renaming_node, rename_buffer
-- @param user_config Optional configuration table
function M.draw(ctx, nodes, state, user_config)
  if not nodes or #nodes == 0 then return end

  local config = user_config or {}

  -- Ensure state tables exist
  if not state.open_nodes then
    state.open_nodes = {}
  end

  -- Apply default config
  config.enable_rename = config.enable_rename ~= false  -- default true
  config.show_colors = config.show_colors ~= false      -- default true

  -- Build flat node list for range selection (if multi-select enabled)
  if config.enable_multi_select then
    _node_counter = 0
    state._flat_node_list = build_flat_node_list(nodes)
  end

  -- Reset counter for consistent IDs
  _node_counter = 0

  -- Render all root nodes
  for _, node in ipairs(nodes) do
    render_tree_node(ctx, node, config, state, 0)
  end

  -- Global click-away check for inline rename
  -- Check AFTER all nodes are rendered to catch clicks anywhere (including below tree)
  -- Only check if InputText has been shown at least once (prevents canceling on the frame rename starts)
  if state.renaming_node and state.rename_focus_set then
    local input_active = state.rename_input_active or false
    local input_hovered = state.rename_input_hovered or false

    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not input_active and not input_hovered then
      -- Cancel rename if clicked anywhere outside the InputText
      state.renaming_node = nil
      state.rename_buffer = ""
      state.rename_focus_set = nil
      state.rename_input_active = nil
      state.rename_input_hovered = nil
    end
  end
end

--- Start renaming a node
-- @param state State table
-- @param node_id Node ID to rename
-- @param current_name Current node name
function M.start_rename(state, node_id, current_name)
  state.renaming_node = node_id
  state.rename_buffer = current_name or ""
end

--- Cancel current rename operation
-- @param state State table
function M.cancel_rename(state)
  state.renaming_node = nil
  state.rename_buffer = ""
end

--- Find node by ID in tree
-- @param nodes Root nodes
-- @param node_id Node ID to find
-- @return node or nil
function M.find_node(nodes, node_id)
  local function search(nodes_list)
    for _, node in ipairs(nodes_list) do
      local id = node.id or node.path or node.name
      if id == node_id then
        return node
      end
      if node.children then
        local found = search(node.children)
        if found then return found end
      end
    end
    return nil
  end
  return search(nodes)
end

--- Expand all nodes in path to target node
-- @param nodes Root nodes
-- @param node_id Target node ID
-- @param state State table
function M.expand_to_node(nodes, node_id, state)
  if not state.open_nodes then
    state.open_nodes = {}
  end

  local function find_path(nodes_list, target_id, path)
    path = path or {}
    for _, node in ipairs(nodes_list) do
      local id = node.id or node.path or node.name
      if id == target_id then
        -- Found it - expand all in path
        for _, parent_id in ipairs(path) do
          state.open_nodes[parent_id] = true
        end
        return true
      end
      if node.children then
        path[#path + 1] = id
        if find_path(node.children, target_id, path) then
          return true
        end
        remove(path)
      end
    end
    return false
  end

  find_path(nodes, node_id)
end

--- Collapse all nodes
-- @param state State table
function M.collapse_all(state)
  if state.open_nodes then
    state.open_nodes = {}
  end
end

--- Expand all nodes
-- @param nodes Root nodes
-- @param state State table
function M.expand_all(nodes, state)
  if not state.open_nodes then
    state.open_nodes = {}
  end

  local function expand_recursive(nodes_list)
    for _, node in ipairs(nodes_list) do
      local id = node.id or node.path or node.name
      state.open_nodes[id] = true
      if node.children then
        expand_recursive(node.children)
      end
    end
  end

  expand_recursive(nodes)
end

return M
