#!/usr/bin/env bash

# Flutter Pre-commit Hook
# This script runs Flutter code quality checks before each commit

echo "🚀 Running Flutter pre-commit checks..."

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    exit 1
fi

# Check if we're in a Flutter project
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Not a Flutter project (pubspec.yaml not found)"
    exit 1
fi

# Get Flutter dependencies
echo "📦 Getting Flutter dependencies..."
if ! flutter pub get; then
    echo "❌ Failed to get Flutter dependencies"
    exit 1
fi

# Run Dart format check
echo "🎨 Checking Dart code formatting..."
if ! dart format --set-exit-if-changed lib/ test/; then
    echo "❌ Code formatting issues found. Run 'dart format lib/ test/' to fix them."
    exit 1
fi
echo "✅ Code formatting check passed"

# Run Dart analyzer
echo "🔍 Running Dart analyzer..."
if ! dart analyze; then
    echo "❌ Dart analyzer found issues. Please fix them before committing."
    exit 1
fi
echo "✅ Dart analyzer passed"

# Run Flutter tests (if test directory exists)
if [ -d "test" ] && [ "$(find test -name '*.dart' | wc -l)" -gt 0 ]; then
    echo "🧪 Running Flutter tests..."
    if ! flutter test; then
        echo "❌ Tests failed. Please fix them before committing."
        exit 1
    fi
    echo "✅ All tests passed"
else
    echo "ℹ️  No tests found, skipping test execution"
fi

# Check for common Flutter/Dart issues
echo "🔧 Running additional checks..."

# Check for print statements (optional - can be removed if not desired)
if grep -r "print(" lib/ --include="*.dart" > /dev/null; then
    echo "⚠️  Warning: Found print() statements in lib/ directory"
    echo "   Consider using debugPrint() or a proper logging solution"
fi

# Check for TODO/FIXME comments (optional warning)
if grep -r -i "TODO\|FIXME" lib/ --include="*.dart" > /dev/null; then
    echo "ℹ️  Info: Found TODO/FIXME comments in code"
fi

echo "✅ All pre-commit checks passed! 🎉"
exit 0