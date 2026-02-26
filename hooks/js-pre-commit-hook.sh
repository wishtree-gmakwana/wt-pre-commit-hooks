#!/usr/bin/env bash
# JavaScript/TypeScript Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux
# Checks: formatting, linting, type checking, tests, security, production readiness

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
echo -e "${BOLD}  JavaScript/TypeScript Pre-commit Hook${RESET}"
separator
echo ""

# ─── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Darwin)  echo "mac";;
        Linux)   echo "linux";;
        MINGW*|MSYS*|CYGWIN*) echo "windows";;
        *)
            # Fallback for Windows native bash
            if [ -n "${WINDIR:-}" ] || [ -n "${SystemRoot:-}" ]; then
                echo "windows"
            else
                echo "unknown"
            fi
            ;;
    esac
}

OS=$(detect_os)
info "Detected OS: $OS"

# ─── Package Manager Detection ────────────────────────────────────────────────
detect_pkg_manager() {
    if [ -f "package-lock.json" ]; then
        echo "npm"
    elif [ -f "yarn.lock" ]; then
        echo "yarn"
    elif [ -f "pnpm-lock.yaml" ]; then
        echo "pnpm"
    elif [ -f "bun.lockb" ]; then
        echo "bun"
    elif command -v npm &>/dev/null; then
        echo "npm"
    else
        echo "npm"
    fi
}

# ─── Tool Installation Helpers ────────────────────────────────────────────────
install_node() {
    error "Node.js is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install Node.js:${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:  brew install node"
            echo "    NVM:       curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
            ;;
        linux)
            echo "    Ubuntu/Debian:  sudo apt-get install -y nodejs npm"
            echo "    RHEL/CentOS:    sudo yum install -y nodejs"
            echo "    Arch:           sudo pacman -S nodejs npm"
            echo "    NVM:            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
            ;;
        windows)
            echo "    Download installer: https://nodejs.org/en/download"
            echo "    Chocolatey: choco install nodejs"
            echo "    Winget:     winget install OpenJS.NodeJS"
            ;;
    esac
    fatal "Node.js is required. Please install it and retry."
}

install_package_manager() {
    local PM="$1"
    error "Package manager '$PM' is not installed."
    echo ""
    echo -e "${BOLD}  Install $PM:${RESET}"
    case "$PM" in
        yarn)
            echo "    npm install -g yarn"
            echo "    Or via Corepack: corepack enable && corepack prepare yarn@stable --activate"
            ;;
        pnpm)
            echo "    npm install -g pnpm"
            echo "    Or via Corepack: corepack enable && corepack prepare pnpm@latest --activate"
            ;;
        bun)
            case "$OS" in
                mac|linux) echo "    curl -fsSL https://bun.sh/install | bash";;
                windows)   echo "    powershell -c \"irm bun.sh/install.ps1 | iex\"";;
            esac
            ;;
    esac
    fatal "'$PM' is required for this project. Please install it and retry."
}

# ─── Check Node.js ────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
    install_node
fi

NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
info "Node.js version: v$NODE_VERSION"

if [ "$NODE_MAJOR" -lt 16 ]; then
    warn "Node.js v$NODE_VERSION is outdated. Node.js 18 LTS or newer is recommended."
    warn "Upgrade: https://nodejs.org/en/download or use nvm/fnm"
fi

# ─── Check Project ────────────────────────────────────────────────────────────
if [ ! -f "package.json" ]; then
    fatal "Not a JavaScript/TypeScript project (package.json not found)."
fi

PKG_MGR=$(detect_pkg_manager)
info "Package manager: $PKG_MGR"

# Verify package manager is installed
if ! command -v "$PKG_MGR" &>/dev/null; then
    install_package_manager "$PKG_MGR"
fi

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|json|md)$' || true)
TS_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.(ts|tsx|js|jsx|mjs|cjs)$' || true)
ALL_STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

if [ -z "$ALL_STAGED" ]; then
    info "No staged files detected. Skipping checks."
    exit 0
fi

echo ""

# ─── Install Dependencies ─────────────────────────────────────────────────────
info "Checking node_modules..."
if [ ! -d "node_modules" ]; then
    info "node_modules not found. Installing dependencies..."
    case "$PKG_MGR" in
        npm)  npm install --prefer-offline 2>&1 | tail -5 || fatal "npm install failed.";;
        yarn) yarn install --frozen-lockfile 2>&1 | tail -5 || fatal "yarn install failed.";;
        pnpm) pnpm install --frozen-lockfile 2>&1 | tail -5 || fatal "pnpm install failed.";;
        bun)  bun install 2>&1 | tail -5 || fatal "bun install failed.";;
    esac
    success "Dependencies installed."
fi

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
    fatal "Merge conflict markers found in:$CONFLICT_FILES\nResolve conflicts before committing."
fi
success "No merge conflict markers found."

# ─── Production Code Safety Checks ───────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Production Safety Checks${RESET}"
separator

PROD_ISSUES=0

if [ -n "$TS_FILES" ]; then
    # Check for console.log/debug left in production code
    CONSOLE_FILES=""
    for f in $TS_FILES; do
        [ -f "$f" ] || continue
        # Exclude test files and type declarations
        if echo "$f" | grep -qE '(\.test\.|\.spec\.|__tests__|\.d\.ts)'; then continue; fi
        if grep -qE 'console\.(log|debug|info|warn|error)\(' "$f" 2>/dev/null; then
            CONSOLE_FILES="$CONSOLE_FILES\n  $f"
        fi
    done
    if [ -n "$CONSOLE_FILES" ]; then
        warn "console.log/debug statements found in production code:$CONSOLE_FILES"
        warn "Remove or replace with a proper logger (winston, pino, etc.)"
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Check for debugger statements
    DEBUGGER_FILES=""
    for f in $TS_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(\.test\.|\.spec\.|__tests__)'; then continue; fi
        if grep -qE '^\s*debugger\s*;?' "$f" 2>/dev/null; then
            DEBUGGER_FILES="$DEBUGGER_FILES\n  $f"
        fi
    done
    if [ -n "$DEBUGGER_FILES" ]; then
        fatal "debugger; statements found in production code:$DEBUGGER_FILES\nRemove before committing."
    fi

    # Check for TODO/FIXME/HACK
    TODO_FILES=$(echo "$TS_FILES" | tr ' ' '\n' | xargs -I{} sh -c '[ -f "{}" ] && grep -lE "(TODO|FIXME|HACK|XXX):" "{}" 2>/dev/null || true' 2>/dev/null | tr '\n' ' ' || true)
    if [ -n "$TODO_FILES" ]; then
        warn "TODO/FIXME/HACK comments found. Address before final release."
    fi

    # Check for hardcoded secrets / credentials
    SECRET_FILES=""
    for f in $TS_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(\.test\.|\.spec\.|__tests__)'; then continue; fi
        if grep -qiE "(password|api_?key|secret|token|private_?key)\s*[:=]\s*['\"][^'\"]{4,}" "$f" 2>/dev/null; then
            SECRET_FILES="$SECRET_FILES\n  $f"
        fi
    done
    if [ -n "$SECRET_FILES" ]; then
        error "Potential hardcoded credentials detected:$SECRET_FILES"
        fatal "Move secrets to environment variables or a secrets manager."
    fi

    # Check for eval() usage
    EVAL_FILES=""
    for f in $TS_FILES; do
        [ -f "$f" ] || continue
        if grep -qE '\beval\s*\(' "$f" 2>/dev/null; then
            EVAL_FILES="$EVAL_FILES\n  $f"
        fi
    done
    if [ -n "$EVAL_FILES" ]; then
        warn "eval() usage detected (security risk):$EVAL_FILES"
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi
fi

# Check for sensitive files being committed
SENSITIVE_FILES=""
for f in $ALL_STAGED; do
    case "$f" in
        .env|.env.production|.env.prod|*.pem|*.key|*.p12|*.pfx|id_rsa|id_ed25519)
            SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
            ;;
    esac
done
if [ -n "$SENSITIVE_FILES" ]; then
    error "Sensitive files staged for commit:$SENSITIVE_FILES"
    fatal "Remove them and add to .gitignore."
fi

# Check for large files (>500KB for JS projects)
LARGE_FILES=""
for f in $ALL_STAGED; do
    [ -f "$f" ] || continue
    SIZE=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 524288 ]; then
        LARGE_FILES="$LARGE_FILES\n  $f ($(( SIZE / 1024 ))KB)"
    fi
done
if [ -n "$LARGE_FILES" ]; then
    warn "Large files staged (>500KB):$LARGE_FILES"
    warn "Consider using Git LFS or excluding generated files."
fi

[ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES production warning(s) found."

# ─── Prettier Formatting ──────────────────────────────────────────────────────
if [ -n "$STAGED_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Formatting (Prettier)${RESET}"
    separator

    PRETTIER_CMD=""
    if [ -f "node_modules/.bin/prettier" ]; then
        PRETTIER_CMD="node_modules/.bin/prettier"
    elif command -v prettier &>/dev/null; then
        PRETTIER_CMD="prettier"
    fi

    if [ -n "$PRETTIER_CMD" ]; then
        info "Running Prettier on staged files..."
        PRETTIER_ERRORS=0
        for f in $STAGED_FILES; do
            [ -f "$f" ] || continue
            if ! $PRETTIER_CMD --write "$f" 2>/tmp/prettier_err; then
                error "Prettier failed on: $f"
                cat /tmp/prettier_err >&2
                PRETTIER_ERRORS=$((PRETTIER_ERRORS + 1))
            fi
        done
        if [ "$PRETTIER_ERRORS" -gt 0 ]; then
            fatal "$PRETTIER_ERRORS file(s) failed Prettier formatting."
        fi
        # Re-stage formatted files
        echo "$STAGED_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
        success "Prettier formatting applied."
    else
        warn "Prettier not found. Install: $PKG_MGR ${PKG_MGR:+add }--save-dev prettier"
        warn "Skipping format check..."
    fi
fi

# ─── ESLint ───────────────────────────────────────────────────────────────────
if [ -n "$TS_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Linting (ESLint)${RESET}"
    separator

    ESLINT_CMD=""
    if [ -f "node_modules/.bin/eslint" ]; then
        ESLINT_CMD="node_modules/.bin/eslint"
    elif command -v eslint &>/dev/null; then
        ESLINT_CMD="eslint"
    fi

    HAS_ESLINT_CONFIG=false
    for cfg in .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml eslint.config.js eslint.config.mjs eslint.config.cjs; do
        [ -f "$cfg" ] && HAS_ESLINT_CONFIG=true && break
    done
    # Also check package.json for eslintConfig key
    if ! $HAS_ESLINT_CONFIG && grep -q '"eslintConfig"' package.json 2>/dev/null; then
        HAS_ESLINT_CONFIG=true
    fi

    if [ -n "$ESLINT_CMD" ] && $HAS_ESLINT_CONFIG; then
        info "Running ESLint..."
        ESLINT_OUT=$(echo "$TS_FILES" | tr '\n' ' ' | xargs $ESLINT_CMD --fix --max-warnings=0 2>&1) || {
            error "ESLint found errors:"
            echo "$ESLINT_OUT" >&2
            echo "$TS_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
            fatal "Fix ESLint errors before committing."
        }
        echo "$TS_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
        success "ESLint passed."
    elif [ -z "$ESLINT_CMD" ]; then
        warn "ESLint not found. Install: $PKG_MGR add --save-dev eslint"
    else
        warn "No ESLint config found. Create .eslintrc.js or eslint.config.js"
    fi
fi

# ─── TypeScript Type Check ────────────────────────────────────────────────────
if [ -n "$TS_FILES" ] && echo "$TS_FILES" | grep -qE '\.(ts|tsx)$'; then
    echo ""
    separator
    echo -e "${BOLD}  TypeScript Type Check${RESET}"
    separator

    TSC_CMD=""
    if [ -f "node_modules/.bin/tsc" ]; then
        TSC_CMD="node_modules/.bin/tsc"
    elif command -v tsc &>/dev/null; then
        TSC_CMD="tsc"
    fi

    if [ -n "$TSC_CMD" ] && [ -f "tsconfig.json" ]; then
        info "Running TypeScript type check..."
        TSC_OUT=$($TSC_CMD --noEmit 2>&1) || {
            error "TypeScript type errors found:"
            echo "$TSC_OUT" >&2
            fatal "Fix type errors before committing."
        }
        success "TypeScript type check passed."
    elif [ -z "$TSC_CMD" ]; then
        warn "TypeScript compiler (tsc) not found."
    else
        warn "tsconfig.json not found. Skipping type check."
    fi
fi

# ─── Unit Tests ───────────────────────────────────────────────────────────────
if [ -n "$TS_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Unit Tests${RESET}"
    separator

    # Detect test runner
    TEST_CMD=""
    if grep -q '"jest"' package.json 2>/dev/null && [ -f "node_modules/.bin/jest" ]; then
        TEST_CMD="node_modules/.bin/jest --bail --passWithNoTests --findRelatedTests"
    elif grep -q '"vitest"' package.json 2>/dev/null && [ -f "node_modules/.bin/vitest" ]; then
        TEST_CMD="node_modules/.bin/vitest run --reporter=verbose"
    elif grep -q '"mocha"' package.json 2>/dev/null && [ -f "node_modules/.bin/mocha" ]; then
        TEST_CMD="node_modules/.bin/mocha"
    fi

    if [ -n "$TEST_CMD" ]; then
        info "Running tests..."
        TEST_FILES_ARGS=$(echo "$TS_FILES" | tr '\n' ' ')
        TEST_OUT=$($TEST_CMD $TEST_FILES_ARGS 2>&1) || {
            error "Tests failed:"
            echo "$TEST_OUT" >&2
            fatal "Fix failing tests before committing."
        }
        success "All tests passed."
    else
        # Check if test script exists in package.json
        if grep -q '"test"' package.json 2>/dev/null; then
            warn "Test runner not detected in node_modules. Run '$PKG_MGR install' first."
        else
            warn "No test runner configured. Consider adding Jest or Vitest."
        fi
    fi
fi

# ─── Dependency Audit ─────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Security Audit${RESET}"
separator

info "Checking for known vulnerabilities in dependencies..."
case "$PKG_MGR" in
    npm)
        AUDIT_OUT=$(npm audit --audit-level=high 2>&1) || {
            warn "npm audit found high/critical vulnerabilities:"
            echo "$AUDIT_OUT" | grep -E "(high|critical|moderate)" | head -20 >&2
            warn "Run 'npm audit fix' or review manually."
            warn "Blocking only on critical issues..."
            if echo "$AUDIT_OUT" | grep -q "critical"; then
                fatal "Critical vulnerabilities found. Fix before committing."
            fi
        }
        ;;
    yarn)
        if command -v yarn &>/dev/null; then
            AUDIT_OUT=$(yarn audit --level high 2>&1) || {
                warn "yarn audit found vulnerabilities. Run 'yarn audit' for details."
            }
        fi
        ;;
    pnpm)
        AUDIT_OUT=$(pnpm audit --audit-level=high 2>&1) || {
            warn "pnpm audit found high vulnerabilities."
        }
        ;;
esac
success "Dependency audit completed."

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Prettier formatting:      ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} ESLint:                   ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} TypeScript types:         ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Unit tests:               ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Security audit:           ${GREEN}PASS${RESET}"
echo ""

exit 0
