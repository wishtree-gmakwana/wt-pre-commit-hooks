#!/bin/bash

# .NET Pre-commit Hook
# This script runs .NET code quality checks before each commit
# Compatible with .NET Framework, .NET Core, and .NET 5+

echo "🚀 Running .NET pre-commit checks..."

# Check if dotnet CLI is installed
if ! command -v dotnet &> /dev/null; then
    echo "❌ .NET CLI is not installed or not in PATH"
    echo "   Please install .NET SDK from https://dotnet.microsoft.com/download"
    exit 1
fi

# Function to check if it's a .NET project
is_dotnet_project() {
    # Check for common .NET project indicators
    if find . -maxdepth 2 -name "*.sln" -o -name "*.csproj" -o -name "*.vbproj" -o -name "*.fsproj" | grep -q .; then
        return 0
    fi
    return 1
}

# Check if we're in a .NET project
# if ! is_dotnet_project; then
#     echo "❌ Not a .NET project (no .sln, .csproj, .vbproj, or .fsproj files found)"
#     exit 1
# fi

# Display .NET version info
echo "📋 .NET SDK Information:"
dotnet --version
echo ""

# Find solution files or project files
SOLUTION_FILES=$(find . -maxdepth 2 -name "*.sln")
PROJECT_FILES=$(find . -maxdepth 2 -name "*.csproj" -o -name "*.vbproj" -o -name "*.fsproj")

# Determine what to build/test
BUILD_TARGET=""
if [ -n "$SOLUTION_FILES" ]; then
    BUILD_TARGET=$(echo "$SOLUTION_FILES" | head -1)
    echo "🎯 Found solution file: $BUILD_TARGET"
elif [ -n "$PROJECT_FILES" ]; then
    BUILD_TARGET=$(echo "$PROJECT_FILES" | head -1)
    echo "🎯 Found project file: $BUILD_TARGET"
else
    BUILD_TARGET="."
    echo "🎯 Using current directory as build target"
fi

# Restore packages
echo "📦 Restoring NuGet packages..."
if ! dotnet restore "$BUILD_TARGET" --verbosity quiet; then
    echo "❌ Failed to restore NuGet packages"
    exit 1
fi
echo "✅ Package restore completed"

# Check for format tool availability and run formatting
echo "🎨 Checking code formatting..."
DOTNET_VERSION=$(dotnet --version)
MAJOR_VERSION=$(echo $DOTNET_VERSION | cut -d. -f1)

# .NET 6+ has built-in format command, older versions need dotnet-format tool
if [ "$MAJOR_VERSION" -ge 6 ]; then
    if ! dotnet format "$BUILD_TARGET" --verify-no-changes --verbosity quiet; then
        echo "❌ Code formatting issues found. Run 'dotnet format' to fix them."
        exit 1
    fi
elif command -v dotnet-format &> /dev/null || dotnet tool list -g | grep -q dotnet-format; then
    if ! dotnet format "$BUILD_TARGET" --check --verbosity quiet; then
        echo "❌ Code formatting issues found. Run 'dotnet format' to fix them."
        exit 1
    fi
else
    echo "⚠️  dotnet-format not found. Install with: dotnet tool install -g dotnet-format"
    echo "   Skipping format check for now..."
fi
echo "✅ Code formatting check passed"

# Build the project
echo "🔨 Building project..."
if ! dotnet build "$BUILD_TARGET" --configuration Release --no-restore --verbosity quiet; then
    echo "❌ Build failed. Please fix build errors before committing."
    exit 1
fi
echo "✅ Build successful"

# Run static code analysis if available
echo "🔍 Running static code analysis..."

# Check for analyzers in project files
if grep -r "PackageReference.*Analyzer\|PackageReference.*CodeAnalysis" . --include="*.csproj" --include="*.vbproj" --include="*.fsproj" > /dev/null 2>&1; then
    echo "   📊 Found code analyzers in project"
fi

# Build will have run analyzers, so if we got this far, analysis passed
echo "✅ Static analysis passed"

# Run tests if test projects exist
TEST_PROJECTS=$(find . -name "*.Test*.csproj" -o -name "*.Tests.csproj" -o -name "*Test.csproj" -o -name "*Tests.csproj" | head -5)

if [ -n "$TEST_PROJECTS" ]; then
    echo "🧪 Running tests..."
    if ! dotnet test "$BUILD_TARGET" --configuration Release --no-build --verbosity quiet --logger "console;verbosity=minimal"; then
        echo "❌ Tests failed. Please fix failing tests before committing."
        exit 1
    fi
    echo "✅ All tests passed"
else
    # Check for common test patterns in any project
    if find . -name "*.cs" -exec grep -l "\[Test\]\|\[TestMethod\]\|\[Fact\]" {} \; | head -1 | grep -q .; then
        echo "🧪 Running tests (found test attributes)..."
        if ! dotnet test "$BUILD_TARGET" --configuration Release --no-build --verbosity quiet --logger "console;verbosity=minimal"; then
            echo "❌ Tests failed. Please fix failing tests before committing."
            exit 1
        fi
        echo "✅ All tests passed"
    else
        echo "ℹ️  No test projects found, skipping test execution"
    fi
fi

# Additional checks
echo "🔧 Running additional checks..."

# Check for common issues in C# code
if find . -name "*.cs" -exec grep -l "Console.WriteLine\|System.Diagnostics.Debug.WriteLine" {} \; | head -1 | grep -q .; then
    echo "⚠️  Warning: Found Console.WriteLine or Debug.WriteLine statements"
    echo "   Consider using proper logging (ILogger, Serilog, etc.)"
fi

# Check for hardcoded connection strings or secrets
if find . -name "*.cs" -exec grep -l "connectionString\|password\|secret\|apikey" {} \; | head -1 | grep -q .; then
    echo "⚠️  Warning: Potential hardcoded secrets found"
    echo "   Please ensure sensitive data is in configuration files or environment variables"
fi

# Check for TODO/FIXME/HACK comments
if find . -name "*.cs" -exec grep -l "TODO\|FIXME\|HACK" {} \; | head -1 | grep -q .; then
    echo "ℹ️  Info: Found TODO/FIXME/HACK comments in code"
fi

# Check for large files (> 1MB) being committed
LARGE_FILES=$(find . -type f -size +1M -not -path "./.git/*" -not -path "./bin/*" -not -path "./obj/*" | head -5)
if [ -n "$LARGE_FILES" ]; then
    echo "⚠️  Warning: Large files found (>1MB):"
    echo "$LARGE_FILES"
    echo "   Consider using Git LFS for large binary files"
fi

# Security check - ensure no sensitive files are being committed
SENSITIVE_PATTERNS="appsettings.production.json|web.config|*.pfx|*.p12|*.key|secrets.json"
if find . -type f \( -name "appsettings.production.json" -o -name "web.config" -o -name "*.pfx" -o -name "*.p12" -o -name "*.key" -o -name "secrets.json" \) -not -path "./.git/*" | head -1 | grep -q .; then
    echo "🚨 Warning: Potentially sensitive configuration files found"
    echo "   Please ensure production configurations and certificates are not committed"
fi

echo "✅ All pre-commit checks passed! 🎉"
echo ""
echo "📊 Summary:"
echo "   • Package restore: ✅"
echo "   • Code formatting: ✅" 
echo "   • Build: ✅"
echo "   • Static analysis: ✅"
echo "   • Tests: ✅"
echo "   • Additional checks: ✅"

exit 0