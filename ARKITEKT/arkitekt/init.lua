-- ARKITEKT Namespace
-- Provides ImGui-style access to all widgets via lazy loading
-- Auto-loads ImGui and bootstrap utilities
-- Usage: local Ark = dofile(debug.getinfo(1,"S").source:sub(2):match("(.-ARKITEKT[/\\])") .. "loader.lua")
--        local ctx = Ark.ImGui.CreateContext('My Script')
--        Ark.Button.draw(ctx, {label = "Click"})

-- ============================================================================
-- AUTO-BOOTSTRAP
-- ============================================================================
-- Run bootstrap to set up package paths and validate dependencies
local sep = package.config:sub(1,1)
local src = debug.getinfo(1,"S").source:sub(2)
-- Get the directory containing this init.lua (arkitekt/)
local arkitekt_dir = src:match("(.-arkitekt)[/\\]") or src:match("(.*)[/\\]")
if not arkitekt_dir then
  error("ARKITEKT init.lua: Cannot determine arkitekt directory from: " .. tostring(src))
end
local bootstrap_path = arkitekt_dir .. sep .. "arkitekt" .. sep .. "app" .. sep .. "bootstrap.lua"
-- If this file IS in arkitekt/, adjust path
if src:match("arkitekt[/\\]init%.lua$") then
  bootstrap_path = arkitekt_dir .. sep .. "app" .. sep .. "bootstrap.lua"
end
local bootstrap_context = dofile(bootstrap_path).init()

if not bootstrap_context then
  error("ARKITEKT bootstrap failed - cannot continue")
end

local Ark = {}

-- Expose ImGui directly (no need to require in every script)
Ark.ImGui = bootstrap_context.ImGui

-- Store full bootstrap context for advanced use cases
Ark._bootstrap = bootstrap_context

-- Module registry - maps names to module paths
-- Lazy loaded on first access to minimize startup overhead
local MODULES = {
  -- Primitives (alphabetically sorted)
  Badge = 'arkitekt.gui.widgets.primitives.badge',
  Button = 'arkitekt.gui.widgets.primitives.button',
  Checkbox = 'arkitekt.gui.widgets.primitives.checkbox',
  CloseButton = 'arkitekt.gui.widgets.primitives.close_button',
  Combo = 'arkitekt.gui.widgets.primitives.combo',
  CornerButton = 'arkitekt.gui.widgets.primitives.corner_button',
  HueSlider = 'arkitekt.gui.widgets.primitives.hue_slider',
  InputText = 'arkitekt.gui.widgets.primitives.inputtext',
  LoadingSpinner = 'arkitekt.gui.widgets.primitives.loading_spinner',
  MarkdownField = 'arkitekt.gui.widgets.primitives.markdown_field',
  ProgressBar = 'arkitekt.gui.widgets.primitives.progress_bar',
  RadioButton = 'arkitekt.gui.widgets.primitives.radio_button',
  Scrollbar = 'arkitekt.gui.widgets.primitives.scrollbar',
  Slider = 'arkitekt.gui.widgets.primitives.slider',
  Spinner = 'arkitekt.gui.widgets.primitives.spinner',
  Splitter = 'arkitekt.gui.widgets.primitives.splitter',

  -- Containers
  Panel = 'arkitekt.gui.widgets.containers.panel',
  SlidingZone = 'arkitekt.gui.widgets.containers.sliding_zone',
  TileGroup = 'arkitekt.gui.widgets.containers.tile_group',

  -- Navigation
  Tree = 'arkitekt.gui.widgets.navigation.tree_view',

  -- Utilities (commonly used modules)
  Anim = 'arkitekt.core.animation',
  Colors = 'arkitekt.core.colors',
  Cursor = 'arkitekt.core.cursor',
  Style = 'arkitekt.gui.style',
  Draw = 'arkitekt.gui.draw.primitives',
  Easing = 'arkitekt.gui.animation.easing',
  Features = 'arkitekt.defs.features',
  Lookup = 'arkitekt.core.lookup',
  Math = 'arkitekt.core.math',
  Notification = 'arkitekt.core.notification',
  UUID = 'arkitekt.core.uuid',

  -- Platform (REAPER + ImGui specific utilities)
  Images = 'arkitekt.platform.images',
}

-- Lazy loading with metatable
-- Widgets are only loaded when first accessed (like ImGui namespace)
setmetatable(Ark, {
  __index = function(t, key)
    local module_path = MODULES[key]
    if module_path then
      -- Load and cache the module
      local success, module = pcall(require, module_path)
      if success then
        t[key] = module  -- Cache to avoid future requires
        return module
      else
        error(string.format("Ark.%s: Failed to load module '%s'\n%s",
                          key, module_path, module), 2)
      end
    end
    error(string.format("Ark.%s is not a valid widget. See MODULES table in arkitekt/init.lua", key), 2)
  end
})

return Ark
