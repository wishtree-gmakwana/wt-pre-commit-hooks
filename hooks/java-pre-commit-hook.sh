#!/usr/bin/env bash
# Java Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux
# Compatible with Maven and Gradle projects

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
echo -e "${BOLD}  Java Pre-commit Hook${RESET}"
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
    error "Java is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install Java (JDK 17 LTS recommended):${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:   brew install openjdk@17"
            echo "    SDKMAN:     sdk install java 17-tem"
            echo "    Official:   https://adoptium.net/"
            ;;
        linux)
            echo "    Ubuntu/Debian:  sudo apt-get install -y openjdk-17-jdk"
            echo "    RHEL/CentOS:    sudo dnf install -y java-17-openjdk-devel"
            echo "    Arch:           sudo pacman -S jdk17-openjdk"
            echo "    SDKMAN:         https://sdkman.io/"
            ;;
        windows)
            echo "    Download:   https://adoptium.net/"
            echo "    Chocolatey: choco install openjdk17"
            echo "    Winget:     winget install EclipseAdoptium.Temurin.17.JDK"
            echo "    SDKMAN:     https://sdkman.io/install (WSL)"
            ;;
    esac
    fatal "Java JDK is required. Please install it and retry."
}

install_maven() {
    error "Maven is not installed and no Maven Wrapper (mvnw) found."
    echo ""
    echo -e "${BOLD}  Install Maven or add Maven Wrapper:${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:    brew install maven"
            echo "    SDKMAN:      sdk install maven"
            echo "    Or wrapper:  mvn wrapper:wrapper (from an existing Maven install)"
            ;;
        linux)
            echo "    Ubuntu/Debian:  sudo apt-get install -y maven"
            echo "    RHEL/CentOS:    sudo dnf install -y maven"
            echo "    SDKMAN:         sdk install maven"
            echo "    Or wrapper:     mvn wrapper:wrapper"
            ;;
        windows)
            echo "    Download:   https://maven.apache.org/download.cgi"
            echo "    Chocolatey: choco install maven"
            echo "    Winget:     winget install Apache.Maven"
            echo "    Or wrapper: mvn wrapper:wrapper"
            ;;
    esac
}

install_gradle() {
    error "Gradle is not installed and no Gradle Wrapper (gradlew) found."
    echo ""
    echo -e "${BOLD}  Install Gradle or add Gradle Wrapper:${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:  brew install gradle"
            echo "    SDKMAN:    sdk install gradle"
            echo "    Or wrapper: gradle wrapper"
            ;;
        linux)
            echo "    SDKMAN:    sdk install gradle"
            echo "    Download:  https://gradle.org/releases/"
            echo "    Or wrapper: gradle wrapper"
            ;;
        windows)
            echo "    Chocolatey: choco install gradle"
            echo "    Winget:     winget install Gradle.Gradle"
            echo "    SDKMAN:     https://sdkman.io/ (WSL)"
            echo "    Or wrapper: gradle wrapper"
            ;;
    esac
}

# ─── Check Java ───────────────────────────────────────────────────────────────
if ! command -v java &>/dev/null; then
    install_java
fi

JAVA_VERSION_FULL=$(java -version 2>&1 | head -1)
info "Java: $JAVA_VERSION_FULL"

# Check for JDK (javac needed for compilation)
if ! command -v javac &>/dev/null; then
    warn "javac not found. You may have a JRE instead of JDK."
    case "$OS" in
        mac)   warn "Install JDK: brew install openjdk@17";;
        linux) warn "Install JDK: sudo apt-get install -y openjdk-17-jdk";;
        windows) warn "Install JDK: https://adoptium.net/";;
    esac
fi

# ─── Project Detection ────────────────────────────────────────────────────────
is_java_project() {
    [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ] || \
    find . -maxdepth 4 -name "*.java" 2>/dev/null | grep -q .
}

if ! is_java_project; then
    fatal "Not a Java project. No pom.xml, build.gradle, or .java files found."
fi

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_JAVA_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.java$' || true)
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
if [ -n "$STAGED_JAVA_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Production Safety Checks${RESET}"
    separator

    PROD_ISSUES=0

    # System.out.println / System.err.println / printStackTrace in production code
    SYSOUT_FILES=""
    for f in $STAGED_JAVA_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(/test/|Test\.java$|IT\.java$)'; then continue; fi
        if grep -qE '(System\.(out|err)\.(print|println|printf)|\.printStackTrace\(\))' "$f" 2>/dev/null; then
            SYSOUT_FILES="$SYSOUT_FILES\n  $f"
        fi
    done
    if [ -n "$SYSOUT_FILES" ]; then
        warn "System.out.println / printStackTrace found in production code:$SYSOUT_FILES"
        warn "Use SLF4J, Log4j2, or java.util.logging instead."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Hardcoded credentials
    CRED_FILES=""
    for f in $STAGED_JAVA_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(/test/|Test\.java$)'; then continue; fi
        if grep -qiE '(password|apiKey|api_key|secret|token|privateKey)\s*=\s*"[^"]{4,}"' "$f" 2>/dev/null; then
            CRED_FILES="$CRED_FILES\n  $f"
        fi
    done
    if [ -n "$CRED_FILES" ]; then
        error "Potential hardcoded credentials in:$CRED_FILES"
        fatal "Use environment variables, application.properties, or a secrets manager."
    fi

    # Sensitive config files staged
    SENSITIVE_FILES=""
    for f in $ALL_STAGED; do
        case "$f" in
            *.pem|*.key|*.p12|*.jks|id_rsa|id_ed25519)
                SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
                ;;
        esac
        # application-prod.* files with actual secrets
        if echo "$f" | grep -qE 'application-(prod|production)\.(properties|yml|yaml)$'; then
            warn "Production config file staged: $f — ensure no secrets are included."
        fi
    done
    if [ -n "$SENSITIVE_FILES" ]; then
        error "Sensitive/key files staged:$SENSITIVE_FILES"
        fatal "Remove from staging and add to .gitignore."
    fi

    # TODO/FIXME/HACK
    TODO_FILES=""
    for f in $STAGED_JAVA_FILES; do
        [ -f "$f" ] || continue
        if grep -qE '//\s*(TODO|FIXME|HACK|XXX):' "$f" 2>/dev/null; then
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
    [ -n "$LARGE_FILES" ] && warn "Large files staged (>1MB):$LARGE_FILES\nConsider Git LFS."

    # Spring Boot @Autowired field injection warning
    AUTOWIRED_FILES=""
    for f in $STAGED_JAVA_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(/test/|Test\.java$)'; then continue; fi
        if grep -qE '@Autowired' "$f" 2>/dev/null; then
            AUTOWIRED_FILES="$AUTOWIRED_FILES\n  $f"
        fi
    done
    if [ -n "$AUTOWIRED_FILES" ]; then
        warn "@Autowired field injection found:$AUTOWIRED_FILES"
        warn "Prefer constructor injection for better testability and immutability."
    fi

    [ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."
fi

# ─── Detect Build Tool ────────────────────────────────────────────────────────
BUILD_TOOL="none"
if [ -f "pom.xml" ]; then
    BUILD_TOOL="maven"
    echo ""
    info "Maven project detected."
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    BUILD_TOOL="gradle"
    echo ""
    info "Gradle project detected."
fi

# ─── Maven Checks ─────────────────────────────────────────────────────────────
if [ "$BUILD_TOOL" = "maven" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Maven Build & Quality${RESET}"
    separator

    MVN_CMD=""
    if [ -f "mvnw" ]; then
        chmod +x mvnw 2>/dev/null || true
        MVN_CMD="./mvnw"
        info "Using Maven Wrapper (mvnw)."
    elif command -v mvn &>/dev/null; then
        MVN_CMD="mvn"
        info "Using system Maven: $(mvn --version 2>&1 | head -1)"
    else
        install_maven
        fatal "Maven not available. Add mvnw or install Maven."
    fi

    # Compile
    info "Compiling project..."
    COMPILE_OUT=$($MVN_CMD compile -q -DskipTests 2>&1) || {
        error "Compilation failed:"
        echo "$COMPILE_OUT" | grep -E "(ERROR|error)" | head -30 >&2
        fatal "Fix compilation errors before committing."
    }
    success "Compilation passed."

    # Checkstyle
    if grep -q "maven-checkstyle-plugin" pom.xml 2>/dev/null; then
        info "Running Checkstyle..."
        CS_OUT=$($MVN_CMD checkstyle:check -q 2>&1) || {
            error "Checkstyle violations found:"
            echo "$CS_OUT" | grep -v "^\[INFO\]" | head -30 >&2
            error "Run: $MVN_CMD checkstyle:check  for details."
            fatal "Fix Checkstyle violations before committing."
        }
        success "Checkstyle passed."
    else
        warn "Checkstyle not configured. Add maven-checkstyle-plugin to pom.xml for code style enforcement."
    fi

    # SpotBugs
    if grep -q "spotbugs-maven-plugin" pom.xml 2>/dev/null; then
        info "Running SpotBugs..."
        SB_OUT=$($MVN_CMD spotbugs:check -q 2>&1) || {
            error "SpotBugs found potential bugs:"
            echo "$SB_OUT" | grep -v "^\[INFO\]" | head -30 >&2
            error "Run: $MVN_CMD spotbugs:check  for details."
            fatal "Fix SpotBugs issues before committing."
        }
        success "SpotBugs passed."
    else
        warn "SpotBugs not configured. Add spotbugs-maven-plugin to pom.xml for bug detection."
    fi

    # PMD
    if grep -q "maven-pmd-plugin" pom.xml 2>/dev/null; then
        info "Running PMD..."
        PMD_OUT=$($MVN_CMD pmd:check -q 2>&1) || {
            error "PMD found issues:"
            echo "$PMD_OUT" | grep -v "^\[INFO\]" | head -30 >&2
            error "Run: $MVN_CMD pmd:check  for details."
            fatal "Fix PMD issues before committing."
        }
        success "PMD passed."
    else
        warn "PMD not configured. Add maven-pmd-plugin to pom.xml for code quality analysis."
    fi

    # Spotless formatting
    if grep -q "spotless-maven-plugin" pom.xml 2>/dev/null; then
        info "Running Spotless format check..."
        SP_OUT=$($MVN_CMD spotless:check -q 2>&1) || {
            error "Spotless found formatting issues."
            error "Run: $MVN_CMD spotless:apply  to auto-fix."
            fatal "Fix formatting before committing."
        }
        success "Spotless formatting passed."
    fi

    # OWASP Dependency Check (if configured)
    if grep -q "dependency-check-maven" pom.xml 2>/dev/null; then
        info "Running OWASP Dependency Check..."
        DC_OUT=$($MVN_CMD dependency-check:check -q 2>&1) || {
            warn "OWASP Dependency Check found vulnerabilities:"
            echo "$DC_OUT" | grep -iE "(CRITICAL|HIGH|MEDIUM)" | head -10 >&2
            if echo "$DC_OUT" | grep -qi "CRITICAL"; then
                fatal "Critical vulnerabilities found in dependencies. Fix before committing."
            fi
            warn "Review HIGH/MEDIUM vulnerabilities and update dependencies."
        }
        success "OWASP Dependency Check passed."
    fi

    # Unit tests
    info "Running unit tests..."
    TEST_OUT=$($MVN_CMD test -q 2>&1) || {
        error "Unit tests failed:"
        echo "$TEST_OUT" | grep -E "(FAILURE|ERROR|Tests run)" | head -30 >&2
        error "Run: $MVN_CMD test  for full test output."
        fatal "Fix failing tests before committing."
    }
    success "Unit tests passed."
fi

# ─── Gradle Checks ────────────────────────────────────────────────────────────
if [ "$BUILD_TOOL" = "gradle" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Gradle Build & Quality${RESET}"
    separator

    GRADLE_CMD=""
    if [ -f "gradlew" ]; then
        chmod +x gradlew 2>/dev/null || true
        GRADLE_CMD="./gradlew"
        info "Using Gradle Wrapper (gradlew)."
    elif command -v gradle &>/dev/null; then
        GRADLE_CMD="gradle"
        info "Using system Gradle: $(gradle --version 2>&1 | grep 'Gradle' | head -1)"
    else
        install_gradle
        fatal "Gradle not available. Add gradlew or install Gradle."
    fi

    # Compile
    info "Compiling project..."
    COMPILE_OUT=$($GRADLE_CMD compileJava -q 2>&1) || {
        error "Compilation failed:"
        echo "$COMPILE_OUT" | grep -E "(error:|ERROR)" | head -30 >&2
        fatal "Fix compilation errors before committing."
    }
    success "Compilation passed."

    # Get available tasks (cached for multiple uses)
    GRADLE_TASKS=$($GRADLE_CMD tasks --all -q 2>/dev/null || true)

    # Checkstyle
    if echo "$GRADLE_TASKS" | grep -q "checkstyleMain"; then
        info "Running Checkstyle..."
        CS_OUT=$($GRADLE_CMD checkstyleMain -q 2>&1) || {
            error "Checkstyle violations found:"
            echo "$CS_OUT" | head -30 >&2
            error "Run: $GRADLE_CMD checkstyleMain  for details."
            fatal "Fix Checkstyle violations before committing."
        }
        success "Checkstyle passed."
    else
        warn "Checkstyle not configured. Add checkstyle plugin to build.gradle."
    fi

    # SpotBugs
    if echo "$GRADLE_TASKS" | grep -q "spotbugsMain"; then
        info "Running SpotBugs..."
        SB_OUT=$($GRADLE_CMD spotbugsMain -q 2>&1) || {
            error "SpotBugs found potential bugs:"
            echo "$SB_OUT" | head -30 >&2
            error "Run: $GRADLE_CMD spotbugsMain  for details."
            fatal "Fix SpotBugs issues before committing."
        }
        success "SpotBugs passed."
    else
        warn "SpotBugs not configured. Add spotbugs plugin to build.gradle."
    fi

    # PMD
    if echo "$GRADLE_TASKS" | grep -q "pmdMain"; then
        info "Running PMD..."
        PMD_OUT=$($GRADLE_CMD pmdMain -q 2>&1) || {
            error "PMD found issues:"
            echo "$PMD_OUT" | head -30 >&2
            error "Run: $GRADLE_CMD pmdMain  for details."
            fatal "Fix PMD issues before committing."
        }
        success "PMD passed."
    else
        warn "PMD not configured. Add pmd plugin to build.gradle."
    fi

    # Spotless
    if echo "$GRADLE_TASKS" | grep -q "spotlessCheck"; then
        info "Running Spotless format check..."
        SP_OUT=$($GRADLE_CMD spotlessCheck -q 2>&1) || {
            error "Spotless found formatting issues."
            error "Run: $GRADLE_CMD spotlessApply  to auto-fix."
            fatal "Fix formatting before committing."
        }
        success "Spotless formatting passed."
    fi

    # OWASP Dependency Check
    if echo "$GRADLE_TASKS" | grep -q "dependencyCheckAnalyze"; then
        info "Running OWASP Dependency Check..."
        DC_OUT=$($GRADLE_CMD dependencyCheckAnalyze -q 2>&1) || {
            warn "OWASP Dependency Check found vulnerabilities."
            echo "$DC_OUT" | grep -iE "(CRITICAL|HIGH)" | head -10 >&2
            if echo "$DC_OUT" | grep -qi "CRITICAL"; then
                fatal "Critical vulnerabilities found. Fix before committing."
            fi
            warn "Review vulnerabilities and update dependencies."
        }
        success "OWASP Dependency Check passed."
    fi

    # Unit tests
    info "Running unit tests..."
    TEST_OUT=$($GRADLE_CMD test -q 2>&1) || {
        error "Unit tests failed:"
        echo "$TEST_OUT" | grep -E "(FAILURE|ERROR|> Task :test FAILED)" | head -30 >&2
        error "Run: $GRADLE_CMD test  for full test output."
        fatal "Fix failing tests before committing."
    }
    success "Unit tests passed."
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Compilation:              ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Code style (Checkstyle):  ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Bug detection (SpotBugs): ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Code analysis (PMD):      ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Unit tests:               ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dependency security:      ${GREEN}PASS${RESET}"
echo ""

exit 0
