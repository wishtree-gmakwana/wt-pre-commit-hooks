#!/usr/bin/env bash
# Exit on error
set -e

echo "🔍 Running pre-commit checks..."

# Get staged Python files
STAGED_PY_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.py$' || true)

# Get staged YAML/JSON/TOML files
STAGED_CONFIG_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '\.(yaml|yml|json|toml)$' || true)

# Get all staged files for general checks
ALL_STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR || true)

# 1. Check for merge conflicts
if [ -n "$ALL_STAGED_FILES" ]; then
  echo "🔀 Checking for merge conflict markers..."
  if echo "$ALL_STAGED_FILES" | xargs grep -l "^<<<<<<< \|^=======$\|^>>>>>>> " 2>/dev/null; then
    echo "❌ Merge conflict markers found! Please resolve conflicts before committing."
    exit 1
  fi
fi

# 2. Fix trailing whitespace and end-of-file issues
if [ -n "$ALL_STAGED_FILES" ]; then
  echo "🧹 Fixing trailing whitespace and EOF..."
  for file in $ALL_STAGED_FILES; do
    # Remove trailing whitespace
    sed -i 's/[[:space:]]*$//' "$file" 2>/dev/null || true
    # Ensure file ends with newline
    if [ -f "$file" ]; then
      tail -c1 "$file" | read -r _ || echo >> "$file"
    fi
  done
  echo "$ALL_STAGED_FILES" | xargs git add 2>/dev/null || true
fi

# 3. Validate YAML files
if [ -n "$STAGED_CONFIG_FILES" ]; then
  YAML_FILES=$(echo "$STAGED_CONFIG_FILES" | grep -E '\.(yaml|yml)$' || true)
  if [ -n "$YAML_FILES" ]; then
    echo "📋 Validating YAML files..."
    echo "$YAML_FILES" | xargs -I {} python -c "import yaml; yaml.safe_load(open('{}'))" || {
      echo "❌ YAML validation failed!"
      exit 1
    }
  fi
  
  # Validate JSON files
  JSON_FILES=$(echo "$STAGED_CONFIG_FILES" | grep -E '\.json$' || true)
  if [ -n "$JSON_FILES" ]; then
    echo "📋 Validating JSON files..."
    echo "$JSON_FILES" | xargs -I {} python -c "import json; json.load(open('{}'))" || {
      echo "❌ JSON validation failed!"
      exit 1
    }
  fi
  
  # Validate TOML files
  TOML_FILES=$(echo "$STAGED_CONFIG_FILES" | grep -E '\.toml$' || true)
  if [ -n "$TOML_FILES" ]; then
    echo "📋 Validating TOML files..."
    echo "$TOML_FILES" | xargs -I {} python -c "import tomli; tomli.load(open('{}', 'rb'))" 2>/dev/null || \
    echo "$TOML_FILES" | xargs -I {} python -c "import tomllib; tomllib.load(open('{}', 'rb'))" || {
      echo "❌ TOML validation failed!"
      exit 1
    }
  fi
fi

# 4. Run Black formatter on staged Python files
if [ -n "$STAGED_PY_FILES" ]; then
  echo "✨ Formatting staged files with Black..."
  echo "$STAGED_PY_FILES" | xargs black --quiet
  echo "$STAGED_PY_FILES" | xargs git add
fi

# 5. Run isort on staged Python files (import sorting)
if [ -n "$STAGED_PY_FILES" ]; then
  echo "📦 Sorting imports with isort..."
  echo "$STAGED_PY_FILES" | xargs isort --profile black --quiet
  echo "$STAGED_PY_FILES" | xargs git add
fi

# 6. Run Flake8 linter on staged Python files
if [ -n "$STAGED_PY_FILES" ]; then
  echo "🔎 Linting staged files with Flake8..."
  echo "$STAGED_PY_FILES" | xargs flake8 || {
    echo "❌ Flake8 linting failed!"
    exit 1
  }
fi

# 7. Run mypy for type checking
if [ -n "$STAGED_PY_FILES" ]; then
  echo "📝 Running mypy type check..."
  echo "$STAGED_PY_FILES" | xargs mypy --no-error-summary 2>/dev/null || {
    echo "⚠️  mypy found type issues (non-blocking)"
  }
fi

# 8. Run Bandit security linter
if [ -n "$STAGED_PY_FILES" ]; then
  echo "🔒 Running Bandit security checks..."
  if [ -f "pyproject.toml" ]; then
    echo "$STAGED_PY_FILES" | xargs bandit -ll -c pyproject.toml --quiet || {
      echo "❌ Bandit security checks failed!"
      exit 1
    }
  else
    echo "$STAGED_PY_FILES" | xargs bandit -ll --quiet || {
      echo "❌ Bandit security checks failed!"
      exit 1
    }
  fi
fi

# 9. Run detect-secrets
if [ -n "$ALL_STAGED_FILES" ]; then
  echo "🔐 Scanning for secrets..."
  if [ -f ".secrets.baseline" ]; then
    detect-secrets scan --baseline .secrets.baseline $ALL_STAGED_FILES || {
      echo "❌ Secrets detected! Please review and update .secrets.baseline if needed."
      exit 1
    }
  else
    echo "⚠️  No .secrets.baseline found, skipping secret detection"
  fi
fi

# 10. Run pytest on related test files
if [ -n "$STAGED_PY_FILES" ]; then
  echo "🧪 Running unit tests..."
  
  # Find related test files
  TEST_FILES=""
  for file in $STAGED_PY_FILES; do
    # Skip if file is already a test file
    if [[ $file == test_* ]] || [[ $file == *_test.py ]] || [[ $file == */tests/* ]]; then
      TEST_FILES="$TEST_FILES $file"
      continue
    fi
    
    # Try to find corresponding test file
    dir=$(dirname "$file")
    base=$(basename "$file" .py)
    
    # Common test patterns
    possible_tests=(
      "${dir}/test_${base}.py"
      "${dir}/${base}_test.py"
      "${dir}/tests/test_${base}.py"
      "tests/${dir}/test_${base}.py"
      "tests/test_${base}.py"
    )
    
    for test_file in "${possible_tests[@]}"; do
      if [ -f "$test_file" ]; then
        TEST_FILES="$TEST_FILES $test_file"
        break
      fi
    done
  done
  
  # Run pytest if we have test files or just run all tests
  if [ -n "$TEST_FILES" ]; then
    echo "Running tests: $TEST_FILES"
    pytest --tb=short --quiet $TEST_FILES || {
      echo "❌ Unit tests failed!"
      exit 1
    }
  else
    # Run pytest with related tests discovery
    echo "$STAGED_PY_FILES" | xargs pytest --tb=short --quiet --co -q > /dev/null 2>&1 && \
    echo "$STAGED_PY_FILES" | xargs pytest --tb=short --quiet 2>/dev/null || {
      echo "⚠️  No related tests found or pytest not configured"
    }
  fi
fi

echo "✅ All pre-commit checks passed!"
