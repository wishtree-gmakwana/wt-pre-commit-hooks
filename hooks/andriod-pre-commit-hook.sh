#!/bin/sh

echo "Running pre-commit hooks..."

# Run spotlessCheck to ensure code formatting
echo "Running spotlessCheck..."
./gradlew spotlessCheck

# Check the exit code of the last command
if [ $? -ne 0 ]; then
  echo ""
  echo "************************************************************************"
  echo "Spotless check failed. Please run './gradlew spotlessApply' to fix"
  echo "formatting issues, or fix them manually."
  echo "Aborting commit."
  echo "************************************************************************"
  exit 1
fi

echo "Pre-commit hooks passed. Committing changes."

exit 0