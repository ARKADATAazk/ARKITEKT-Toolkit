# ARK DevKit

Development launcher for ARKITEKT apps across multiple git worktrees.

## Purpose

ARK DevKit provides a single, stable entry point for launching ARKITEKT apps from any worktree in a multi-branch development workflow. It auto-detects all `ARKITEKT-Toolkit*` worktrees and their entrypoints, making it easy to switch between different feature branches and apps.

## Features

- **Auto-detection**: Automatically finds all ARKITEKT-Toolkit* worktrees
- **Entrypoint scanning**: Lists all `ARK_*.lua` scripts in each worktree
- **State persistence**: Remembers your last worktree and app selection
- **Single action**: Register once in REAPER, use forever

## Installation

1. Register `ARK_DevKit.lua` as a REAPER action (Actions → Load ReaScript)
2. Optionally bind it to a keyboard shortcut for quick access

## Usage

1. Run the ARK DevKit action
2. Select a worktree (main, tiles, theme, etc.)
3. Select an app to launch
4. The app launches from the selected worktree

Your selections are saved and used as defaults next time.

## State Storage

DevKit state is stored outside the repository at:

```
<REAPER Resource Path>/Data/ARKITEKT/DevKit/DevKit_State.lua
```

This includes:
- `base_dir`: Parent directory containing all worktrees
- `last_worktree_key`: Last selected worktree
- `last_app_key`: Last selected app

## Worktree Structure

ARK DevKit expects worktrees to follow this naming convention:

```
/base/dir/
  ARKITEKT-Toolkit/          (main worktree, key: "main")
  ARKITEKT-Toolkit-tiles/    (feature worktree, key: "tiles")
  ARKITEKT-Toolkit-theme/    (feature worktree, key: "theme")
  ...
```

Each worktree should have:

```
ARKITEKT-Toolkit*/
  scripts/
    AppName/
      ARK_AppName.lua        (entrypoint)
      ...
```

## First Run

On first run, DevKit will:

1. Try to auto-detect the base directory from its own path
2. If that fails, prompt you to enter the base directory manually
3. Scan for worktrees and entrypoints
4. Present the selection UI

## Text UI

Currently uses a simple text-based UI with console output and input dialogs. This can be upgraded to a full ReaImGui interface in the future while keeping the same backend logic.

## Evolution Path

Future enhancements could include:

- ReaImGui-based UI with clickable buttons
- Worktree branch status display (git status)
- Quick access to recently used apps
- Favorites/pinning system
- Launch with command-line arguments
