-- @noindex
-- Centralized font loading for ARKITEKT applications
-- Eliminates duplication of font loading logic across entry points

local Typography = require('arkitekt.defs.typography')

local M = {}

-- Helper to check if file exists
local function file_exists(path)
  local f = io.open(path, 'rb')
  if f then
    f:close()
    return true
  end
  return false
end

-- Find fonts directory relative to fonts.lua location
local function find_fonts_dir()
  local sep = package.config:sub(1,1)
  -- Get the path to this file (fonts.lua)
  local src = debug.getinfo(1, 'S').source:sub(2)
  local this_dir = src:match('(.*'..sep..')') or ('.'..sep)
  -- Go up from app/assets/ to app/
  local app_dir = this_dir:match('^(.*'..sep..')[^'..sep..']*'..sep..'$') or this_dir
  -- Go up from app/ to arkitekt/
  local arkitekt_dir = app_dir:match('^(.*'..sep..')[^'..sep..']*'..sep..'$') or app_dir
  -- Now add fonts/
  local fonts_dir = arkitekt_dir .. 'fonts' .. sep
  return fonts_dir
end

-- Export for use by other modules (e.g., shell.lua)
M.find_fonts_dir = find_fonts_dir

---Load standard ARKITEKT fonts and attach to ImGui context
---@param ImGui table ReaImGui module
---@param ctx userdata ImGui context to attach fonts to
---@param opts? table Optional size overrides: { default_size, title_size, monospace_size, orbitron_size, icons_size }
---@return table fonts Table with font objects and their sizes
function M.load(ImGui, ctx, opts)
  opts = opts or {}

  -- Use typography for default sizes, allow overrides
  local default_size = opts.default_size or Typography.SEMANTIC.body
  local title_size = opts.title_size or Typography.SEMANTIC.heading
  local monospace_size = opts.monospace_size or Typography.SEMANTIC.code
  local orbitron_size = opts.orbitron_size or (Typography.SEMANTIC.heading * 1.5)  -- Larger for branding
  local icons_size = opts.icons_size or 14  -- Default icon font size

  -- Find fonts directory
  local fonts_dir = find_fonts_dir()
  local roboto_regular = fonts_dir .. 'Roboto-Regular.ttf'
  local roboto_medium = fonts_dir .. 'Roboto-Medium.ttf'
  local mono = fonts_dir .. 'JetBrainsMono-Regular.ttf'
  local orbitron = fonts_dir .. 'Orbitron-Bold.ttf'
  local remixicon = fonts_dir .. 'remixicon.ttf'

  -- Create fonts - use Roboto for consistent cross-platform display with tabular figures
  local fonts = {
    default = file_exists(roboto_regular) and ImGui.CreateFontFromFile(roboto_regular, 0, 0) or ImGui.CreateFont('sans-serif', 0),
    default_size = default_size,

    title = file_exists(roboto_medium) and ImGui.CreateFontFromFile(roboto_medium, 0, 0) or ImGui.CreateFont('sans-serif', 0),
    title_size = title_size,

    monospace = file_exists(mono) and ImGui.CreateFontFromFile(mono, 0, 0) or ImGui.CreateFont('monospace', 0),
    monospace_size = monospace_size,

    orbitron = file_exists(orbitron) and ImGui.CreateFontFromFile(orbitron, 0, 0) or nil,
    orbitron_size = orbitron_size,

    icons = file_exists(remixicon) and ImGui.CreateFontFromFile(remixicon, 0, 0) or nil,
    icons_size = icons_size,
  }

  -- Attach all font objects to context
  for _, font in pairs(fonts) do
    if font and type(font) ~= "number" then
      ImGui.Attach(ctx, font)
    end
  end

  return fonts
end

return M
