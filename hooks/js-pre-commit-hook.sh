#!/usr/bin/env bash
# Exit on error
set -e

echo "🔍 Running pre-commit checks..."

# Run Prettier on staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.(ts|tsx|js|jsx|json|md)$')
if [ -n "$STAGED_FILES" ]; then
  echo "✨ Formatting staged files with Prettier..."
  echo "$STAGED_FILES" | xargs npx prettier --write
  echo "$STAGED_FILES" | xargs git add
fi

# Run ESLint on staged TS/JS files
TS_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.(ts|tsx|js|jsx)$')
if [ -n "$TS_FILES" ]; then
  echo "🔎 Linting staged files with ESLint..."
  echo "$TS_FILES" | xargs npx eslint --fix
  echo "$TS_FILES" | xargs git add
fi

# Optional: Run type check (lightweight or skip here for speed)
# echo "📝 Running TypeScript type check..."
# npx tsc --noEmit

# Optional: Run unit tests for changed files (if using Jest)
# echo "🧪 Running Jest on related tests..."
# npx jest --bail --findRelatedTests $TS_FILES

echo "✅ Pre-commit checks passed!"
