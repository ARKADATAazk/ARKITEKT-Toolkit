-- @noindex
-- TemplateBrowser/ui/shortcuts.lua
-- Keyboard shortcuts configuration and handling

local ImGui = require('arkitekt.platform.imgui')

local M = {}

-- Shortcut definitions
-- Format: { key, mods, action, description }
M.SHORTCUTS = {
  -- Search
  {
    key = "F",
    mods = {"Ctrl"},
    action = "focus_search",
    description = "Focus search box",
  },

  -- Template operations
  {
    key = "Enter",
    mods = {},
    action = "apply_template",
    description = "Apply selected template to track",
  },
  {
    key = "Enter",
    mods = {"Shift"},
    action = "insert_template",
    description = "Insert selected template as new track",
  },
  {
    key = "S",
    mods = {"Ctrl"},
    action = "save_template",
    description = "Save selected track(s) as template",
  },
  {
    key = "F2",
    mods = {},
    action = "rename_template",
    description = "Rename selected template",
  },
  {
    key = "Delete",
    mods = {},
    action = "archive_template",
    description = "Archive selected template(s)",
  },

  -- Navigation
  {
    key = "LeftArrow",
    mods = {},
    action = "navigate_left",
    description = "Navigate left in grid",
  },
  {
    key = "RightArrow",
    mods = {},
    action = "navigate_right",
    description = "Navigate right in grid",
  },
  {
    key = "UpArrow",
    mods = {},
    action = "navigate_up",
    description = "Navigate up in grid",
  },
  {
    key = "DownArrow",
    mods = {},
    action = "navigate_down",
    description = "Navigate down in grid",
  },

  -- Undo/Redo
  {
    key = "Z",
    mods = {"Ctrl"},
    action = "undo",
    description = "Undo last action",
  },
  {
    key = "Z",
    mods = {"Ctrl", "Shift"},
    action = "redo",
    description = "Redo last undone action",
  },

  -- Window
  {
    key = "Escape",
    mods = {},
    action = "close_window",
    description = "Close Template Browser",
  },
}

-- Check if a modifier is pressed
local function is_mod_pressed(ctx, mod)
  if mod == "Ctrl" then
    return ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
  elseif mod == "Shift" then
    return ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
  elseif mod == "Alt" then
    return ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)
  end
  return false
end

-- Check if all required modifiers are pressed and only those
local function check_mods(ctx, required_mods)
  local ctrl_required = false
  local shift_required = false
  local alt_required = false

  for _, mod in ipairs(required_mods) do
    if mod == "Ctrl" then ctrl_required = true end
    if mod == "Shift" then shift_required = true end
    if mod == "Alt" then alt_required = true end
  end

  local ctrl_pressed = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
  local shift_pressed = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
  local alt_pressed = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)

  return ctrl_pressed == ctrl_required and
         shift_pressed == shift_required and
         alt_pressed == alt_required
end

-- Get ImGui key constant from key name
local function get_key_constant(ctx, key_name)
  -- Map key names to ImGui constants
  local key_map = {
    -- Letters
    A = ImGui.Key_A, B = ImGui.Key_B, C = ImGui.Key_C, D = ImGui.Key_D,
    E = ImGui.Key_E, F = ImGui.Key_F, G = ImGui.Key_G, H = ImGui.Key_H,
    I = ImGui.Key_I, J = ImGui.Key_J, K = ImGui.Key_K, L = ImGui.Key_L,
    M = ImGui.Key_M, N = ImGui.Key_N, O = ImGui.Key_O, P = ImGui.Key_P,
    Q = ImGui.Key_Q, R = ImGui.Key_R, S = ImGui.Key_S, T = ImGui.Key_T,
    U = ImGui.Key_U, V = ImGui.Key_V, W = ImGui.Key_W, X = ImGui.Key_X,
    Y = ImGui.Key_Y, Z = ImGui.Key_Z,

    -- Function keys
    F1 = ImGui.Key_F1, F2 = ImGui.Key_F2, F3 = ImGui.Key_F3, F4 = ImGui.Key_F4,
    F5 = ImGui.Key_F5, F6 = ImGui.Key_F6, F7 = ImGui.Key_F7, F8 = ImGui.Key_F8,
    F9 = ImGui.Key_F9, F10 = ImGui.Key_F10, F11 = ImGui.Key_F11, F12 = ImGui.Key_F12,

    -- Arrow keys
    LeftArrow = ImGui.Key_LeftArrow,
    RightArrow = ImGui.Key_RightArrow,
    UpArrow = ImGui.Key_UpArrow,
    DownArrow = ImGui.Key_DownArrow,

    -- Other keys
    Enter = ImGui.Key_Enter,
    Escape = ImGui.Key_Escape,
    Delete = ImGui.Key_Delete,
    Backspace = ImGui.Key_Backspace,
    Tab = ImGui.Key_Tab,
    Space = ImGui.Key_Space,
  }

  return key_map[key_name]
end

-- Check if a shortcut is triggered
-- Returns: action_name (string or nil)
function M.check_shortcuts(ctx)
  for _, shortcut in ipairs(M.SHORTCUTS) do
    local key_constant = get_key_constant(ctx, shortcut.key)

    if key_constant and ImGui.IsKeyPressed(ctx, key_constant) then
      if check_mods(ctx, shortcut.mods) then
        return shortcut.action
      end
    end
  end

  return nil
end

-- Get formatted shortcut string for display
-- e.g., "Ctrl+F", "Shift+Enter", "Delete"
function M.format_shortcut(shortcut)
  local parts = {}

  for _, mod in ipairs(shortcut.mods) do
    parts[#parts + 1] = mod
  end

  parts[#parts + 1] = shortcut.key

  return table.concat(parts, "+")
end

-- Get all shortcuts as formatted strings (for help dialog)
function M.get_shortcuts_list()
  local list = {}

  for _, shortcut in ipairs(M.SHORTCUTS) do
    list[#list + 1] = {
      keys = M.format_shortcut(shortcut),
      description = shortcut.description,
      action = shortcut.action,
    }
  end

  return list
end

return M
