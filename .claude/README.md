# ARKITEKT Claude Code Configuration

Autonomous multi-phase pipeline for ARKITEKT development.

## Features

### 🎯 Auto-Accept Mode (Shift+Tab)

Toggle autonomous execution - Claude works through all phases without manual approval.

**Usage:**
```
You: "Refactor widget system per PHASE_1 plan"
[Press Shift+Tab]
Claude: [Executes all phases autonomously]
```

### 🔒 Architecture Hooks

Automated validation enforcing CLAUDE.md rules:

#### Session Start Hook
- Loads ARKITEKT context automatically
- Displays quick reference on startup
- Shows current branch

#### Post-Edit Hook (After Edit/Write)
- **BLOCKS** ImGui in `domain/*` layers (exit code 2)
- Warns about potential globals
- Real-time validation as files are edited

#### Stop Hook (Before Claude finishes)
- Validates no ImGui in domain layers
- Checks namespace compliance (arkitekt.*)
- Warns about globals
- Monitors diff budget (≤12 files, ≤700 LOC)
- Git status check

**Exit codes:**
- `0` = Pass (allow)
- `1` = Error (warn and allow)
- `2` = Block (prevent operation)

### ⚡ Workflow Commands

Pre-built multi-phase workflows:

- `/widget` - Create new widget with framework conventions
- `/refactor` - Execute phased refactor (shims → new path → migration)
- `/validate` - Run architecture compliance checks

## Usage Examples

### Autonomous Widget Creation
```
You: /widget Create a multi-select dropdown
[Shift+Tab to enable auto-accept]
Claude: [Reads references → Plans → Implements → Validates → Done]
```

### Autonomous Refactor
```
You: /refactor Extract domain logic from UI components
[Shift+Tab enabled]
Claude: [Phase 1: Shims → Phase 2: New path → Phase 3: Migration]
         [Hooks validate after each phase]
```

### Manual Override
If hook blocks an operation:
- Review the validation error
- Fix the issue (e.g., remove ImGui from domain layer)
- Claude will retry automatically in auto-accept mode

## File Structure

```
.claude/
├── settings.json          # Hook configuration
├── hooks/
│   ├── session-start.sh   # Context loading
│   ├── post-edit-check.sh # Real-time validation
│   └── stop-validation.sh # Pre-finish checks
├── commands/
│   ├── widget.md          # Widget creation workflow
│   ├── refactor.md        # Phased refactor workflow
│   └── validate.md        # Architecture validation
└── README.md              # This file
```

## Customization

### Add New Workflow Command

Create `.claude/commands/myworkflow.md`:
```markdown
---
description: Brief description shown in /menu
---

Your multi-phase workflow instructions here.
Execute automatically (I'll use auto-accept mode).
```

### Modify Validation Rules

Edit hook scripts in `.claude/hooks/`:
- Add checks: append to existing scripts
- Block on failure: `exit 2`
- Warn only: `echo "⚠️ ..." && exit 0`

### Adjust Diff Budget

Edit `stop-validation.sh` thresholds:
```bash
if [ "$CHANGED_FILES" -gt 12 ]; then  # ← Adjust here
```

## Tips

1. **Start with auto-accept ON** for well-defined workflows
2. **Toggle OFF** when exploring or uncertain
3. **Let hooks catch violations** - they're faster than manual review
4. **Chain workflows** - `/validate` after `/refactor`
5. **Check hook output** - warnings highlight potential issues

## Architecture Rules Enforced

Per `CLAUDE.md`:
- ✅ No ImGui in `domain/*` (BLOCKED by hooks)
- ✅ Namespace: `arkitekt.*` for require, `Ark.*` for loader
- ✅ No globals, return table M
- ✅ Surgical diffs (≤12 files, ≤700 LOC)
- ✅ Layer separation: UI → app → domain ← infra

## Troubleshooting

**Hook blocks valid code?**
- Review the validation logic in `.claude/hooks/[hook].sh`
- Adjust regex patterns if needed
- Comment out overly strict checks

**Auto-accept not working?**
- Verify `Shift+Tab` toggled (check status indicator)
- Hooks can still block in auto-accept mode (by design)
- Check hook exit codes in output

**Commands not appearing?**
- Ensure `.md` files in `.claude/commands/`
- Check frontmatter has `description:` field
- Restart Claude Code session if needed
