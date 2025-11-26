-- @noindex
-- Arkitekt/gui/widgets/nodal/core/node.lua
-- Node data structure and logic with trigger UI height calculation

local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

function M.new(opts)
  local node = {
    guid = opts.guid or reaper.genGuid(),
    id = opts.id or "node",
    name = opts.name or "Unnamed Node",
    
    mirror_mode = opts.mirror_mode or "linked",
    
    template_ref = opts.template_ref,
    
    properties = opts.properties or {
      wwise_state = "DefaultState",
      loop_count = 1,
      transition_type = "crossfade",
      transition_duration = 2.0,
    },
    
    next_section = opts.next_section,
    
    triggers = opts.triggers or {},
    
    x = opts.x or 0,
    y = opts.y or 0,
    width = opts.width or 280,
    height = opts.height or 0,
    
    selected = false,
    hovered = false,
    collapsed = false,
    
    ports = {
      sequential_in = nil,
      sequential_out = nil,
      triggers = {},
    },
  }
  
  M.update_ports(node)
  
  return node
end

function M.update_ports(node)
  node.ports.sequential_in = nil
  node.ports.sequential_out = nil
  
  node.ports.triggers = {}
  for i, trigger in ipairs(node.triggers) do
    node.ports.triggers[i] = {
      type = "trigger",
      direction = "out",
      event_name = trigger.event,
      target_section = trigger.target_section,
      jump_mode = trigger.mode or "INCREMENTAL",
      x = 0,
      y = 0,
      hovered = false,
      active = false,
    }
  end
end

function M.calculate_height(node, config)
  local height = config.node.header_height
  
  -- Body section
  height = height + config.node.body_padding_top
  height = height + (config.node.body_line_height * 3)  -- 3 lines of body text
  height = height + config.node.body_padding_bottom
  
  -- Trigger section
  local trigger_count = (node.triggers and #node.triggers) or 0
  
  -- Always include trigger section (even if empty, for "Add Trigger" button)
  height = height + config.node.trigger_section_padding_top
  height = height + config.trigger_ui.section_label_height
  
  if trigger_count > 0 then
    -- Each trigger takes 2 rows (event name + target/mode) + spacing
    local per_trigger_height = (config.trigger_ui.item_height * 2) + config.trigger_ui.item_spacing
    height = height + (trigger_count * per_trigger_height)
  end
  
  -- Add trigger button
  height = height + config.trigger_ui.add_button_height + config.trigger_ui.item_spacing
  
  return math.max(height, config.node.min_height)
end

function M.get_base_color(node, config)
  return config.colors.mirror_modes[node.mirror_mode] or hexrgb("#88CEFF")
end

function M.is_point_inside(node, x, y)
  return x >= node.x and x <= node.x + node.width and
         y >= node.y and y <= node.y + node.height
end

function M.get_all_ports(node)
  local ports = {}

  if node.ports.sequential_in then
    ports[#ports + 1] = node.ports.sequential_in
  end

  if node.ports.sequential_out then
    ports[#ports + 1] = node.ports.sequential_out
  end

  for _, port in ipairs(node.ports.triggers) do
    ports[#ports + 1] = port
  end

  return ports
end

function M.find_port_at(node, x, y, config)
  local ports = M.get_all_ports(node)
  local radius = config.port.size * config.port.hitbox_extend
  
  for _, port in ipairs(ports) do
    local dx = x - port.x
    local dy = y - port.y
    if (dx * dx + dy * dy) < (radius * radius) then
      return port
    end
  end
  
  return nil
end

return M