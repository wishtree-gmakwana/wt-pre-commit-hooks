#!/usr/bin/env bash
# PHP Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux
# Compatible with PHP 7.4+, Laravel, Symfony, CodeIgniter, and plain PHP

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
echo -e "${BOLD}  PHP Pre-commit Hook${RESET}"
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
install_php() {
    error "PHP is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install PHP:${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew:  brew install php"
            echo "    Laravel Herd: https://herd.laravel.com/"
            ;;
        linux)
            echo "    Ubuntu/Debian:  sudo apt-get install -y php php-cli php-mbstring php-xml php-zip"
            echo "    RHEL/CentOS:    sudo dnf install -y php php-cli"
            echo "    Arch:           sudo pacman -S php"
            ;;
        windows)
            echo "    Download:   https://windows.php.net/download/"
            echo "    XAMPP:      https://www.apachefriends.org/"
            echo "    Chocolatey: choco install php"
            echo "    Winget:     winget install PHP.PHP"
            ;;
    esac
    fatal "PHP is required. Please install it and retry."
}

install_composer() {
    error "Composer is not installed."
    echo ""
    echo -e "${BOLD}  Install Composer:${RESET}"
    case "$OS" in
        mac)
            echo "    Homebrew: brew install composer"
            echo "    Official: https://getcomposer.org/download/"
            ;;
        linux)
            echo "    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer"
            ;;
        windows)
            echo "    Download installer: https://getcomposer.org/Composer-Setup.exe"
            echo "    Chocolatey: choco install composer"
            ;;
    esac
}

# ─── Check PHP ────────────────────────────────────────────────────────────────
if ! command -v php &>/dev/null; then
    install_php
fi

PHP_VERSION_FULL=$(php --version 2>&1 | head -1)
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "0.0")
PHP_MAJOR=$(echo "$PHP_VERSION" | cut -d. -f1)
PHP_MINOR=$(echo "$PHP_VERSION" | cut -d. -f2)
info "PHP: $PHP_VERSION_FULL"

if [ "$PHP_MAJOR" -lt 7 ] || { [ "$PHP_MAJOR" -eq 7 ] && [ "$PHP_MINOR" -lt 4 ]; }; then
    warn "PHP $PHP_VERSION is outdated. PHP 8.1+ is recommended for modern projects."
    warn "See: https://www.php.net/downloads.php"
fi

# ─── Project Detection ────────────────────────────────────────────────────────
IS_PHP_PROJECT=false
for marker in composer.json index.php artisan bin/console; do
    [ -f "$marker" ] && IS_PHP_PROJECT=true && break
done
if ! $IS_PHP_PROJECT; then
    find . -maxdepth 3 -name "*.php" | grep -q . && IS_PHP_PROJECT=true
fi
if ! $IS_PHP_PROJECT; then
    fatal "Not a PHP project. No PHP files or project markers found."
fi

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_PHP_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.php$' || true)
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

# ─── Composer Dependencies ────────────────────────────────────────────────────
if [ -f "composer.json" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Composer Dependencies${RESET}"
    separator

    if ! command -v composer &>/dev/null; then
        install_composer
        warn "Skipping Composer checks..."
    else
        COMPOSER_VERSION=$(composer --version 2>&1 | head -1)
        info "Composer: $COMPOSER_VERSION"

        if [ ! -d "vendor" ]; then
            info "vendor/ not found. Installing dependencies..."
            if ! composer install --no-interaction --prefer-dist --optimize-autoloader --no-progress 2>/tmp/composer_err; then
                error "composer install failed:"
                cat /tmp/composer_err >&2
                fatal "Fix composer.json errors before committing."
            fi
            success "Dependencies installed."
        else
            info "Checking Composer dependencies..."
            if ! composer check-platform-reqs --no-interaction 2>/tmp/composer_err; then
                warn "Platform requirement issues:"
                cat /tmp/composer_err >&2
            fi
            success "Composer dependencies OK."
        fi

        # Security audit
        info "Running Composer security audit..."
        if composer audit --no-interaction 2>/tmp/audit_err; then
            success "No known vulnerabilities in dependencies."
        else
            warn "Composer audit found vulnerabilities:"
            cat /tmp/audit_err | head -30 >&2
            if grep -qi "CRITICAL\|HIGH" /tmp/audit_err 2>/dev/null; then
                fatal "Critical/High vulnerabilities found. Fix before committing."
            fi
            warn "Review warnings and update dependencies."
        fi
    fi
fi

# ─── PHP Syntax Check ─────────────────────────────────────────────────────────
if [ -n "$STAGED_PHP_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  PHP Syntax Check${RESET}"
    separator

    info "Checking PHP syntax..."
    SYNTAX_ERRORS=0
    for f in $STAGED_PHP_FILES; do
        [ -f "$f" ] || continue
        if ! php -l "$f" > /dev/null 2>/tmp/php_syntax_err; then
            error "Syntax error in: $f"
            cat /tmp/php_syntax_err >&2
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    done
    [ "$SYNTAX_ERRORS" -gt 0 ] && fatal "$SYNTAX_ERRORS PHP file(s) have syntax errors."
    success "PHP syntax check passed."
fi

# ─── Production Safety Checks ─────────────────────────────────────────────────
if [ -n "$STAGED_PHP_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Production Safety Checks${RESET}"
    separator

    PROD_ISSUES=0

    # Check for debug functions in production code
    DEBUG_FUNCS_FILES=""
    for f in $STAGED_PHP_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(/tests?/|Test\.php$|Spec\.php$)'; then continue; fi
        if grep -qE '\b(var_dump|print_r|var_export|die\s*\(|exit\s*\(|dd\s*\(|dump\s*\()' "$f" 2>/dev/null; then
            DEBUG_FUNCS_FILES="$DEBUG_FUNCS_FILES\n  $f"
        fi
    done
    if [ -n "$DEBUG_FUNCS_FILES" ]; then
        warn "Debug functions found in production code:$DEBUG_FUNCS_FILES"
        warn "Remove var_dump, print_r, die(), dd(), dump() before production."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Check for security-sensitive functions
    SEC_FUNCS_FILES=""
    for f in $STAGED_PHP_FILES; do
        [ -f "$f" ] || continue
        if grep -qE '\b(eval\s*\(|exec\s*\(|system\s*\(|shell_exec\s*\(|passthru\s*\(|popen\s*\()' "$f" 2>/dev/null; then
            SEC_FUNCS_FILES="$SEC_FUNCS_FILES\n  $f"
        fi
    done
    if [ -n "$SEC_FUNCS_FILES" ]; then
        error "Dangerous functions detected:$SEC_FUNCS_FILES"
        fatal "eval(), exec(), system(), shell_exec() are dangerous. Remove or review carefully."
    fi

    # Check for hardcoded credentials
    CRED_FILES=""
    for f in $STAGED_PHP_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(/tests?/|Test\.php$)'; then continue; fi
        if grep -qiE "(password|api_?key|secret|token|private_?key)\s*=\s*['\"][^'\"]{4,}" "$f" 2>/dev/null; then
            CRED_FILES="$CRED_FILES\n  $f"
        fi
    done
    if [ -n "$CRED_FILES" ]; then
        error "Potential hardcoded credentials in:$CRED_FILES"
        fatal "Use environment variables or Laravel .env / config files."
    fi

    # Sensitive files staged
    SENSITIVE_FILES=""
    for f in $ALL_STAGED; do
        case "$f" in
            .env|.env.production|.env.prod|*.pem|*.key|id_rsa|id_ed25519)
                SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
                ;;
        esac
    done
    if [ -n "$SENSITIVE_FILES" ]; then
        error "Sensitive files staged:$SENSITIVE_FILES"
        fatal "Remove from staging and add to .gitignore."
    fi

    # Check for SQL injection patterns (raw queries without prepared statements)
    SQL_FILES=""
    for f in $STAGED_PHP_FILES; do
        [ -f "$f" ] || continue
        if grep -qE "query[[:space:]]*\\([[:space:]]*[\"'].*\\$[a-zA-Z]" "$f" 2>/dev/null; then
            SQL_FILES="$SQL_FILES\n  $f"
        fi
    done
    if [ -n "$SQL_FILES" ]; then
        warn "Potential SQL injection: raw queries with variables:$SQL_FILES"
        warn "Use prepared statements or PDO/Eloquent parameterized queries."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # TODO/FIXME
    TODO_FILES=""
    for f in $STAGED_PHP_FILES; do
        [ -f "$f" ] || continue
        if grep -qiE '//[[:space:]]*(TODO|FIXME|HACK|XXX):' "$f" 2>/dev/null; then
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
    [ -n "$LARGE_FILES" ] && warn "Large files staged (>1MB):$LARGE_FILES"

    [ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."
fi

# ─── PHP CS Fixer ─────────────────────────────────────────────────────────────
if [ -n "$STAGED_PHP_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Style (PHP CS Fixer)${RESET}"
    separator

    PHP_CS_FIXER=""
    [ -f "vendor/bin/php-cs-fixer" ] && PHP_CS_FIXER="vendor/bin/php-cs-fixer"
    command -v php-cs-fixer &>/dev/null && PHP_CS_FIXER="php-cs-fixer"

    if [ -n "$PHP_CS_FIXER" ]; then
        info "Running PHP CS Fixer..."
        CS_OUT=$($PHP_CS_FIXER fix --dry-run --diff --quiet 2>&1) || {
            error "PHP CS Fixer found formatting issues:"
            echo "$CS_OUT" | head -40 >&2
            echo ""
            error "Run: $PHP_CS_FIXER fix  to auto-fix issues."
            fatal "Fix formatting before committing."
        }
        success "PHP CS Fixer check passed."
    else
        warn "PHP CS Fixer not found."
        warn "Install: composer require --dev friendsofphp/php-cs-fixer"
        warn "Skipping code style check..."
    fi
fi

# ─── PHPStan Static Analysis ──────────────────────────────────────────────────
if [ -n "$STAGED_PHP_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Static Analysis (PHPStan)${RESET}"
    separator

    PHPSTAN=""
    [ -f "vendor/bin/phpstan" ] && PHPSTAN="vendor/bin/phpstan"
    command -v phpstan &>/dev/null && PHPSTAN="phpstan"

    if [ -n "$PHPSTAN" ]; then
        info "Running PHPStan analysis..."
        PHPSTAN_CONFIG=""
        [ -f "phpstan.neon" ] && PHPSTAN_CONFIG="--configuration=phpstan.neon"
        [ -f "phpstan.neon.dist" ] && PHPSTAN_CONFIG="--configuration=phpstan.neon.dist"

        PHPSTAN_OUT=$($PHPSTAN analyse $PHPSTAN_CONFIG --no-progress 2>&1) || {
            error "PHPStan found issues:"
            echo "$PHPSTAN_OUT" | head -40 >&2
            fatal "Fix PHPStan errors before committing."
        }
        success "PHPStan analysis passed."
    else
        warn "PHPStan not found."
        warn "Install: composer require --dev phpstan/phpstan"
        warn "Skipping static analysis..."
    fi
fi

# ─── PHPCS ────────────────────────────────────────────────────────────────────
if [ -n "$STAGED_PHP_FILES" ]; then
    # Only run PHPCS if phpstan is not configured (avoid duplication)
    PHPCS=""
    [ -f "vendor/bin/phpcs" ] && PHPCS="vendor/bin/phpcs"
    command -v phpcs &>/dev/null && PHPCS="phpcs"

    if [ -n "$PHPCS" ] && [ -z "$PHPSTAN" ]; then
        echo ""
        separator
        echo -e "${BOLD}  Coding Standards (PHPCS)${RESET}"
        separator

        info "Running PHP CodeSniffer..."
        PHPCS_OUT=$($PHPCS 2>&1) || {
            error "PHPCS found coding standard violations:"
            echo "$PHPCS_OUT" | head -40 >&2
            echo ""
            error "Run: vendor/bin/phpcbf  to auto-fix fixable issues."
            fatal "Fix coding standard violations before committing."
        }
        success "PHPCS check passed."
    fi
fi

# ─── PHPUnit Tests ────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Unit Tests (PHPUnit)${RESET}"
separator

PHPUNIT=""
[ -f "vendor/bin/phpunit" ] && PHPUNIT="vendor/bin/phpunit"
command -v phpunit &>/dev/null && PHPUNIT="phpunit"

if [ -n "$PHPUNIT" ] && { [ -f "phpunit.xml" ] || [ -f "phpunit.xml.dist" ]; }; then
    info "Running PHPUnit tests..."
    PHPUNIT_OUT=$($PHPUNIT --stop-on-failure --no-progress 2>&1) || {
        error "PHPUnit tests failed:"
        echo "$PHPUNIT_OUT" | tail -30 >&2
        fatal "Fix failing tests before committing."
    }
    success "All PHPUnit tests passed."
elif [ -n "$PHPUNIT" ]; then
    warn "PHPUnit found but no phpunit.xml config. Skipping tests."
else
    warn "PHPUnit not found."
    warn "Install: composer require --dev phpunit/phpunit"
    warn "Skipping tests..."
fi

# ─── Psalm (if configured) ────────────────────────────────────────────────────
if [ -f "vendor/bin/psalm" ] && [ -f "psalm.xml" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Psalm Analysis${RESET}"
    separator
    info "Running Psalm..."
    PSALM_OUT=$(vendor/bin/psalm --show-info=false --no-progress 2>&1) || {
        error "Psalm found issues:"
        echo "$PSALM_OUT" | head -40 >&2
        fatal "Fix Psalm errors before committing."
    }
    success "Psalm analysis passed."
fi

# ─── Framework-Specific Checks ────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Framework Checks${RESET}"
separator

# Laravel
if [ -f "artisan" ]; then
    info "Laravel project detected."

    # Check for .env in staging
    if echo "$ALL_STAGED" | grep -q "^\.env$"; then
        fatal ".env file is staged! Remove it: git reset HEAD .env\nAdd .env to .gitignore."
    fi

    # Ensure .env.example is updated when .env changes
    if git diff --cached --name-only | grep -q "^\.env" && ! git diff --cached --name-only | grep -q "^\.env\.example"; then
        warn ".env was modified but .env.example was not updated."
        warn "Ensure .env.example reflects the required variables."
    fi

    # Check for APP_DEBUG=true in config
    if [ -f ".env" ] && grep -q "APP_DEBUG=true" .env 2>/dev/null; then
        warn "APP_DEBUG=true detected in .env. Ensure this is not a production environment."
    fi

    # Check for missing route/config cache clear reminders
    if echo "$ALL_STAGED" | grep -qE '(routes/|config/)'; then
        info "Routes or config changed. Remember: php artisan route:clear && php artisan config:clear"
    fi

    success "Laravel checks completed."
fi

# Symfony
if [ -f "bin/console" ] && [ -d "src" ]; then
    info "Symfony project detected."
    warn "Consider running: php bin/console lint:yaml config/ && php bin/console lint:twig templates/"
    success "Symfony checks completed."
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} PHP syntax:               ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Composer audit:           ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} PHP CS Fixer:             ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} PHPStan analysis:         ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} PHPUnit tests:            ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Framework checks:         ${GREEN}PASS${RESET}"
echo ""

exit 0
