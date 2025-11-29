#!/bin/bash
# ARKITEKT Post-Edit Hook - Validates edits as they happen

# Get the file that was just edited from environment
FILE="$CLAUDE_TOOL_FILE_PATH"

if [ -z "$FILE" ]; then
  exit 0  # No file path, skip
fi

# Check if file is in domain layer
if [[ "$FILE" == *"/domain/"* ]]; then
  # Verify no ImGui calls in domain layer
  if grep -q "ImGui\." "$FILE" 2>/dev/null; then
    echo "🚫 BLOCKED: ImGui found in domain layer file: $FILE"
    echo "   Rule: domain/* must not contain UI/ImGui calls (CLAUDE.md #3)"
    exit 2  # Block the edit
  fi
fi

# Check for globals in any file
if grep -E "^[^local]*\s+[A-Z_]+\s*=\s*" "$FILE" | grep -v "^--" | grep -v "local"; then
  echo "⚠️  Possible global in $FILE"
  echo "   Review: Use 'local M = {}' pattern (CLAUDE.md #4)"
  # Warn but don't block
fi

exit 0  # Allow edit
