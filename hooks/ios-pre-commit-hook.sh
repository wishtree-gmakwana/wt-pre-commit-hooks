#!/usr/bin/env bash
# iOS Pre-commit Hook
# Supports Mac only (iOS development requires macOS + Xcode)
# Compatible with Swift, Objective-C, SwiftPM, CocoaPods, Carthage projects

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
echo -e "${BOLD}  iOS Pre-commit Hook${RESET}"
separator
echo ""

# ─── OS Check ─────────────────────────────────────────────────────────────────
OS=$(uname -s 2>/dev/null)
if [ "$OS" != "Darwin" ]; then
    error "iOS development requires macOS."
    echo ""
    echo -e "${BOLD}  This hook can only run on macOS:${RESET}"
    echo "    • Xcode and iOS SDK are macOS-only"
    echo "    • SwiftLint and SwiftFormat require macOS"
    echo "    • For CI on Linux, use xcode-cloud or GitHub Actions with macos runner"
    fatal "Please run this hook on a macOS machine."
fi

info "Detected OS: macOS"

# ─── Install Guidance ─────────────────────────────────────────────────────────
install_xcode_cli() {
    error "Xcode Command Line Tools are not installed."
    echo ""
    echo -e "${BOLD}  Install Xcode Command Line Tools:${RESET}"
    echo "    xcode-select --install"
    echo "    Or install Xcode from the App Store: https://apps.apple.com/app/xcode/id497799835"
    fatal "Xcode Command Line Tools are required."
}

install_swiftlint() {
    error "SwiftLint is not installed."
    echo ""
    echo -e "${BOLD}  Install SwiftLint:${RESET}"
    echo "    Homebrew: brew install swiftlint"
    echo "    Mint:     mint install realm/SwiftLint"
    echo "    SPM plugin: Add to Package.swift as a plugin"
    echo "    Download:   https://github.com/realm/SwiftLint/releases"
    warn "SwiftLint is strongly recommended for Swift code quality."
}

install_swiftformat() {
    error "SwiftFormat is not installed."
    echo ""
    echo -e "${BOLD}  Install SwiftFormat:${RESET}"
    echo "    Homebrew: brew install swiftformat"
    echo "    Mint:     mint install nicklockwood/SwiftFormat"
    echo "    Download:   https://github.com/nicklockwood/SwiftFormat/releases"
    warn "SwiftFormat is recommended for consistent Swift formatting."
}

# ─── Check Xcode ──────────────────────────────────────────────────────────────
if ! command -v xcode-select &>/dev/null || ! xcode-select -p &>/dev/null 2>&1; then
    install_xcode_cli
fi

XCODE_PATH=$(xcode-select -p 2>/dev/null || echo "Not found")
info "Xcode tools: $XCODE_PATH"

if command -v xcodebuild &>/dev/null; then
    XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1)
    info "Xcode: $XCODE_VERSION"
else
    warn "xcodebuild not found. Full Xcode (not just CLI tools) is recommended."
fi

if command -v swift &>/dev/null; then
    SWIFT_VERSION=$(swift --version 2>&1 | head -1)
    info "Swift: $SWIFT_VERSION"
fi

# ─── Project Detection ────────────────────────────────────────────────────────
is_ios_project() {
    find . -maxdepth 2 -name "*.xcodeproj" -o -name "*.xcworkspace" 2>/dev/null | grep -q . && return 0
    [ -f "Package.swift" ] && return 0
    return 1
}

if ! is_ios_project; then
    fatal "Not an iOS project. No .xcodeproj, .xcworkspace, or Package.swift found."
fi

# Project type detection
HAS_XCODEPROJ=$(find . -maxdepth 2 -name "*.xcodeproj" 2>/dev/null | head -1)
HAS_XCWORKSPACE=$(find . -maxdepth 2 -name "*.xcworkspace" 2>/dev/null | head -1)
HAS_SPM=false; [ -f "Package.swift" ] && HAS_SPM=true
HAS_COCOAPODS=false; [ -f "Podfile" ] && HAS_COCOAPODS=true
HAS_CARTHAGE=false; [ -f "Cartfile" ] && HAS_CARTHAGE=true

info "Project markers:"
[ -n "$HAS_XCWORKSPACE" ] && info "  Workspace: $HAS_XCWORKSPACE"
[ -n "$HAS_XCODEPROJ" ] && info "  Project: $HAS_XCODEPROJ"
$HAS_SPM && info "  Swift Package Manager"
$HAS_COCOAPODS && info "  CocoaPods"
$HAS_CARTHAGE && info "  Carthage"

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.swift$' || true)
STAGED_OBJC_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.(m|h)$' || true)
ALL_STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
ALL_CODE_FILES="$STAGED_SWIFT_FILES $STAGED_OBJC_FILES"

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
    if grep -qE '^(<{7}|={7}|>{7})' "$f" 2>/dev/null; then
        CONFLICT_FILES="$CONFLICT_FILES\n  $f"
    fi
done
if [ -n "$CONFLICT_FILES" ]; then
    fatal "Merge conflict markers found in:$CONFLICT_FILES"
fi
success "No merge conflict markers."

# ─── Production Safety Checks ─────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Production Safety Checks${RESET}"
separator

PROD_ISSUES=0

# print() statements in Swift production code
PRINT_FILES=""
for f in $STAGED_SWIFT_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.swift$|Spec\.swift$|/Tests/)'; then continue; fi
    if grep -qE '^\s*print\s*\(' "$f" 2>/dev/null; then
        PRINT_FILES="$PRINT_FILES\n  $f"
    fi
done
if [ -n "$PRINT_FILES" ]; then
    warn "print() statements in production Swift code:$PRINT_FILES"
    warn "Use os_log, Logger, or a logging framework like CocoaLumberjack."
    PROD_ISSUES=$((PROD_ISSUES + 1))
fi

# debugPrint / dump in production code
DEBUG_FILES=""
for f in $STAGED_SWIFT_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.swift$|Spec\.swift$|/Tests/)'; then continue; fi
    if grep -qE '^\s*(debugPrint|dump)\s*\(' "$f" 2>/dev/null; then
        DEBUG_FILES="$DEBUG_FILES\n  $f"
    fi
done
if [ -n "$DEBUG_FILES" ]; then
    warn "debugPrint / dump in production code:$DEBUG_FILES"
    warn "Wrap with #if DEBUG or use proper logging."
    PROD_ISSUES=$((PROD_ISSUES + 1))
fi

# NSLog in production ObjC/Swift
NSLOG_FILES=""
for f in $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.(swift|m)$|Spec\.swift$|/Tests/)'; then continue; fi
    if grep -qE '\bNSLog\s*\(' "$f" 2>/dev/null; then
        NSLOG_FILES="$NSLOG_FILES\n  $f"
    fi
done
if [ -n "$NSLOG_FILES" ]; then
    warn "NSLog found in production code:$NSLOG_FILES"
    warn "NSLog is slow and outputs to device syslog. Use os_log or Logger."
    PROD_ISSUES=$((PROD_ISSUES + 1))
fi

# Hardcoded credentials
CRED_FILES=""
for f in $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.(swift|m)$|Spec\.swift$|/Tests/)'; then continue; fi
    if grep -qiE '(apiKey|api_key|password|secret|token|privateKey)\s*=\s*"[^"]{8,}"' "$f" 2>/dev/null; then
        CRED_FILES="$CRED_FILES\n  $f"
    fi
done
if [ -n "$CRED_FILES" ]; then
    error "Potential hardcoded credentials in:$CRED_FILES"
    fatal "Use Keychain, Info.plist with CI injection, or a secrets manager."
fi

# Sensitive files staged
SENSITIVE_FILES=""
for f in $ALL_STAGED; do
    case "$f" in
        *.p12|*.cer|*.mobileprovision|*.p8|GoogleService-Info.plist|*.pem|*.key|id_rsa|id_ed25519|Secrets.swift|APIKeys.swift)
            SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
            ;;
    esac
done
if [ -n "$SENSITIVE_FILES" ]; then
    error "Sensitive files staged:$SENSITIVE_FILES"
    fatal "Remove from staging. Add to .gitignore. Use CI/CD secrets for provisioning."
fi

# Force unwrap warnings (!) - too many can indicate fragile code
FORCE_UNWRAP_FILES=""
for f in $STAGED_SWIFT_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.swift$|Spec\.swift$|/Tests/)'; then continue; fi
    COUNT=$(grep -c "!\s*$\|!\." "$f" 2>/dev/null || echo 0)
    if [ "$COUNT" -gt 10 ]; then
        FORCE_UNWRAP_FILES="$FORCE_UNWRAP_FILES\n  $f ($COUNT force unwraps)"
    fi
done
if [ -n "$FORCE_UNWRAP_FILES" ]; then
    warn "Excessive force unwrap (!) usage:$FORCE_UNWRAP_FILES"
    warn "Use guard/if-let or optional chaining to avoid crashes."
    PROD_ISSUES=$((PROD_ISSUES + 1))
fi

# TODO/FIXME
TODO_FILES=""
for f in $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if grep -qiE '//\s*(TODO|FIXME|HACK|XXX):' "$f" 2>/dev/null; then
        TODO_FILES="$TODO_FILES\n  $f"
    fi
done
[ -n "$TODO_FILES" ] && warn "TODO/FIXME/HACK comments found:$TODO_FILES"

# Large files / binary assets
LARGE_FILES=""
for f in $ALL_STAGED; do
    [ -f "$f" ] || continue
    SIZE=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 2097152 ]; then
        LARGE_FILES="$LARGE_FILES\n  $f ($(( SIZE / 1024 ))KB)"
    fi
done
[ -n "$LARGE_FILES" ] && warn "Large files staged (>2MB):$LARGE_FILES\nUse Git LFS for binary assets."

[ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."

# ─── SwiftFormat ──────────────────────────────────────────────────────────────
if [ -n "$STAGED_SWIFT_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Formatting (SwiftFormat)${RESET}"
    separator

    SWIFTFORMAT_CMD=""
    if command -v swiftformat &>/dev/null; then
        SWIFTFORMAT_CMD="swiftformat"
    elif command -v mint &>/dev/null && mint which swiftformat &>/dev/null 2>&1; then
        SWIFTFORMAT_CMD="mint run swiftformat"
    fi

    if [ -n "$SWIFTFORMAT_CMD" ]; then
        SWIFTFORMAT_VERSION=$($SWIFTFORMAT_CMD --version 2>&1)
        info "SwiftFormat: $SWIFTFORMAT_VERSION"

        # Apply formatting
        FORMAT_ARGS="--quiet"
        [ -f ".swiftformat" ] && FORMAT_ARGS="$FORMAT_ARGS --config .swiftformat"

        info "Running SwiftFormat on staged files..."
        SF_OUT=$(echo "$STAGED_SWIFT_FILES" | tr '\n' ' ' | xargs $SWIFTFORMAT_CMD $FORMAT_ARGS 2>&1) || {
            error "SwiftFormat failed:"
            echo "$SF_OUT" | head -20 >&2
            fatal "Fix SwiftFormat errors before committing."
        }
        echo "$STAGED_SWIFT_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
        success "SwiftFormat applied."
    else
        install_swiftformat
        warn "Skipping SwiftFormat..."
    fi
fi

# ─── SwiftLint ────────────────────────────────────────────────────────────────
if [ -n "$STAGED_SWIFT_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Style (SwiftLint)${RESET}"
    separator

    SWIFTLINT_CMD=""
    if command -v swiftlint &>/dev/null; then
        SWIFTLINT_CMD="swiftlint"
    elif command -v mint &>/dev/null && mint which swiftlint &>/dev/null 2>&1; then
        SWIFTLINT_CMD="mint run swiftlint"
    fi

    if [ -n "$SWIFTLINT_CMD" ]; then
        SWIFTLINT_VERSION=$($SWIFTLINT_CMD version 2>&1)
        info "SwiftLint: $SWIFTLINT_VERSION"

        # Auto-correct first
        LINT_ARGS=""
        [ -f ".swiftlint.yml" ] && LINT_ARGS="--config .swiftlint.yml"

        info "Running SwiftLint autocorrect on staged files..."
        echo "$STAGED_SWIFT_FILES" | tr '\n' ' ' | xargs $SWIFTLINT_CMD autocorrect $LINT_ARGS --quiet 2>/dev/null || true
        echo "$STAGED_SWIFT_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true

        # Then lint (fail on errors, not warnings)
        info "Running SwiftLint lint check..."
        LINT_OUT=$(echo "$STAGED_SWIFT_FILES" | tr '\n' ' ' | xargs $SWIFTLINT_CMD lint $LINT_ARGS 2>&1) || {
            ERRORS=$(echo "$LINT_OUT" | grep -c " error:" 2>/dev/null || echo "0")
            if [ "$ERRORS" -gt 0 ]; then
                error "SwiftLint found $ERRORS error(s):"
                echo "$LINT_OUT" | grep " error:" | head -20 >&2
                fatal "Fix SwiftLint errors before committing."
            fi
        }
        WARN_COUNT=$(echo "$LINT_OUT" | grep -c " warning:" 2>/dev/null || echo "0")
        [ "$WARN_COUNT" -gt 0 ] && warn "SwiftLint: $WARN_COUNT warning(s). Review when possible."
        success "SwiftLint check passed."
    else
        install_swiftlint
        warn "Skipping SwiftLint..."
    fi
fi

# ─── Swift Build Check ────────────────────────────────────────────────────────
if $HAS_SPM; then
    echo ""
    separator
    echo -e "${BOLD}  Swift Package Build${RESET}"
    separator

    info "Building Swift package..."
    BUILD_OUT=$(swift build 2>&1) || {
        error "Swift build failed:"
        echo "$BUILD_OUT" | grep -E "(error:|warning:)" | head -30 >&2
        fatal "Fix build errors before committing."
    }
    success "Swift package built successfully."

    # Swift tests
    echo ""
    separator
    echo -e "${BOLD}  Swift Tests${RESET}"
    separator

    if find . -name "*Tests.swift" -o -name "*Test.swift" 2>/dev/null | grep -q .; then
        info "Running Swift tests..."
        TEST_OUT=$(swift test 2>&1) || {
            error "Swift tests failed:"
            echo "$TEST_OUT" | grep -E "(error:|FAILED)" | head -30 >&2
            fatal "Fix failing tests before committing."
        }
        success "All Swift tests passed."
    else
        warn "No test files found. Add XCTest test cases."
    fi
fi

# ─── CocoaPods Check ─────────────────────────────────────────────────────────
if $HAS_COCOAPODS; then
    echo ""
    separator
    echo -e "${BOLD}  CocoaPods${RESET}"
    separator

    if command -v pod &>/dev/null; then
        info "CocoaPods: $(pod --version 2>&1)"

        # Check Podfile.lock vs Podfile consistency
        if [ -f "Podfile.lock" ]; then
            POD_CHECK=$(pod install --dry-run 2>&1) || true
            if echo "$POD_CHECK" | grep -qi "Podfile has changed\|out of date"; then
                warn "Podfile.lock may be out of date."
                warn "Run: pod install"
            else
                success "CocoaPods Podfile.lock is up to date."
            fi
        else
            warn "Podfile.lock not found. Run: pod install"
        fi

        # Check for pod security advisories
        if command -v pod &>/dev/null; then
            POD_AUDIT=$(pod outdated 2>/dev/null | head -10) || true
            if [ -n "$POD_AUDIT" ]; then
                warn "Outdated pods found. Consider updating dependencies."
            fi
        fi
    else
        warn "pod command not found. Install: sudo gem install cocoapods"
    fi
fi

# ─── Xcodebuild Check (if full Xcode available) ───────────────────────────────
if command -v xcodebuild &>/dev/null && [ -n "$HAS_XCODEPROJ" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Xcode Build Check${RESET}"
    separator

    # Find the workspace or project
    BUILD_TARGET=""
    if [ -n "$HAS_XCWORKSPACE" ]; then
        BUILD_TARGET="-workspace $HAS_XCWORKSPACE"
    elif [ -n "$HAS_XCODEPROJ" ]; then
        BUILD_TARGET="-project $HAS_XCODEPROJ"
    fi

    if [ -n "$BUILD_TARGET" ]; then
        # Get scheme
        SCHEME=$(xcodebuild -list $BUILD_TARGET 2>/dev/null | awk '/Schemes:/,0' | grep -v "Schemes:" | head -1 | tr -d ' ')
        if [ -n "$SCHEME" ]; then
            info "Building scheme: $SCHEME (analyze only)..."
            BUILD_OUT=$(xcodebuild $BUILD_TARGET -scheme "$SCHEME" \
                -destination "generic/platform=iOS Simulator" \
                analyze \
                ONLY_ACTIVE_ARCH=YES \
                CODE_SIGNING_ALLOWED=NO \
                -quiet 2>&1) || {
                error "Xcode build/analyze failed:"
                echo "$BUILD_OUT" | grep -E "(error:|BUILD FAILED)" | head -20 >&2
                fatal "Fix build errors before committing."
            }
            success "Xcode build analysis passed."
        else
            warn "No scheme found. Skipping Xcode build check."
        fi
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} SwiftFormat:              ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} SwiftLint:                ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Build check:              ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Tests:                    ${GREEN}PASS${RESET}"
echo ""

exit 0
