-- @noindex
-- ReArkitekt/features/region_playlist/engine/transport.lua
-- Transport control and seeking logic

local M = {}
local Transport = {}
Transport.__index = Transport

local function _has_sws()
  return (reaper.SNM_GetIntConfigVar ~= nil) and (reaper.SNM_SetIntConfigVar ~= nil)
end

local function _is_playing(proj)
  proj = proj or 0
  local st = reaper.GetPlayStateEx(proj)
  return (st & 1) == 1
end

local function _get_play_pos(proj)
  return reaper.GetPlayPositionEx(proj or 0)
end

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Transport)

  self.proj = opts.proj or 0
  self.state = opts.state

  self.transport_override = (opts.transport_override == true)
  self.loop_playlist = (opts.loop_playlist == true)
  self.follow_viewport = (opts.follow_viewport == true)
  self.shuffle_enabled = false  -- Initialize to false, will be set properly below

  self.is_playing = false
  self.is_paused = false  -- Track pause state separately from stopped
  self.last_seek_time = 0
  self.seek_throttle = 0.06

  self._playlist_mode = false
  self._old_smoothseek = nil
  self._old_repeat = nil
  self._old_smooth_scroll = nil

  -- Set shuffle mode first if provided
  if opts.shuffle_mode and self.state and self.state.set_shuffle_mode then
    self.state:set_shuffle_mode(opts.shuffle_mode)
  end

  -- Set shuffle after initialization to trigger state sync
  if opts.shuffle_enabled then
    self:set_shuffle_enabled(true)
  end

  return self
end

function Transport:_enter_playlist_mode_if_needed()
  if self._playlist_mode then return end

  -- Save and override SWS settings
  if _has_sws() then
    self._old_smoothseek = reaper.SNM_GetIntConfigVar("smoothseek", -1)
    reaper.SNM_SetIntConfigVar("smoothseek", 3)

    self._old_repeat = reaper.GetSetRepeat(-1)
    if self._old_repeat == 1 then
      reaper.GetSetRepeat(0)
    end
  end

  -- Save and enable continuous scrolling if Follow Viewport is enabled
  -- Command 41817: View: Toggle continuous scrolling during playback
  if self.follow_viewport then
    self._old_smooth_scroll = reaper.GetToggleCommandState(41817)
    if self._old_smooth_scroll == 0 then
      reaper.Main_OnCommand(41817, 0)  -- Enable smooth scroll
    end
  end

  self._playlist_mode = true
end

function Transport:_leave_playlist_mode_if_needed()
  if not self._playlist_mode then return end

  -- Restore SWS settings
  if _has_sws() then
    if self._old_smoothseek ~= nil then
      reaper.SNM_SetIntConfigVar("smoothseek", self._old_smoothseek)
      self._old_smoothseek = nil
    end
    if self._old_repeat == 1 then
      reaper.GetSetRepeat(1)
    end
    self._old_repeat = nil
  end

  -- Restore continuous scrolling to original state
  -- Command 41817: View: Toggle continuous scrolling during playback
  if self._old_smooth_scroll ~= nil then
    local current_state = reaper.GetToggleCommandState(41817)
    if current_state ~= self._old_smooth_scroll then
      reaper.Main_OnCommand(41817, 0)  -- Toggle back to original
    end
    self._old_smooth_scroll = nil
  end

  self._playlist_mode = false
end

function Transport:_seek_to_region(region_num)
  local now = reaper.time_precise()
  if now - self.last_seek_time < self.seek_throttle then
    return false
  end
  
  local cursor_pos = reaper.GetCursorPositionEx(self.proj)
  
  reaper.PreventUIRefresh(1)
  reaper.GoToRegion(self.proj, region_num, false)
  
  if not _is_playing(self.proj) then
    reaper.OnPlayButton()
  end
  
  reaper.SetEditCurPos2(self.proj, cursor_pos, false, false)
  reaper.PreventUIRefresh(-1)
  
  self.last_seek_time = now
  return true
end

function Transport:play()
  local rid = self.state:get_current_rid()
  if not rid then return false end

  local region = self.state:get_region_by_rid(rid)
  if not region then return false end

  self:_enter_playlist_mode_if_needed()

  -- Detect pause/resume using is_paused flag
  local is_resuming = self.is_paused

  if _is_playing(self.proj) then
    local region_num = region.rid
    self:_seek_to_region(region_num)
  else
    if is_resuming then
      -- Resuming from pause - just unpause without seeking
      reaper.OnPlayButton()
    else
      -- Starting fresh - seek to region start and reset indices
      reaper.SetEditCurPos2(self.proj, region.start, false, false)
      reaper.OnPlayButton()
      self.state.current_idx = -1
      self.state.next_idx = self.state.playlist_pointer
    end
  end

  self.is_playing = true
  self.is_paused = false  -- Clear pause state when playing
  self.state:update_bounds()

  return true
end

function Transport:pause()
  -- Pause without resetting playlist position (for resume)
  reaper.OnStopButton()
  self.is_playing = false
  self.is_paused = true  -- Set pause flag so resume detection works
  -- Don't reset current_idx, next_idx, or playlist_pointer - keep for resume
  -- Don't leave playlist mode - we might resume
end

function Transport:stop()
  reaper.OnStopButton()
  self.is_playing = false
  self.is_paused = false  -- Clear pause flag
  self.state.current_idx = -1
  self.state.next_idx = -1
  self.state.playlist_pointer = 1  -- Reset to beginning for next play
  self:_leave_playlist_mode_if_needed()
end

function Transport:next()
  if #self.state.playlist_order == 0 then return false end
  if self.state.playlist_pointer >= #self.state.playlist_order then return false end
  
  self.state.playlist_pointer = self.state.playlist_pointer + 1

  if _is_playing(self.proj) then
    local rid = self.state:get_current_rid()
    local region = self.state:get_region_by_rid(rid)
    if region then
      return self:_seek_to_region(region.rid)
    end
  else
    return self:play()
  end
  
  return false
end

function Transport:prev()
  if #self.state.playlist_order == 0 then return false end
  if self.state.playlist_pointer <= 1 then return false end
  
  self.state.playlist_pointer = self.state.playlist_pointer - 1

  if _is_playing(self.proj) then
    local rid = self.state:get_current_rid()
    local region = self.state:get_region_by_rid(rid)
    if region then
      return self:_seek_to_region(region.rid)
    end
  else
    return self:play()
  end
  
  return false
end

function Transport:poll_transport_sync()
  if not self.transport_override then return end
  if self.is_playing then return end
  if not _is_playing(self.proj) then return end
  
  local playpos = _get_play_pos(self.proj)
  
  for i, rid in ipairs(self.state.playlist_order) do
    local region = self.state:get_region_by_rid(rid)
    if region then
      if playpos >= region.start and playpos < region["end"] then
        self.state.playlist_pointer = i
        self.is_playing = true
        self.state.current_idx = i
        
        local meta = self.state.playlist_metadata[i]
        local should_loop = meta and meta.current_loop < meta.reps
        
        if should_loop then
          self.state.next_idx = i
        else
          if i < #self.state.playlist_order then
            self.state.next_idx = i + 1
          elseif self.loop_playlist and #self.state.playlist_order > 0 then
            self.state.next_idx = 1
          else
            self.state.next_idx = -1
          end
        end
        
        self.state:update_bounds()
        self:_enter_playlist_mode_if_needed()
        return
      end
    end
  end
end

function Transport:set_transport_override(enabled)
  self.transport_override = not not enabled
end

function Transport:get_transport_override()
  return self.transport_override
end

function Transport:set_follow_viewport(enabled)
  local was_enabled = self.follow_viewport
  self.follow_viewport = not not enabled

  -- If we're already in playlist mode, update smooth scroll state immediately
  if self._playlist_mode then
    if enabled and not was_enabled then
      -- Enabling: save and enable smooth scroll
      if self._old_smooth_scroll == nil then
        self._old_smooth_scroll = reaper.GetToggleCommandState(41817)
        if self._old_smooth_scroll == 0 then
          reaper.Main_OnCommand(41817, 0)
        end
      end
    elseif not enabled and was_enabled then
      -- Disabling: restore smooth scroll
      if self._old_smooth_scroll ~= nil then
        local current_state = reaper.GetToggleCommandState(41817)
        if current_state ~= self._old_smooth_scroll then
          reaper.Main_OnCommand(41817, 0)
        end
        self._old_smooth_scroll = nil
      end
    end
  end
end

function Transport:get_follow_viewport()
  return self.follow_viewport
end

function Transport:set_shuffle_enabled(enabled)
  self.shuffle_enabled = not not enabled
  -- Notify state to reshuffle if needed
  if self.state and self.state.on_shuffle_changed then
    self.state:on_shuffle_changed(enabled)
  end
end

function Transport:get_shuffle_enabled()
  return self.shuffle_enabled
end

function Transport:set_shuffle_mode(mode)
  if self.state and self.state.set_shuffle_mode then
    self.state:set_shuffle_mode(mode)
  end
end

function Transport:get_shuffle_mode()
  if self.state and self.state.get_shuffle_mode then
    return self.state:get_shuffle_mode()
  end
  return "true_shuffle"
end

function Transport:set_loop_playlist(enabled)
  self.loop_playlist = not not enabled
end

function Transport:get_loop_playlist()
  return self.loop_playlist
end

function Transport:check_stopped()
  if not _is_playing(self.proj) then
    if self.is_playing then
      self.is_playing = false
      -- Only reset indices if we're NOT paused (external stop, not our pause button)
      if not self.is_paused then
        self.state.current_idx = -1
        self.state.next_idx = -1
        -- Don't reset playlist_pointer here - user might be pausing to resume later
        -- Only reset when user explicitly presses Stop button
        self:_leave_playlist_mode_if_needed()
      end
      return true
    end
  end
  return false
end

M.Transport = Transport
M._is_playing = _is_playing
M._get_play_pos = _get_play_pos
M._has_sws = _has_sws
return M