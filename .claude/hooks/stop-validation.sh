#!/bin/bash
# ARKITEKT Stop Hook - Validates architecture before allowing Claude to stop

set -e

echo "🔍 ARKITEKT Architecture Validation..."

# 1. Check for ImGui in domain layers
echo "   → Checking for ImGui in domain/*..."
if grep -r "ImGui\." --include="*.lua" arkitekt/*/domain/ 2>/dev/null; then
  echo "❌ BLOCKED: ImGui found in domain layer!"
  echo "   Fix: Remove ImGui calls from domain/* (see CLAUDE.md #3)"
  exit 2  # Exit code 2 = block
fi

# 2. Check for new globals
echo "   → Checking for new globals..."
if git diff --cached | grep -E "^[+].*[^local]\s+[A-Z_]+\s*=\s*" | grep -v "^[+].*--"; then
  echo "⚠️  WARNING: Possible new global variable detected"
  echo "   Review: All modules should return table M (see CLAUDE.md #4)"
  # Don't block, just warn
fi

# 3. Check namespace compliance
echo "   → Checking namespace compliance..."
if git diff --cached | grep -E "require\(['\"](?!arkitekt\.)" --include="*.lua"; then
  echo "⚠️  WARNING: Non-arkitekt.* require() found"
  echo "   Review: Use arkitekt.* namespace (see CLAUDE.md #1)"
fi

# 4. Diff budget check
CHANGED_FILES=$(git diff --cached --name-only | wc -l)
CHANGED_LINES=$(git diff --cached --stat | tail -1 | grep -oE '[0-9]+' | head -1)

echo "   → Diff budget: $CHANGED_FILES files, ~$CHANGED_LINES LOC"

if [ "$CHANGED_FILES" -gt 12 ]; then
  echo "⚠️  WARNING: Changed $CHANGED_FILES files (budget: ≤12)"
  echo "   Consider: Split into multiple phases (see CLAUDE.md #4)"
fi

if [ "$CHANGED_LINES" -gt 700 ]; then
  echo "⚠️  WARNING: Changed ~$CHANGED_LINES LOC (budget: ≤700)"
  echo "   Consider: Break into smaller tasks (see CLAUDE.md #4)"
fi

# 5. Git status check
if ! git diff-index --quiet HEAD --; then
  echo "✅ Changes staged and validated"
  exit 0
else
  echo "✅ No changes to validate"
  exit 0
fi
