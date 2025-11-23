-- @noindex
-- ReArkitekt/reaper/region_operations.lua
-- Region playlist operations matching SWS behavior (Append, Paste, Crop, etc.)

local Colors = require('arkitekt.core.colors')

local M = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

--- Get project length based on last item end
local function get_project_length(proj)
  proj = proj or 0
  local length = 0

  for i = 0, reaper.CountTracks(proj) - 1 do
    local track = reaper.GetTrack(proj, i)
    for j = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local item_end = reaper.GetMediaItemInfo_Value(item, "D_POSITION") +
                      reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if item_end > length then
        length = item_end
      end
    end
  end

  return length
end

--- Split items at region boundaries and return items in region
local function split_items_in_region(proj, region_start, region_end)
  local items_in_region = {}

  for i = 0, reaper.CountMediaItems(proj) - 1 do
    local item = reaper.GetMediaItem(proj, i)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_pos + item_len

    -- Check if item overlaps with region
    if item_pos < region_end and item_end > region_start then
      -- Split at region start if item starts before
      if item_pos < region_start and item_end > region_start then
        reaper.SplitMediaItem(item, region_start)
      end

      -- Split at region end if item extends beyond
      if item_pos < region_end and item_end > region_end then
        reaper.SplitMediaItem(item, region_end)
      end

      -- Check if this item is now fully within region
      item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      item_end = item_pos + item_len

      if item_pos >= region_start and item_end <= region_end then
        table.insert(items_in_region, item)
      end
    end
  end

  return items_in_region
end

--- Duplicate items to target position
local function duplicate_items_to_position(items, time_offset)
  local new_items = {}

  for _, item in ipairs(items) do
    local track = reaper.GetMediaItem_Track(item)
    local _, chunk = reaper.GetItemStateChunk(item, "", false)

    -- Create new item
    local new_item = reaper.AddMediaItemToTrack(track)

    -- Set chunk
    reaper.SetItemStateChunk(new_item, chunk, false)

    -- Update position
    local old_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", old_pos + time_offset)

    table.insert(new_items, new_item)
  end

  return new_items
end

--- Copy tempo markers in range to target position
local function copy_tempo_markers(proj, source_start, source_end, time_offset)
  local tempo_count = reaper.CountTempoTimeSigMarkers(proj)

  for i = 0, tempo_count - 1 do
    local retval, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo =
      reaper.GetTempoTimeSigMarker(proj, i)

    if timepos >= source_start and timepos <= source_end then
      local new_time = timepos + time_offset
      reaper.SetTempoTimeSigMarker(proj, -1, new_time, -1, -1, bpm, timesig_num, timesig_denom, lineartempo)
    end
  end
end

--- Copy envelope points in range to target position
local function copy_envelope_points(proj, source_start, source_end, time_offset)
  for i = 0, reaper.CountTracks(proj) - 1 do
    local track = reaper.GetTrack(proj, i)
    for j = 0, reaper.CountTrackEnvelopes(track) - 1 do
      local envelope = reaper.GetTrackEnvelope(track, j)
      local num_points = reaper.CountEnvelopePoints(envelope)

      local points_to_copy = {}
      for k = 0, num_points - 1 do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(envelope, k)
        if time >= source_start and time <= source_end then
          table.insert(points_to_copy, {
            time = time + time_offset,
            value = value,
            shape = shape,
            tension = tension
          })
        end
      end

      -- Insert copied points
      for _, point in ipairs(points_to_copy) do
        reaper.InsertEnvelopePoint(envelope, point.time, point.value, point.shape, point.tension, false, true)
      end
    end
  end
end

--- Insert silence at position by moving everything after it
local function insert_silence(proj, position, length)
  -- Select all items after position
  reaper.SelectAllMediaItems(proj, false)

  for i = 0, reaper.CountMediaItems(proj) - 1 do
    local item = reaper.GetMediaItem(proj, i)
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

    if item_pos >= position then
      reaper.SetMediaItemSelected(item, true)
    end
  end

  -- Move selected items
  if reaper.CountSelectedMediaItems(proj) > 0 then
    reaper.ApplyNudge(proj, 0, 0, 0, length, false, 0)
  end

  -- Move tempo markers
  local tempo_count = reaper.CountTempoTimeSigMarkers(proj)
  for i = tempo_count - 1, 0, -1 do
    local retval, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo =
      reaper.GetTempoTimeSigMarker(proj, i)

    if timepos >= position then
      reaper.DeleteTempoTimeSigMarker(proj, i)
      reaper.SetTempoTimeSigMarker(proj, -1, timepos + length, -1, -1, bpm, timesig_num, timesig_denom, lineartempo)
    end
  end

  -- Move envelope points
  for i = 0, reaper.CountTracks(proj) - 1 do
    local track = reaper.GetTrack(proj, i)
    for j = 0, reaper.CountTrackEnvelopes(track) - 1 do
      local envelope = reaper.GetTrackEnvelope(track, j)
      local num_points = reaper.CountEnvelopePoints(envelope)

      local points_to_move = {}
      for k = num_points - 1, 0, -1 do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(envelope, k)
        if time >= position then
          table.insert(points_to_move, {idx = k, time = time, value = value, shape = shape, tension = tension})
        end
      end

      for _, point in ipairs(points_to_move) do
        reaper.DeleteEnvelopePointEx(envelope, -1, point.idx)
        reaper.InsertEnvelopePoint(envelope, point.time + length, point.value, point.shape, point.tension, false, true)
      end
    end
  end
end

-- ============================================================================
-- PUBLIC API - MATCHING SWS BEHAVIOR
-- ============================================================================

--- Append playlist to the end of the project
--- @param playlist_items table Array of {rid, reps} objects
--- @return boolean success
function M.append_playlist_to_project(playlist_items)
  if not playlist_items or #playlist_items == 0 then
    return false
  end

  local proj = 0
  local Regions = require('arkitekt.reaper.regions')

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- Get current project end
  local project_end = get_project_length(proj)
  local current_position = project_end

  -- Process each playlist item
  for _, pl_item in ipairs(playlist_items) do
    local rid = pl_item.rid
    local reps = pl_item.reps or 1

    local region = Regions.get_region_by_rid(proj, rid)
    if region then
      local region_length = region["end"] - region.start

      -- Split items in this region
      local items_in_region = split_items_in_region(proj, region.start, region["end"])

      -- Duplicate for each rep
      for rep = 1, reps do

        local time_offset = current_position - region.start

        -- Duplicate items
        duplicate_items_to_position(items_in_region, time_offset)

        -- Copy tempo markers
        copy_tempo_markers(proj, region.start, region["end"], time_offset)

        -- Copy envelope points
        copy_envelope_points(proj, region.start, region["end"], time_offset)

        -- Create region marker
        local new_region_start = current_position
        local new_region_end = current_position + region_length

        -- Convert RGBA color to native REAPER color
        local native_color = region.color and Colors.rgba_to_reaper_native(region.color) or 0

        reaper.AddProjectMarker2(proj, true, new_region_start, new_region_end, region.name or "", -1, native_color)

        current_position = current_position + region_length
      end
    end
  end

  reaper.Undo_EndBlock("Append playlist to project", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()

  return true
end

--- Paste playlist at edit cursor
--- @param playlist_items table Array of {rid, reps} objects
--- @return boolean success
function M.paste_playlist_at_cursor(playlist_items)
  if not playlist_items or #playlist_items == 0 then
    return false
  end

  local proj = 0
  local Regions = require('arkitekt.reaper.regions')

  -- Get edit cursor position
  local cursor_pos = reaper.GetCursorPosition()
  local project_end = get_project_length(proj)

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- Calculate total playlist length
  local total_length = 0
  for _, pl_item in ipairs(playlist_items) do
    local region = Regions.get_region_by_rid(proj, pl_item.rid)
    if region then
      local region_length = region["end"] - region.start
      local reps = pl_item.reps or 1
      total_length = total_length + (region_length * reps)
    end
  end

  -- Insert silence if pasting inside project
  if cursor_pos < project_end then
    insert_silence(proj, cursor_pos, total_length)
  end

  local current_position = cursor_pos

  -- Process each playlist item
  for _, pl_item in ipairs(playlist_items) do
    local rid = pl_item.rid
    local reps = pl_item.reps or 1

    local region = Regions.get_region_by_rid(proj, rid)
    if region then
      local region_length = region["end"] - region.start

      -- Split items in this region
      local items_in_region = split_items_in_region(proj, region.start, region["end"])

      -- Duplicate for each rep
      for rep = 1, reps do

        local time_offset = current_position - region.start

        -- Duplicate items
        duplicate_items_to_position(items_in_region, time_offset)

        -- Copy tempo markers
        copy_tempo_markers(proj, region.start, region["end"], time_offset)

        -- Copy envelope points
        copy_envelope_points(proj, region.start, region["end"], time_offset)

        -- Create region marker
        local new_region_start = current_position
        local new_region_end = current_position + region_length

        local native_color = region.color and Colors.rgba_to_reaper_native(region.color) or 0

        reaper.AddProjectMarker2(proj, true, new_region_start, new_region_end, region.name or "", -1, native_color)

        current_position = current_position + region_length
      end
    end
  end

  reaper.Undo_EndBlock("Paste playlist at cursor", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()

  return true
end

--- Crop project to playlist
--- @param playlist_items table Array of {rid, reps} objects
--- @return boolean success
function M.crop_to_playlist(playlist_items)
  if not playlist_items or #playlist_items == 0 then
    return false
  end

  local proj = 0
  local Regions = require('arkitekt.reaper.regions')

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- Build playlist content at position 0
  local current_position = 0
  local regions_to_create = {}

  for _, pl_item in ipairs(playlist_items) do
    local rid = pl_item.rid
    local reps = pl_item.reps or 1

    local region = Regions.get_region_by_rid(proj, rid)
    if region then
      local region_length = region["end"] - region.start

      -- Split items in this region
      local items_in_region = split_items_in_region(proj, region.start, region["end"])

      -- Duplicate for each rep
      for rep = 1, reps do
        local time_offset = current_position - region.start

        -- Duplicate items
        duplicate_items_to_position(items_in_region, time_offset)

        -- Copy tempo markers
        copy_tempo_markers(proj, region.start, region["end"], time_offset)

        -- Copy envelope points
        copy_envelope_points(proj, region.start, region["end"], time_offset)

        -- Store region for creation
        table.insert(regions_to_create, {
          start = current_position,
          ["end"] = current_position + region_length,
          name = region.name,
          color = region.color
        })

        current_position = current_position + region_length
      end
    end
  end

  local playlist_end = current_position

  -- Set time selection to playlist range
  reaper.GetSet_LoopTimeRange(true, false, 0, playlist_end, false)

  -- Crop project to time selection
  reaper.Main_OnCommand(40289, 0) -- Item: Remove items/tracks/envelope points/markers/regions/... Time selection

  -- Create region markers
  for _, rgn in ipairs(regions_to_create) do
    local native_color = rgn.color and Colors.rgba_to_reaper_native(rgn.color) or 0

    reaper.AddProjectMarker2(proj, true, rgn.start, rgn["end"], rgn.name or "", -1, native_color)
  end

  -- Clear time selection
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
  reaper.SetEditCurPos(0, false, false)

  reaper.Undo_EndBlock("Crop project to playlist", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()

  return true
end

--- Crop playlist to new project tab (SWS-style with undo trick)
--- @param playlist_items table Array of {rid, reps} objects
--- @param playlist_name string Name of the playlist to recreate
--- @param playlist_chip_color number Chip color of the playlist
--- @return boolean success
function M.crop_to_playlist_new_tab(playlist_items, playlist_name, playlist_chip_color)
  if not playlist_items or #playlist_items == 0 then
    return false
  end

  -- First, build the playlist in current project using crop_to_playlist logic
  local proj = 0
  local Regions = require('arkitekt.reaper.regions')

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  -- Build playlist content at position 0
  local current_position = 0
  local regions_to_create = {}

  for _, pl_item in ipairs(playlist_items) do
    local rid = pl_item.rid
    local reps = pl_item.reps or 1

    local region = Regions.get_region_by_rid(proj, rid)
    if region then
      local region_length = region["end"] - region.start

      -- Split items in this region
      local items_in_region = split_items_in_region(proj, region.start, region["end"])

      -- Duplicate for each rep
      for rep = 1, reps do
        local time_offset = current_position - region.start

        -- Duplicate items
        duplicate_items_to_position(items_in_region, time_offset)

        -- Copy tempo markers
        copy_tempo_markers(proj, region.start, region["end"], time_offset)

        -- Copy envelope points
        copy_envelope_points(proj, region.start, region["end"], time_offset)

        -- Store region for creation (preserving original RID!)
        table.insert(regions_to_create, {
          start = current_position,
          ["end"] = current_position + region_length,
          name = region.name,
          color = region.color,
          rid = rid,  -- CRITICAL: Store original RID for playlist recreation
          reps = reps  -- Store reps for playlist recreation
        })

        current_position = current_position + region_length
      end
    end
  end

  -- Store master track state
  local master_track = reaper.GetMasterTrack(proj)
  local _, master_chunk = reaper.GetTrackStateChunk(master_track, "", false)

  -- Select and copy all tracks
  reaper.Main_OnCommand(40296, 0) -- Track: Select all tracks
  reaper.Main_OnCommand(40210, 0) -- Track: Copy selected tracks

  reaper.PreventUIRefresh(-1)

  -- Undo trick: end block and undo to restore original project
  reaper.Undo_EndBlock("Crop playlist to new tab", -1)
  reaper.Undo_DoUndo2(0)

  -- Create new project tab with EMPTY project (no template)
  reaper.Main_OnCommand(41929, 0) -- File: New project tab (ignore default template)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Paste tracks
  reaper.Main_OnCommand(40058, 0) -- Track: Paste tracks/items
  reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks

  -- Restore master track
  local new_master = reaper.GetMasterTrack(0)
  reaper.SetTrackStateChunk(new_master, master_chunk, false)

  -- Create region markers with PRESERVED region numbers
  local region_rid_map = {}  -- Track which RID appears at which position for playlist
  for idx, rgn in ipairs(regions_to_create) do
    local native_color = 0
    if rgn.color then
      local r = (rgn.color >> 24) & 0xFF
      local g = (rgn.color >> 16) & 0xFF
      local b = (rgn.color >> 8) & 0xFF
      native_color = reaper.ColorToNative(r, g, b) | 0x1000000
    end

    -- Use the original RID (markrgnindexnumber) instead of -1 to preserve region numbers
    reaper.AddProjectMarker2(0, true, rgn.start, rgn["end"], rgn.name or "", rgn.rid, native_color)

    -- Track this region for playlist creation
    if not region_rid_map[rgn.rid] then
      region_rid_map[rgn.rid] = {rid = rgn.rid, reps = rgn.reps}
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Crop playlist to new tab", -1)
  reaper.UpdateArrange()

  -- Now recreate the playlist in the new project tab
  local State = require('RegionPlaylist.core.app_state')
  local UUID = require('arkitekt.core.uuid')

  -- Create new playlist with the same name
  local new_playlist = {
    id = UUID.generate(),
    name = playlist_name or "Cropped Playlist",
    items = {},
    chip_color = playlist_chip_color
  }

  -- Rebuild playlist items with the preserved RIDs
  for _, pl_item in ipairs(playlist_items) do
    table.insert(new_playlist.items, {
      type = "region",
      rid = pl_item.rid,  -- RID is preserved since we used it when creating regions
      reps = pl_item.reps or 1,
      enabled = true,
      key = UUID.generate()
    })
  end

  -- Add playlist to state
  local playlists = State.get_playlists()
  table.insert(playlists, new_playlist)
  State.set_active_playlist(new_playlist.id)
  State.persist()  -- Save to project

  return true
end

return M
