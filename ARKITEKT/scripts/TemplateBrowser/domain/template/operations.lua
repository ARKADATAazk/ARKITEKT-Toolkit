-- @noindex
-- TemplateBrowser/domain/template/operations.lua
-- Template apply/insert operations

-- Dependencies (cached at module load per Lua Performance Guide)
local Logger = require('arkitekt.debug.logger')
local Persistence = require('TemplateBrowser.data.storage')

local M = {}

-- PRIVATE HELPERS

-- Remove blocks matching a pattern from chunk
-- Handles nested blocks by counting depth
local function _strip_blocks(chunk, block_pattern)
  local lines = {}
  local in_block = false
  local block_depth = 0

  for line in chunk:gmatch("[^\r\n]+") do
    -- Check if line starts a block we want to strip
    if line:match("^%s*<" .. block_pattern) then
      in_block = true
      block_depth = 1
    elseif in_block then
      -- Count nested blocks
      if line:match("^%s*<[A-Z_]+") then
        block_depth = block_depth + 1
      elseif line:match("^%s*>%s*$") then
        block_depth = block_depth - 1
        if block_depth == 0 then
          in_block = false
        end
      end
    else
      -- Keep this line
      lines[#lines + 1] = line
    end
  end

  return table.concat(lines, "\n")
end

-- Filter chunk based on options
local function _filter_chunk(chunk, opts)
  opts = opts or {}
  local filtered = chunk

  -- Strip items if not included
  if not opts.include_items then
    filtered = _strip_blocks(filtered, "ITEM")
  end

  -- Strip envelopes if not included
  if not opts.include_envelopes then
    -- Strip all envelope types: VOLENV, PANENV, AUXENV, etc.
    filtered = _strip_blocks(filtered, "[A-Z_]*ENV[0-9]*")
  end

  return filtered
end

-- PUBLIC API

-- Apply template to selected track(s)
function M.apply_to_selected_track(template_path, template_uuid, state)
  local track_count = reaper.CountSelectedTracks(0)

  if track_count == 0 then
    state.set_status("No track selected. Please select a track first.", "warning")
    return false
  end

  -- Read template file
  local f, err = io.open(template_path, "r")
  if not f then
    Logger.error("TEMPLATE", "Failed to read: %s - %s", template_path, err or "unknown")
    state.set_status("Could not read template file", "error")
    return false
  end
  local chunk = f:read("*all")
  f:close()

  reaper.Undo_BeginBlock()

  for i = 0, track_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      reaper.SetTrackStateChunk(track, chunk, false)
    end
  end

  reaper.Undo_EndBlock("Apply Track Template", -1)
  reaper.UpdateArrange()

  -- Track usage
  if template_uuid and state.metadata then
    local tmpl_metadata = state.metadata.templates[template_uuid]
    if tmpl_metadata then
      local now = os.time()
      tmpl_metadata.usage_count = (tmpl_metadata.usage_count or 0) + 1
      tmpl_metadata.last_used = now
      -- Add to usage history for time-based statistics
      if not tmpl_metadata.usage_history then
        tmpl_metadata.usage_history = {}
      end
      tmpl_metadata.usage_history[#tmpl_metadata.usage_history + 1] = now
      Persistence.save_metadata(state.metadata)
    end
  end

  return true
end

-- Insert template as new track(s)
function M.insert_as_new_track(template_path, template_uuid, state)
  -- Get insertion point (after selected track, or at end)
  local sel_track = reaper.GetSelectedTrack(0, 0)
  local insert_idx = sel_track
    and reaper.GetMediaTrackInfo_Value(sel_track, "IP_TRACKNUMBER")
    or reaper.CountTracks(0)

  -- Read template file
  local f, err = io.open(template_path, "r")
  if not f then
    Logger.error("TEMPLATE", "Failed to read: %s - %s", template_path, err or "unknown")
    state.set_status("Could not read template file", "error")
    return false
  end
  local chunk = f:read("*all")
  f:close()

  reaper.Undo_BeginBlock()

  -- Count how many tracks are in the template
  local track_count = 0
  for line in chunk:gmatch("[^\r\n]+") do
    if line:match("^<TRACK") then
      track_count = track_count + 1
    end
  end

  if track_count == 0 then track_count = 1 end

  -- Insert first track at position
  reaper.InsertTrackAtIndex(insert_idx, true)
  local new_track = reaper.GetTrack(0, insert_idx)

  if new_track then
    reaper.SetTrackStateChunk(new_track, chunk, false)
    reaper.SetOnlyTrackSelected(new_track)
  end

  reaper.Undo_EndBlock("Insert Track Template", -1)
  reaper.UpdateArrange()
  reaper.TrackList_AdjustWindows(false)

  -- Track usage
  if template_uuid and state.metadata then
    local tmpl_metadata = state.metadata.templates[template_uuid]
    if tmpl_metadata then
      local now = os.time()
      tmpl_metadata.usage_count = (tmpl_metadata.usage_count or 0) + 1
      tmpl_metadata.last_used = now
      -- Add to usage history for time-based statistics
      if not tmpl_metadata.usage_history then
        tmpl_metadata.usage_history = {}
      end
      tmpl_metadata.usage_history[#tmpl_metadata.usage_history + 1] = now
      Persistence.save_metadata(state.metadata)
    end
  end

  return true
end

-- Save selected track(s) as template
-- opts: {
--   name: string - Template name (required)
--   folder: string - Subfolder path (optional, relative to TrackTemplates)
--   include_items: boolean - Include media items (default: false)
--   include_envelopes: boolean - Include automation envelopes (default: true)
-- }
function M.save_template(opts, state)
  opts = opts or {}

  if not opts.name or opts.name == "" then
    state.set_status("Template name is required", "error")
    return false, "Name required"
  end

  local track_count = reaper.CountSelectedTracks(0)
  if track_count == 0 then
    state.set_status("No track selected. Please select a track to save.", "warning")
    return false, "No track selected"
  end

  -- Get base templates directory
  local templates_dir = reaper.GetResourcePath() .. "/TrackTemplates"
  local sep = package.config:sub(1,1)

  -- Add subfolder if specified
  local save_dir = templates_dir
  if opts.folder and opts.folder ~= "" then
    save_dir = save_dir .. sep .. opts.folder
    -- Create folder if it doesn't exist
    reaper.RecursiveCreateDirectory(save_dir, 0)
  end

  -- Build file path
  local file_path = save_dir .. sep .. opts.name
  if not file_path:match("%.RTrackTemplate$") then
    file_path = file_path .. ".RTrackTemplate"
  end

  -- Check if file exists
  local existing = io.open(file_path, "r")
  if existing then
    existing:close()
    -- File exists - could add overwrite confirmation here
    -- For now, just proceed (will overwrite)
  end

  -- Collect chunks from all selected tracks
  local chunks = {}
  for i = 0, track_count - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
      local ret, chunk = reaper.GetTrackStateChunk(track, "", false)
      if ret then
        -- Filter chunk based on options
        chunk = _filter_chunk(chunk, {
          include_items = opts.include_items,
          include_envelopes = opts.include_envelopes == nil and true or opts.include_envelopes
        })
        chunks[#chunks + 1] = chunk
      end
    end
  end

  if #chunks == 0 then
    state.set_status("Failed to get track data", "error")
    return false, "Failed to get track chunk"
  end

  -- Combine chunks for multi-track templates
  local final_chunk = table.concat(chunks, "\n")

  -- Write to file
  local f, err = io.open(file_path, "w")
  if not f then
    Logger.error("TEMPLATE", "Failed to write: %s - %s", file_path, err or "unknown")
    state.set_status("Could not write template file", "error")
    return false, "Write failed: " .. (err or "unknown")
  end

  f:write(final_chunk)
  f:close()

  Logger.info("TEMPLATE", "Saved template: %s", file_path)
  state.set_status(string.format("Template '%s' saved successfully", opts.name), "success")

  return true, file_path
end

return M
