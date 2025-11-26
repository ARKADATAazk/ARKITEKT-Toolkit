-- @noindex
-- arkitekt/gui/widgets/containers/tile_group/init.lua
-- Tile grouping system for organizing Grid items into collapsible groups
--
-- Usage:
--   local TileGroup = require('arkitekt.gui.widgets.containers.tile_group')
--
--   -- Create group structure
--   local groups = {
--     TileGroup.create_group({
--       id = "group_1",
--       name = "Custom Meters",
--       color = "#FF6600",
--       collapsed = false,
--       items = {item1, item2, item3}
--     }),
--     TileGroup.create_group({...})
--   }
--
--   -- In your Grid's get_items() function:
--   function get_items()
--     local ungrouped = {...}  -- Items not in any group
--     return TileGroup.flatten_groups(groups, ungrouped)
--   end
--
--   -- In your Grid's render_tile() function:
--   function render_tile(ctx, rect, item, state, grid)
--     if TileGroup.is_group_header(item) then
--       local clicked = TileGroup.render_header(ctx, rect, item, state)
--       if clicked then
--         TileGroup.toggle_group(item)
--         -- Trigger grid refresh if needed
--       end
--     else
--       -- Render regular tile
--       render_regular_tile(ctx, rect, item, state)
--     end
--   end

local Header = require('arkitekt.gui.widgets.containers.tile_group.header')
local Defaults = require('arkitekt.gui.widgets.containers.tile_group.defaults')

local M = {}

-- Item type markers
M.ITEM_TYPE = {
  GROUP_HEADER = "__tile_group_header__",
  GROUPED_ITEM = "__tile_group_item__",
  REGULAR_ITEM = "__regular_item__",
}

--- Creates a new tile group structure
--- @param opts table {id, name, color, collapsed, items}
--- @return table - Group structure
function M.create_group(opts)
  return {
    id = opts.id or ("group_" .. tostring(math.random(100000))),
    name = opts.name or "Unnamed Group",
    color = opts.color,
    collapsed = opts.collapsed or false,
    items = opts.items or {},
    _tile_group_meta = true,  -- Internal marker
  }
end

--- Checks if an item is a group header
--- @param item table - Item to check
--- @return boolean
function M.is_group_header(item)
  return item and item.__type == M.ITEM_TYPE.GROUP_HEADER
end

--- Checks if an item is a grouped item (belongs to a group)
--- @param item table - Item to check
--- @return boolean
function M.is_grouped_item(item)
  return item and item.__group_id ~= nil
end

--- Checks if an item is part of the tile group system
--- @param item table - Item to check
--- @return boolean
function M.is_tile_group_item(item)
  return M.is_group_header(item) or M.is_grouped_item(item)
end

--- Toggles a group's collapsed state
--- @param group_header table - Group header item (with __group_ref)
function M.toggle_group(group_header)
  if M.is_group_header(group_header) and group_header.__group_ref then
    group_header.__group_ref.collapsed = not group_header.__group_ref.collapsed
  end
end

--- Sets a group's collapsed state
--- @param group_header table - Group header item
--- @param collapsed boolean - New collapsed state
function M.set_group_collapsed(group_header, collapsed)
  if M.is_group_header(group_header) and group_header.__group_ref then
    group_header.__group_ref.collapsed = collapsed
  end
end

--- Flattens groups and ungrouped items into a flat list for Grid consumption
--- This function creates the flat item list that Grid.get_items() should return
---
--- @param groups table - Array of group structures
--- @param ungrouped_items table - Optional array of items not in any group
--- @param opts table - Optional {indent_grouped_items = true}
--- @return table - Flat array of items with metadata
function M.flatten_groups(groups, ungrouped_items, opts)
  opts = opts or {}
  local indent_grouped = opts.indent_grouped_items ~= false  -- Default true

  local flat_items = {}

  -- Add groups
  for _, group in ipairs(groups or {}) do
    -- Add group header
    local header_item = {
      __type = M.ITEM_TYPE.GROUP_HEADER,
      __group_id = group.id,
      __group_ref = group,  -- Reference to the actual group for state changes
      name = group.name,
      color = group.color,
      collapsed = group.collapsed,
      count = #group.items,
    }
    flat_items[#flat_items + 1] = header_item

    -- Add group items if expanded
    if not group.collapsed then
      for _, item in ipairs(group.items) do
        -- Wrap item with metadata
        local wrapped_item = {
          __type = M.ITEM_TYPE.GROUPED_ITEM,
          __group_id = group.id,
          __indented = indent_grouped,
          __original = item,  -- Store original item
        }

        -- Copy all properties from original item to wrapped item
        -- This allows grid renderers to access item properties directly
        for k, v in pairs(item) do
          if not wrapped_item[k] then  -- Don't overwrite metadata
            wrapped_item[k] = v
          end
        end

        flat_items[#flat_items + 1] = wrapped_item
      end
    end
  end

  -- Add ungrouped items
  for _, item in ipairs(ungrouped_items or {}) do
    -- Wrap item to mark as ungrouped
    local wrapped_item = {
      __type = M.ITEM_TYPE.REGULAR_ITEM,
      __original = item,
    }

    -- Copy properties
    for k, v in pairs(item) do
      if not wrapped_item[k] then
        wrapped_item[k] = v
      end
    end

    flat_items[#flat_items + 1] = wrapped_item
  end

  return flat_items
end

--- Renders a group header
--- @param ctx ImGui context
--- @param rect table {x1, y1, x2, y2}
--- @param group_header table - Group header item
--- @param state table - {hover, selected, index}
--- @param config table - Optional styling overrides
--- @return boolean - True if clicked
function M.render_header(ctx, rect, group_header, state, config)
  if not M.is_group_header(group_header) then
    error("TileGroup.render_header: item is not a group header")
  end

  return Header.render(ctx, rect, group_header, state, config)
end

--- Gets the original item from a wrapped item
--- @param item table - Wrapped item
--- @return table - Original item, or item itself if not wrapped
function M.get_original_item(item)
  return item.__original or item
end

--- Gets the group ID for an item
--- @param item table - Item to check
--- @return string|nil - Group ID if item is part of a group
function M.get_group_id(item)
  return item.__group_id
end

--- Gets the indent amount for a grouped item
--- @param item table - Item to check
--- @param config table - Optional config with custom indent
--- @return number - Indent in pixels (0 if not indented)
function M.get_indent(item, config)
  if not item.__indented then
    return 0
  end

  config = config or {}
  return config.indent or Defaults.CONTENT.indent
end

--- Finds a group by ID
--- @param groups table - Array of groups
--- @param group_id string - Group ID to find
--- @return table|nil - Group structure or nil
function M.find_group(groups, group_id)
  for _, group in ipairs(groups) do
    if group.id == group_id then
      return group
    end
  end
  return nil
end

--- Collapses all groups
--- @param groups table - Array of groups
function M.collapse_all(groups)
  for _, group in ipairs(groups) do
    group.collapsed = true
  end
end

--- Expands all groups
--- @param groups table - Array of groups
function M.expand_all(groups)
  for _, group in ipairs(groups) do
    group.collapsed = false
  end
end

--- Gets the default header height
--- @param config table - Optional config
--- @return number - Header height in pixels
function M.get_header_height(config)
  return Header.get_height(config)
end

--- Helper to organize items into groups based on a grouping function
--- @param items table - Array of items to organize
--- @param group_fn function(item) - Returns {id, name, color} for each item, or nil for ungrouped
--- @return table, table - groups array, ungrouped items array
function M.organize_items(items, group_fn)
  local groups_map = {}  -- id -> group structure
  local ungrouped = {}

  for _, item in ipairs(items) do
    local group_info = group_fn(item)

    if group_info and group_info.id then
      -- Add to group
      if not groups_map[group_info.id] then
        groups_map[group_info.id] = M.create_group({
          id = group_info.id,
          name = group_info.name or group_info.id,
          color = group_info.color,
          collapsed = group_info.collapsed or false,
          items = {}
        })
      end

      local group_items = groups_map[group_info.id].items
      group_items[#group_items + 1] = item
    else
      -- Ungrouped item
      ungrouped[#ungrouped + 1] = item
    end
  end

  -- Convert groups_map to array
  local groups = {}
  for _, group in pairs(groups_map) do
    groups[#groups + 1] = group
  end

  -- Sort groups by name (optional - users can sort themselves)
  table.sort(groups, function(a, b) return a.name < b.name end)

  return groups, ungrouped
end

-- Export defaults for customization
M.Defaults = Defaults

return M
