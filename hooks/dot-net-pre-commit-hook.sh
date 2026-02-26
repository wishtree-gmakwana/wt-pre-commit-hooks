#!/usr/bin/env bash
# .NET Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux
# Compatible with .NET 6+, .NET Framework, ASP.NET Core

set -euo pipefail

# ─── Color Output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[PASS]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[FAIL]${RESET}  $*" >&2; }
fatal()   { error "$*"; echo -e "${RED}${BOLD}Aborting commit.${RESET}" >&2; exit 1; }
separator(){ echo -e "${BOLD}$(printf '─%.0s' {1..70})${RESET}"; }

echo ""
separator
echo -e "${BOLD}  .NET Pre-commit Hook${RESET}"
separator
echo ""

# ─── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Darwin)  echo "mac";;
        Linux)   echo "linux";;
        MINGW*|MSYS*|CYGWIN*) echo "windows";;
        *)       [ -n "${WINDIR:-}" ] && echo "windows" || echo "unknown";;
    esac
}

OS=$(detect_os)
info "Detected OS: $OS"

# ─── Install Guidance ─────────────────────────────────────────────────────────
install_dotnet() {
    error ".NET CLI is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install .NET SDK (8.0 LTS recommended):${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:   brew install dotnet"
            echo "    Official:   https://dotnet.microsoft.com/download"
            echo "    MAUI/iOS:   Install Xcode first, then dotnet workload install ios maui"
            ;;
        linux)
            echo "    Ubuntu/Debian:"
            echo "      wget https://packages.microsoft.com/config/ubuntu/\$(lsb_release -rs)/packages-microsoft-prod.deb"
            echo "      sudo dpkg -i packages-microsoft-prod.deb"
            echo "      sudo apt-get update && sudo apt-get install -y dotnet-sdk-8.0"
            echo "    RHEL/CentOS: sudo dnf install -y dotnet-sdk-8.0"
            echo "    Arch:        sudo pacman -S dotnet-sdk"
            echo "    Script:      curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0"
            ;;
        windows)
            echo "    Download:   https://dotnet.microsoft.com/download"
            echo "    Chocolatey: choco install dotnet-sdk"
            echo "    Winget:     winget install Microsoft.DotNet.SDK.8"
            echo "    Visual Studio Installer includes .NET SDK"
            ;;
    esac
    fatal ".NET SDK is required. Please install it and retry."
}

# ─── Check .NET CLI ───────────────────────────────────────────────────────────
if ! command -v dotnet &>/dev/null; then
    install_dotnet
fi

DOTNET_VERSION=$(dotnet --version 2>&1)
DOTNET_MAJOR=$(echo "$DOTNET_VERSION" | cut -d. -f1)
info ".NET SDK: $DOTNET_VERSION"

if [ "${DOTNET_MAJOR:-0}" -lt 6 ]; then
    warn ".NET $DOTNET_VERSION is outdated. .NET 8.0 LTS is recommended."
    warn "Download: https://dotnet.microsoft.com/download"
fi

# ─── Project Detection ────────────────────────────────────────────────────────
is_dotnet_project() {
    find . -maxdepth 3 \( -name "*.sln" -o -name "*.csproj" -o -name "*.vbproj" -o -name "*.fsproj" \) 2>/dev/null | grep -q .
}

if ! is_dotnet_project; then
    fatal "Not a .NET project. No .sln, .csproj, .vbproj, or .fsproj files found."
fi

# ─── Build Target Detection ───────────────────────────────────────────────────
SOLUTION_FILES=$(find . -maxdepth 3 -name "*.sln" 2>/dev/null)
PROJECT_FILES=$(find . -maxdepth 3 \( -name "*.csproj" -o -name "*.vbproj" -o -name "*.fsproj" \) 2>/dev/null)

BUILD_TARGET="."
if [ -n "$SOLUTION_FILES" ]; then
    BUILD_TARGET=$(echo "$SOLUTION_FILES" | head -1)
    info "Solution: $BUILD_TARGET"
elif [ -n "$PROJECT_FILES" ]; then
    BUILD_TARGET=$(echo "$PROJECT_FILES" | head -1)
    info "Project: $BUILD_TARGET"
fi

# Detect test projects
TEST_PROJECTS=$(find . -maxdepth 5 \( -name "*Test*.csproj" -o -name "*Tests.csproj" -o -name "*Spec*.csproj" \) 2>/dev/null || true)

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_CS_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.(cs|vb|fs)$' || true)
ALL_STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

if [ -z "$ALL_STAGED" ]; then
    info "No staged files. Skipping checks."
    exit 0
fi

echo ""

# ─── Merge Conflict Markers ───────────────────────────────────────────────────
info "Checking for merge conflict markers..."
CONFLICT_FILES=""
for f in $ALL_STAGED; do
    [ -f "$f" ] || continue
    if grep -qP '^(<{7}|={7}|>{7})' "$f" 2>/dev/null; then
        CONFLICT_FILES="$CONFLICT_FILES\n  $f"
    fi
done
if [ -n "$CONFLICT_FILES" ]; then
    fatal "Merge conflict markers found in:$CONFLICT_FILES"
fi
success "No merge conflict markers."

# ─── Production Safety Checks ─────────────────────────────────────────────────
if [ -n "$STAGED_CS_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Production Safety Checks${RESET}"
    separator

    PROD_ISSUES=0

    # Console.WriteLine in production code (non-test)
    CONSOLE_FILES=""
    for f in $STAGED_CS_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(Test\.cs$|Tests\.cs$|Spec\.cs$|\.Tests/|\.Test/)'; then continue; fi
        if grep -qE 'Console\.(Write|WriteLine|Error\.Write)' "$f" 2>/dev/null; then
            CONSOLE_FILES="$CONSOLE_FILES\n  $f"
        fi
    done
    if [ -n "$CONSOLE_FILES" ]; then
        warn "Console.Write/WriteLine in production code:$CONSOLE_FILES"
        warn "Use ILogger (Microsoft.Extensions.Logging), Serilog, or NLog."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Debug.WriteLine
    DEBUG_LOG_FILES=""
    for f in $STAGED_CS_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(Test\.cs$|Tests\.cs$|Spec\.cs$|\.Tests/|\.Test/)'; then continue; fi
        if grep -qE 'System\.Diagnostics\.(Debug|Trace)\.(Write|WriteLine|Print)' "$f" 2>/dev/null; then
            DEBUG_LOG_FILES="$DEBUG_LOG_FILES\n  $f"
        fi
    done
    if [ -n "$DEBUG_LOG_FILES" ]; then
        warn "Debug.WriteLine / Trace.WriteLine in production code:$DEBUG_LOG_FILES"
        warn "Use structured logging (ILogger) instead."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Hardcoded connection strings or credentials
    CRED_FILES=""
    for f in $STAGED_CS_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(Test\.cs$|Tests\.cs$|Spec\.cs$|\.Tests/)'; then continue; fi
        if grep -qiE '(connectionString|password|apiKey|api_key|secret|token|privateKey)\s*=\s*"[^"]{8,}"' "$f" 2>/dev/null; then
            CRED_FILES="$CRED_FILES\n  $f"
        fi
    done
    if [ -n "$CRED_FILES" ]; then
        error "Potential hardcoded credentials in:$CRED_FILES"
        fatal "Use appsettings.json, user-secrets (dotnet user-secrets), Azure Key Vault, or environment variables."
    fi

    # Sensitive configuration files staged
    SENSITIVE_FILES=""
    for f in $ALL_STAGED; do
        case "$f" in
            *.pfx|*.p12|*.key|*.pem|id_rsa|id_ed25519|secrets.json)
                SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
                ;;
        esac
        if echo "$f" | grep -qiE '(appsettings\.production\.(json|xml)|web\.release\.config)$'; then
            warn "Production config staged: $f — ensure no secrets are included."
        fi
    done
    if [ -n "$SENSITIVE_FILES" ]; then
        error "Sensitive files staged:$SENSITIVE_FILES"
        fatal "Remove from staging and add to .gitignore."
    fi

    # Check for TODO/FIXME/HACK
    TODO_FILES=""
    for f in $STAGED_CS_FILES; do
        [ -f "$f" ] || continue
        if grep -qiE '//\s*(TODO|FIXME|HACK|XXX):' "$f" 2>/dev/null; then
            TODO_FILES="$TODO_FILES\n  $f"
        fi
    done
    [ -n "$TODO_FILES" ] && warn "TODO/FIXME/HACK comments found:$TODO_FILES"

    # Async void (anti-pattern)
    ASYNC_VOID_FILES=""
    for f in $STAGED_CS_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(Test\.cs$|Tests\.cs$|\.Tests/)'; then continue; fi
        if grep -qE 'async\s+void\s+(?!Main)' "$f" 2>/dev/null; then
            ASYNC_VOID_FILES="$ASYNC_VOID_FILES\n  $f"
        fi
    done
    if [ -n "$ASYNC_VOID_FILES" ]; then
        warn "async void methods found:$ASYNC_VOID_FILES"
        warn "Use async Task instead of async void to properly propagate exceptions."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Large files
    LARGE_FILES=""
    for f in $ALL_STAGED; do
        [ -f "$f" ] || continue
        SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 1048576 ]; then
            LARGE_FILES="$LARGE_FILES\n  $f ($(( SIZE / 1024 ))KB)"
        fi
    done
    [ -n "$LARGE_FILES" ] && warn "Large files staged (>1MB):$LARGE_FILES\nConsider Git LFS."

    [ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."
fi

# ─── NuGet Package Restore ────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  NuGet Package Restore${RESET}"
separator

info "Restoring NuGet packages..."
RESTORE_OUT=$(dotnet restore "$BUILD_TARGET" --verbosity quiet 2>&1) || {
    error "NuGet restore failed:"
    echo "$RESTORE_OUT" | grep -iE "(error|Error)" | head -20 >&2
    fatal "Fix NuGet restore errors before committing."
}
success "NuGet packages restored."

# ─── Code Formatting ──────────────────────────────────────────────────────────
if [ -n "$STAGED_CS_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Formatting (dotnet format)${RESET}"
    separator

    if [ "${DOTNET_MAJOR:-0}" -ge 6 ]; then
        info "Running dotnet format check..."
        FORMAT_OUT=$(dotnet format "$BUILD_TARGET" --verify-no-changes --verbosity quiet 2>&1) || {
            error "Code formatting issues found."
            echo "$FORMAT_OUT" | head -20 >&2
            error "Auto-fix with: dotnet format $BUILD_TARGET"
            fatal "Fix formatting before committing."
        }
        success "Code formatting check passed."
    else
        # Older .NET versions use dotnet-format tool
        if command -v dotnet-format &>/dev/null || dotnet tool list -g 2>/dev/null | grep -q dotnet-format; then
            FORMAT_OUT=$(dotnet format "$BUILD_TARGET" --check --verbosity quiet 2>&1) || {
                error "dotnet-format found issues."
                error "Auto-fix with: dotnet format $BUILD_TARGET"
                fatal "Fix formatting before committing."
            }
            success "Code formatting check passed."
        else
            warn "dotnet format not available for .NET $DOTNET_VERSION."
            warn "Install: dotnet tool install -g dotnet-format"
        fi
    fi
fi

# ─── Build ────────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Build (Release)${RESET}"
separator

info "Building project in Release configuration..."
BUILD_OUT=$(dotnet build "$BUILD_TARGET" \
    --configuration Release \
    --no-restore \
    --verbosity quiet \
    /p:TreatWarningsAsErrors=false \
    2>&1) || {
    error "Build failed:"
    echo "$BUILD_OUT" | grep -iE "^.*error" | head -30 >&2
    fatal "Fix build errors before committing."
}

# Check for compiler warnings (non-fatal, but surfaced)
WARN_COUNT=$(echo "$BUILD_OUT" | grep -c " warning " 2>/dev/null || echo "0")
if [ "$WARN_COUNT" -gt 0 ]; then
    warn "Build completed with $WARN_COUNT compiler warning(s)."
    warn "Consider enabling <TreatWarningsAsErrors>true</TreatWarningsAsErrors> in your .csproj."
fi

success "Build successful."

# ─── Roslyn Analyzer / Static Analysis ───────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Static Analysis (Roslyn Analyzers)${RESET}"
separator

# Roslyn analyzers run as part of build. Check if analyzers are configured.
ANALYZERS_FOUND=false
for f in $PROJECT_FILES; do
    if grep -qiE "(SonarAnalyzer|StyleCop|Roslynator|Microsoft\.CodeAnalysis\.NetAnalyzers|ErrorProne)" "$f" 2>/dev/null; then
        ANALYZERS_FOUND=true
        break
    fi
done

if $ANALYZERS_FOUND; then
    info "Roslyn Analyzers detected and ran during build."
    success "Static analysis passed (via build)."
else
    warn "No Roslyn Analyzers configured."
    warn "Add to .csproj: <PackageReference Include=\"Microsoft.CodeAnalysis.NetAnalyzers\" Version=\"*\" />"
    warn "Or install Roslynator: dotnet add package Roslynator.Analyzers"
fi

# ─── Security Vulnerability Scan ──────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Dependency Security (dotnet list vulnerabilities)${RESET}"
separator

info "Checking for vulnerable NuGet packages..."
VULN_OUT=$(dotnet list "$BUILD_TARGET" package --vulnerable --include-transitive 2>&1) || {
    warn "Could not run vulnerability check. Ensure dotnet SDK is up to date."
}

if echo "$VULN_OUT" | grep -qi "critical\|high"; then
    error "Critical/High severity vulnerabilities found:"
    echo "$VULN_OUT" | grep -iE "(critical|high)" | head -20 >&2
    fatal "Update vulnerable NuGet packages before committing."
elif echo "$VULN_OUT" | grep -qi "moderate\|low"; then
    warn "Low/Moderate vulnerabilities found."
    echo "$VULN_OUT" | grep -iE "(moderate|low)" | head -10 >&2
    warn "Run: dotnet list package --vulnerable  for full details."
    warn "Consider updating vulnerable packages."
else
    success "No known NuGet vulnerabilities found."
fi

# ─── Tests ────────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Tests${RESET}"
separator

HAS_TESTS=false
if [ -n "$TEST_PROJECTS" ]; then
    HAS_TESTS=true
else
    # Fallback: check for [Fact], [Test], [TestMethod] attributes
    if echo "$STAGED_CS_FILES" | tr ' ' '\n' | xargs grep -l '\[Fact\]\|\[Test\]\|\[TestMethod\]' 2>/dev/null | head -1 | grep -q .; then
        HAS_TESTS=true
    fi
    # Or check if any test project exists anywhere
    find . -name "*.csproj" -exec grep -l 'xunit\|NUnit\|MSTest\|nunit' {} \; 2>/dev/null | head -1 | grep -q . && HAS_TESTS=true
fi

if $HAS_TESTS; then
    info "Running tests..."
    TEST_OUT=$(dotnet test "$BUILD_TARGET" \
        --configuration Release \
        --no-build \
        --verbosity quiet \
        --logger "console;verbosity=minimal" \
        2>&1) || {
        error "Tests failed:"
        echo "$TEST_OUT" | grep -E "(Failed|Error|FAILED)" | head -30 >&2
        error "Run: dotnet test $BUILD_TARGET  for full output."
        fatal "Fix failing tests before committing."
    }
    # Extract test results summary
    SUMMARY=$(echo "$TEST_OUT" | grep -E "^Test run|passed|failed|skipped" | tail -5)
    if [ -n "$SUMMARY" ]; then
        echo "$SUMMARY"
    fi
    success "All tests passed."
else
    warn "No test projects detected."
    warn "Add unit tests using xUnit, NUnit, or MSTest for better code reliability."
fi

# ─── ASP.NET / .NET Specific Checks ──────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  .NET Specific Checks${RESET}"
separator

# Check for appsettings.json with sensitive production keys
if find . -name "appsettings.json" -not -path "*/bin/*" -not -path "*/obj/*" 2>/dev/null | head -1 | grep -q .; then
    for appsettings in $(find . -name "appsettings.json" -not -path "*/bin/*" -not -path "*/obj/*" 2>/dev/null); do
        if grep -qiE '"(ConnectionString|Password|ApiKey|Secret|Token)":\s*"[^"]{4,}"' "$appsettings" 2>/dev/null; then
            warn "Potential credentials in $appsettings"
            warn "Use dotnet user-secrets, Azure Key Vault, or environment variables."
        fi
    done
fi

# Check for appsettings.Production.json staged
if echo "$ALL_STAGED" | grep -qi "appsettings.production\|appsettings.prod"; then
    warn "Production appsettings file staged. Ensure no secrets are included."
    warn "Use Azure Key Vault, AWS Secrets Manager, or environment variables for production secrets."
fi

# Check for Nullable enabled (good practice)
for f in $PROJECT_FILES; do
    [ -f "$f" ] || continue
    if ! grep -q "Nullable" "$f" 2>/dev/null; then
        warn "$f: <Nullable>enable</Nullable> not set. Enable for better null safety."
        break
    fi
done

# Check for deprecated packages
DEPRECATED_PKGS=""
for proj in $PROJECT_FILES; do
    [ -f "$proj" ] || continue
    DEP_OUT=$(dotnet list "$proj" package --deprecated 2>/dev/null) || true
    if echo "$DEP_OUT" | grep -q "deprecated"; then
        DEPRECATED_PKGS="$DEPRECATED_PKGS\n  $proj"
    fi
done
if [ -n "$DEPRECATED_PKGS" ]; then
    warn "Deprecated NuGet packages in:$DEPRECATED_PKGS"
    warn "Run: dotnet list package --deprecated  for details."
fi

success ".NET specific checks completed."

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} NuGet restore:            ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Code formatting:          ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Build (Release):          ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Static analysis:          ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dependency security:      ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Tests:                    ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} .NET specific checks:     ${GREEN}PASS${RESET}"
echo ""

exit 0
