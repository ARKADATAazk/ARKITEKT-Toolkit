---
description: Validate ARKITEKT architecture compliance across codebase
---

Run comprehensive architecture validation:

1. **Layer separation**: Verify no ImGui in `domain/*` layers
2. **Namespace compliance**: Check all requires use `arkitekt.*` pattern
3. **No globals**: Verify all modules return table M
4. **Bootstrap pattern**: Verify entry points use `dofile` bootstrap (not `require`)
5. **Anti-patterns**: Check for hardcoded colors/magic numbers when defs exist

For any violations found:
- Report file:line_number references
- Explain the rule violation per CLAUDE.md
- Suggest fix if obvious

Execute validation autonomously and report findings.
