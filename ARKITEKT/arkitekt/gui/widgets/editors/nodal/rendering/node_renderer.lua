-- @noindex
-- Arkitekt/gui/widgets/nodal/rendering/node_renderer.lua
-- Node rendering with dropdown-based trigger targeting

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.10'

local TileFX = require('arkitekt.gui.rendering.tile.renderer')
local TileFXConfig = require('arkitekt.gui.rendering.tile.defaults')
local Colors = require('arkitekt.core.colors')
local Draw = require('arkitekt.gui.draw')
local Chip = require('arkitekt.gui.widgets.data.chip')
local MarchingAnts = require('arkitekt.gui.fx.interactions.marching_ants')
local Port = require('arkitekt.gui.widgets.editors.nodal.core.port')

local M = {}
local hexrgb = Colors.hexrgb

-- Store available nodes for dropdowns (set by canvas)
M.available_nodes = {}

function M.set_available_nodes(nodes)
  M.available_nodes = nodes
end

function M.render(ctx, node, animator, config)
  local dl = ImGui.GetWindowDrawList(ctx)
  
  local hover_key = node.guid .. '_hover'
  if not animator.values then animator.values = {} end
  if not animator.targets then animator.targets = {} end
  if not animator.speeds then animator.speeds = {} end
  
  animator.targets[hover_key] = node.hovered and 1.0 or 0.0
  animator.speeds[hover_key] = 12.0
  
  if not animator.values[hover_key] then
    animator.values[hover_key] = animator.targets[hover_key]
  end
  
  local hover_factor = animator.values[hover_key] or 0.0
  
  local x1, y1 = node.x, node.y
  local x2, y2 = node.x + node.width, node.y + node.height
  
  -- Use dark neutral background instead of base_color
  local bg_color = config.colors.bg_base or hexrgb("#1A1A1A")
  
  -- Get colored chip color from mirror_mode
  local chip_color = require('arkitekt.gui.widgets.editors.nodal.core.node').get_base_color(node, config)
  
  local fx_config = config.tile_fx
  
  TileFX.render_complete(ctx, dl, x1, y1, x2, y2, bg_color, fx_config, node.selected, hover_factor)
  
  if node.selected and fx_config.ants_enabled then
    local ants_color = Colors.same_hue_variant(chip_color, fx_config.border_saturation, fx_config.border_brightness, fx_config.ants_alpha)
    MarchingAnts.draw(dl, x1, y1, x2, y2, ants_color, fx_config.ants_thickness, config.node.rounding, fx_config.ants_dash, fx_config.ants_gap, fx_config.ants_speed)
  end
  
  M.render_header(ctx, dl, node, config, chip_color)
  M.render_body(ctx, dl, node, config)
  M.render_loop_badge(ctx, dl, node, config, chip_color)
  M.render_triggers_ui(ctx, dl, node, config, chip_color)
  M.render_ports(ctx, dl, node, config, chip_color)
end

function M.render_header(ctx, dl, node, config, chip_color)
  local x1 = node.x + config.node.padding
  local y1 = node.y + (config.node.header_height - 16) / 2
  
  Chip.draw(ctx, {
    style = Chip.STYLE.INDICATOR,
    color = chip_color,
    draw_list = dl,
    x = x1 + 6,
    y = y1 + 8,
    radius = 5,
    is_selected = node.selected,
    is_hovered = node.hovered,
    show_glow = node.selected or node.hovered,
    glow_layers = 2,
    alpha_factor = 1.0,
  })
  
  local sequence_text = "#" .. (node.sequence_index or "?")
  local seq_w, seq_h = ImGui.CalcTextSize(ctx, sequence_text)
  local seq_x = x1 + 24
  local seq_y = y1
  Draw.text(dl, seq_x, seq_y, hexrgb("#888888"), sequence_text)
  
  local name_x = seq_x + seq_w + 8
  local name_y = y1
  Draw.text(dl, name_x, name_y, config.colors.text.header, node.name)
end

function M.render_body(ctx, dl, node, config)
  local x1 = node.x + config.node.padding
  local y1 = node.y + config.node.header_height + config.node.body_padding_top
  
  local text_color = config.colors.text.body
  
  local line1 = "Wwise: " .. node.properties.wwise_state
  Draw.text(dl, x1, y1, text_color, line1)
  y1 = y1 + config.node.body_line_height
  
  local line2 = "Loops: ×" .. node.properties.loop_count
  Draw.text(dl, x1, y1, text_color, line2)
  y1 = y1 + config.node.body_line_height
  
  local line3 = "Transition: " .. node.properties.transition_type .. " (" .. node.properties.transition_duration .. "s)"
  Draw.text(dl, x1, y1, text_color, line3)
end

function M.render_loop_badge(ctx, dl, node, config, chip_color)
  local badge_config = config.badge or {
    rounding = 4,
    padding_x = 6,
    padding_y = 3,
    margin = 6,
    bg = hexrgb("#14181C"),
    border_alpha = 0x33,
    font_scale = 0.88,
  }
  
  local loop_count = node.properties.loop_count or 1
  local badge_text = (loop_count == 0) and "∞" or ("×" .. loop_count)
  
  local bw, bh = ImGui.CalcTextSize(ctx, badge_text)
  bw = bw * badge_config.font_scale
  bh = bh * badge_config.font_scale
  
  local badge_x = node.x + node.width - bw - badge_config.padding_x * 2 - badge_config.margin
  local badge_y = node.y + badge_config.margin
  local badge_x2 = badge_x + bw + badge_config.padding_x * 2
  local badge_y2 = badge_y + bh + badge_config.padding_y * 2
  
  ImGui.DrawList_AddRectFilled(dl, badge_x, badge_y, badge_x2, badge_y2, badge_config.bg, badge_config.rounding)
  ImGui.DrawList_AddRect(dl, badge_x, badge_y, badge_x2, badge_y2, 
    Colors.with_alpha(chip_color, badge_config.border_alpha), 
    badge_config.rounding, 0, 0.5)
  
  Draw.text(dl, badge_x + badge_config.padding_x, badge_y + badge_config.padding_y, 
    hexrgb("#FFFFFFDD"), badge_text)
end

function M.render_triggers_ui(ctx, dl, node, config, chip_color)
  if not node.triggers or #node.triggers == 0 then
    -- Show "Add Trigger" button even if no triggers
    M.render_add_trigger_button(ctx, node, config)
    return
  end
  
  local trigger_config = config.trigger_ui
  local x1 = node.x + config.node.padding
  local y_offset = node.y + config.node.header_height + config.node.body_padding_top + 
                   (config.node.body_line_height * 3) + config.node.body_padding_bottom + 
                   config.node.trigger_section_padding_top
  
  -- Section label
  Draw.text(dl, x1, y_offset, config.colors.text.trigger_section, "⚡ TRIGGERS")
  y_offset = y_offset + trigger_config.section_label_height
  
  -- Render each trigger
  local triggers_to_remove = {}
  local needs_port_update = false
  
  for i, trigger in ipairs(node.triggers) do
    local changed, should_remove = M.render_trigger_item(ctx, node, trigger, i, x1, y_offset, config, chip_color)
    
    if should_remove then
      triggers_to_remove[#triggers_to_remove + 1] = i
      needs_port_update = true
    end
    
    if changed then
      needs_port_update = true
    end
    
    y_offset = y_offset + (trigger_config.item_height * 2) + trigger_config.item_spacing
  end
  
  -- Remove triggers marked for deletion (in reverse to maintain indices)
  for i = #triggers_to_remove, 1, -1 do
    table.remove(node.triggers, triggers_to_remove[i])
  end
  
  -- Update ports if triggers changed
  if needs_port_update then
    local Node = require('arkitekt.gui.widgets.editors.nodal.core.node')
    Node.update_ports(node)
    node.height = Node.calculate_height(node, config)
  end
  
  -- Add trigger button
  M.render_add_trigger_button(ctx, node, config)
end

function M.render_trigger_item(ctx, node, trigger, index, x, y, config, chip_color)
  local dl = ImGui.GetWindowDrawList(ctx)
  local trigger_config = config.trigger_ui
  local indent = x + trigger_config.indent
  local item_width = node.width - config.node.padding * 2 - trigger_config.indent - trigger_config.delete_button_size - 4
  
  -- Event name (editable)
  Draw.text(dl, indent, y, config.colors.text.body, "Event:")
  ImGui.SetCursorScreenPos(ctx, indent + 50, y - 2)
  ImGui.PushItemWidth(ctx, item_width - 50)
  ImGui.PushID(ctx, "trigger_event_" .. node.guid .. "_" .. index)
  
  local event_name = trigger.event or "OnEvent"
  local changed, new_event = ImGui.InputText(ctx, "##event", event_name)
  if changed then
    trigger.event = new_event
  end
  
  ImGui.PopID(ctx)
  ImGui.PopItemWidth(ctx)
  
  y = y + trigger_config.item_height
  
  -- Target dropdown
  Draw.text(dl, indent, y, config.colors.text.body, "→")
  ImGui.SetCursorScreenPos(ctx, indent + trigger_config.label_width, y - 2)
  ImGui.PushItemWidth(ctx, item_width - trigger_config.label_width - trigger_config.mode_width - 4)
  ImGui.PushID(ctx, "trigger_target_" .. node.guid .. "_" .. index)
  
  local target_name = trigger.target_name or "Select Target..."
  
  if ImGui.BeginCombo(ctx, "##target", target_name) then
    for _, other_node in ipairs(M.available_nodes) do
      if other_node.guid ~= node.guid then  -- Don't allow self-targeting
        local is_selected = trigger.target_section == other_node.guid
        if ImGui.Selectable(ctx, other_node.name, is_selected) then
          trigger.target_section = other_node.guid
          trigger.target_name = other_node.name
          changed = true
        end
      end
    end
    ImGui.EndCombo(ctx)
  end
  
  ImGui.PopID(ctx)
  ImGui.PopItemWidth(ctx)
  
  -- Mode dropdown
  ImGui.SameLine(ctx, 0, 4)
  ImGui.PushItemWidth(ctx, trigger_config.mode_width)
  ImGui.PushID(ctx, "trigger_mode_" .. node.guid .. "_" .. index)
  
  local mode = trigger.mode or "INCREMENTAL"
  if ImGui.BeginCombo(ctx, "##mode", mode) then
    local modes = {"IMMEDIATE", "INCREMENTAL", "END_OF_SEGMENT"}
    for _, m in ipairs(modes) do
      if ImGui.Selectable(ctx, m, mode == m) then
        trigger.mode = m
        changed = true
      end
    end
    ImGui.EndCombo(ctx)
  end
  
  ImGui.PopID(ctx)
  ImGui.PopItemWidth(ctx)
  
  -- Delete button
  ImGui.SameLine(ctx, 0, 4)
  ImGui.PushID(ctx, "trigger_delete_" .. node.guid .. "_" .. index)
  local should_remove = ImGui.Button(ctx, "×", trigger_config.delete_button_size, trigger_config.delete_button_size)
  ImGui.PopID(ctx)
  
  return changed, should_remove
end

function M.render_add_trigger_button(ctx, node, config)
  local trigger_config = config.trigger_ui
  local button_width = node.width - config.node.padding * 2 - trigger_config.indent
  
  -- Calculate y position based on current content
  local y_offset = node.y + config.node.header_height + config.node.body_padding_top + 
                   (config.node.body_line_height * 3) + config.node.body_padding_bottom + 
                   config.node.trigger_section_padding_top
  
  if node.triggers and #node.triggers > 0 then
    y_offset = y_offset + trigger_config.section_label_height
    y_offset = y_offset + (#node.triggers * ((trigger_config.item_height * 2) + trigger_config.item_spacing))
  end
  
  local x = node.x + config.node.padding + trigger_config.indent
  ImGui.SetCursorScreenPos(ctx, x, y_offset)
  ImGui.PushID(ctx, "add_trigger_" .. node.guid)
  
  if ImGui.Button(ctx, trigger_config.add_button_text, button_width, trigger_config.add_button_height) then
    -- Add new trigger
    if not node.triggers then
      node.triggers = {}
    end
    
    local new_trigger = {
      guid = reaper.genGuid(),
      event = "OnEvent" .. (#node.triggers + 1),
      target_section = nil,
      target_name = "Select Target...",
      mode = "INCREMENTAL",
    }

    node.triggers[#node.triggers + 1] = new_trigger

    -- Update node structure
    local Node = require('arkitekt.gui.widgets.editors.nodal.core.node')
    Node.update_ports(node)
    node.height = Node.calculate_height(node, config)
    
    -- Recalculate layout
    local Layout = require('arkitekt.gui.widgets.editors.nodal.systems.auto_layout')
    -- Note: Canvas should handle full layout recalc, but we update this node's height immediately
  end
  
  ImGui.PopID(ctx)
end

function M.render_ports(ctx, dl, node, config, base_color)
  -- Ports are still rendered for visual connections, but not interactive
  local trigger_y = node.y + config.node.header_height + config.port.trigger_start_y
  for i, trigger_port in ipairs(node.ports.triggers) do
    trigger_port.x = node.x + node.width + config.port.offset
    trigger_port.y = trigger_y + ((i - 1) * config.port.trigger_spacing)
    
    local color = config.colors.connection_types.trigger
    Port.render(ctx, dl, trigger_port, color, config)
  end
end

return M