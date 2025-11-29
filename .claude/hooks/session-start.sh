#!/bin/bash
# ARKITEKT Session Start Hook - Loads project context

echo "🚀 ARKITEKT Framework Session Starting..."
echo ""
echo "📋 Quick Reference:"
echo "   • Namespace: arkitekt.* (require) | Ark.* (loader)"
echo "   • Layers: UI → app → domain ← infra"
echo "   • No ImGui in domain/*"
echo "   • Diff budget: ≤12 files, ≤700 LOC"
echo ""
echo "📖 CLAUDE.md loaded - strict rules active"
echo ""
echo "💡 Tip: Use Shift+Tab for auto-accept mode on multi-phase tasks"
echo ""

# Optional: Print current branch
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
  echo "🌿 Branch: $BRANCH"
  echo ""
fi

exit 0
