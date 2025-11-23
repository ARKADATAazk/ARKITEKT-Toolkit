-- @noindex
-- ReArkitekt/reaper/regions.lua
-- REAPER Region API wrapper - uses native markrgnindexnumber as stable RID

local Colors = require('arkitekt.core.colors')
local hexrgb = Colors.hexrgb

local M = {}

local FALLBACK_COLOR = hexrgb("#4A5A6A")

local function convert_reaper_color_to_rgba(native_color)
  if not native_color or native_color == 0 then
    return FALLBACK_COLOR
  end

  -- Strip the custom color flag (0x1000000) before converting
  -- ColorFromNative expects just the RGB value
  local color_int = native_color & 0xFFFFFF
  local r, g, b = reaper.ColorFromNative(color_int)

  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

local function convert_rgba_to_reaper_color(rgba_color)
  return Colors.rgba_to_reaper_native(rgba_color)
end

function M.scan_project_regions(proj)
  proj = proj or 0
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  
  for i = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = 
      reaper.EnumProjectMarkers3(proj, i)
    
    if isrgn then
      regions[#regions + 1] = {
        rid = markrgnindexnumber,
        index = i,
        name = name,
        start = pos,
        ["end"] = rgnend,
        color = convert_reaper_color_to_rgba(color),
      }
    end
  end
  
  return regions
end

function M.get_region_by_rid(proj, target_rid)
  proj = proj or 0
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  
  for i = 0, num_markers + num_regions - 1 do
    local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = 
      reaper.EnumProjectMarkers3(proj, i)
    
    if isrgn and markrgnindexnumber == target_rid then
      return {
        rid = markrgnindexnumber,
        index = i,
        name = name,
        start = pos,
        ["end"] = rgnend,
        color = convert_reaper_color_to_rgba(color),
      }
    end
  end
  
  return nil
end

-- NEW (Seamless) Implementation using native API function
function M.go_to_region(proj, target_rid)
  proj = proj or 0
  local rgn = M.get_region_by_rid(proj, target_rid)
  if not rgn then return false end

  -- The core REAPER API function that performs a smooth seek to the region's start.
  -- The rgn.index (the internal marker index number) is the required 'region_index'.
  -- The 'false' argument tells REAPER to use the assigned region number, not the timeline order.
  -- This single call handles the smooth seek on its own, similar to the C++ extension.
  reaper.GoToRegion(proj, rgn.index, false)

  reaper.UpdateTimeline()
  return true
end

--- Set the color of a region by RID (internal - no undo block)
--- @param proj number Project (0 for current)
--- @param target_rid number Region ID (markrgnindexnumber)
--- @param rgba_color number Color in RGBA format
--- @return boolean success Whether the operation succeeded
local function set_region_color_raw(proj, target_rid, rgba_color)
  proj = proj or 0

  -- Get the current region data
  local rgn = M.get_region_by_rid(proj, target_rid)
  if not rgn then
    return false
  end

  -- Convert RGBA to native Reaper color
  local native_color = convert_rgba_to_reaper_color(rgba_color)

  local success = reaper.SetProjectMarkerByIndex2(
    proj,
    rgn.index,        -- marker/region index
    true,             -- isrgn (true for region)
    rgn.start,        -- position
    rgn["end"],       -- region end
    target_rid,       -- markrgnindexnumber (RID) - BEFORE name!
    rgn.name,         -- name - AFTER markrgnindexnumber!
    native_color,     -- color
    0                 -- flags
  )

  if success then
    reaper.MarkProjectDirty(proj)
  end

  return success
end

--- Set the color of a region by RID
--- @param proj number Project (0 for current)
--- @param target_rid number Region ID (markrgnindexnumber)
--- @param rgba_color number Color in RGBA format
--- @return boolean success Whether the operation succeeded
function M.set_region_color(proj, target_rid, rgba_color)
  reaper.Undo_BeginBlock()
  local success = set_region_color_raw(proj, target_rid, rgba_color)
  reaper.Undo_EndBlock("Set region color", -1)

  -- Force immediate visual update
  reaper.UpdateTimeline()
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  return success
end

M.set_region_color_raw = set_region_color_raw

--- Set region name (internal - no undo block)
--- @param proj number Project (0 for current)
--- @param target_rid number Region ID (markrgnindexnumber)
--- @param new_name string New name for the region
--- @return boolean success Whether the operation succeeded
local function set_region_name_raw(proj, target_rid, new_name)
  proj = proj or 0

  -- Get the current region data
  local rgn = M.get_region_by_rid(proj, target_rid)
  if not rgn then
    return false
  end

  -- Convert RGBA color back to REAPER's native format
  local native_color = convert_rgba_to_reaper_color(rgn.color)

  local success = reaper.SetProjectMarkerByIndex2(
    proj,
    rgn.index,        -- marker/region index
    true,             -- isrgn (true for region)
    rgn.start,        -- position
    rgn["end"],       -- region end
    target_rid,       -- markrgnindexnumber (RID) - BEFORE name!
    new_name,         -- name - AFTER markrgnindexnumber!
    native_color,     -- keep existing color (converted to native format)
    0                 -- flags
  )

  if success then
    reaper.MarkProjectDirty(proj)
  end

  return success
end

--- Set region name
--- @param proj number Project (0 for current)
--- @param target_rid number Region ID (markrgnindexnumber)
--- @param new_name string New name for the region
--- @return boolean success Whether the operation succeeded
function M.set_region_name(proj, target_rid, new_name)
  reaper.Undo_BeginBlock()
  local success = set_region_name_raw(proj, target_rid, new_name)
  reaper.Undo_EndBlock("Rename region", -1)

  -- Force immediate visual update
  reaper.UpdateTimeline()
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  return success
end

M.set_region_name_raw = set_region_name_raw

--- Set colors for multiple regions in a single batch operation
--- @param proj number Project (0 for current)
--- @param rids table Array of region IDs (markrgnindexnumber)
--- @param rgba_color number Color in RGBA format
--- @return number count Number of successfully updated regions
function M.set_region_colors_batch(proj, rids, rgba_color)
  proj = proj or 0

  if not rids or #rids == 0 then
    return 0
  end

  -- Convert color once for all regions
  local native_color = convert_rgba_to_reaper_color(rgba_color)

  -- Single undo block for all changes
  reaper.Undo_BeginBlock()

  local success_count = 0

  -- Update all regions
  for _, target_rid in ipairs(rids) do
    local rgn = M.get_region_by_rid(proj, target_rid)
    if rgn then
      local success = reaper.SetProjectMarkerByIndex2(
        proj,
        rgn.index,
        true,
        rgn.start,
        rgn["end"],
        target_rid,
        rgn.name,
        native_color,
        0
      )
      if success then
        success_count = success_count + 1
      end
    end
  end

  if success_count > 0 then
    reaper.MarkProjectDirty(proj)
  end

  reaper.Undo_EndBlock("Set region colors", -1)

  -- Single UI refresh for all changes
  reaper.UpdateTimeline()
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  return success_count
end

--- Rename multiple regions in a single batch operation
--- @param proj number Project (0 for current)
--- @param renames table Array of {rid = number, name = string} entries
--- @return number count Number of successfully updated regions
function M.set_region_names_batch(proj, renames)
  proj = proj or 0

  if not renames or #renames == 0 then
    return 0
  end

  -- Single undo block for all changes
  reaper.Undo_BeginBlock()

  local success_count = 0

  -- Update all regions
  for _, entry in ipairs(renames) do
    local target_rid = entry.rid
    local new_name = entry.name

    local rgn = M.get_region_by_rid(proj, target_rid)
    if rgn then
      -- Convert RGBA color back to REAPER's native format
      local native_color = convert_rgba_to_reaper_color(rgn.color)

      local success = reaper.SetProjectMarkerByIndex2(
        proj,
        rgn.index,
        true,
        rgn.start,
        rgn["end"],
        target_rid,
        new_name,
        native_color,
        0
      )
      if success then
        success_count = success_count + 1
      end
    end
  end

  if success_count > 0 then
    reaper.MarkProjectDirty(proj)
  end

  reaper.Undo_EndBlock("Rename regions", -1)

  -- Single UI refresh for all changes
  reaper.UpdateTimeline()
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  return success_count
end

return M