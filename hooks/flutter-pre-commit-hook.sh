#!/usr/bin/env bash
# Flutter Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux

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
echo -e "${BOLD}  Flutter Pre-commit Hook${RESET}"
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
install_flutter() {
    error "Flutter is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install Flutter:${RESET}"
    case "$OS" in
        mac)
            echo "    Official:  https://docs.flutter.dev/get-started/install/macos"
            echo "    FVM:       dart pub global activate fvm && fvm install stable"
            echo "    Homebrew:  brew install --cask flutter"
            ;;
        linux)
            echo "    Official:  https://docs.flutter.dev/get-started/install/linux"
            echo "    Snap:      sudo snap install flutter --classic"
            echo "    FVM:       dart pub global activate fvm && fvm install stable"
            ;;
        windows)
            echo "    Official:  https://docs.flutter.dev/get-started/install/windows"
            echo "    Chocolatey: choco install flutter"
            echo "    FVM:       dart pub global activate fvm && fvm install stable"
            ;;
    esac
    fatal "Flutter is required. Please install it and retry."
}

# ─── Check Flutter ────────────────────────────────────────────────────────────
# Support FVM (Flutter Version Manager)
FLUTTER_CMD="flutter"
if [ -f ".fvm/flutter_sdk/bin/flutter" ]; then
    FLUTTER_CMD=".fvm/flutter_sdk/bin/flutter"
    info "Using FVM Flutter: $FLUTTER_CMD"
elif command -v fvm &>/dev/null && fvm flutter --version &>/dev/null 2>&1; then
    FLUTTER_CMD="fvm flutter"
    info "Using FVM: $FLUTTER_CMD"
elif ! command -v flutter &>/dev/null; then
    install_flutter
fi

FLUTTER_VERSION=$($FLUTTER_CMD --version 2>&1 | head -1)
info "Flutter: $FLUTTER_VERSION"

DART_CMD="${FLUTTER_CMD/flutter/dart}"
command -v dart &>/dev/null && DART_CMD="dart"

# ─── Project Detection ────────────────────────────────────────────────────────
if [ ! -f "pubspec.yaml" ]; then
    fatal "Not a Flutter project. pubspec.yaml not found."
fi

# Check if this is a Flutter or pure Dart project
IS_FLUTTER=false
grep -q "flutter:" pubspec.yaml 2>/dev/null && IS_FLUTTER=true
$IS_FLUTTER && info "Flutter app project detected." || info "Dart package project detected."

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_DART_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.dart$' || true)
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

# ─── Dependencies ─────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Flutter Dependencies${RESET}"
separator

info "Getting Flutter/Dart dependencies..."
PUB_OUT=$($FLUTTER_CMD pub get 2>&1) || {
    error "flutter pub get failed:"
    echo "$PUB_OUT" | tail -20 >&2
    fatal "Fix pubspec.yaml errors before committing."
}
success "Dependencies resolved."

# ─── Outdated Dependency Check ────────────────────────────────────────────────
if $FLUTTER_CMD pub outdated --no-color > /tmp/pub_outdated 2>&1; then
    OUTDATED_COUNT=$(grep -c "^[[:space:]]*[*!]" /tmp/pub_outdated 2>/dev/null || echo "0")
    if [ "$OUTDATED_COUNT" -gt 0 ]; then
        warn "$OUTDATED_COUNT outdated package(s) found. Run: flutter pub upgrade"
    fi
fi

# ─── Production Safety Checks ─────────────────────────────────────────────────
if [ -n "$STAGED_DART_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Production Safety Checks${RESET}"
    separator

    PROD_ISSUES=0

    # print() statements (should use logger in production)
    PRINT_FILES=""
    for f in $STAGED_DART_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(_test\.dart$|/test/)'; then continue; fi
        if grep -qE '^\s*print\s*\(' "$f" 2>/dev/null; then
            PRINT_FILES="$PRINT_FILES\n  $f"
        fi
    done
    if [ -n "$PRINT_FILES" ]; then
        warn "print() statements in production code:$PRINT_FILES"
        warn "Use debugPrint() for debug or a logging package (e.g., logger) for production."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # debugPrint in production (non-test)
    DEBUG_PRINT_FILES=""
    for f in $STAGED_DART_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(_test\.dart$|/test/)'; then continue; fi
        if grep -qE '^\s*debugPrint\s*\(' "$f" 2>/dev/null; then
            DEBUG_PRINT_FILES="$DEBUG_PRINT_FILES\n  $f"
        fi
    done
    if [ -n "$DEBUG_PRINT_FILES" ]; then
        warn "debugPrint() found in production code:$DEBUG_PRINT_FILES"
        warn "Remove or wrap with kDebugMode before release."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Hardcoded API keys / secrets in Dart files
    CRED_FILES=""
    for f in $STAGED_DART_FILES; do
        [ -f "$f" ] || continue
        if grep -qiE "(apiKey|api_key|secret|token|password)\s*=\s*['\"][^'\"]{8,}" "$f" 2>/dev/null; then
            CRED_FILES="$CRED_FILES\n  $f"
        fi
    done
    if [ -n "$CRED_FILES" ]; then
        error "Potential hardcoded secrets in:$CRED_FILES"
        fatal "Use flutter_dotenv, --dart-define, or a secrets manager. Never hardcode secrets."
    fi

    # Sensitive files staged
    SENSITIVE_FILES=""
    for f in $ALL_STAGED; do
        case "$f" in
            *.pem|*.key|*.p8|*.p12|google-services.json|GoogleService-Info.plist|.env|.env.production)
                SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
                ;;
        esac
    done
    if [ -n "$SENSITIVE_FILES" ]; then
        error "Sensitive files staged:$SENSITIVE_FILES"
        fatal "Add them to .gitignore. Use firebase_options.dart with --dart-define instead."
    fi

    # TODO/FIXME
    TODO_FILES=""
    for f in $STAGED_DART_FILES; do
        [ -f "$f" ] || continue
        if grep -qiE '//\s*(TODO|FIXME|HACK|XXX):' "$f" 2>/dev/null; then
            TODO_FILES="$TODO_FILES\n  $f"
        fi
    done
    [ -n "$TODO_FILES" ] && warn "TODO/FIXME/HACK comments found:$TODO_FILES"

    # Large files
    LARGE_FILES=""
    for f in $ALL_STAGED; do
        [ -f "$f" ] || continue
        SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 1048576 ]; then
            LARGE_FILES="$LARGE_FILES\n  $f ($(( SIZE / 1024 ))KB)"
        fi
    done
    [ -n "$LARGE_FILES" ] && warn "Large files staged (>1MB):$LARGE_FILES\nOptimize assets or use Git LFS."

    [ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."
fi

# ─── Dart Format ──────────────────────────────────────────────────────────────
if [ -n "$STAGED_DART_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Dart Formatting${RESET}"
    separator

    info "Checking Dart code formatting..."
    FORMAT_FILES=$(echo "$STAGED_DART_FILES" | tr '\n' ' ')

    FORMAT_OUT=$(dart format --output=none $FORMAT_FILES 2>&1)
    if echo "$FORMAT_OUT" | grep -q "Changed"; then
        warn "Formatting issues found. Auto-fixing..."
        dart format $FORMAT_FILES 2>/dev/null || true
        echo "$STAGED_DART_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
        success "Dart formatting applied and files re-staged."
    else
        FORMAT_CHECK_OUT=$(dart format --set-exit-if-changed $FORMAT_FILES 2>&1) || {
            error "Dart formatting issues:"
            echo "$FORMAT_CHECK_OUT" | head -20 >&2
            error "Fix with: dart format lib/ test/"
            fatal "Formatting issues found. Fix before committing."
        }
        success "Dart formatting check passed."
    fi
fi

# ─── Dart Analyzer ────────────────────────────────────────────────────────────
if [ -n "$STAGED_DART_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Static Analysis (dart analyze)${RESET}"
    separator

    info "Running Dart analyzer..."
    ANALYZER_OUT=$(dart analyze 2>&1) || {
        error "Dart analyzer found issues:"
        echo "$ANALYZER_OUT" | grep -E "(error|warning)" | head -30 >&2
        # Only fail on errors, not warnings
        if echo "$ANALYZER_OUT" | grep -q "^  error •"; then
            fatal "Fix Dart analyzer errors before committing."
        fi
        warn "Warnings found. Consider fixing them."
    }
    success "Dart analyzer passed."
fi

# ─── Custom Lint (dart_code_metrics / very_good_analysis) ─────────────────────
if [ -n "$STAGED_DART_FILES" ]; then
    if grep -q "dart_code_metrics\|very_good_analysis\|flutter_lints" pubspec.yaml 2>/dev/null; then
        info "Custom lint rules detected. Analyzer checks already cover these."
    fi
fi

# ─── Flutter Tests ────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Tests${RESET}"
separator

TEST_COUNT=$(find test -name "*_test.dart" 2>/dev/null | wc -l | tr -d ' ')

if [ "$TEST_COUNT" -gt 0 ]; then
    info "Running Flutter tests ($TEST_COUNT test file(s))..."
    TEST_OUT=$($FLUTTER_CMD test --reporter=compact 2>&1) || {
        error "Tests failed:"
        echo "$TEST_OUT" | grep -E "(FAILED|Error)" | head -30 >&2
        fatal "Fix failing tests before committing."
    }
    success "All tests passed."
else
    warn "No test files found in test/. Add tests to improve code quality."
fi

# ─── pubspec.yaml Validation ──────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  pubspec.yaml Validation${RESET}"
separator

# Check for version format
if ! grep -qE '^version:\s+[0-9]+\.[0-9]+\.[0-9]+' pubspec.yaml 2>/dev/null; then
    warn "pubspec.yaml version may not follow semver (X.Y.Z)."
fi

# Check pubspec.lock is committed
if [ ! -f "pubspec.lock" ]; then
    warn "pubspec.lock not found. Commit it for reproducible builds."
fi

# Check if pubspec.lock is in .gitignore (it shouldn't be for apps)
if grep -q "pubspec.lock" .gitignore 2>/dev/null; then
    if $IS_FLUTTER; then
        warn "pubspec.lock is in .gitignore. For Flutter apps, commit pubspec.lock for reproducibility."
    fi
fi

success "pubspec.yaml validation completed."

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dependencies:             ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dart formatting:          ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dart analyzer:            ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Tests:                    ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} pubspec.yaml:             ${GREEN}PASS${RESET}"
echo ""

exit 0
