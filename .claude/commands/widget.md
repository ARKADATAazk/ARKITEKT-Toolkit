---
description: Create a new ARKITEKT widget following framework conventions
---

Create a new widget following ARKITEKT conventions:

1. **Read reference**: Review similar widget in `arkitekt/gui/widgets/[category]/`
2. **Pattern**: Use single-frame `M.draw(ctx, opts)` or multi-frame `M.begin_*/M.end_*`
3. **Architecture**:
   - Return table M
   - No globals, no side effects at require time
   - Use `arkitekt/defs/*` for constants (never hardcode colors/timing)
   - Reference `Theme.COLORS` for theming
4. **Validation**:
   - Check `cookbook/API_DESIGN_PHILOSOPHY.md` for patterns
   - Follow existing widget style in same category
   - Keep diff surgical (≤300 LOC for new widget)

Execute all phases automatically (I'll use auto-accept mode).
