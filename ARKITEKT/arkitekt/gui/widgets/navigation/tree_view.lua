-- @noindex
-- arkitekt/gui/widgets/navigation/tree_view.lua
-- TreeView widget with ImGui-style hidden state API
-- Supports inline rename, multi-select, drag-drop, and folder icons

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'
local Theme = require('arkitekt.core.theme')
local Colors = require('arkitekt.core.colors')
local Base = require('arkitekt.gui.widgets.base')
local Logger = require('arkitekt.debug.logger')

local M = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local STALE_THRESHOLD = 30.0  -- Seconds before state is cleaned up

-- ============================================================================
-- HIDDEN STATE MANAGEMENT (ID-keyed, auto-cleanup after 30s)
-- ============================================================================

-- Strong tables required - weak tables cause flickering due to inter-frame GC
local tree_states = {}
local access_times = {}
local last_cleanup_time = 0
local CLEANUP_INTERVAL = 60.0

-- Deprecation warning tracking (warn once per ID)
local deprecation_warned = {}

local function get_tree_state(id)
  if not tree_states[id] then
    tree_states[id] = {
      open_nodes = {},
      selected_nodes = {},
      last_clicked_node = nil,
      renaming_node = nil,
      rename_buffer = "",
      rename_focus_set = nil,
      rename_input_active = nil,
      rename_input_hovered = nil,
      _flat_node_list = {},
    }
  end
  access_times[id] = reaper.time_precise()
  return tree_states[id]
end

local function cleanup_stale_states()
  local now = reaper.time_precise()
  if now - last_cleanup_time < CLEANUP_INTERVAL then
    return
  end
  last_cleanup_time = now

  for id, last_access in pairs(access_times) do
    if now - last_access > STALE_THRESHOLD then
      tree_states[id] = nil
      access_times[id] = nil
    end
  end
end

-- ============================================================================
-- TREE ARROW RENDERING
-- ============================================================================

local function draw_tree_arrow(ctx, dl, x, y, is_open)
  local size = 5
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1
  local arrow_color = Colors.hexrgb("#B0B0B0FF")

  if is_open then
    local x1, y1 = x, y
    local x2, y2 = x + size, y
    local x3, y3 = (x + size / 2 + 0.5) // 1, y + size
    ImGui.DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, arrow_color)
  else
    local x1, y1 = x, y
    local x2, y2 = x, y + size
    local x3, y3 = x + size, y + size / 2
    ImGui.DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, arrow_color)
  end
end

-- ============================================================================
-- FOLDER ICON RENDERING
-- ============================================================================

local function draw_folder_icon(ctx, dl, x, y, color)
  local main_w = 13
  local main_h = 7
  local tab_w = 5
  local tab_h = 2
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1
  local icon_color = color or Colors.hexrgb("#888888")
  ImGui.DrawList_AddRectFilled(dl, x, y, x + tab_w, y + tab_h, icon_color, 0)
  ImGui.DrawList_AddRectFilled(dl, x, y + tab_h, x + main_w, y + tab_h + main_h, icon_color, 0)
  return main_w + 4
end

local function draw_file_icon(ctx, dl, x, y, color)
  local main_w = 10
  local main_h = 12
  local fold_size = 3
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1
  local icon_color = color or Colors.hexrgb("#888888")
  ImGui.DrawList_AddRectFilled(dl, x, y, x + main_w - fold_size, y + main_h, icon_color, 0)
  ImGui.DrawList_AddRectFilled(dl, x, y + fold_size, x + main_w, y + main_h, icon_color, 0)
  local corner_color = Colors.hexrgb("#555555")
  ImGui.DrawList_AddTriangleFilled(dl,
    x + main_w - fold_size, y + fold_size,
    x + main_w, y + fold_size,
    x + main_w - fold_size, y,
    corner_color)
  return main_w + 4
end

local function draw_virtual_folder_icon(ctx, dl, x, y, color)
  local main_w = 13
  local main_h = 7
  local tab_w = 5
  local tab_h = 2
  x = (x + 0.5) // 1
  y = (y + 0.5) // 1
  local icon_color = color or Colors.hexrgb("#888888")
  ImGui.DrawList_AddRect(dl, x, y, x + tab_w, y + tab_h, icon_color, 0, 0, 2)
  ImGui.DrawList_AddRect(dl, x, y + tab_h, x + main_w, y + tab_h + main_h, icon_color, 0, 0, 2)
  local v_color = Colors.with_alpha(icon_color, 0xFF)
  local v_x = x + 4
  local v_y = y + tab_h + 2
  local v_size = 4
  ImGui.DrawList_AddLine(dl, v_x, v_y, v_x + v_size/2, v_y + v_size, v_color, 1.5)
  ImGui.DrawList_AddLine(dl, v_x + v_size/2, v_y + v_size, v_x + v_size, v_y, v_color, 1.5)
  return main_w + 4
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function build_flat_node_list(nodes, flat_list, counter)
  flat_list = flat_list or {}
  counter = counter or { value = 0 }
  for _, node in ipairs(nodes) do
    counter.value = counter.value + 1
    local node_id = node.id or node.path or tostring(counter.value)
    flat_list[#flat_list + 1] = node_id
    if node.children and #node.children > 0 then
      build_flat_node_list(node.children, flat_list, counter)
    end
  end
  return flat_list
end

-- ============================================================================
-- NODE RENDERING (internal)
-- ============================================================================

local function render_tree_node(ctx, node, opts, state, result, depth, node_counter)
  depth = depth or 0
  node_counter.value = node_counter.value + 1
  local node_id = node.id or node.path or tostring(node_counter.value)

  ImGui.PushID(ctx, node_id)

  -- Determine if node is open
  local is_open = state.open_nodes[node_id]
  if is_open == nil then is_open = false end

  -- Check if node is selected
  local is_selected = state.selected_nodes[node_id] ~= nil

  -- Check if renaming
  local is_renaming = state.renaming_node == node_id

  -- Node color
  local node_color = node.color

  -- Tree node flags
  local flags = ImGui.TreeNodeFlags_SpanAvailWidth | ImGui.TreeNodeFlags_DrawLinesFull
  flags = flags | ImGui.TreeNodeFlags_OpenOnArrow

  if is_selected then
    flags = flags | ImGui.TreeNodeFlags_Selected
  end

  if not node.children or #node.children == 0 then
    flags = flags | ImGui.TreeNodeFlags_Leaf
  end

  if is_open then
    ImGui.SetNextItemOpen(ctx, true)
  end

  if is_renaming then
    ImGui.SetNextItemAllowOverlap(ctx)
  end

  local node_open = ImGui.TreeNodeEx(ctx, node_id, "", flags)

  -- Get interaction state
  local tree_item_hovered = not is_renaming and ImGui.IsItemHovered(ctx)
  local tree_item_clicked = not is_renaming and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left)
  local tree_item_right_clicked = not is_renaming and ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right)
  local tree_item_double_clicked = not is_renaming and tree_item_hovered and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left)
  local tree_toggled = ImGui.IsItemToggledOpen(ctx)

  -- Get item rect for drawing overlays
  local item_min_x, item_min_y = ImGui.GetItemRectMin(ctx)
  local item_max_x, item_max_y = ImGui.GetItemRectMax(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  -- Update result for hovered
  if tree_item_hovered then
    result.hovered_id = node_id
  end

  -- Draw hover effect
  if tree_item_hovered and not is_selected then
    local hover_color = Colors.hexrgb("#FFFFFF08")
    ImGui.DrawList_AddRectFilled(dl, item_min_x, item_min_y, item_max_x, item_max_y, hover_color, 0)
  end

  -- Draw selection indicator
  if is_selected then
    local selection_bar_width = 3
    local selection_color = Colors.hexrgb("#FFFFFFFF")
    local selection_bg = Colors.hexrgb("#FFFFFF15")
    ImGui.DrawList_AddRectFilled(dl, item_min_x, item_min_y, item_min_x + selection_bar_width, item_max_y, selection_color, 0)
    ImGui.DrawList_AddRectFilled(dl, item_min_x, item_min_y, item_max_x, item_max_y, selection_bg, 0)
  end

  -- Draw icon and text
  local arrow_width = ImGui.GetTreeNodeToLabelSpacing(ctx)
  local icon_x = item_min_x + arrow_width
  local text_y_offset = (ImGui.GetTextLineHeight(ctx) - 9) * 0.5
  local icon_y = item_min_y + text_y_offset

  -- Draw custom arrow overlay (only for non-leaf nodes)
  if node.children and #node.children > 0 then
    local arrow_x = item_min_x + (arrow_width / 2) - 2.5
    local arrow_y = item_min_y + (item_max_y - item_min_y) / 2 - 2.5
    arrow_y = (arrow_y + 0.5) // 1
    draw_tree_arrow(ctx, dl, arrow_x, arrow_y, is_open)
  end

  -- Draw icon
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

  -- Inline rename
  if is_renaming then
    local saved_cursor_x, saved_cursor_y = ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx, text_x, item_min_y)

    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, Colors.hexrgb("#FFFFFF15"))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, Colors.hexrgb("#FFFFFF20"))
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, Colors.hexrgb("#FFFFFF25"))

    if not state.rename_focus_set then
      ImGui.SetKeyboardFocusHere(ctx, 0)
      state.rename_focus_set = true
    end

    ImGui.SetNextItemWidth(ctx, item_max_x - text_x - 8)
    local rv, buf = ImGui.InputText(ctx, "##rename_" .. node_id, state.rename_buffer, ImGui.InputTextFlags_AutoSelectAll)

    if rv then
      state.rename_buffer = buf
    end

    ImGui.PopStyleColor(ctx, 3)

    local input_active = ImGui.IsItemActive(ctx)
    local input_hovered = ImGui.IsItemHovered(ctx)
    ImGui.SetCursorScreenPos(ctx, saved_cursor_x, saved_cursor_y)

    state.rename_input_active = input_active
    state.rename_input_hovered = input_hovered

    -- Commit on Enter
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter) then
      if state.rename_buffer ~= "" and state.rename_buffer ~= node.name then
        result.renamed = true
        result.renamed_node_id = node_id
        result.renamed_value = state.rename_buffer
        if opts.on_rename then
          opts.on_rename(node, state.rename_buffer)
        end
      end
      state.renaming_node = nil
      state.rename_buffer = ""
      state.rename_focus_set = nil
    end

    -- Cancel on Escape
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      state.renaming_node = nil
      state.rename_buffer = ""
      state.rename_focus_set = nil
    end
  else
    -- Draw text label
    local text_color
    if node_color and opts.show_colors ~= false then
      text_color = Colors.lerp(node_color, Colors.hexrgb("#FFFFFFFF"), 0.7)
    else
      text_color = Colors.hexrgb("#FFFFFFFF")
    end
    ImGui.DrawList_AddText(dl, text_x, text_y, text_color, node.name)

    -- Draw template count
    if node.template_count and node.template_count > 0 and opts.show_template_count then
      local count_text = "(" .. node.template_count .. ")"
      local count_w = ImGui.CalcTextSize(ctx, count_text)
      local count_x = item_max_x - count_w - 8
      local count_y = item_min_y
      local count_color = Colors.hexrgb("#808080FF")
      ImGui.DrawList_AddText(dl, count_x, count_y, count_color, count_text)
    end
  end

  -- Handle click for selection
  if tree_item_clicked and not tree_toggled and not is_renaming then
    local ctrl_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
    local shift_down = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)

    result.clicked_id = node_id

    if opts.multi_select ~= false then
      -- Multi-select mode
      if shift_down and state.last_clicked_node then
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

          if not ctrl_down then
            state.selected_nodes = {}
          end

          for i = start_idx, end_idx do
            state.selected_nodes[state._flat_node_list[i]] = true
          end
        end
      elseif ctrl_down then
        if state.selected_nodes[node_id] then
          state.selected_nodes[node_id] = nil
        else
          state.selected_nodes[node_id] = true
        end
        state.last_clicked_node = node_id
      else
        if not state.selected_nodes[node_id] then
          state.selected_nodes = {}
        end
        state.selected_nodes[node_id] = true
        state.last_clicked_node = node_id
      end

      result.selection_changed = true
      if opts.on_select then
        opts.on_select(node, state.selected_nodes)
      end
    else
      -- Single select mode
      state.selected_nodes = { [node_id] = true }
      result.selection_changed = true
      if opts.on_select then
        opts.on_select(node)
      end
    end
  end

  -- Track open state
  if state.open_nodes[node_id] ~= node_open then
    result.expand_changed = true
  end
  state.open_nodes[node_id] = node_open

  -- Handle F2 key for rename
  if is_selected and opts.renameable ~= false and ImGui.IsKeyPressed(ctx, ImGui.Key_F2) and not is_renaming then
    local can_rename = true
    if opts.can_rename then
      can_rename = opts.can_rename(node)
    end
    if can_rename then
      state.renaming_node = node_id
      state.rename_buffer = node.name
    end
  end

  -- Handle Delete key
  if is_selected and ImGui.IsKeyPressed(ctx, ImGui.Key_Delete) and not is_renaming then
    if opts.on_delete then
      opts.on_delete(node)
    end
  end

  -- Handle double-click
  if tree_item_double_clicked and not is_renaming then
    result.double_clicked_id = node_id
    if opts.renameable ~= false then
      local can_rename = true
      if opts.can_rename then
        can_rename = opts.can_rename(node)
      end
      if can_rename then
        state.renaming_node = node_id
        state.rename_buffer = node.name
      end
    end
    if opts.on_double_click then
      opts.on_double_click(node)
    end
  end

  -- Handle right-click
  if not is_renaming and tree_item_right_clicked then
    result.right_clicked_id = node_id
    if opts.on_right_click then
      opts.on_right_click(node)
    end
  end

  -- Context menu
  if not is_renaming and opts.context_menu_id then
    ImGui.OpenPopupOnItemClick(ctx, opts.context_menu_id, ImGui.PopupFlags_MouseButtonRight)
    if opts.render_context_menu then
      opts.render_context_menu(ctx, node)
    end
  end

  -- Drag-drop source
  if opts.draggable and ImGui.BeginDragDropSource(ctx) then
    local drag_payload = node_id
    local drag_label = "Move: " .. node.name

    if opts.multi_select ~= false then
      local is_node_selected = state.selected_nodes[node_id] ~= nil
      local selected_ids = {}
      local count = 0
      for id, _ in pairs(state.selected_nodes) do
        selected_ids[#selected_ids + 1] = id
        count = count + 1
      end

      if is_node_selected and count > 1 then
        drag_payload = table.concat(selected_ids, "\n")
        drag_label = "Move: " .. count .. " folders"
      end
    end

    ImGui.SetDragDropPayload(ctx, "TREENODE_FOLDER", drag_payload)
    ImGui.Text(ctx, drag_label)
    ImGui.EndDragDropSource(ctx)
  end

  -- Drag-drop target
  if opts.draggable and ImGui.BeginDragDropTarget(ctx) then
    local accepted_folder, folder_payload = ImGui.AcceptDragDropPayload(ctx, "TREENODE_FOLDER")
    if accepted_folder and folder_payload and opts.on_drop_folder then
      opts.on_drop_folder(folder_payload, node)
    end

    local accepted_template, template_payload = ImGui.AcceptDragDropPayload(ctx, "TEMPLATE")
    if accepted_template and template_payload and opts.on_drop_template then
      opts.on_drop_template(template_payload, node)
    end

    ImGui.EndDragDropTarget(ctx)
  end

  -- Render children if node is open
  if node_open then
    if node.children and #node.children > 0 then
      for _, child in ipairs(node.children) do
        render_tree_node(ctx, child, opts, state, result, depth + 1, node_counter)
      end
    end
    ImGui.TreePop(ctx)
  end

  ImGui.PopID(ctx)
end

-- ============================================================================
-- PUBLIC API (New ImGui-style)
-- ============================================================================

--- Draw a tree view widget with hidden state management
--- @param ctx userdata ImGui context
--- @param opts table Widget options (id required)
--- @return table Result object with selection, expansion, rename info
function M.draw(ctx, opts)
  -- Validate opts
  if type(opts) ~= "table" then
    error("Ark.Tree: expected opts table, got " .. type(opts), 2)
  end

  -- Require explicit ID
  if not opts.id then
    error("Ark.Tree: 'id' field is required. Explicit ID prevents helper function collisions.", 2)
  end

  -- Get or create hidden state
  local state = get_tree_state(opts.id)

  -- Periodic cleanup of stale states
  cleanup_stale_states()

  -- Initialize result object
  local result = {
    -- Selection
    selected_ids = {},
    selection_changed = false,
    clicked_id = nil,
    double_clicked_id = nil,
    right_clicked_id = nil,

    -- Expansion
    expanded_ids = {},
    expand_changed = false,

    -- Rename
    renamed = false,
    renamed_node_id = nil,
    renamed_value = nil,

    -- Hover
    hovered_id = nil,
  }

  -- Early return if no nodes
  local nodes = opts.nodes or opts.items or {}
  if #nodes == 0 then
    return result
  end

  -- Build flat node list for range selection
  if opts.multi_select ~= false then
    state._flat_node_list = build_flat_node_list(nodes)
  end

  -- Render all root nodes
  local node_counter = { value = 0 }
  for _, node in ipairs(nodes) do
    render_tree_node(ctx, node, opts, state, result, 0, node_counter)
  end

  -- Global click-away check for inline rename
  if state.renaming_node and state.rename_focus_set then
    local input_active = state.rename_input_active or false
    local input_hovered = state.rename_input_hovered or false

    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not input_active and not input_hovered then
      state.renaming_node = nil
      state.rename_buffer = ""
      state.rename_focus_set = nil
      state.rename_input_active = nil
      state.rename_input_hovered = nil
    end
  end

  -- Copy selected and expanded IDs to result
  for id, _ in pairs(state.selected_nodes) do
    result.selected_ids[#result.selected_ids + 1] = id
  end
  for id, is_open in pairs(state.open_nodes) do
    if is_open then
      result.expanded_ids[#result.expanded_ids + 1] = id
    end
  end

  return result
end

-- ============================================================================
-- DEPRECATED API (Legacy compatibility shim)
-- ============================================================================

--- Draw tree view (DEPRECATED - use Ark.Tree(ctx, opts) instead)
--- @deprecated Use Ark.Tree(ctx, {id = "...", nodes = nodes, ...}) instead
--- @param ctx userdata ImGui context
--- @param nodes table Root nodes
--- @param state table External state table (will be synced)
--- @param user_config table|nil Configuration options
function M.draw_legacy(ctx, nodes, state, user_config)
  -- Warn once per unique caller
  local caller_info = debug.getinfo(2, "Sl")
  local caller_key = (caller_info.source or "unknown") .. ":" .. (caller_info.currentline or 0)
  if not deprecation_warned[caller_key] then
    deprecation_warned[caller_key] = true
    Logger.warn("TreeView", "M.draw(ctx, nodes, state, config) is deprecated. Use Ark.Tree(ctx, {id = '...', nodes = nodes, ...}) instead. Called from: %s", caller_key)
  end

  if not nodes or #nodes == 0 then return end

  local config = user_config or {}

  -- Ensure state tables exist
  if not state.open_nodes then
    state.open_nodes = {}
  end
  if config.enable_multi_select and not state.selected_nodes then
    state.selected_nodes = {}
  end

  -- Generate a pseudo-ID from caller location
  local pseudo_id = "legacy_tree_" .. caller_key

  -- Convert legacy config to new opts format
  local opts = {
    id = pseudo_id,
    nodes = nodes,
    multi_select = config.enable_multi_select,
    renameable = config.enable_rename ~= false,
    draggable = config.enable_drag_drop,
    show_colors = config.show_colors ~= false,
    show_template_count = config.show_template_count,
    context_menu_id = config.context_menu_id,
    can_rename = config.can_rename,
    on_select = config.on_select,
    on_rename = config.on_rename,
    on_delete = config.on_delete,
    on_double_click = config.on_double_click,
    on_right_click = config.on_right_click,
    on_drop_folder = config.on_drop_folder,
    on_drop_template = config.on_drop_template,
    render_context_menu = config.render_context_menu,
  }

  -- Get internal state and sync from external
  local internal_state = get_tree_state(pseudo_id)

  -- Sync from external state to internal
  if state.open_nodes then
    for k, v in pairs(state.open_nodes) do
      internal_state.open_nodes[k] = v
    end
  end
  if state.selected_nodes then
    internal_state.selected_nodes = state.selected_nodes
  elseif state.selected_node then
    internal_state.selected_nodes = { [state.selected_node] = true }
  end
  if state.renaming_node then
    internal_state.renaming_node = state.renaming_node
    internal_state.rename_buffer = state.rename_buffer or ""
  end

  -- Draw using new API
  local result = M.draw(ctx, opts)

  -- Sync back from internal state to external
  state.open_nodes = {}
  for k, v in pairs(internal_state.open_nodes) do
    state.open_nodes[k] = v
  end

  if config.enable_multi_select then
    state.selected_nodes = {}
    for _, id in ipairs(result.selected_ids) do
      state.selected_nodes[id] = true
    end
  else
    state.selected_node = result.clicked_id or (result.selected_ids[1])
  end

  state.renaming_node = internal_state.renaming_node
  state.rename_buffer = internal_state.rename_buffer
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Start renaming a node
--- @param tree_id string Tree widget ID
--- @param node_id string Node ID to rename
--- @param current_name string Current node name
function M.start_rename(tree_id, node_id, current_name)
  local state = get_tree_state(tree_id)
  state.renaming_node = node_id
  state.rename_buffer = current_name or ""
  state.rename_focus_set = nil
end

--- Cancel current rename operation
--- @param tree_id string Tree widget ID
function M.cancel_rename(tree_id)
  local state = get_tree_state(tree_id)
  state.renaming_node = nil
  state.rename_buffer = ""
  state.rename_focus_set = nil
end

--- Find node by ID in tree
--- @param nodes table Root nodes
--- @param node_id string Node ID to find
--- @return table|nil node The found node or nil
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
--- @param tree_id string Tree widget ID
--- @param nodes table Root nodes
--- @param target_id string Target node ID
function M.expand_to_node(tree_id, nodes, target_id)
  local state = get_tree_state(tree_id)

  local function find_path(nodes_list, target, path)
    path = path or {}
    for _, node in ipairs(nodes_list) do
      local id = node.id or node.path or node.name
      if id == target then
        for _, parent_id in ipairs(path) do
          state.open_nodes[parent_id] = true
        end
        return true
      end
      if node.children then
        path[#path + 1] = id
        if find_path(node.children, target, path) then
          return true
        end
        table.remove(path)
      end
    end
    return false
  end

  find_path(nodes, target_id)
end

--- Collapse all nodes
--- @param tree_id string Tree widget ID
function M.collapse_all(tree_id)
  local state = get_tree_state(tree_id)
  state.open_nodes = {}
end

--- Expand all nodes
--- @param tree_id string Tree widget ID
--- @param nodes table Root nodes
function M.expand_all(tree_id, nodes)
  local state = get_tree_state(tree_id)

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

--- Select a node
--- @param tree_id string Tree widget ID
--- @param node_id string Node ID to select
--- @param append boolean|nil If true, add to selection; if false, replace selection
function M.select_node(tree_id, node_id, append)
  local state = get_tree_state(tree_id)
  if not append then
    state.selected_nodes = {}
  end
  state.selected_nodes[node_id] = true
end

--- Clear selection
--- @param tree_id string Tree widget ID
function M.clear_selection(tree_id)
  local state = get_tree_state(tree_id)
  state.selected_nodes = {}
end

--- Get selected node IDs
--- @param tree_id string Tree widget ID
--- @return table selected_ids Array of selected node IDs
function M.get_selected(tree_id)
  local state = get_tree_state(tree_id)
  local selected = {}
  for id, _ in pairs(state.selected_nodes) do
    selected[#selected + 1] = id
  end
  return selected
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

-- Make callable: Ark.Tree(ctx, opts) → M.draw(ctx, opts)
return setmetatable(M, {
  __call = function(_, ctx, opts_or_nodes, state, user_config)
    -- Detect old vs new API
    if type(opts_or_nodes) == "table" and opts_or_nodes.id then
      -- New API: Ark.Tree(ctx, {id = "...", nodes = ...})
      return M.draw(ctx, opts_or_nodes)
    elseif state ~= nil then
      -- Old API: M.draw(ctx, nodes, state, config)
      return M.draw_legacy(ctx, opts_or_nodes, state, user_config)
    else
      -- Assume new API with missing id
      return M.draw(ctx, opts_or_nodes)
    end
  end
})
