#!/bin/bash

# Define the tools to be run
LINT_TOOL="swiftlint"
FORMAT_TOOL="swiftformat"

# Run SwiftLint
echo "Running SwiftLint..."
if mint run "$LINT_TOOL" autocorrect; then
  echo "SwiftLint passed."
else
  echo "SwiftLint failed. Please fix the issues before committing."
  exit 1
fi

# Run SwiftFormat
echo "Running SwiftFormat..."
if mint run "$FORMAT_TOOL" . --autocorrect --quiet; then
  echo "SwiftFormat passed. 🎉"
else
  echo "SwiftFormat failed. Please fix the issues before committing."
  exit 1
fi