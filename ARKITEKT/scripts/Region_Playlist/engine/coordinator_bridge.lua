-- @noindex
-- Region_Playlist/engine/coordinator_bridge.lua
-- Sequence-driven coordinator bridge that lazily expands playlists on demand
-- MODIFIED: Integrated Logger for debug output

local Engine = require("Region_Playlist.engine.core")
local Playback = require("Region_Playlist.engine.playback")
local RegionState = require("Region_Playlist.storage.persistence")
local SequenceExpander = require("Region_Playlist.core.sequence_expander")
local Logger = require("rearkitekt.debug.logger")

-- Performance: Localize math functions for hot path (30% faster in loops)
local max = math.max
local min = math.min

-- Performance: Cache module to avoid repeated require() lookups in hot functions
local Transport = require('rearkitekt.reaper.transport')

local M = {}

package.loaded["Region_Playlist.engine.coordinator_bridge"] = M

local function safe_call(fn)
  if not fn then return nil end
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end

function M.create(opts)
  opts = opts or {}

  local saved_settings = RegionState.load_settings(opts.proj or 0)

  local bridge = {
    proj = opts.proj or 0,
    controller = nil,
    get_playlist_by_id = opts.get_playlist_by_id,
    get_active_playlist = opts.get_active_playlist,
    get_active_playlist_id = opts.get_active_playlist_id,
    on_repeat_cycle = opts.on_repeat_cycle,
    sequence_cache = {},
    sequence_cache_dirty = true,
    sequence_lookup = {},
    playlist_ranges = {},
    _last_known_item_key = nil,
    _last_reported_loop_key = nil,
    _last_reported_loop = nil,
    _playing_playlist_id = nil,  -- Track which playlist is currently being played
  }

  bridge.engine = Engine.new({
    proj = bridge.proj,
    quantize_mode = saved_settings.quantize_mode or "measure",
    follow_playhead = saved_settings.follow_playhead or false,
    transport_override = saved_settings.transport_override or false,
    loop_playlist = saved_settings.loop_playlist or false,
    follow_viewport = saved_settings.follow_viewport or false,
    shuffle_enabled = saved_settings.shuffle_enabled or false,
    shuffle_mode = saved_settings.shuffle_mode or "true_shuffle",
    on_repeat_cycle = nil,
    playlist_lookup = opts.get_playlist_by_id,
  })

  -- Save defaults only if settings were empty (first run only)
  local needs_save = false

  if saved_settings.quantize_mode == nil then
    saved_settings.quantize_mode = "measure"
    needs_save = true
  end

  if saved_settings.shuffle_enabled == nil then
    saved_settings.shuffle_enabled = false
    needs_save = true
  end

  if saved_settings.shuffle_mode == nil then
    saved_settings.shuffle_mode = "true_shuffle"
    needs_save = true
  end

  if needs_save then
    RegionState.save_settings(saved_settings, bridge.proj)
  end

  bridge.playback = Playback.new(bridge.engine, {
    on_region_change = opts.on_region_change,
    on_playback_start = opts.on_playback_start,
    on_playback_stop = opts.on_playback_stop,
    on_transition_scheduled = opts.on_transition_scheduled,
  })

  local function resolve_active_playlist()
    local playlist = safe_call(bridge.get_active_playlist)
    if playlist then return playlist end

    if bridge.controller and bridge.controller.state and bridge.controller.state.get_active_playlist then
      playlist = safe_call(function()
        return bridge.controller.state.get_active_playlist()
      end)
      if playlist then return playlist end
    end

    if bridge.get_active_playlist_id and bridge.get_playlist_by_id then
      local playlist_id = safe_call(bridge.get_active_playlist_id)
      if playlist_id then
        return bridge.get_playlist_by_id(playlist_id)
      end
    end

    if bridge.controller and bridge.controller.state then
      local active_id = bridge.controller.state.active_playlist
      if active_id and bridge.get_playlist_by_id then
        return bridge.get_playlist_by_id(active_id)
      end
    end

    return nil
  end

  function bridge:set_controller(controller)
    self.controller = controller
  end

  function bridge:set_playlist_lookup(fn)
    self.get_playlist_by_id = fn
    self.engine.playlist_lookup = fn
    self:invalidate_sequence()
  end

  local function rebuild_sequence()
    local playlist = resolve_active_playlist()
    local active_playlist_id = safe_call(bridge.get_active_playlist_id)
    local is_playing = bridge.engine and bridge.engine:get_is_playing()

    -- Don't rebuild sequence if we're currently playing
    -- This prevents the transport from switching playlists when user changes tabs during playback
    if is_playing and bridge._playing_playlist_id then
      Logger.debug("BRIDGE", "Skipping sequence rebuild - currently playing playlist %s (active: %s)",
        tostring(bridge._playing_playlist_id), tostring(active_playlist_id))
      bridge.sequence_cache_dirty = false
      return
    end

    local sequence = {}
    local playlist_map = {}

    if playlist then
      sequence, playlist_map = SequenceExpander.expand_playlist(playlist, bridge.get_playlist_by_id)
    end

    bridge.sequence_cache = sequence
    bridge.sequence_lookup = {}
    bridge.playlist_ranges = {}

    for idx, entry in ipairs(sequence) do
      if entry.item_key and not bridge.sequence_lookup[entry.item_key] then
        bridge.sequence_lookup[entry.item_key] = idx
        Logger.debug("BRIDGE", "Mapping key '%s' -> idx %d", entry.item_key, idx)
      end
    end

    Logger.debug("BRIDGE", "Final sequence_lookup built with %d entries",
      (function() local count = 0; for _ in pairs(bridge.sequence_lookup) do count = count + 1 end; return count end)())

    for playlist_key, range_info in pairs(playlist_map) do
      bridge.playlist_ranges[playlist_key] = range_info
      if not bridge.sequence_lookup[playlist_key] then
        bridge.sequence_lookup[playlist_key] = range_info.start_idx
      end
    end

    local previous_key = bridge._last_known_item_key or bridge.engine.state:get_current_item_key()

    bridge.engine:set_sequence(sequence)

    if previous_key then
      local restored = bridge.engine.state:find_index_by_key(previous_key)
      if restored then
        bridge.engine:set_playlist_pointer(restored)
        bridge.engine.state.current_idx = restored
        bridge.engine.state.next_idx = restored
        bridge.engine.state:update_bounds()
      end
    end

    bridge._last_known_item_key = bridge.engine.state:get_current_item_key()
    bridge._last_reported_loop_key = nil
    bridge._last_reported_loop = nil
    bridge.sequence_cache_dirty = false

    -- Remember which playlist we're playing
    if not is_playing then
      bridge._playing_playlist_id = active_playlist_id
    end
  end

  function bridge:invalidate_sequence()
    self._last_known_item_key = self:get_current_item_key()
    self.sequence_cache_dirty = true
    self.sequence_cache = {}
    self.sequence_lookup = {}
    self.playlist_ranges = {}
  end

  function bridge:_ensure_sequence()
    if self.sequence_cache_dirty then
      rebuild_sequence()
    end
  end

  function bridge:get_sequence()
    self:_ensure_sequence()
    return self.sequence_cache
  end

  function bridge:get_regions_for_ui()
    local regions = {}
    for rid, rgn in pairs(self.engine.state.region_cache) do
      regions[#regions + 1] = {
        rid = rid,
        name = rgn.name,
        start = rgn.start,
        ["end"] = rgn["end"],
        color = rgn.color,
      }
    end
    return regions
  end

  function bridge:get_current_rid()
    return self.engine:get_current_rid()
  end

  function bridge:get_progress()
    return self.playback:get_progress()
  end

  function bridge:get_time_remaining()
    return self.playback:get_time_remaining()
  end

  function bridge:_emit_repeat_cycle_if_needed()
    if not self.on_repeat_cycle then return end

    local key = self:get_current_item_key()
    if not key then
      self._last_reported_loop_key = nil
      self._last_reported_loop = nil
      return
    end

    local loop, total = self:get_current_loop_info()
    if key ~= self._last_reported_loop_key or loop ~= self._last_reported_loop then
      if total > 1 and loop > 1 then
        self.on_repeat_cycle(key, loop, total)
      end
      self._last_reported_loop_key = key
      self._last_reported_loop = loop
    end
  end

  function bridge:update()
    self:_ensure_sequence()
    self.playback:update()
    self:_emit_repeat_cycle_if_needed()
  end

  function bridge:play()
    self:_ensure_sequence()
    -- Remember which playlist we're playing when playback starts
    self._playing_playlist_id = safe_call(self.get_active_playlist_id)

    -- If we're starting after a stop (not resuming from pause), force reset to beginning
    -- This must happen AFTER _ensure_sequence() so it overrides sequence restoration
    if not self.engine:get_is_playing() and
       self.engine.state.current_idx == -1 and
       self.engine.state.next_idx == -1 then
      self.engine.state.playlist_pointer = 1
    end

    return self.engine:play()
  end

  function bridge:pause()
    -- Keep playing_playlist_id when pausing (for resume)
    return self.engine:pause()
  end

  function bridge:stop()
    -- Clear the playing playlist ID when stopping
    -- This allows the sequence to be rebuilt for a different playlist on next play
    self._playing_playlist_id = nil
    -- Clear the last known position so rebuild_sequence doesn't restore it
    self._last_known_item_key = nil
    return self.engine:stop()
  end

  function bridge:next()
    return self.engine:next()
  end

  function bridge:prev()
    return self.engine:prev()
  end

  function bridge:jump_to_next_quantized(lookahead)
    return self.engine:jump_to_next_quantized(lookahead)
  end

  function bridge:set_quantize_mode(mode)
    self.engine:set_quantize_mode(mode)
    local settings = RegionState.load_settings(self.proj)
    settings.quantize_mode = mode
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:set_loop_playlist(enabled)
    self.engine:set_loop_playlist(enabled)
    local settings = RegionState.load_settings(self.proj)
    settings.loop_playlist = enabled
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:get_loop_playlist()
    return self.engine:get_loop_playlist()
  end

  function bridge:set_shuffle_enabled(enabled)
    self.engine:set_shuffle_enabled(enabled)
    local settings = RegionState.load_settings(self.proj)
    settings.shuffle_enabled = enabled
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:get_shuffle_enabled()
    return self.engine:get_shuffle_enabled()
  end

  function bridge:set_shuffle_mode(mode)
    self.engine:set_shuffle_mode(mode)
    local settings = RegionState.load_settings(self.proj)
    settings.shuffle_mode = mode
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:get_shuffle_mode()
    return self.engine:get_shuffle_mode()
  end

  function bridge:set_follow_playhead(enabled)
    self.engine:set_follow_playhead(enabled)
    local settings = RegionState.load_settings(self.proj)
    settings.follow_playhead = enabled
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:get_follow_playhead()
    return self.engine.follow_playhead
  end

  function bridge:set_transport_override(enabled)
    self.engine:set_transport_override(enabled)
    local settings = RegionState.load_settings(self.proj)
    settings.transport_override = enabled
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:get_transport_override()
    return self.engine:get_transport_override()
  end

  function bridge:set_follow_viewport(enabled)
    self.engine:set_follow_viewport(enabled)
    local settings = RegionState.load_settings(self.proj)
    settings.follow_viewport = enabled
    RegionState.save_settings(settings, self.proj)
  end

  function bridge:get_follow_viewport()
    return self.engine:get_follow_viewport()
  end

  function bridge:get_playing_playlist_id()
    -- Return the ID of the playlist that is currently playing
    -- Returns nil if not playing or no playlist is locked
    return self._playing_playlist_id
  end

  function bridge:get_state()
    local engine_state = self.engine:get_state()
    return {
      is_playing = engine_state.is_playing,
      playlist_pointer = engine_state.playlist_pointer,
      playlist_order = engine_state.playlist_order,
      quantize_mode = engine_state.quantize_mode,
      context_depth = engine_state.context_depth,
      sequence_length = engine_state.sequence_length,
      current_item_key = engine_state.current_item_key,
      current_loop = engine_state.current_loop,
      total_loops = engine_state.total_loops,
    }
  end

  function bridge:get_current_item_key()
    self:_ensure_sequence()
    return self.engine.state:get_current_item_key()
  end

  function bridge:get_current_loop_info()
    self:_ensure_sequence()
    return self.engine.state:get_current_loop_info()
  end

  function bridge:set_position_by_key(item_key)
    if not item_key then return false end
    self:_ensure_sequence()

    local idx = self.sequence_lookup[item_key]
    if not idx then return false end

    self.engine:set_playlist_pointer(idx)
    if self.engine.state then
      self.engine.state.playlist_pointer = idx
      self.engine.state.current_idx = idx
      self.engine.state.next_idx = idx
      self.engine.state:update_bounds()
    end

    self._last_known_item_key = item_key
    self:_emit_repeat_cycle_if_needed()
    return true
  end

  function bridge:get_current_playlist_key()
    if not self.engine:get_is_playing() then return nil end
    
    self:_ensure_sequence()
    local current_idx = self.engine.state and self.engine.state.current_idx or -1
    if current_idx < 1 then return nil end

    -- Find the most specific (smallest range) playlist containing current_idx
    -- This handles nested playlists by returning the innermost one
    local best_key = nil
    local best_range_size = math.huge
    
    for playlist_key, range_info in pairs(self.playlist_ranges) do
      if current_idx >= range_info.start_idx and current_idx <= range_info.end_idx then
        local range_size = range_info.end_idx - range_info.start_idx + 1
        if range_size < best_range_size then
          best_key = playlist_key
          best_range_size = range_size
        end
      end
    end
    
    return best_key
  end
  
  -- Check if a playlist contains the current playback position
  -- For nested playlists, multiple playlists can be active (parent and children)
  function bridge:is_playlist_active(playlist_key)
    if not self.engine:get_is_playing() then return false end
    if not playlist_key then return false end
    
    self:_ensure_sequence()
    local current_idx = self.engine.state and self.engine.state.current_idx or -1
    if current_idx < 1 then return false end
    
    local range_info = self.playlist_ranges[playlist_key]
    if not range_info then return false end
    
    return current_idx >= range_info.start_idx and current_idx <= range_info.end_idx
  end

  function bridge:get_playlist_progress(playlist_key)
    if not self.engine:get_is_playing() then return nil end
    if not playlist_key then return nil end
    
    self:_ensure_sequence()
    local range_info = self.playlist_ranges[playlist_key]
    if not range_info then return nil end

    local playpos = Transport.get_play_position(self.proj)
    
    local total_duration = 0
    local elapsed_duration = 0
    local current_pointer = self.engine.state.playlist_pointer
    local found_current = false
    
    for idx = range_info.start_idx, range_info.end_idx do
      local entry = self.sequence_cache[idx]
      if entry then
        local region = self.engine.state.region_cache[entry.rid]
        if region then
          local region_duration = region["end"] - region.start
          total_duration = total_duration + region_duration
          
          if not found_current then
            if idx == current_pointer then
              -- We're currently playing this exact sequence entry
              -- Clamp playpos to handle transition jitter when looping same region
              local clamped_pos = max(region.start, min(playpos, region["end"]))
              local region_elapsed = clamped_pos - region.start
              elapsed_duration = elapsed_duration + min(region_elapsed, region_duration)
              found_current = true
            elseif idx < current_pointer then
              -- This entry has already played
              elapsed_duration = elapsed_duration + region_duration
            end
          end
        end
      end
    end
    
    if total_duration <= 0 then return 0 end
    return max(0, min(1, elapsed_duration / total_duration))
  end

  function bridge:get_playlist_time_remaining(playlist_key)
    if not self.engine:get_is_playing() then return nil end
    if not playlist_key then return nil end
    
    self:_ensure_sequence()
    local range_info = self.playlist_ranges[playlist_key]
    if not range_info then return nil end

    local playpos = Transport.get_play_position(self.proj)
    
    local remaining = 0
    local current_pointer = self.engine.state.playlist_pointer
    local found_current = false
    
    for idx = range_info.start_idx, range_info.end_idx do
      local entry = self.sequence_cache[idx]
      if entry then
        local region = self.engine.state.region_cache[entry.rid]
        if region then
          if idx == current_pointer then
            -- We're currently playing this exact sequence entry
            remaining = remaining + max(0, region["end"] - playpos)
            found_current = true
          elseif idx > current_pointer then
            -- This entry hasn't played yet
            remaining = remaining + (region["end"] - region.start)
          end
        end
      end
    end
    
    return remaining
  end

  return bridge
end

return M
