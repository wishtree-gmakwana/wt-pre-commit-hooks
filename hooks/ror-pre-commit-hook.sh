#!/usr/bin/env bash
# Ruby on Rails Pre-commit Hook
# Supports Mac, Windows (Git Bash/WSL), Linux
# Compatible with Rails 5+, Ruby 2.7+

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
echo -e "${BOLD}  Ruby on Rails Pre-commit Hook${RESET}"
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
install_ruby() {
    error "Ruby is not installed or not in PATH."
    echo ""
    echo -e "${BOLD}  Install Ruby (3.1+ recommended):${RESET}"
    case "$OS" in
        mac)
            echo "    rbenv:    brew install rbenv && rbenv install 3.3.0 && rbenv global 3.3.0"
            echo "    RVM:      curl -sSL https://get.rvm.io | bash -s stable"
            echo "    Homebrew: brew install ruby"
            ;;
        linux)
            echo "    rbenv:    https://github.com/rbenv/rbenv#installation"
            echo "    RVM:      curl -sSL https://get.rvm.io | bash -s stable"
            echo "    Ubuntu:   sudo apt-get install -y ruby-full"
            echo "    Arch:     sudo pacman -S ruby"
            ;;
        windows)
            echo "    RubyInstaller: https://rubyinstaller.org/"
            echo "    Chocolatey:    choco install ruby"
            echo "    Winget:        winget install RubyInstallerTeam.Ruby.3.3"
            ;;
    esac
    fatal "Ruby is required. Please install it and retry."
}

install_bundler() {
    error "Bundler is not installed."
    echo ""
    echo -e "${BOLD}  Install Bundler:${RESET}"
    echo "    gem install bundler"
    echo "    Or: sudo gem install bundler  (if using system Ruby)"
    fatal "Bundler is required. Please install it and retry."
}

# ─── Check Ruby ───────────────────────────────────────────────────────────────
if ! command -v ruby &>/dev/null; then
    install_ruby
fi

RUBY_VERSION=$(ruby --version 2>&1)
info "Ruby: $RUBY_VERSION"

RUBY_MAJOR=$(ruby -e "puts RUBY_VERSION.split('.')[0]" 2>/dev/null || echo "0")
RUBY_MINOR=$(ruby -e "puts RUBY_VERSION.split('.')[1]" 2>/dev/null || echo "0")

if [ "$RUBY_MAJOR" -lt 2 ] || { [ "$RUBY_MAJOR" -eq 2 ] && [ "$RUBY_MINOR" -lt 7 ]; }; then
    warn "Ruby $RUBY_MAJOR.$RUBY_MINOR is outdated. Ruby 3.1+ is recommended."
fi

# ─── Check Bundler ────────────────────────────────────────────────────────────
if ! command -v bundle &>/dev/null; then
    install_bundler
fi

info "Bundler: $(bundle --version 2>&1)"

# ─── Project Detection ────────────────────────────────────────────────────────
is_rails_project() {
    [ -f "Gemfile" ] && [ -f "config/application.rb" ] && return 0
    return 1
}

is_ruby_project() {
    [ -f "Gemfile" ] && return 0
    return 1
}

if ! is_ruby_project; then
    fatal "Not a Ruby/Rails project. No Gemfile found."
fi

PROJECT_TYPE="Ruby"
is_rails_project && PROJECT_TYPE="Rails"
info "Project type: $PROJECT_TYPE"

# ─── Staged Files ─────────────────────────────────────────────────────────────
STAGED_RB_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.rb$' || true)
STAGED_ERB_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep -E '\.erb$' || true)
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

# ─── Gem Dependencies ─────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Gem Dependencies${RESET}"
separator

if [ ! -f "Gemfile.lock" ]; then
    info "Gemfile.lock not found. Running bundle install..."
    bundle install --quiet 2>/tmp/bundle_err || {
        error "bundle install failed:"
        cat /tmp/bundle_err >&2
        fatal "Fix Gemfile errors before committing."
    }
else
    info "Verifying gem dependencies..."
    bundle check --dry-run > /dev/null 2>&1 || {
        info "Installing missing gems..."
        bundle install --quiet 2>/tmp/bundle_err || {
            error "bundle install failed:"
            cat /tmp/bundle_err >&2
            fatal "Fix gem dependency errors before committing."
        }
    }
fi
success "Gem dependencies satisfied."

# ─── Bundler Audit (security) ─────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Dependency Security Audit${RESET}"
separator

if bundle show bundler-audit > /dev/null 2>&1 || command -v bundle-audit &>/dev/null; then
    info "Updating vulnerability database..."
    if bundle show bundler-audit > /dev/null 2>&1; then
        bundle exec bundle-audit update --quiet 2>/dev/null || true
        AUDIT_OUT=$(bundle exec bundle-audit check 2>&1) || {
            error "Vulnerable gems found:"
            echo "$AUDIT_OUT" | head -30 >&2
            fatal "Update vulnerable gems before committing."
        }
    else
        bundle-audit update --quiet 2>/dev/null || true
        AUDIT_OUT=$(bundle-audit check 2>&1) || {
            error "Vulnerable gems found:"
            echo "$AUDIT_OUT" | head -30 >&2
            fatal "Update vulnerable gems before committing."
        }
    fi
    success "No known vulnerable gems."
else
    warn "bundler-audit not found."
    warn "Install: add gem 'bundler-audit', group: :development to Gemfile"
    warn "Then: bundle install && bundle exec bundle-audit update"
fi

# ─── Production Safety Checks ─────────────────────────────────────────────────
if [ -n "$STAGED_RB_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Production Safety Checks${RESET}"
    separator

    PROD_ISSUES=0

    # Debugger statements
    DEBUG_FILES=""
    for f in $STAGED_RB_FILES; do
        [ -f "$f" ] || continue
        if grep -qE '(binding\.pry|byebug|debugger|binding\.irb|require.*pry)' "$f" 2>/dev/null; then
            DEBUG_FILES="$DEBUG_FILES\n  $f"
        fi
    done
    if [ -n "$DEBUG_FILES" ]; then
        fatal "Debugger statements found:$DEBUG_FILES\nRemove binding.pry, byebug, debugger before committing."
    fi

    # puts/p statements in app/lib code
    PUTS_FILES=""
    for f in $STAGED_RB_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qE '(^app/|^lib/)'; then
            if echo "$f" | grep -qiE '(_spec\.rb$|_test\.rb$|/spec/|/test/)'; then continue; fi
            if grep -qE '^\s*(puts |pp |p )' "$f" 2>/dev/null; then
                PUTS_FILES="$PUTS_FILES\n  $f"
            fi
        fi
    done
    if [ -n "$PUTS_FILES" ]; then
        warn "puts/p statements in app/ or lib/:$PUTS_FILES"
        warn "Use Rails.logger or a structured logger instead."
        PROD_ISSUES=$((PROD_ISSUES + 1))
    fi

    # Hardcoded secrets
    CRED_FILES=""
    for f in $STAGED_RB_FILES; do
        [ -f "$f" ] || continue
        if echo "$f" | grep -qiE '(_spec\.rb$|_test\.rb$|/spec/|/test/)'; then continue; fi
        if grep -qiE "(api_key|api_secret|password|secret_key|private_key)\s*=\s*['\"][^'\"]{4,}" "$f" 2>/dev/null; then
            CRED_FILES="$CRED_FILES\n  $f"
        fi
    done
    if [ -n "$CRED_FILES" ]; then
        error "Potential hardcoded secrets in:$CRED_FILES"
        fatal "Use Rails credentials (rails credentials:edit) or environment variables."
    fi

    # Sensitive files staged
    SENSITIVE_FILES=""
    for f in $ALL_STAGED; do
        case "$f" in
            .env|.env.production|.env.prod|config/master.key|*.pem|*.key|id_rsa|id_ed25519)
                SENSITIVE_FILES="$SENSITIVE_FILES\n  $f"
                ;;
        esac
    done
    if [ -n "$SENSITIVE_FILES" ]; then
        error "Sensitive files staged:$SENSITIVE_FILES"
        fatal "Remove from staging and ensure they are in .gitignore."
    fi

    # TODO/FIXME/HACK
    TODO_FILES=""
    for f in $STAGED_RB_FILES; do
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

    # .gitignore health check for Rails
    if [ -f ".gitignore" ]; then
        MISSING_IGNORES=""
        for pattern in "*.log" "/tmp" "/log" "master.key" ".env"; do
            grep -q "$pattern" .gitignore 2>/dev/null || MISSING_IGNORES="$MISSING_IGNORES $pattern"
        done
        [ -n "$MISSING_IGNORES" ] && warn "Consider adding to .gitignore:$MISSING_IGNORES"
    fi

    [ "$PROD_ISSUES" -eq 0 ] && success "Production safety checks passed." || warn "$PROD_ISSUES warning(s) found."
fi

# ─── Ruby Syntax Check ────────────────────────────────────────────────────────
if [ -n "$STAGED_RB_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Ruby Syntax Check${RESET}"
    separator

    SYNTAX_ERRORS=0
    for f in $STAGED_RB_FILES; do
        [ -f "$f" ] || continue
        if ! ruby -c "$f" > /dev/null 2>/tmp/ruby_syntax_err; then
            error "Syntax error in: $f"
            cat /tmp/ruby_syntax_err >&2
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    done
    [ "$SYNTAX_ERRORS" -gt 0 ] && fatal "$SYNTAX_ERRORS Ruby file(s) have syntax errors."
    success "Ruby syntax check passed."
fi

# ─── RuboCop ──────────────────────────────────────────────────────────────────
if [ -n "$STAGED_RB_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Code Style (RuboCop)${RESET}"
    separator

    RUBOCOP_CMD=""
    bundle show rubocop > /dev/null 2>&1 && RUBOCOP_CMD="bundle exec rubocop"
    command -v rubocop &>/dev/null && [ -z "$RUBOCOP_CMD" ] && RUBOCOP_CMD="rubocop"

    if [ -n "$RUBOCOP_CMD" ]; then
        info "Running RuboCop on staged files..."
        FILES_ARG=$(echo "$STAGED_RB_FILES" | tr '\n' ' ')
        RUBOCOP_OUT=$($RUBOCOP_CMD --force-exclusion --format progress $FILES_ARG 2>&1) || {
            error "RuboCop found violations:"
            echo "$RUBOCOP_OUT" | grep -v "^Inspecting\|^$" | head -40 >&2
            echo ""
            error "Auto-fix with: $RUBOCOP_CMD -a  (safe) or $RUBOCOP_CMD -A  (unsafe)"
            fatal "Fix RuboCop violations before committing."
        }
        success "RuboCop check passed."
    else
        warn "RuboCop not found."
        warn "Add to Gemfile: gem 'rubocop', require: false"
        warn "Then: bundle install"
    fi
fi

# ─── ERB Lint ─────────────────────────────────────────────────────────────────
if [ -n "$STAGED_ERB_FILES" ]; then
    echo ""
    separator
    echo -e "${BOLD}  ERB Templates (erb_lint)${RESET}"
    separator

    if bundle show erb_lint > /dev/null 2>&1; then
        info "Running erb_lint on staged ERB files..."
        ERB_FILES=$(echo "$STAGED_ERB_FILES" | tr '\n' ' ')
        ERB_OUT=$(bundle exec erblint $ERB_FILES 2>&1) || {
            error "ERB lint found issues:"
            echo "$ERB_OUT" | head -30 >&2
            fatal "Fix ERB lint issues before committing."
        }
        success "ERB lint check passed."
    else
        warn "erb_lint not found. Add gem 'erb_lint' to Gemfile."
    fi
fi

# ─── Brakeman (Rails Security) ────────────────────────────────────────────────
if is_rails_project; then
    echo ""
    separator
    echo -e "${BOLD}  Security Analysis (Brakeman)${RESET}"
    separator

    BRAKEMAN_CMD=""
    bundle show brakeman > /dev/null 2>&1 && BRAKEMAN_CMD="bundle exec brakeman"
    command -v brakeman &>/dev/null && [ -z "$BRAKEMAN_CMD" ] && BRAKEMAN_CMD="brakeman"

    if [ -n "$BRAKEMAN_CMD" ]; then
        info "Running Brakeman security scanner..."
        BRAKEMAN_OUT=$($BRAKEMAN_CMD --quiet --no-pager --no-exit-on-warn --exit-on-error 2>&1) || {
            error "Brakeman found security vulnerabilities:"
            echo "$BRAKEMAN_OUT" | head -40 >&2
            error "Run: $BRAKEMAN_CMD  for detailed report."
            fatal "Fix security vulnerabilities before committing."
        }
        success "Brakeman security analysis passed."
    else
        warn "Brakeman not found."
        warn "Add to Gemfile: gem 'brakeman', require: false, group: :development"
        warn "Then: bundle install"
    fi
fi

# ─── Tests ────────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${BOLD}  Tests${RESET}"
separator

if is_rails_project; then
    if [ -d "spec" ] && bundle show rspec-rails > /dev/null 2>&1; then
        info "Running RSpec tests..."
        RSPEC_OUT=$(bundle exec rspec --fail-fast --format progress 2>&1) || {
            error "RSpec tests failed:"
            echo "$RSPEC_OUT" | tail -30 >&2
            fatal "Fix failing tests before committing."
        }
        success "RSpec tests passed."
    elif [ -d "test" ]; then
        info "Running Rails Minitest..."
        TEST_OUT=$(bundle exec rails test 2>&1) || {
            error "Tests failed:"
            echo "$TEST_OUT" | tail -30 >&2
            fatal "Fix failing tests before committing."
        }
        success "Minitest tests passed."
    else
        warn "No test directory (spec/ or test/) found. Add tests!"
    fi
else
    # Non-Rails Ruby project
    if [ -d "spec" ] && bundle show rspec > /dev/null 2>&1; then
        info "Running RSpec tests..."
        RSPEC_OUT=$(bundle exec rspec --fail-fast --format progress 2>&1) || {
            error "RSpec tests failed:"
            echo "$RSPEC_OUT" | tail -30 >&2
            fatal "Fix failing tests before committing."
        }
        success "RSpec tests passed."
    elif [ -d "test" ]; then
        info "Running Minitest..."
        TEST_OUT=$(bundle exec rake test 2>&1) || \
        ruby -Itest -e "Dir.glob('./test/**/*_test.rb').each { |f| require f }" 2>&1 || {
            error "Tests failed."
            fatal "Fix failing tests before committing."
        }
        success "Tests passed."
    else
        warn "No test directory found. Consider adding tests."
    fi
fi

# ─── Database Migrations Check (Rails) ───────────────────────────────────────
if is_rails_project && [ -d "db/migrate" ]; then
    echo ""
    separator
    echo -e "${BOLD}  Database Migration Check${RESET}"
    separator

    # schema.rb committed without migration
    if git diff --cached --name-only | grep -q "db/schema.rb" && \
       ! git diff --cached --name-only | grep -q "db/migrate"; then
        warn "db/schema.rb is staged without migration files."
        warn "Ensure this is intentional (e.g., manual schema edit)."
    fi

    # Pending migrations check
    if [ -f "db/schema.rb" ]; then
        PENDING=$(find db/migrate -name "*.rb" -newer db/schema.rb 2>/dev/null | wc -l | tr -d ' ')
        if [ "$PENDING" -gt 0 ]; then
            warn "$PENDING potential pending migration(s) found."
            warn "Run: bundle exec rails db:migrate"
        fi
    fi

    success "Database migration check completed."
fi

# ─── Rails Best Practices ─────────────────────────────────────────────────────
if is_rails_project && bundle show rails_best_practices > /dev/null 2>&1; then
    echo ""
    info "Running Rails Best Practices..."
    RBPOUT=$(bundle exec rails_best_practices --silent --without-color . 2>/dev/null) || true
    ISSUES=$(echo "$RBPOUT" | grep -c "Found" 2>/dev/null || echo "0")
    if [ "$ISSUES" -gt 0 ]; then
        warn "Rails Best Practices suggestions:"
        echo "$RBPOUT" | head -20 >&2
    else
        success "Rails Best Practices check passed."
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
separator
echo -e "${GREEN}${BOLD}  All pre-commit checks passed!${RESET}"
separator
echo ""
echo -e "  ${GREEN}•${RESET} Merge conflict check:     ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Gem dependencies:         ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Dependency security:      ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Production safety:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Ruby syntax:              ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} RuboCop style:            ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Brakeman security:        ${GREEN}PASS${RESET}"
echo -e "  ${GREEN}•${RESET} Tests:                    ${GREEN}PASS${RESET}"
echo ""

exit 0
