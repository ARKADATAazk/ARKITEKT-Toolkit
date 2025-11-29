-- @description ARK DevKit - Launch ARKITEKT app from any worktree
-- @version 1.0.0
-- @author ARKADATA
-- @noindex
-- @about
--   # ARK DevKit
--
--   Development launcher for ARKITEKT apps across multiple git worktrees.
--
--   ## Features
--   - Auto-detects all ARKITEKT-Toolkit* worktrees
--   - Lists all ARK_*.lua entrypoints
--   - Persists state under REAPER/Data/ARKITEKT/DevKit/
--   - Single stable entry point for REAPER actions
--
--   ## Usage
--   1. Register this script as a REAPER action
--   2. Run it to select worktree and app
--   3. State is remembered between sessions

local reaper = reaper
local sep = package.config:sub(1,1)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function normalize(path)
  return (path:gsub(sep.."+$", ""))
end

local function dirname(path)
  path = normalize(path)
  local dir = path:match("^(.*"..sep..")")
  if not dir then return nil end
  return normalize(dir)
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(content)
  f:close()
  return true
end

----------------------------------------------------------------------
-- DevKit state under REAPER/Data/ARKITEKT/DevKit
----------------------------------------------------------------------

local function get_devkit_state_paths()
  local resource = reaper.GetResourcePath()  -- e.g. C:\Users\...\REAPER
  local data_dir = resource .. sep .. "Data" .. sep .. "ARKITEKT" .. sep .. "DevKit"
  reaper.RecursiveCreateDirectory(data_dir, 0)
  local state_path = data_dir .. sep .. "DevKit_State.lua"
  return data_dir, state_path
end

local function load_state()
  local _, state_path = get_devkit_state_paths()
  if not file_exists(state_path) then
    return {}
  end

  local ok, tbl = pcall(dofile, state_path)
  if not ok or type(tbl) ~= "table" then
    return {}
  end
  return tbl
end

local function save_state(state)
  local _, state_path = get_devkit_state_paths()
  local content = "return " .. string.format("{\n  base_dir = %q,\n  last_worktree_key = %q,\n  last_app_key = %q,\n}\n",
    state.base_dir or "",
    state.last_worktree_key or "",
    state.last_app_key or ""
  )
  write_file(state_path, content)
end

----------------------------------------------------------------------
-- Auto-detect base_dir & worktrees
----------------------------------------------------------------------

local function detect_default_base_dir()
  -- We assume this DevKit script lives in:
  --   <base_dir>/ARKITEKT-Toolkit/scripts/DevKit/ARK_DevKit.lua
  local src = debug.getinfo(1, "S").source:sub(2)
  local devkit_dir = dirname(src)
  if not devkit_dir then return nil end
  local scripts_dir = dirname(devkit_dir)     -- .../scripts
  if not scripts_dir then return nil end
  local repo_root = dirname(scripts_dir)      -- .../ARKITEKT-Toolkit
  if not repo_root then return nil end
  local base_dir = dirname(repo_root)         -- .../ (parent of all worktrees)
  return base_dir
end

local function find_worktrees(base_dir)
  base_dir = normalize(base_dir)
  local worktrees = {}

  local i = 0
  while true do
    local name = reaper.EnumerateSubdirectories(base_dir, i)
    if not name then break end
    if name == "ARKITEKT-Toolkit" or name:match("^ARKITEKT%-Toolkit%-") then
      local path = normalize(base_dir .. sep .. name)
      local key
      if name == "ARKITEKT-Toolkit" then
        key = "main"
      else
        -- e.g. ARKITEKT-Toolkit-tiles -> tiles
        key = name:sub(#"ARKITEKT-Toolkit-" + 1)
      end
      table.insert(worktrees, {
        key  = key,
        name = name,
        path = path
      })
    end
    i = i + 1
  end

  return worktrees
end

----------------------------------------------------------------------
-- Scan entrypoints inside a worktree
----------------------------------------------------------------------

local function find_entrypoints(worktree_path)
  local scripts_dir = normalize(worktree_path .. sep .. "scripts")
  local apps = {}

  local i = 0
  while true do
    local app_dir_name = reaper.EnumerateSubdirectories(scripts_dir, i)
    if not app_dir_name then break end
    local app_dir = normalize(scripts_dir .. sep .. app_dir_name)

    -- Look for ARK_*.lua inside this app dir
    local j = 0
    while true do
      local fname = reaper.EnumerateFiles(app_dir, j)
      if not fname then break end
      if fname:match("^ARK_.*%.lua$") then
        local full = normalize(app_dir .. sep .. fname)
        local app_key = app_dir_name         -- e.g. Region_Playlist
        table.insert(apps, {
          key       = app_key,
          name      = app_key,
          full_path = full
        })
      end
      j = j + 1
    end

    i = i + 1
  end

  return apps
end

----------------------------------------------------------------------
-- Simple text UI helpers
----------------------------------------------------------------------

local function choose_from_list(title, items, last_key)
  if #items == 0 then return nil end

  local lines = {}
  local default_index = 1

  for i, item in ipairs(items) do
    local label = item.label or (item.key .. " -> " .. (item.path or ""))
    lines[#lines+1] = string.format("%d) %s", i, label)
    if last_key and item.key == last_key then
      default_index = i
    end
  end

  local message = table.concat(lines, "\n")
  reaper.ShowConsoleMsg("") -- clear console
  reaper.ShowConsoleMsg(title .. "\n\n" .. message .. "\n\n")

  local ok, input = reaper.GetUserInputs(
    title,
    1,
    "Enter number (1-"..#items..")",
    tostring(default_index)
  )
  if not ok then return nil end

  local idx = tonumber(input)
  if not idx or idx < 1 or idx > #items then
    reaper.MB("Invalid selection.", title, 0)
    return nil
  end

  return items[idx]
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------

local state = load_state()

-- 1) Resolve base_dir
local base_dir = state.base_dir
if not base_dir or base_dir == "" then
  base_dir = detect_default_base_dir()
end

if not base_dir or base_dir == "" then
  local ok, input = reaper.GetUserInputs(
    "ARK DevKit - Base directory",
    1,
    "Base dir (where ARKITEKT-Toolkit* live):",
    ""
  )
  if not ok or input == "" then return end
  base_dir = input
end

base_dir = normalize(base_dir)

-- 2) Find worktrees
local worktrees = find_worktrees(base_dir)
if #worktrees == 0 then
  reaper.MB("No ARKITEKT-Toolkit* worktrees found in:\n\n" .. base_dir, "ARK DevKit error", 0)
  return
end

-- wrap worktrees for chooser
local wt_items = {}
for _, wt in ipairs(worktrees) do
  table.insert(wt_items, {
    key   = wt.key,
    label = string.format("[%s] %s", wt.key, wt.path),
    path  = wt.path,
    _raw  = wt
  })
end

-- 3) Choose worktree
local selected_wt = choose_from_list("ARK DevKit - Select worktree", wt_items, state.last_worktree_key)
if not selected_wt then return end

state.base_dir = base_dir
state.last_worktree_key = selected_wt.key
save_state(state)

-- 4) Find entrypoints in this worktree
local apps = find_entrypoints(selected_wt.path)
if #apps == 0 then
  reaper.MB("No ARK_*.lua entrypoints found under:\n\n" .. selected_wt.path .. sep .. "scripts", "ARK DevKit error", 0)
  return
end

local app_items = {}
for _, app in ipairs(apps) do
  table.insert(app_items, {
    key   = app.key,
    label = string.format("[%s] %s", app.key, app.full_path),
    path  = app.full_path,
    _raw  = app
  })
end

-- 5) Choose app/entrypoint
local selected_app = choose_from_list("ARK DevKit - Select app", app_items, state.last_app_key)
if not selected_app then return end

state.last_app_key = selected_app.key
save_state(state)

-- 6) Launch
local entry = selected_app.path
if not file_exists(entry) then
  reaper.MB("Selected entrypoint not found:\n\n" .. entry, "ARK DevKit error", 0)
  return
end

dofile(entry)
