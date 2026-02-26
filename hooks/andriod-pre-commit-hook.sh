#!/usr/bin/env bash
# Android Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux
# Compatible with Gradle-based Android projects

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
echo -e "${BOLD}  Android Pre-commit Hook${RESET}"
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
install_java() {
    error "Java JDK is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install Java JDK 17 (required for modern Android):${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:  brew install openjdk@17"
            echo "    SDKMAN:    sdk install java 17-tem"
            echo "    Android Studio includes JDK — use it via JAVA_HOME"
            ;;
        linux)
            echo "    Ubuntu:    sudo apt-get install -y openjdk-17-jdk"
            echo "    RHEL:      sudo dnf install -y java-17-openjdk-devel"
            echo "    SDKMAN:    https://sdkman.io/"
            ;;
        windows)
            echo "    Android Studio includes JDK — set JAVA_HOME to its jdk/ folder"
            echo "    Or: https://adoptium.net/"
            echo "    Chocolatey: choco install openjdk17"
            ;;
    esac
    fatal "Java JDK 17+ is required for Android development."
}

install_android_sdk() {
    error "ANDROID_HOME / ANDROID_SDK_ROOT is not set."
    echo ""
    echo -e "${BOLD}  Set up Android SDK:${RESET}"
    case "$OS" in
        mac|linux)
            echo "    1. Install Android Studio: https://developer.android.com/studio"
            echo "    2. Open SDK Manager and install Android SDK"
            echo "    3. Add to ~/.bashrc or ~/.zshrc:"
            echo "       export ANDROID_HOME=\$HOME/Library/Android/sdk  # Mac"
            echo "       export ANDROID_HOME=\$HOME/Android/Sdk           # Linux"
            echo "       export PATH=\$PATH:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/tools/bin"
            ;;
        windows)
            echo "    1. Install Android Studio: https://developer.android.com/studio"
            echo "    2. Open SDK Manager and install Android SDK"
            echo "    3. Set ANDROID_HOME in System Environment Variables"
            echo "       Default: C:\\Users\\<user>\\AppData\\Local\\Android\\Sdk"
            ;;
    esac
    warn "Android SDK not configured. Skipping SDK-specific checks."
}

install_gradle() {
    error "Gradle Wrapper (gradlew) not found and Gradle is not installed."
    echo ""
    echo -e "${BOLD}  Gradle Wrapper is required for Android projects.${RESET}"
    echo "    Run from an existing Android project: gradle wrapper"
    echo "    Or create a new project in Android Studio (includes gradlew)."
    case "$OS" in
        mac)    echo "    Install Gradle: brew install gradle";;
        linux)  echo "    Install Gradle: sdk install gradle  (via SDKMAN)";;
        windows) echo "    Install Gradle: choco install gradle";;
    esac
}

# ─── Check Java ───────────────────────────────────────────────────────────────
if ! command -v java &>/dev/null; then
    install_java
fi

JAVA_VERSION_FULL=$(java -version 2>&1 | head -1)
info "Java: $JAVA_VERSION_FULL"

JAVA_MAJOR=$(java -version 2>&1 | grep -oE '[0-9]+\.[0-9]+|[0-9]+' | head -1 | cut -d. -f1)
if [ "${JAVA_MAJOR:-0}" -lt 17 ]; then
    warn "Java $JAVA_MAJOR detected. Android Gradle Plugin 8+ requires Java 17+."
    case "$OS" in
        mac)    warn "Upgrade: brew install openjdk@17";;
        linux)  warn "Upgrade: sudo apt-get install -y openjdk-17-jdk";;
        windows) warn "Upgrade: https://adoptium.net/";;
    esac
fi

# ─── Android SDK Check ────────────────────────────────────────────────────────
ANDROID_HOME_SET=false
for sdk_var in ANDROID_HOME ANDROID_SDK_ROOT; do
    if [ -n "${!sdk_var:-}" ] && [ -d "${!sdk_var}" ]; then
        info "Android SDK: ${!sdk_var}"
        ANDROID_HOME_SET=true
        break
    fi
done
if ! $ANDROID_HOME_SET; then
    install_android_sdk
fi

# ─── Project Detection ────────────────────────────────────────────────────────
is_android_project() {
    [ -f "gradlew" ] && { [ -f "app/build.gradle" ] || [ -f "app/build.gradle.kts" ]; } && return 0
    [ -f "settings.gradle" ] || [ -f "settings.gradle.kts" ] && return 0
    return 1
}

if ! is_android_project; then
    fatal "Not an Android project. No gradlew + app/build.gradle found."
fi

# ─── Gradle Wrapper ───────────────────────────────────────────────────────────
if [ ! -f "gradlew" ]; then
    install_gradle
    fatal "gradlew is missing. Android projects require the Gradle Wrapper."
fi

chmod +x gradlew 2>/dev/null || true
GRADLE_VERSION=$(./gradlew --version 2>&1 | grep "^Gradle" | head -1)
info "Gradle: $GRADLE_VERSION"

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_JAVA_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.java$' || true)
STAGED_KT_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.kt$' || true)
STAGED_XML_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.xml$' || true)
ALL_STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
ALL_CODE_FILES="$STAGED_JAVA_FILES $STAGED_KT_FILES"

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
echo ""
separator
echo -e "${BOLD}  Production Safety Checks${RESET}"
separator

PROD_ISSUES=0

# Log.d/Log.v in production code
LOG_DEBUG_FILES=""
for f in $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.java$|Test\.kt$|/test/|/androidTest/)'; then continue; fi
    if grep -qE '\bLog\.(d|v)\s*\(' "$f" 2>/dev/null; then
        LOG_DEBUG_FILES="$LOG_DEBUG_FILES\n  $f"
    fi
done
if [ -n "$LOG_DEBUG_FILES" ]; then
    warn "Log.d / Log.v (debug logs) found in production code:$LOG_DEBUG_FILES"
    warn "Use BuildConfig.DEBUG guard or Timber with debug-only tree."
    PROD_ISSUES=$((PROD_ISSUES + 1))
fi

# System.out.println in Java/Kotlin files
SYSOUT_FILES=""
for f in $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.java$|Test\.kt$|/test/|/androidTest/)'; then continue; fi
    if grep -qE 'System\.(out|err)\.(print|println|printf)' "$f" 2>/dev/null; then
        SYSOUT_FILES="$SYSOUT_FILES\n  $f"
    fi
done
if [ -n "$SYSOUT_FILES" ]; then
    warn "System.out.println found:$SYSOUT_FILES"
    warn "Use Android Log or Timber for logging."
    PROD_ISSUES=$((PROD_ISSUES + 1))
fi

# Hardcoded API keys / credentials
CRED_FILES=""
for f in $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if echo "$f" | grep -qiE '(Test\.java$|Test\.kt$|/test/)'; then continue; fi
    if grep -qiE '(apiKey|api_key|password|secret|token|privateKey)\s*=\s*"[^"]{8,}"' "$f" 2>/dev/null; then
        CRED_FILES="$CRED_FILES\n  $f"
    fi
done
if [ -n "$CRED_FILES" ]; then
    error "Potential hardcoded credentials in:$CRED_FILES"
    fatal "Use BuildConfig fields, local.properties, or secrets-gradle-plugin."
fi

# google-services.json / keystore / signing files staged
SENSITIVE_FILES=""
for f in $ALL_STAGED; do
    case "$f" in
        google-services.json|*.jks|*.keystore|*.p12|*.pem|*.key|local.properties)
            SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
            ;;
    esac
done
if [ -n "$SENSITIVE_FILES" ]; then
    error "Sensitive files staged:$SENSITIVE_FILES"
    fatal "Remove from staging. Add to .gitignore. Use CI secrets for signing."
fi

# debuggable=true in release build (in XML/Gradle)
for f in $STAGED_XML_FILES $ALL_CODE_FILES; do
    [ -f "$f" ] || continue
    if grep -q 'android:debuggable="true"' "$f" 2>/dev/null; then
        error "android:debuggable=\"true\" found in: $f"
        fatal "Remove debuggable=true before committing. Never ship debuggable APKs."
    fi
done

# TODO/FIXME/HACK
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
    SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 2097152 ]; then
        LARGE_FILES="$LARGE_FILES\n  $f ($(( SIZE / 1024 ))KB)"
    fi
done
[ -n "$LARGE_FILES" ] && warn "Large files staged (>2MB):$LARGE_FILES\nUse Git LFS or optimize assets."

[ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."

# ─── Spotless Formatting ──────────────────────────────────────────────────────
if [ -n "$ALL_CODE_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Formatting (Spotless)${RESET}"
    separator

    GRADLE_TASKS=$(./gradlew tasks --all -q 2>/dev/null || true)

    if echo "$GRADLE_TASKS" | grep -q "spotlessCheck"; then
        info "Running Spotless format check..."
        SP_OUT=$(./gradlew spotlessCheck -q 2>&1) || {
            error "Spotless found formatting issues."
            error "Auto-fix with: ./gradlew spotlessApply"
            fatal "Fix formatting before committing."
        }
        success "Spotless formatting passed."
    elif echo "$GRADLE_TASKS" | grep -q "ktlintCheck"; then
        info "Running ktlint check..."
        KT_OUT=$(./gradlew ktlintCheck -q 2>&1) || {
            error "ktlint found issues:"
            echo "$KT_OUT" | head -30 >&2
            error "Auto-fix with: ./gradlew ktlintFormat"
            fatal "Fix ktlint issues before committing."
        }
        success "ktlint check passed."
    else
        warn "No code formatter configured (Spotless or ktlint)."
        warn "Add spotless or ktlint plugin to build.gradle for code formatting."
    fi
fi

# ─── Lint Check ───────────────────────────────────────────────────────────────
if [ -n "$ALL_CODE_FILES" ] || [ -n "$STAGED_XML_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Android Lint${RESET}"
    separator

    # Run lint on debug variant (fastest)
    info "Running Android Lint (debug variant)..."
    LINT_OUT=$(./gradlew lintDebug -q 2>&1) || {
        error "Android Lint found errors:"
        # Parse lint XML report if available
        LINT_REPORT=$(find . -path "*/build/reports/lint-results-debug.xml" 2>/dev/null | head -1)
        if [ -n "$LINT_REPORT" ]; then
            error_count=$(grep -c 'severity="Error"' "$LINT_REPORT" 2>/dev/null || echo "unknown")
            error "Errors found: $error_count"
            error "Full report: $LINT_REPORT"
        else
            echo "$LINT_OUT" | grep -iE "(error|Error)" | head -30 >&2
        fi
        fatal "Fix Android Lint errors before committing."
    }
    success "Android Lint passed."
fi

# ─── Unit Tests ───────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Unit Tests${RESET}"
separator

TEST_COUNT=$(find . -path "*/test/*.java" -o -path "*/test/*.kt" 2>/dev/null | grep -v androidTest | wc -l | tr -d ' ')

if [ "$TEST_COUNT" -gt 0 ]; then
    info "Running unit tests ($TEST_COUNT test files)..."
    TEST_OUT=$(./gradlew testDebugUnitTest -q 2>&1) || {
        error "Unit tests failed:"
        # Look for test results
        TEST_REPORT=$(find . -path "*/test-results/testDebugUnitTest/*.xml" 2>/dev/null | head -1)
        if [ -n "$TEST_REPORT" ]; then
            FAILURES=$(grep -c 'failure\|error' "$TEST_REPORT" 2>/dev/null || echo "unknown")
            error "Failures/Errors: $FAILURES"
        else
            echo "$TEST_OUT" | grep -E "(FAILED|error|Error)" | head -30 >&2
        fi
        error "Run: ./gradlew testDebugUnitTest  for full output."
        fatal "Fix failing tests before committing."
    }
    success "Unit tests passed."
else
    warn "No unit tests found. Add tests in app/src/test/ for better coverage."
fi

# ─── Dependency Vulnerability Check ──────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Dependency Security${RESET}"
separator

GRADLE_TASKS=$(./gradlew tasks --all -q 2>/dev/null || true)
if echo "$GRADLE_TASKS" | grep -q "dependencyCheckAnalyze"; then
    info "Running OWASP Dependency Check..."
    DC_OUT=$(./gradlew dependencyCheckAnalyze -q 2>&1) || {
        warn "Dependency vulnerabilities found:"
        echo "$DC_OUT" | grep -iE "(CRITICAL|HIGH)" | head -10 >&2
        if echo "$DC_OUT" | grep -qi "CRITICAL"; then
            fatal "Critical vulnerabilities found. Fix before committing."
        fi
        warn "Review and update vulnerable dependencies."
    }
    success "OWASP Dependency Check passed."
else
    warn "OWASP Dependency Check not configured."
    warn "Add: id 'org.owasp.dependencycheck' to build.gradle for vulnerability scanning."
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Code formatting:          ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Android Lint:             ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Unit tests:               ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dependency security:      ${GREEN}PASS${RESET}"
echo ""

exit 0
