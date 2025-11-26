-- @noindex
-- Arkitekt/gui/widgets/nodal/canvas.lua
-- Main container for node system with vertical sequencer

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local Config = require('arkitekt.gui.widgets.editors.nodal.defaults')
local Node = require('arkitekt.gui.widgets.editors.nodal.core.node')
local NodeRenderer = require('arkitekt.gui.widgets.editors.nodal.rendering.node_renderer')
local Connection = require('arkitekt.gui.widgets.editors.nodal.core.connection')
local ConnectionRenderer = require('arkitekt.gui.widgets.editors.nodal.rendering.connection_renderer')
local Port = require('arkitekt.gui.widgets.editors.nodal.core.port')
local Layout = require('arkitekt.gui.widgets.editors.nodal.systems.auto_layout')
local Viewport = require('arkitekt.gui.widgets.editors.nodal.systems.viewport')
local Dnd = require('arkitekt.gui.fx.interactions.dnd')
local DragIndicator = Dnd.DragIndicator
local DropIndicator = Dnd.DropIndicator
local Background = require('arkitekt.gui.draw.pattern')
local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb


local M = {}

M.VIEWPORT_CONFIG = {
  border_color = hexrgb("#000000"),
  border_thickness = 2,
  rounding = 8,
  inset = 1,  -- Inset from actual bounds to prevent clipping
}

local function create_simple_animator()
  return {
    values = {},
    targets = {},
    speeds = {},
    update = function(self, dt)
      for key, target in pairs(self.targets) do
        local current = self.values[key] or target
        local speed = self.speeds[key] or 10.0
        local diff = target - current
        
        if math.abs(diff) > 0.001 then
          self.values[key] = current + diff * math.min(1.0, dt * speed)
        else
          self.values[key] = target
        end
      end
    end
  }
end

function M.new(opts)
  local canvas = {
    nodes = opts.nodes or {},
    connections = opts.connections or {},
    node_lookup = {},  -- guid -> node (O(1) lookup)

    config = opts.config or Config.get(),

    container_x = opts.container_x or 50,
    container_width = opts.container_width or 320,

    animator = create_simple_animator(),

    viewport = Viewport.new({
      scale = opts.initial_scale or 1.0,
      min_scale = opts.min_scale or 0.5,
      max_scale = opts.max_scale or 1.5,
    }),

    selected_nodes = {},
    hovered_node = nil,
    hovered_connection = nil,
    hovered_port = nil,

    drag_connection = nil,
    drag_node = nil,
    drag_node_index = nil,
    drag_drop_index = nil,
  }

  -- Build node lookup table for O(1) access
  for _, node in ipairs(canvas.nodes) do
    if node.guid then
      canvas.node_lookup[node.guid] = node
    end
  end

  Layout.calculate_container_layout(canvas.nodes, canvas.config, canvas.container_x, canvas.container_width)

  return canvas
end

function M.render(canvas, ctx, bounds_x, bounds_y, bounds_w, bounds_h)
  if not bounds_x or not bounds_y or not bounds_w or not bounds_h then
    return
  end
  
  if bounds_w <= 0 or bounds_h <= 0 then
    return
  end
  
  local dl = ImGui.GetWindowDrawList(ctx)
  
  -- Apply inset to create visual padding for border
  local inset = M.VIEWPORT_CONFIG.inset
  local viewport_x = bounds_x + inset
  local viewport_y = bounds_y + inset
  local viewport_w = bounds_w - (inset * 2)
  local viewport_h = bounds_h - (inset * 2)
  
  Viewport.set_bounds(canvas.viewport, viewport_x, viewport_y, viewport_w, viewport_h)
  
  local mx, my = ImGui.GetMousePos(ctx)
  
  if not mx or not my then
    mx, my = 0, 0
  end
  
  -- Push clip rect with rounded corners
  ImGui.DrawList_PushClipRect(dl, viewport_x, viewport_y, viewport_x + viewport_w, viewport_y + viewport_h, true)
  
  -- IMPORTANT: Update viewport first to handle pan/zoom before anything else
  local viewport_handled = Viewport.update(canvas.viewport, ctx)
  
  -- Only update hover states and handle node input if viewport isn't being manipulated
  if not viewport_handled and not canvas.viewport.is_panning then
    M.update_hover_states(canvas, ctx, mx, my)
    M.handle_input(canvas, ctx, mx, my)
  else
    canvas.hovered_node = nil
    canvas.hovered_connection = nil
    canvas.hovered_port = nil
  end
  
  -- Draw background color
  ImGui.DrawList_AddRectFilled(dl, viewport_x, viewport_y, viewport_x + viewport_w, viewport_y + viewport_h, 
    canvas.config.bg_color or hexrgb("#1A1A1A"), M.VIEWPORT_CONFIG.rounding)
  
  -- Draw grid pattern - ensure it covers the full canvas bounds
  M.render_grid(canvas, ctx, dl, viewport_x, viewport_y, viewport_w, viewport_h)
  
  -- Draw container outline
  M.render_container(canvas, ctx, dl)
  
  -- Draw nodes first (so connections can be on top)
  M.render_nodes(canvas, ctx)
  
  -- Draw connections AFTER nodes (so they appear on top)
  M.render_connections(canvas, ctx)
  
  if canvas.drag_node and not canvas.viewport.is_panning then
    M.render_drop_indicator(canvas, ctx, dl)
    M.render_drag_ghost(canvas, ctx, dl, mx, my)
  end
  
  if canvas.drag_connection and not canvas.viewport.is_panning then
    M.render_drag_connection(canvas, ctx, mx, my)
  end
  
  -- Pop clip rect
  ImGui.DrawList_PopClipRect(dl)
  
  -- Draw viewport border with rounded corners (outside clip rect so it's always visible)
  ImGui.DrawList_AddRect(dl, viewport_x, viewport_y, viewport_x + viewport_w, viewport_y + viewport_h,
    M.VIEWPORT_CONFIG.border_color, M.VIEWPORT_CONFIG.rounding, 0, M.VIEWPORT_CONFIG.border_thickness)
  
  canvas.animator:update(1/60)
end

function M.render_grid(canvas, ctx, dl, bounds_x, bounds_y, bounds_w, bounds_h)
  if not canvas.config.background_pattern or not canvas.config.background_pattern.enabled then 
    return 
  end
  
  local vp = canvas.viewport
  if not vp or not vp.scale then return end
  
  -- Calculate the world origin position in screen space
  local world_origin_screen_x = vp.offset_x + vp.bounds_x
  local world_origin_screen_y = vp.offset_y + vp.bounds_y
  
  -- Create scaled pattern configuration
  local scaled_pattern = {
    enabled = canvas.config.background_pattern.enabled,
  }
  
  if canvas.config.background_pattern.primary then
    scaled_pattern.primary = {
      type = canvas.config.background_pattern.primary.type,
      spacing = canvas.config.background_pattern.primary.spacing * vp.scale,
      color = canvas.config.background_pattern.primary.color,
      line_thickness = canvas.config.background_pattern.primary.line_thickness,
      dot_size = canvas.config.background_pattern.primary.dot_size,
      offset_x = world_origin_screen_x,
      offset_y = world_origin_screen_y,
    }
  end
  
  if canvas.config.background_pattern.secondary then
    scaled_pattern.secondary = {
      enabled = canvas.config.background_pattern.secondary.enabled,
      type = canvas.config.background_pattern.secondary.type,
      spacing = canvas.config.background_pattern.secondary.spacing * vp.scale,
      color = canvas.config.background_pattern.secondary.color,
      line_thickness = canvas.config.background_pattern.secondary.line_thickness,
      dot_size = canvas.config.background_pattern.secondary.dot_size,
      offset_x = world_origin_screen_x,
      offset_y = world_origin_screen_y,
    }
  end
  
  -- Make sure we're drawing the grid over the entire canvas bounds
  Background.draw(ctx, dl, bounds_x, bounds_y, bounds_x + bounds_w, bounds_y + bounds_h, scaled_pattern)
end

function M.render_container(canvas, ctx, dl)
  if #canvas.nodes == 0 then return end
  
  local first_node = canvas.nodes[1]
  local last_node = canvas.nodes[#canvas.nodes]
  
  local container_world_x = canvas.container_x
  local container_world_y = first_node.y - canvas.config.node.spacing
  local container_world_w = canvas.container_width
  local container_world_h = (last_node.y + last_node.height) - container_world_y + canvas.config.node.spacing
  
  local screen_x1, screen_y1 = Viewport.world_to_screen(canvas.viewport, container_world_x, container_world_y)
  local screen_x2, screen_y2 = Viewport.world_to_screen(canvas.viewport, 
    container_world_x + container_world_w, 
    container_world_y + container_world_h)
  
  ImGui.DrawList_AddRect(dl, screen_x1, screen_y1, screen_x2, screen_y2, hexrgb("#404040AA"), 4, 0, 1.5)
end

function M.render_nodes(canvas, ctx)
  -- Pass available nodes to renderer for dropdown population
  NodeRenderer.set_available_nodes(canvas.nodes)
  
  for i, node in ipairs(canvas.nodes) do
    if canvas.drag_node ~= node then
      local screen_x, screen_y = Viewport.world_to_screen(canvas.viewport, node.x, node.y)
      
      local render_node = {
        guid = node.guid,
        id = node.id,
        name = node.name,
        mirror_mode = node.mirror_mode,
        template_ref = node.template_ref,
        properties = node.properties,
        next_section = node.next_section,
        triggers = node.triggers,
        sequence_index = i,
        x = screen_x,
        y = screen_y,
        width = node.width * canvas.viewport.scale,
        height = node.height * canvas.viewport.scale,
        selected = node.selected,
        hovered = node.hovered,
        collapsed = node.collapsed,
        ports = node.ports,
      }
      
      NodeRenderer.render(ctx, render_node, canvas.animator, canvas.config)
      
      M.render_node_interaction(canvas, ctx, node, i, screen_x, screen_y, 
        node.width * canvas.viewport.scale, node.height * canvas.viewport.scale)
    end
  end
end

function M.render_node_interaction(canvas, ctx, node, node_index, screen_x, screen_y, screen_w, screen_h)
  ImGui.SetCursorScreenPos(ctx, screen_x, screen_y)
  ImGui.InvisibleButton(ctx, "##node_" .. node.guid, screen_w, screen_h)
  
  if ImGui.IsItemHovered(ctx) then
    canvas.hovered_node = node
  end
  
  if ImGui.IsItemClicked(ctx, 0) then
    local ctrl = ImGui.IsKeyDown(ctx, ImGui.Key_LeftCtrl) or ImGui.IsKeyDown(ctx, ImGui.Key_RightCtrl)
    
    if ctrl then
      node.selected = not node.selected
    else
      for _, n in ipairs(canvas.nodes) do
        n.selected = false
      end
      node.selected = true
    end
  end
  
  if ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0, 5) then
    if not canvas.drag_node and not canvas.viewport.is_panning then
      canvas.drag_node = node
      canvas.drag_node_index = node_index
    end
  end
end

function M.render_connections(canvas, ctx)
  local scaled_nodes = {}
  for _, node in ipairs(canvas.nodes) do
    local screen_x, screen_y = Viewport.world_to_screen(canvas.viewport, node.x, node.y)
    scaled_nodes[#scaled_nodes + 1] = {
      guid = node.guid,
      x = screen_x,
      y = screen_y,
      width = node.width * canvas.viewport.scale,
      height = node.height * canvas.viewport.scale,
      ports = node.ports,
    }
  end
  
  for _, conn in ipairs(canvas.connections) do
    if conn.type == "trigger" then
      ConnectionRenderer.render(ctx, conn, scaled_nodes, canvas.config)
    end
  end
end

function M.render_drag_connection(canvas, ctx, mx, my)
  local start_x = canvas.drag_connection.start_x
  local start_y = canvas.drag_connection.start_y
  
  ConnectionRenderer.render_drag_connection(ctx, start_x, start_y, mx, my, canvas.drag_connection.color, canvas.config)
end

function M.render_drag_ghost(canvas, ctx, dl, mx, my)
  if not canvas.drag_node then return end
  
  local base_color = Node.get_base_color(canvas.drag_node, canvas.config)
  local drag_config = canvas.config.drag_indicator
  
  DragIndicator.draw(ctx, dl, mx, my, 1, drag_config, {base_color}, false, false)
end

function M.render_drop_indicator(canvas, ctx, dl)
  if not canvas.drag_drop_index then return end
  
  local drop_y
  
  if canvas.drag_drop_index == 1 then
    local first_node = canvas.nodes[1]
    drop_y = first_node.y - canvas.config.node.spacing / 2
  elseif canvas.drag_drop_index > #canvas.nodes then
    local last_node = canvas.nodes[#canvas.nodes]
    drop_y = last_node.y + last_node.height + canvas.config.node.spacing / 2
  else
    local prev_node = canvas.nodes[canvas.drag_drop_index - 1]
    local next_node = canvas.nodes[canvas.drag_drop_index]
    drop_y = (prev_node.y + prev_node.height + next_node.y) / 2
  end
  
  local screen_x1, screen_y = Viewport.world_to_screen(canvas.viewport, canvas.container_x, drop_y)
  local screen_x2, _ = Viewport.world_to_screen(canvas.viewport, canvas.container_x + canvas.container_width, drop_y)
  
  local drop_config = canvas.config.drop_indicator
  DropIndicator.draw_horizontal(ctx, dl, screen_x1, screen_x2, screen_y, drop_config, false)
end

function M.update_hover_states(canvas, ctx, mx, my)
  local world_mx, world_my = Viewport.screen_to_world(canvas.viewport, mx, my)
  
  canvas.hovered_node = nil
  canvas.hovered_connection = nil
  canvas.hovered_port = nil
  
  for _, node in ipairs(canvas.nodes) do
    node.hovered = false
    
    for _, port in ipairs(Node.get_all_ports(node)) do
      port.hovered = false
    end
  end
  
  for _, conn in ipairs(canvas.connections) do
    conn.hovered = false
  end
  
  for _, node in ipairs(canvas.nodes) do
    if Node.is_point_inside(node, world_mx, world_my) then
      node.hovered = true
      canvas.hovered_node = node
    end
    
    local port = Node.find_port_at(node, world_mx, world_my, canvas.config)
    if port then
      port.hovered = true
      canvas.hovered_port = port
    end
  end
  
  local scaled_nodes = {}
  for _, node in ipairs(canvas.nodes) do
    local screen_x, screen_y = Viewport.world_to_screen(canvas.viewport, node.x, node.y)
    scaled_nodes[#scaled_nodes + 1] = {
      guid = node.guid,
      x = screen_x,
      y = screen_y,
      width = node.width * canvas.viewport.scale,
      height = node.height * canvas.viewport.scale,
      ports = node.ports,
    }
  end
  
  for _, conn in ipairs(canvas.connections) do
    if conn.type == "trigger" and Connection.is_point_on_line(conn, scaled_nodes, canvas.config, mx, my) then
      conn.hovered = true
      canvas.hovered_connection = conn
    end
  end
end

function M.handle_input(canvas, ctx, mx, my)
  if canvas.drag_node and ImGui.IsMouseDragging(ctx, 0) then
    local world_mx, world_my = Viewport.screen_to_world(canvas.viewport, mx, my)
    
    canvas.drag_drop_index = nil
    
    for i, node in ipairs(canvas.nodes) do
      if i ~= canvas.drag_node_index then
        local threshold_y = node.y + node.height / 2
        
        if world_my < threshold_y then
          if i < canvas.drag_node_index then
            canvas.drag_drop_index = i
          else
            canvas.drag_drop_index = i
          end
          break
        end
      end
    end
    
    if not canvas.drag_drop_index then
      canvas.drag_drop_index = #canvas.nodes + 1
    end
  end
  
  if ImGui.IsMouseReleased(ctx, 0) then
    if canvas.drag_node and canvas.drag_drop_index then
      if canvas.drag_drop_index ~= canvas.drag_node_index and 
         canvas.drag_drop_index ~= canvas.drag_node_index + 1 then
        local node = table.remove(canvas.nodes, canvas.drag_node_index)
        
        local insert_index = canvas.drag_drop_index
        if canvas.drag_drop_index > canvas.drag_node_index then
          insert_index = canvas.drag_drop_index - 1
        end
        
        table.insert(canvas.nodes, insert_index, node)
        
        Layout.calculate_container_layout(canvas.nodes, canvas.config, canvas.container_x, canvas.container_width)
      end
    end
    
    canvas.drag_node = nil
    canvas.drag_node_index = nil
    canvas.drag_drop_index = nil
    
    if canvas.drag_connection then
      if canvas.hovered_port then
        M.try_create_connection(canvas, canvas.drag_connection.source_port, canvas.hovered_port)
      end
      canvas.drag_connection = nil
    end
  end
  
  if canvas.hovered_port and ImGui.IsMouseClicked(ctx, 0) then
    if canvas.hovered_port.direction == "out" then
      local screen_x, screen_y = Viewport.world_to_screen(canvas.viewport, 
        canvas.hovered_port.x, canvas.hovered_port.y)
      
      canvas.drag_connection = {
        source_port = canvas.hovered_port,
        start_x = screen_x,
        start_y = screen_y,
        color = canvas.config.colors.connection_types.trigger,
      }
    end
  end
end

function M.try_create_connection(canvas, source_port, target_port)
  if not Port.can_connect(source_port, target_port) then
    return
  end
  
  local source_node = M.find_node_with_port(canvas, source_port)
  local target_node = M.find_node_with_port(canvas, target_port)
  
  if not source_node or not target_node then
    return
  end
  
  local conn = Connection.new_trigger(source_node.guid, target_node.guid,
    source_port.event_name, source_port.jump_mode, canvas.config.colors.connection_types.trigger)

  canvas.connections[#canvas.connections + 1] = conn
end

function M.find_node_with_port(canvas, port)
  for _, node in ipairs(canvas.nodes) do
    for _, p in ipairs(Node.get_all_ports(node)) do
      if p == port then
        return node
      end
    end
  end
  return nil
end

function M.center_on_content(canvas)
  if #canvas.nodes == 0 then return end
  
  local bounds_x, bounds_y, bounds_w, bounds_h = Layout.get_bounds(canvas.nodes)
  
  if not bounds_x or not bounds_y or not bounds_w or not bounds_h then
    return
  end
  
  if bounds_w == 0 or bounds_h == 0 then
    return
  end
  
  local center_x = bounds_x + bounds_w / 2
  local center_y = bounds_y + bounds_h / 2
  
  Viewport.center_on_point(canvas.viewport, center_x, center_y)
end

function M.reset_viewport(canvas)
  Viewport.reset(canvas.viewport)
end

return M