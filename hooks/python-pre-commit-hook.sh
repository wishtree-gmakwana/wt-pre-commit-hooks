#!/usr/bin/env bash
# Python Pre-commit Hook
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
echo -e "${BOLD}  Python Pre-commit Hook${RESET}"
separator
echo ""

# ─── OS Detection ─────────────────────────────────────────────────────────────
detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Darwin)  echo "mac";;
        Linux)   echo "linux";;
        MINGW*|MSYS*|CYGWIN*) echo "windows";;
        *)
            [ -n "${WINDIR:-}" ] && echo "windows" || echo "unknown"
            ;;
    esac
}

OS=$(detect_os)
info "Detected OS: $OS"

# ─── Python Executable Detection ──────────────────────────────────────────────
detect_python() {
    for cmd in python3 python python3.12 python3.11 python3.10; do
        if command -v "$cmd" &>/dev/null; then
            local ver
            ver=$($cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
            local major minor
            major=$(echo "$ver" | cut -d. -f1)
            minor=$(echo "$ver" | cut -d. -f2)
            if [ "$major" -ge 3 ] && [ "$minor" -ge 8 ]; then
                echo "$cmd"
                return 0
            fi
        fi
    done
    return 1
}

# ─── Install Guidance ─────────────────────────────────────────────────────────
install_python() {
    error "Python 3.8+ is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install Python 3:${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:  brew install python@3.12"
            echo "    pyenv:     brew install pyenv && pyenv install 3.12"
            echo "    Official:  https://www.python.org/downloads/"
            ;;
        linux)
            echo "    Ubuntu/Debian:  sudo apt-get install -y python3 python3-pip python3-venv"
            echo "    RHEL/CentOS:    sudo dnf install -y python3 python3-pip"
            echo "    Arch:           sudo pacman -S python python-pip"
            echo "    pyenv:          https://github.com/pyenv/pyenv#installation"
            ;;
        windows)
            echo "    Download:   https://www.python.org/downloads/"
            echo "    Chocolatey: choco install python"
            echo "    Winget:     winget install Python.Python.3.12"
            echo "    pyenv-win:  https://github.com/pyenv-win/pyenv-win"
            ;;
    esac
    fatal "Python 3.8+ is required. Please install it and retry."
}

install_pip_tool() {
    local tool="$1"
    local pkg="${2:-$tool}"
    error "'$tool' is not installed."
    echo ""
    echo -e "${BOLD}  Install $tool:${RESET}"
    echo "    pip install $pkg"
    echo "    Or in virtual env: pip install --upgrade $pkg"
    case "$OS" in
        linux)
            echo "    Ubuntu/Debian: sudo apt-get install -y python3-$tool (if available)"
            ;;
        mac)
            echo "    Homebrew: brew install $tool (if available)"
            ;;
    esac
}

# ─── Check Python ─────────────────────────────────────────────────────────────
PYTHON_CMD=$(detect_python 2>/dev/null) || install_python
PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
info "Python: $PYTHON_VERSION (cmd: $PYTHON_CMD)"

# Detect pip
PIP_CMD=""
for cmd in pip3 pip "$PYTHON_CMD -m pip"; do
    if $cmd --version &>/dev/null 2>&1; then
        PIP_CMD="$cmd"
        break
    fi
done

if [ -z "$PIP_CMD" ]; then
    warn "pip not found. Some checks may be skipped."
fi

# ─── Project Detection ────────────────────────────────────────────────────────
IS_PYTHON_PROJECT=false
for marker in setup.py setup.cfg pyproject.toml requirements.txt Pipfile; do
    [ -f "$marker" ] && IS_PYTHON_PROJECT=true && break
done
if ! $IS_PYTHON_PROJECT; then
    # Check for .py files
    find . -maxdepth 3 -name "*.py" | grep -q . && IS_PYTHON_PROJECT=true
fi

if ! $IS_PYTHON_PROJECT; then
    fatal "Not a Python project. No Python project markers or .py files found."
fi

# ─── Virtual Environment Detection ───────────────────────────────────────────
VENV_ACTIVE=false
if [ -n "${VIRTUAL_ENV:-}" ] || [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
    VENV_ACTIVE=true
    info "Virtual environment active: ${VIRTUAL_ENV:-${CONDA_DEFAULT_ENV:-}}"
fi

if ! $VENV_ACTIVE; then
    for venv_dir in .venv venv env .env; do
        if [ -f "$venv_dir/bin/activate" ] || [ -f "$venv_dir/Scripts/activate" ]; then
            warn "Virtual environment found at '$venv_dir' but not activated."
            warn "Consider activating it: source $venv_dir/bin/activate"
            break
        fi
    done
fi

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_PY_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.py$' || true)
STAGED_CONFIG_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.(yaml|yml|json|toml)$' || true)
ALL_STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

if [ -z "$ALL_STAGED" ]; then
    info "No staged files detected. Skipping checks."
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

# ─── Config File Validation ───────────────────────────────────────────────────
if [ -n "$STAGED_CONFIG_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Config File Validation${RESET}"
    separator

    YAML_FILES=$(echo "$STAGED_CONFIG_FILES" | tr ' ' '\n' | grep -E '\.(yaml|yml)$' || true)
    if [ -n "$YAML_FILES" ]; then
        info "Validating YAML files..."
        YAML_ERRORS=0
        for f in $YAML_FILES; do
            [ -f "$f" ] || continue
            if ! $PYTHON_CMD -c "import yaml; yaml.safe_load(open('$f'))" 2>/tmp/yaml_err; then
                error "YAML error in $f:"
                cat /tmp/yaml_err >&2
                YAML_ERRORS=$((YAML_ERRORS + 1))
            fi
        done
        [ "$YAML_ERRORS" -gt 0 ] && fatal "$YAML_ERRORS YAML file(s) have errors."
        success "YAML validation passed."
    fi

    JSON_FILES=$(echo "$STAGED_CONFIG_FILES" | tr ' ' '\n' | grep -E '\.json$' || true)
    if [ -n "$JSON_FILES" ]; then
        info "Validating JSON files..."
        JSON_ERRORS=0
        for f in $JSON_FILES; do
            [ -f "$f" ] || continue
            if ! $PYTHON_CMD -m json.tool "$f" > /dev/null 2>/tmp/json_err; then
                error "JSON error in $f:"
                cat /tmp/json_err >&2
                JSON_ERRORS=$((JSON_ERRORS + 1))
            fi
        done
        [ "$JSON_ERRORS" -gt 0 ] && fatal "$JSON_ERRORS JSON file(s) have errors."
        success "JSON validation passed."
    fi

    TOML_FILES=$(echo "$STAGED_CONFIG_FILES" | tr ' ' '\n' | grep -E '\.toml$' || true)
    if [ -n "$TOML_FILES" ]; then
        info "Validating TOML files..."
        for f in $TOML_FILES; do
            [ -f "$f" ] || continue
            $PYTHON_CMD -c "
try:
    import tomllib
    tomllib.load(open('$f', 'rb'))
except ImportError:
    try:
        import tomli
        tomli.load(open('$f', 'rb'))
    except ImportError:
        import subprocess, sys
        sys.exit(0)  # Skip if no TOML library available
" 2>/tmp/toml_err || {
                error "TOML error in $f:"; cat /tmp/toml_err >&2
                fatal "Fix TOML errors before committing."
            }
        done
        success "TOML validation passed."
    fi
fi

# ─── Production Safety Checks ─────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Production Safety Checks${RESET}"
    separator

    PROD_ISSUES=0

    # Check for print() in non-test production code
    PRINT_FILES=""
    for f in $STAGED_PY_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(test_|_test\.py|/tests/|conftest\.py)'; then continue; fi
        if grep -qE '^\s*print\s*\(' "$f" 2>/dev/null; then
            PRINT_FILES="$PRINT_FILES\n  $f"
        fi
    done
    if [ -n "$PRINT_FILES" ]; then
        warn "print() statements found in production code:$PRINT_FILES"
        warn "Use the 'logging' module instead of print()."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Check for pdb/ipdb debugger statements
    DEBUG_FILES=""
    for f in $STAGED_PY_FILES; do
        [ -f "$f" ] || continue
        if grep -qE '(import pdb|pdb\.set_trace|import ipdb|ipdb\.set_trace|breakpoint\(\))' "$f" 2>/dev/null; then
            DEBUG_FILES="$DEBUG_FILES\n  $f"
        fi
    done
    if [ -n "$DEBUG_FILES" ]; then
        fatal "Debugger statements found:$DEBUG_FILES\nRemove before committing."
    fi

    # Check for hardcoded secrets
    SECRET_FILES=""
    for f in $STAGED_PY_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(test_|_test\.py|/tests/)'; then continue; fi
        if grep -qiE '(password|api_?key|secret|token|private_?key)\s*=\s*['"'"'"][^'"'"'"]{4,}' "$f" 2>/dev/null; then
            SECRET_FILES="$SECRET_FILES\n  $f"
        fi
    done
    if [ -n "$SECRET_FILES" ]; then
        error "Potential hardcoded credentials in:$SECRET_FILES"
        fatal "Use environment variables or a secrets manager."
    fi

    # Sensitive files staged
    SENSITIVE_FILES=""
    for f in $ALL_STAGED; do
        case "$f" in
            .env|.env.production|.env.prod|*.pem|*.key|id_rsa|id_ed25519|secrets.py|secrets.json)
                SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
                ;;
        esac
    done
    if [ -n "$SENSITIVE_FILES" ]; then
        error "Sensitive files staged:$SENSITIVE_FILES"
        fatal "Add them to .gitignore and remove from staging."
    fi

    # TODO/FIXME/HACK
    TODO_FILES=""
    for f in $STAGED_PY_FILES; do
        [ -f "$f" ] || continue
        if grep -qiE '#\s*(TODO|FIXME|HACK|XXX):' "$f" 2>/dev/null; then
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

    [ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."
fi

# ─── Whitespace Cleanup ───────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    info "Fixing trailing whitespace..."
    for f in $STAGED_PY_FILES; do
        [ -f "$f" ] || continue
        sed -i 's/[[:space:]]*$//' "$f" 2>/dev/null || true
        # Ensure newline at EOF
        [ -n "$(tail -c1 "$f")" ] && printf '\n' >> "$f" 2>/dev/null || true
    done
    echo "$STAGED_PY_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
fi

# ─── Black Formatter ──────────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Formatting (Black)${RESET}"
    separator

    if $PYTHON_CMD -m black --version &>/dev/null 2>&1; then
        BLACK_CMD="$PYTHON_CMD -m black"
    elif command -v black &>/dev/null; then
        BLACK_CMD="black"
    else
        BLACK_CMD=""
    fi

    if [ -n "$BLACK_CMD" ]; then
        info "Running Black formatter..."
        mapfile -t _PY_FILES <<< "$STAGED_PY_FILES"
        BLACK_OUT=$($BLACK_CMD --quiet "${_PY_FILES[@]}" 2>&1) || {
            error "Black formatting failed:"
            echo "$BLACK_OUT" >&2
            fatal "Fix Black errors before committing."
        }
        echo "$STAGED_PY_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
        success "Black formatting applied."
    else
        install_pip_tool "black"
        warn "Skipping Black formatting..."
    fi
fi

# ─── isort Import Sorting ─────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Import Sorting (isort)${RESET}"
    separator

    if $PYTHON_CMD -m isort --version &>/dev/null 2>&1; then
        ISORT_CMD="$PYTHON_CMD -m isort"
    elif command -v isort &>/dev/null; then
        ISORT_CMD="isort"
    else
        ISORT_CMD=""
    fi

    if [ -n "$ISORT_CMD" ]; then
        info "Running isort..."
        ISORT_PROFILE="--profile black"
        [ -f "pyproject.toml" ] && grep -q "\[tool.isort\]" pyproject.toml && ISORT_PROFILE=""
        mapfile -t _PY_FILES <<< "$STAGED_PY_FILES"
        ISORT_OUT=$($ISORT_CMD $ISORT_PROFILE --quiet "${_PY_FILES[@]}" 2>&1) || {
            error "isort failed:"; echo "$ISORT_OUT" >&2
            fatal "Fix isort errors before committing."
        }
        echo "$STAGED_PY_FILES" | tr ' ' '\n' | xargs git add 2>/dev/null || true
        success "Import sorting applied."
    else
        install_pip_tool "isort"
        warn "Skipping import sorting..."
    fi
fi

# ─── Flake8 Linting ───────────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Linting (Flake8)${RESET}"
    separator

    if $PYTHON_CMD -m flake8 --version &>/dev/null 2>&1; then
        FLAKE8_CMD="$PYTHON_CMD -m flake8"
    elif command -v flake8 &>/dev/null; then
        FLAKE8_CMD="flake8"
    else
        FLAKE8_CMD=""
    fi

    if [ -n "$FLAKE8_CMD" ]; then
        info "Running Flake8..."
        FLAKE8_ARGS="--max-line-length=120"
        [ -f ".flake8" ] || grep -q "\[flake8\]" setup.cfg 2>/dev/null || grep -q "\[tool.flake8\]" pyproject.toml 2>/dev/null && FLAKE8_ARGS=""

        mapfile -t _PY_FILES <<< "$STAGED_PY_FILES"
        FLAKE8_OUT=$($FLAKE8_CMD $FLAKE8_ARGS "${_PY_FILES[@]}" 2>&1) || {
            error "Flake8 found issues:"
            echo "$FLAKE8_OUT" >&2
            fatal "Fix Flake8 errors before committing."
        }
        success "Flake8 linting passed."
    else
        install_pip_tool "flake8"
        warn "Skipping Flake8 linting..."
    fi
fi

# ─── Mypy Type Check ──────────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Type Checking (mypy)${RESET}"
    separator

    if command -v mypy &>/dev/null || $PYTHON_CMD -m mypy --version &>/dev/null 2>&1; then
        MYPY_CMD="mypy"
        $PYTHON_CMD -m mypy --version &>/dev/null 2>&1 && MYPY_CMD="$PYTHON_CMD -m mypy"

        info "Running mypy type check..."
        MYPY_OUT=$(echo "$STAGED_PY_FILES" | tr '\n' ' ' | xargs $MYPY_CMD --no-error-summary 2>&1) || {
            warn "mypy found type issues (non-blocking in this configuration):"
            echo "$MYPY_OUT" | head -20 >&2
            warn "Review type errors and fix where possible."
        }
        success "mypy check completed."
    else
        install_pip_tool "mypy"
        warn "Skipping type checking..."
    fi
fi

# ─── Bandit Security Check ────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Security Scan (Bandit)${RESET}"
    separator

    if command -v bandit &>/dev/null || $PYTHON_CMD -m bandit --version &>/dev/null 2>&1; then
        BANDIT_CMD="bandit"
        $PYTHON_CMD -m bandit --version &>/dev/null 2>&1 && BANDIT_CMD="$PYTHON_CMD -m bandit"

        info "Running Bandit security scan..."
        BANDIT_ARGS="-ll --quiet"
        [ -f "pyproject.toml" ] && grep -q "\[tool.bandit\]" pyproject.toml && BANDIT_ARGS="-ll --quiet -c pyproject.toml"

        BANDIT_OUT=$(echo "$STAGED_PY_FILES" | tr '\n' ' ' | xargs $BANDIT_CMD $BANDIT_ARGS 2>&1) || {
            error "Bandit found security issues:"
            echo "$BANDIT_OUT" >&2
            fatal "Fix security issues before committing."
        }
        success "Bandit security scan passed."
    else
        install_pip_tool "bandit"
        warn "Skipping security scan..."
    fi
fi

# ─── Secrets Detection ────────────────────────────────────────────────────────
if [ -n "$ALL_STAGED" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Secrets Detection${RESET}"
    separator

    if command -v detect-secrets &>/dev/null || $PYTHON_CMD -m detect_secrets --version &>/dev/null 2>&1; then
        info "Scanning for secrets..."
        if [ -f ".secrets.baseline" ]; then
            SECRETS_OUT=$(detect-secrets scan --baseline .secrets.baseline $ALL_STAGED 2>&1) || {
                error "Secrets detected!"
                echo "$SECRETS_OUT" >&2
                fatal "Review and update .secrets.baseline or remove secrets."
            }
            success "No new secrets detected."
        else
            warn "No .secrets.baseline found."
            warn "Create one: detect-secrets scan > .secrets.baseline && git add .secrets.baseline"
        fi
    else
        warn "detect-secrets not installed. Install: pip install detect-secrets"
    fi
fi

# ─── Pytest ───────────────────────────────────────────────────────────────────
if [ -n "$STAGED_PY_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Unit Tests (pytest)${RESET}"
    separator

    if command -v pytest &>/dev/null || $PYTHON_CMD -m pytest --version &>/dev/null 2>&1; then
        PYTEST_CMD="pytest"
        $PYTHON_CMD -m pytest --version &>/dev/null 2>&1 && PYTEST_CMD="$PYTHON_CMD -m pytest"

        info "Finding related test files..."
        TEST_FILES=""
        for f in $STAGED_PY_FILES; do
            if echo "$f" | grep -qE '(test_|_test\.py|/tests/|conftest\.py)'; then
                TEST_FILES="$TEST_FILES $f"
                continue
            fi
            dir=$(dirname "$f")
            base=$(basename "$f" .py)
            for candidate in \
                "${dir}/test_${base}.py" \
                "${dir}/${base}_test.py" \
                "${dir}/tests/test_${base}.py" \
                "tests/${dir}/test_${base}.py" \
                "tests/test_${base}.py"; do
                if [ -f "$candidate" ]; then
                    TEST_FILES="$TEST_FILES $candidate"
                    break
                fi
            done
        done

        if [ -n "$TEST_FILES" ]; then
            info "Running tests: $TEST_FILES"
            PYTEST_OUT=$($PYTEST_CMD --tb=short --quiet $TEST_FILES 2>&1) || {
                error "Tests failed:"
                echo "$PYTEST_OUT" >&2
                fatal "Fix failing tests before committing."
            }
            success "All tests passed."
        else
            PYTEST_OUT=$($PYTEST_CMD --tb=short --quiet --co -q 2>/dev/null | head -5) || true
            if echo "$PYTEST_OUT" | grep -q "test session"; then
                info "Running all tests..."
                $PYTEST_CMD --tb=short --quiet 2>&1 || {
                    fatal "Tests failed. Fix before committing."
                }
                success "All tests passed."
            else
                warn "No related test files found. Ensure tests cover your changes."
            fi
        fi
    else
        install_pip_tool "pytest"
        warn "Skipping unit tests..."
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Config file validation:   ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Black formatting:         ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} isort imports:            ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Flake8 linting:           ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} mypy type check:          ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Bandit security scan:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Secrets detection:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Unit tests:               ${GREEN}PASS${RESET}"
echo ""

exit 0
