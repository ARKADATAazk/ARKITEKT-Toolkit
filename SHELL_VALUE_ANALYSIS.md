# Shell.run() Value Analysis & Naming Considerations

**Date:** 2025-11-26
**Questions:**
1. Should we call it "ReaImGui ARKITEKT"?
2. Is Shell.run() actually useful or just abstraction overhead?

---

## Part 1: Naming - "ReaImGui ARKITEKT"?

### Current Naming Analysis

**Current:** "ARKITEKT"
- ✅ Distinct brand identity
- ✅ Memorable
- ❌ Doesn't indicate it's built on ReaImGui
- ❌ Not immediately clear what it does

**Proposed:** "ReaImGui ARKITEKT" or "ARKITEKT for ReaImGui"

### Precedents from Other Ecosystems

**Successful "X for Y" naming:**

| Project | Pattern | Success? |
|---------|---------|----------|
| **React Native** | "React" + qualifier | ✅ Huge success |
| **React Router** | "React" + feature | ✅ Huge success |
| **Vue Router** | "Vue" + feature | ✅ Standard library |
| **Material-UI** | No parent mention | ✅ Success (implies Material Design) |
| **Ant Design** | No parent mention | ✅ Success |
| **Next.js** | No parent mention | ✅ Huge success (but "for React" in docs) |
| **Nuxt** | No parent mention | ✅ Success (but "for Vue" in docs) |

**Less successful "X for Y" naming:**

| Project | Pattern | Problem |
|---------|---------|---------|
| **jQuery UI** | "jQuery" + qualifier | ⚠️ Sounds like just widgets |
| **Bootstrap jQuery** | Parent + name | ❌ Never took off (Bootstrap alone did) |

### Recommendation: Hybrid Approach

**Best of both worlds:**

1. **Primary name:** "ARKITEKT"
   - Keep distinct brand
   - Easier to say/remember

2. **Tagline:** "A GUI Framework for ReaImGui"
   - Makes relationship clear
   - SEO-friendly
   - Shows up in searches for "ReaImGui framework"

3. **Package name:** "arkitekt" (keep as-is)
   - Clean, no namespace pollution

**Examples in the wild:**

```
Next.js - The React Framework
Nuxt - The Intuitive Vue Framework
Remix - The Full Stack Web Framework (built on React)
ARKITEKT - A GUI Framework for ReaImGui  ← THIS
```

**Why NOT "ReaImGui ARKITEKT":**
- Sounds like an official ReaImGui project (you're not affiliated)
- Limits you if you ever want to support other backends
- Less distinct brand identity
- "ARKITEKT" alone is more memorable

**Why YES to mentioning ReaImGui prominently:**
- ✅ In tagline/description
- ✅ In documentation
- ✅ In search terms
- ❌ Not in the primary name

---

## Part 2: Is Shell.run() Actually Useful?

### The Core Question

> "They can ignore it and recreate it for their own scripts right? The abstraction makes it hard to replicate all the flags ImGui can take."

**This is a VERY valid concern.** Let's analyze objectively.

---

## What Shell.run() Provides

### Feature 1: Defer Loop Management

**Shell.run():**
```lua
Shell.run({
  draw = function(ctx, state)
    -- Your code
  end,
})
```

**DIY alternative:**
```lua
local open = true
local function loop()
  -- Your code
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
```

**Value added:** Saves ~5 lines
**Complexity hidden:** Minimal
**Verdict:** ⚠️ **MARGINAL VALUE** - trivial to replicate

---

### Feature 2: Error Handling

**Shell.run():**
```lua
-- Automatic xpcall wrapper with stack traces
Shell.run({
  draw = function(ctx, state)
    error("Oops!")  -- Caught and logged with full stack trace
  end,
})
```

**DIY alternative:**
```lua
local function loop()
  xpcall(function()
    -- Your code
  end, function(err)
    reaper.ShowConsoleMsg("ERROR: " .. err .. "\n" .. debug.traceback())
  end)
  reaper.defer(loop)
end
```

**Value added:** Saves ~8 lines, better error messages
**Complexity hidden:** Moderate
**Verdict:** ✅ **MODERATE VALUE** - nice to have, not essential

---

### Feature 3: Settings Persistence

**Shell.run():**
```lua
Shell.run({
  app_name = "my_app",  -- Auto-creates settings file
  draw = function(ctx, state)
    -- state.settings available automatically
  end,
})
```

**DIY alternative:**
```lua
local Settings = require('arkitekt.core.settings')
local settings = Settings.new(data_dir, 'settings.json')
-- Manual flush calls
settings:flush()
```

**Value added:** Auto-initialization, auto-flush
**Complexity hidden:** High
**Verdict:** ✅ **HIGH VALUE** - would be annoying to replicate

---

### Feature 4: Font Loading

**Shell.run():**
```lua
Shell.run({
  fonts = {
    default = 16,
    title = 18,
  },
  -- Fonts automatically loaded and attached
})
```

**DIY alternative:**
```lua
local font = ImGui.CreateFontFromFile(path, flags)
ImGui.Attach(ctx, font)
-- Fallback handling
-- Size configuration
-- Multiple font variants
-- ~50 lines of code
```

**Value added:** Saves ~50 lines, handles fallbacks
**Complexity hidden:** High
**Verdict:** ✅ **HIGH VALUE** - font loading is tedious

---

### Feature 5: Window Chrome (Titlebar, Status Bar)

**Shell.run():**
```lua
Shell.run({
  title = "My App",
  version = "1.0.0",
  show_titlebar = true,
  show_status_bar = true,
  -- Professional chrome automatically rendered
})
```

**DIY alternative:**
```lua
-- Custom titlebar rendering: ~200+ lines
-- Draggable region
-- Close button
-- Version display
-- Status bar
-- Window positioning
-- etc.
```

**Value added:** Saves ~200+ lines, professional look
**Complexity hidden:** Very high
**Verdict:** ✅ **VERY HIGH VALUE** - this is the killer feature

---

### Feature 6: ImGui Window Flags

**Shell.run() (current):**
```lua
Shell.run({
  flags = ImGui.WindowFlags_NoScrollbar,
  -- Limited to what Shell exposes
})
```

**DIY alternative:**
```lua
local flags = ImGui.WindowFlags_NoScrollbar |
              ImGui.WindowFlags_NoScrollWithMouse |
              ImGui.WindowFlags_NoBackground |
              ImGui.WindowFlags_NoNav
-- Full control over all flags
```

**Value added:** None (actually removes control!)
**Complexity hidden:** None
**Verdict:** ❌ **NEGATIVE VALUE** - abstraction gets in the way

---

## Value Assessment Matrix

| Feature | Lines Saved | Value | Can Users Skip Shell? |
|---------|-------------|-------|----------------------|
| Defer loop | ~5 | ⚠️ Low | ✅ Yes (trivial) |
| Error handling | ~8 | ✅ Medium | ✅ Yes (manageable) |
| Settings | ~20 | ✅ High | ⚠️ Maybe (tedious) |
| Fonts | ~50 | ✅ High | ⚠️ Maybe (tedious) |
| Window chrome | ~200+ | ✅ **Very High** | ❌ No (too much work) |
| ImGui flags | 0 | ❌ **Negative** | ✅ Yes (Shell limits) |

---

## The Problem: Shell Abstracts Away Control

### Specific Pain Points

**1. Can't access all ImGui window flags**

```lua
-- What if I want these flags?
local flags = ImGui.WindowFlags_NoTitleBar |
              ImGui.WindowFlags_NoResize |
              ImGui.WindowFlags_NoMove |
              ImGui.WindowFlags_NoBackground |
              ImGui.WindowFlags_NoNav |
              ImGui.WindowFlags_NoDocking

Shell.run({
  flags = ???  -- Can only pass one flag, can't combine!
})
```

**2. Can't customize window behavior**

```lua
-- What if I want custom window positioning logic?
-- What if I want multi-window app?
-- What if I want docking?
-- Shell doesn't expose these!
```

**3. "Magic" that users don't understand**

```lua
Shell.run({
  draw = function(ctx, state)
    -- What is state? Where does it come from?
    -- What if I don't want window chrome?
    -- How do I customize the titlebar?
  end,
})
```

---

## Solutions: Three Approaches

### Approach 1: Make Shell Optional (Recommended)

**Current structure:**
```
ARKITEKT
├── Framework (Shell.run) ← REQUIRED
└── Widgets ← Use within Shell
```

**Proposed structure:**
```
ARKITEKT
├── Widgets ← PRIMARY, standalone
├── Utilities (Settings, Fonts, etc.) ← Standalone modules
└── Shell (optional) ← Convenience wrapper
```

**Example:**

```lua
-- OPTION A: Use Shell (convenience)
Shell.run({
  draw = function(ctx, state)
    ark.Button.draw(ctx, {})
  end,
})

-- OPTION B: Use widgets directly (full control)
local ctx = ImGui.CreateContext('My App')
local fonts = require('arkitekt.app.fonts').load(ctx, {})
local settings = require('arkitekt.core.settings').new(data_dir)

local function loop()
  local visible, open = ImGui.Begin(ctx, 'My Window', true, flags)
  if visible then
    ark.Button.draw(ctx, {})
    ImGui.End(ctx)
  end
  if open then reaper.defer(loop) end
end
reaper.defer(loop)

-- OPTION C: Use Shell components à la carte
local WindowChrome = require('arkitekt.app.chrome.window')
local chrome = WindowChrome.new({ title = "My App" })

local function loop()
  chrome:Begin(ctx)
  ark.Button.draw(ctx, {})
  chrome:End(ctx)
  reaper.defer(loop)
end
```

**Benefits:**
- ✅ Users can choose their level of abstraction
- ✅ Shell becomes a convenience, not a requirement
- ✅ Power users get full ImGui access
- ✅ Beginners still get easy Shell.run()

---

### Approach 2: Make Shell More Configurable

**Add passthrough for all ImGui flags:**

```lua
Shell.run({
  window = {
    flags = ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoNav,
    -- Expose ALL ImGui window options
    pos_x = 100,
    pos_y = 100,
    size_w = 800,
    size_h = 600,
    bg_alpha = 1.0,
    -- etc.
  },

  -- Keep convenience options
  show_titlebar = true,  -- But these override flags if needed
  show_status_bar = true,
})
```

**Benefits:**
- ✅ Keeps Shell as primary API
- ✅ Power users get full control
- ⚠️ More complex API surface

**Drawbacks:**
- ⚠️ Docs become more complex
- ⚠️ Two ways to do everything (confusion)

---

### Approach 3: Minimal Shell + Composable Utilities

**Make Shell VERY thin:**

```lua
-- Shell becomes just error handling + defer loop
Shell.run({
  window_fn = function(ctx)
    -- User manages window completely
    local visible, open = ImGui.Begin(ctx, 'My App', true, flags)
    return visible, open
  end,

  draw = function(ctx, state)
    ark.Button.draw(ctx, {})
  end,
})

-- Or use components directly:
local ErrorHandler = require('arkitekt.app.error_handler')
local DeferLoop = require('arkitekt.app.defer_loop')

DeferLoop.run(ErrorHandler.wrap(my_loop_function))
```

**Benefits:**
- ✅ Maximum flexibility
- ✅ Clear what each piece does
- ✅ Can compose only what you need

**Drawbacks:**
- ⚠️ More verbose for simple cases
- ⚠️ Loses "batteries included" feel

---

## Recommendation: Hybrid Approach

### Make Widgets the Star, Shell the Optional Helper

**Documentation structure:**

```markdown
# ARKITEKT Documentation

## Quick Start (Shell - Recommended for Beginners)
Use Shell.run() for rapid development with batteries included.

## Widget Library (Core)
All widgets work standalone. Use with or without Shell.

## Advanced Usage (Full Control)
Skip Shell and use widgets with raw ImGui for maximum flexibility.

## Shell API Reference
Full Shell.run() configuration options.
```

**Code changes:**

1. **Make Shell flag passthrough easier:**
```lua
Shell.run({
  window_flags = ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoNav,
  -- Full control over ImGui flags
})
```

2. **Export Shell components separately:**
```lua
-- Users can use pieces without Shell.run()
local WindowChrome = require('arkitekt.app.chrome.window')
local Settings = require('arkitekt.core.settings')
local Fonts = require('arkitekt.app.fonts')
```

3. **Show both approaches in docs:**
```lua
-- EASY WAY (Shell)
Shell.run({ draw = function() ... end })

-- POWERFUL WAY (Direct)
local ctx = ImGui.CreateContext()
-- Full ImGui control
```

---

## Answering Your Questions Directly

### 1. "Couldn't we call it ReaImGui ARKITEKT?"

**Answer:** ❌ No, but DO mention ReaImGui prominently

**Recommended:**
- **Name:** ARKITEKT
- **Tagline:** "A GUI Framework for ReaImGui"
- **Description:** "ARKITEKT is a comprehensive GUI framework built on ReaImGui..."

**Why:**
- Keeps distinct brand
- Avoids sounding like an official ReaImGui project
- Still SEO-friendly for "ReaImGui framework" searches

---

### 2. "Is what we do in Shell really useful?"

**Answer:** ⚠️ **Mixed - some parts very useful, some get in the way**

**VERY useful:**
- ✅ Window chrome (titlebar, status bar) - saves ~200 lines
- ✅ Font loading - saves ~50 lines, handles fallbacks
- ✅ Settings persistence - saves ~20 lines

**Marginally useful:**
- ⚠️ Defer loop - saves ~5 lines (trivial)
- ⚠️ Error handling - saves ~8 lines (nice but not essential)

**Gets in the way:**
- ❌ ImGui flag abstraction - limits control
- ❌ "Magic" state injection - confusing
- ❌ All-or-nothing approach - can't pick and choose

---

### 3. "They can ignore it and recreate it for their own scripts right?"

**Answer:** ✅ **YES, and that's GOOD!**

**Make this explicit:**

```markdown
## When to Use Shell.run()

✅ **Use Shell when:**
- You want rapid prototyping
- You want professional window chrome
- You want batteries-included setup

❌ **Skip Shell when:**
- You need full ImGui window control
- You're integrating with existing ImGui code
- You want maximum performance (no overhead)
- You have your own application framework

Shell is **optional** - all widgets work without it!
```

---

### 4. "The abstraction makes it hard to replicate all the flags ImGui can take"

**Answer:** ✅ **100% VALID CRITICISM**

**Fix this with flag passthrough:**

```lua
-- BEFORE (limited)
Shell.run({
  flags = ImGui.WindowFlags_NoScrollbar,  -- Can only pass one?
})

-- AFTER (full control)
Shell.run({
  window_flags = ImGui.WindowFlags_NoScrollbar |
                 ImGui.WindowFlags_NoNav |
                 ImGui.WindowFlags_NoBackground,
  -- All ImGui flags supported
})
```

**Or make it explicit that Shell is opinionated:**

```markdown
## Shell Limitations

Shell.run() provides sensible defaults but abstracts some ImGui features.

**If you need:**
- Custom window flags
- Multi-window applications
- Docking support
- Non-standard window behavior

**Then:** Use widgets directly with raw ImGui (see Advanced Usage guide)
```

---

## Final Recommendations

### 1. **Naming:** Keep "ARKITEKT", add tagline

```
ARKITEKT
A GUI Framework for ReaImGui
```

### 2. **Positioning:** Widgets first, Shell second

**Current messaging:**
> "ARKITEKT is a framework for building REAPER GUIs"

**Better messaging:**
> "ARKITEKT is a widget library for ReaImGui with 50+ professional components. Includes an optional application framework (Shell.run) for rapid development."

### 3. **Documentation:** Show both paths

- **Quick Start:** Use Shell (easy)
- **Core Guide:** Widget library (standalone)
- **Advanced:** Skip Shell (full control)

### 4. **API Changes:**

**Priority 1 (easy):**
```lua
Shell.run({
  window_flags = flags,  -- Pass through all ImGui flags
  raw_content = true,    -- Skip chrome if desired
})
```

**Priority 2 (medium):**
```lua
-- Export components separately
local WindowChrome = require('arkitekt.app.chrome.window')
local Settings = require('arkitekt.core.settings')
```

**Priority 3 (optional):**
```lua
-- Show "Shell-less" examples in docs
```

---

## Value Proposition Clarity

**What makes ARKITEKT valuable?**

1. ✅ **50+ professional widgets** (this is the core value)
2. ✅ **Automatic theming and animations** (makes apps look polished)
3. ✅ **Window chrome and app structure** (Shell - optional convenience)
4. ✅ **Built on ReaImGui** (familiar to existing users)

**Don't let Shell overshadow the widgets!**

The widgets are the star. Shell is a nice optional helper.

---

## Summary

| Question | Answer |
|----------|--------|
| **Call it "ReaImGui ARKITEKT"?** | ❌ No, but mention ReaImGui in tagline |
| **Is Shell useful?** | ⚠️ Mixed - chrome is valuable, flags abstraction is not |
| **Can users skip Shell?** | ✅ Yes, and that should be encouraged for power users |
| **Does Shell limit control?** | ✅ Yes, currently - fix with flag passthrough |

**Action items:**
1. Add `window_flags` passthrough to Shell
2. Document Shell as optional (widgets work standalone)
3. Position widgets as primary, Shell as convenience
4. Use tagline "A GUI Framework for ReaImGui"

---

**END OF ANALYSIS**

Generated: 2025-11-26
