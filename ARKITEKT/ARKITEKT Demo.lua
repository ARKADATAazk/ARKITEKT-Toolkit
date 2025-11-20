-- @noindex
-- @description ARKITEKT Demo
-- @author ARKADATA
-- @version 1.0.0
-- @about
--   Interactive demo showcasing ARKITEKT framework features.
--   Learn how to build professional REAPER interfaces with primitives,
--   widgets, grid systems, and more.
--
--   Perfect for getting started with ARKITEKT development!

-- ============================================================================
-- BOOTSTRAP ARKITEKT FRAMEWORK
-- ============================================================================
--
-- WHY THIS PATTERN:
-- Every ARKITEKT app starts by locating and loading the bootstrap module.
-- This scans upward from the script's directory to find rearkitekt/app/init/
-- and initializes the framework with all necessary paths and utilities.
--
-- The ARK context provides:
-- - ImGui: Pre-loaded ImGui module
-- - Constants: Framework constants (colors, fonts, etc.)
-- - dirname(): Path utilities
-- - And more utilities defined in bootstrap.lua

local ARK
do
  local sep = package.config:sub(1,1)
  local src = debug.getinfo(1, "S").source:sub(2)
  local path = src:match("(.*"..sep..")")

  -- Scan upward for rearkitekt/app/init/init.lua
  while path and #path > 3 do
    local init = path .. "rearkitekt" .. sep .. "app" .. sep .. "init" .. sep .. "init.lua"
    local f = io.open(init, "r")
    if f then
      f:close()
      local Init = dofile(init)
      ARK = Init.bootstrap()
      break
    end
    path = path:match("(.*"..sep..")[^"..sep.."]-"..sep.."$")
  end

  if not ARK then
    reaper.MB("ARKITEKT framework not found!\n\nMake sure this script is in the ARKITEKT folder.", "Demo Error", 0)
    return
  end
end

-- ============================================================================
-- LOAD DEPENDENCIES
-- ============================================================================
--
-- WHY REQUIRE AFTER BOOTSTRAP:
-- The bootstrap sets up package.path to include rearkitekt modules.
-- Now we can require both framework modules and our demo modules.

local ImGui = ARK.ImGui

-- Framework modules
local Shell = require("rearkitekt.app.runtime.shell")

-- Load ARKITEKT style (provides default ImGui styling)
local style_ok, Style = pcall(require, "rearkitekt.gui.style.imgui_defaults")

-- Demo modules
local State = require("Demo.core.state")
local MainGUI = require("Demo.ui.main_gui")

-- ============================================================================
-- INITIALIZE APPLICATION STATE
-- ============================================================================
--
-- WHY SEPARATE STATE INITIALIZATION:
-- Keeping state separate from UI makes the code more maintainable.
-- State holds all runtime data, UI just renders it.

local state = State.initialize()

-- ============================================================================
-- MAIN DRAW FUNCTION
-- ============================================================================
--
-- WHY THIS PATTERN:
-- The draw function is called every frame by the Shell.
-- We receive the ImGui context and need to draw our entire UI.
-- The Shell handles window management, styling, fonts - we just draw content.
--
-- @param ctx ImGui context
-- @param app_state table Application state managed by Shell (fonts, style, etc.)

local function draw(ctx, app_state)
  -- Get available space
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)

  -- Render main GUI
  MainGUI.render(ctx, state, avail_w, avail_h)
end

-- ============================================================================
-- RUN APPLICATION
-- ============================================================================
--
-- WHY Shell.run:
-- Shell.run() is ARKITEKT's application runner. It:
-- - Creates and manages the ImGui window
-- - Handles the defer loop for continuous rendering
-- - Manages fonts and styling (via style parameter)
-- - Provides window chrome (titlebar, etc.)
-- - Handles visibility toggling (run script again to hide)
--
-- Configuration options:
-- - title: Window title in REAPER
-- - initial_size: Initial window size {w, h}
-- - draw: Your draw function called every frame (NOT render!)
-- - style: Style module for ImGui colors/styling (CRITICAL!)
-- - fonts: Custom font configuration (optional)

Shell.run({
  title = "ARKITEKT Demo",
  version = "1.0.0",

  -- Initial window size
  initial_size = { w = 900, h = 700 },
  min_size = { w = 700, h = 500 },

  -- Custom font sizes (optional)
  fonts = {
    default = 14,
    title = 18,
    version = 11,
  },

  -- Main draw function (NOT render!)
  draw = draw,

  -- CRITICAL: Pass the style to get ARKITEKT colors/styling
  style = style_ok and Style or nil,

  -- Optional: Show icon in titlebar
  show_icon = true,
})

-- ============================================================================
-- NOTES FOR DEVELOPERS
-- ============================================================================
--[[

WHAT YOU CAN LEARN FROM THIS DEMO:

1. **Bootstrap Pattern**
   Every ARKITEKT app uses the same bootstrap pattern to locate and
   initialize the framework. Copy this pattern for your own apps.

2. **State Management**
   See Demo/core/state.lua for how to structure application state.
   Keep state separate from UI for maintainability.

3. **Modular UI**
   See Demo/ui/ for how to split UI into logical view modules.
   Each view is self-contained and receives state as a parameter.

4. **Panel & Tabs**
   See Demo/ui/main_gui.lua for how to use Panel with tabs for
   multi-section applications.

5. **Primitives**
   See Demo/ui/primitives_view.lua for button, checkbox, text,
   drawing, and color utilities examples.

6. **Grid System**
   See Demo/ui/grid_view.lua for responsive grid layout with
   selection and interaction examples.

NEXT STEPS:

- Explore the code in Demo/ folder
- Read the inline documentation
- Experiment by modifying the demo
- Use these patterns in your own REAPER scripts

For more information:
- GitHub: [Your repo URL]
- Forum: [Your forum thread]
- Documentation: [Your docs]

]]
