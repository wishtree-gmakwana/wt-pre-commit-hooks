#!/usr/bin/env bash
#
# wt-pre-commit-hooks Setup Script
# Works on Linux, macOS, and Windows (Git Bash / WSL / MSYS2)
#
# Usage: bash setup.sh
#

set -e

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── Helper Functions ─────────────────────────────────────────────────────────

print_banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       ${BOLD}wt-pre-commit-hooks Setup Script${NC}${CYAN}                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
success() { echo -e "${GREEN}[OK]${NC}      $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
error()   { echo -e "${RED}[ERROR]${NC}   $1"; }

# ─── Detect OS ────────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Linux*)   OS="Linux"   ;;
        Darwin*)  OS="macOS"   ;;
        CYGWIN*|MINGW*|MSYS*) OS="Windows" ;;
        *)        OS="Unknown" ;;
    esac
    info "Detected OS: ${BOLD}${OS}${NC}"
}

# ─── Check if inside a Git repository ─────────────────────────────────────────

check_git_repo() {
    if ! command -v git &>/dev/null; then
        error "git is not installed. Please install git first."
        echo ""
        case "$OS" in
            Linux)   echo "  sudo apt install git   # Debian/Ubuntu"
                     echo "  sudo yum install git   # CentOS/RHEL"
                     echo "  sudo pacman -S git     # Arch" ;;
            macOS)   echo "  brew install git" ;;
            Windows) echo "  Download from https://git-scm.com/download/win" ;;
        esac
        exit 1
    fi
    success "git is installed."

    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        error "Not inside a git repository!"
        error "Please run this script from the root of your git project."
        exit 1
    fi

    GIT_ROOT=$(git rev-parse --show-toplevel)
    success "Git repository found at: ${BOLD}${GIT_ROOT}${NC}"
}

# ─── Check Python & pip ──────────────────────────────────────────────────────

check_python() {
    PYTHON_CMD=""
    if command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="python"
    fi

    if [ -z "$PYTHON_CMD" ]; then
        error "Python is not installed. Python is required to install pre-commit."
        echo ""
        case "$OS" in
            Linux)   echo "  sudo apt install python3 python3-pip   # Debian/Ubuntu"
                     echo "  sudo yum install python3 python3-pip   # CentOS/RHEL"
                     echo "  sudo pacman -S python python-pip       # Arch" ;;
            macOS)   echo "  brew install python3" ;;
            Windows) echo "  Download from https://www.python.org/downloads/"
                     echo "  Or: winget install Python.Python.3" ;;
        esac
        exit 1
    fi
    success "Python found: ${BOLD}$($PYTHON_CMD --version 2>&1)${NC}"
}

# ─── Check / Install pre-commit ──────────────────────────────────────────────

check_pre_commit() {
    if command -v pre-commit &>/dev/null; then
        success "pre-commit is already installed: ${BOLD}$(pre-commit --version 2>&1)${NC}"
        return
    fi

    warn "pre-commit is not installed."
    echo ""
    read -rp "$(echo -e "${YELLOW}  Do you want to install pre-commit now? (y/n): ${NC}")" INSTALL_PC

    if [[ "$INSTALL_PC" =~ ^[Yy]$ ]]; then
        info "Installing pre-commit..."

        PIP_CMD=""
        if command -v pip3 &>/dev/null; then
            PIP_CMD="pip3"
        elif command -v pip &>/dev/null; then
            PIP_CMD="pip"
        else
            error "pip is not installed. Cannot install pre-commit automatically."
            echo ""
            case "$OS" in
                Linux)   echo "  sudo apt install python3-pip   # Debian/Ubuntu" ;;
                macOS)   echo "  $PYTHON_CMD -m ensurepip --upgrade" ;;
                Windows) echo "  $PYTHON_CMD -m ensurepip --upgrade" ;;
            esac
            exit 1
        fi

        $PIP_CMD install pre-commit
        if command -v pre-commit &>/dev/null; then
            success "pre-commit installed successfully: ${BOLD}$(pre-commit --version 2>&1)${NC}"
        else
            error "pre-commit installation failed. Please install it manually:"
            echo "  pip install pre-commit"
            exit 1
        fi
    else
        error "pre-commit is required. Exiting."
        exit 1
    fi
}

# ─── Check if pre-commit hook is already set up ──────────────────────────────

check_existing_hook() {
    CONFIG_FILE="${GIT_ROOT}/.pre-commit-config.yaml"
    HOOK_FILE="${GIT_ROOT}/.git/hooks/pre-commit"

    HOOK_INSTALLED=false
    CONFIG_EXISTS=false

    if [ -f "$HOOK_FILE" ] && grep -q "pre-commit" "$HOOK_FILE" 2>/dev/null; then
        HOOK_INSTALLED=true
    fi

    if [ -f "$CONFIG_FILE" ]; then
        CONFIG_EXISTS=true
    fi

    if $HOOK_INSTALLED && $CONFIG_EXISTS; then
        success "Pre-commit hook is already set up!"
        echo ""
        info "Current .pre-commit-config.yaml:"
        echo -e "${CYAN}──────────────────────────────────────${NC}"
        cat "$CONFIG_FILE"
        echo -e "${CYAN}──────────────────────────────────────${NC}"
        echo ""
        read -rp "$(echo -e "${YELLOW}  Do you want to reconfigure? (y/n): ${NC}")" RECONFIGURE
        if [[ ! "$RECONFIGURE" =~ ^[Yy]$ ]]; then
            success "Setup complete. No changes made."
            exit 0
        fi
    elif $CONFIG_EXISTS; then
        warn ".pre-commit-config.yaml exists but hook is not installed."
        echo ""
        read -rp "$(echo -e "${YELLOW}  Do you want to reconfigure the config file? (y/n): ${NC}")" RECONFIGURE
        if [[ ! "$RECONFIGURE" =~ ^[Yy]$ ]]; then
            info "Keeping existing config. Installing the hook..."
            cd "$GIT_ROOT" && pre-commit install
            success "Pre-commit hook installed successfully!"
            exit 0
        fi
    fi
}

# ─── Language Selection ──────────────────────────────────────────────────────

select_languages() {
    echo ""
    echo -e "${BOLD}Available language hooks:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC}  Android (Java/Kotlin)      - Spotless formatting"
    echo -e "  ${CYAN}2)${NC}  .NET (C#)                  - Format, build, test, security"
    echo -e "  ${CYAN}3)${NC}  Flutter (Dart)             - Format, analyze, test"
    echo -e "  ${CYAN}4)${NC}  iOS (Swift)                - SwiftLint, SwiftFormat"
    echo -e "  ${CYAN}5)${NC}  JavaScript / TypeScript    - Prettier, ESLint"
    echo -e "  ${CYAN}6)${NC}  PHP                        - CS Fixer, PHPStan, PHPUnit"
    echo -e "  ${CYAN}7)${NC}  Python                     - Black, Flake8, Bandit, pytest"
    echo -e "  ${CYAN}8)${NC}  Ruby on Rails              - RuboCop, Brakeman, RSpec"
    echo ""
    echo -e "  ${BOLD}You can select multiple languages (comma-separated).${NC}"
    echo -e "  ${BOLD}Example: 5,7 for JavaScript + Python${NC}"
    echo ""
    read -rp "$(echo -e "${YELLOW}  Enter your choice(s): ${NC}")" LANGUAGE_INPUT

    if [ -z "$LANGUAGE_INPUT" ]; then
        error "No language selected. Exiting."
        exit 1
    fi

    # Parse selections into array
    IFS=',' read -ra SELECTIONS <<< "$LANGUAGE_INPUT"

    SELECTED_HOOKS=()
    for sel in "${SELECTIONS[@]}"; do
        sel=$(echo "$sel" | xargs) # trim whitespace
        case "$sel" in
            1) SELECTED_HOOKS+=("custom-android-script")  ;;
            2) SELECTED_HOOKS+=("custom-dot-net-script")   ;;
            3) SELECTED_HOOKS+=("custom-flutter-script")   ;;
            4) SELECTED_HOOKS+=("custom-ios-script")       ;;
            5) SELECTED_HOOKS+=("custom-js-script")        ;;
            6) SELECTED_HOOKS+=("custom-php-script")       ;;
            7) SELECTED_HOOKS+=("custom-python-script")    ;;
            8) SELECTED_HOOKS+=("custom-ror-script")       ;;
            *) warn "Invalid selection: '$sel' (skipped)"  ;;
        esac
    done

    if [ ${#SELECTED_HOOKS[@]} -eq 0 ]; then
        error "No valid languages selected. Exiting."
        exit 1
    fi

    # Map hook IDs to display names for confirmation
    echo ""
    info "You selected:"
    for hook in "${SELECTED_HOOKS[@]}"; do
        case "$hook" in
            custom-android-script)    echo -e "    - Android (Java/Kotlin)" ;;
            custom-dot-net-script)    echo -e "    - .NET (C#)" ;;
            custom-flutter-script)    echo -e "    - Flutter (Dart)" ;;
            custom-ios-script)        echo -e "    - iOS (Swift)" ;;
            custom-js-script)         echo -e "    - JavaScript / TypeScript" ;;
            custom-php-script)        echo -e "    - PHP" ;;
            custom-python-script)     echo -e "    - Python" ;;
            custom-ror-script)        echo -e "    - Ruby on Rails" ;;
        esac
    done
    echo ""
}

# ─── Generate .pre-commit-config.yaml ────────────────────────────────────────

generate_config() {
    CONFIG_FILE="${GIT_ROOT}/.pre-commit-config.yaml"

    # Backup existing config if present
    if [ -f "$CONFIG_FILE" ]; then
        BACKUP="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$CONFIG_FILE" "$BACKUP"
        warn "Existing config backed up to: ${BOLD}$(basename "$BACKUP")${NC}"
    fi

    info "Generating .pre-commit-config.yaml..."

    # Build the YAML content
    CONFIG_CONTENT="repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:"

    for hook in "${SELECTED_HOOKS[@]}"; do
        CONFIG_CONTENT="${CONFIG_CONTENT}
      - id: ${hook}"
    done

    echo "$CONFIG_CONTENT" > "$CONFIG_FILE"

    success "Config file created at: ${BOLD}${CONFIG_FILE}${NC}"
    echo ""
    echo -e "${CYAN}──────────────────────────────────────${NC}"
    cat "$CONFIG_FILE"
    echo -e "${CYAN}──────────────────────────────────────${NC}"
    echo ""
}

# ─── Install the pre-commit hook ──────────────────────────────────────────────

install_hook() {
    info "Installing pre-commit hook into .git/hooks..."
    cd "$GIT_ROOT"
    pre-commit install

    if [ $? -eq 0 ]; then
        success "Pre-commit hook installed successfully!"
    else
        error "Failed to install pre-commit hook."
        exit 1
    fi
}

# ─── Ask to run against all files ────────────────────────────────────────────

run_optional_check() {
    echo ""
    read -rp "$(echo -e "${YELLOW}  Run pre-commit on all existing files now? (y/n): ${NC}")" RUN_ALL

    if [[ "$RUN_ALL" =~ ^[Yy]$ ]]; then
        info "Running pre-commit on all files (this may take a while)..."
        echo ""
        cd "$GIT_ROOT"
        pre-commit run --all-files || true
        echo ""
    fi
}

# ─── Print language-specific requirements ─────────────────────────────────────

print_requirements() {
    echo ""
    echo -e "${BOLD}Language-specific tool requirements:${NC}"
    echo -e "${CYAN}──────────────────────────────────────${NC}"

    for hook in "${SELECTED_HOOKS[@]}"; do
        case "$hook" in
            custom-android-script)
                echo -e "${BOLD}  Android:${NC}"
                echo "    - Gradle wrapper (gradlew) in project root"
                echo "    - Spotless Gradle plugin configured"
                echo ""
                ;;
            custom-dot-net-script)
                echo -e "${BOLD}  .NET:${NC}"
                echo "    - .NET SDK 6+ (for built-in dotnet format)"
                echo ""
                ;;
            custom-flutter-script)
                echo -e "${BOLD}  Flutter:${NC}"
                echo "    - Flutter SDK installed"
                echo "    - pubspec.yaml in project root"
                echo ""
                ;;
            custom-ios-script)
                echo -e "${BOLD}  iOS:${NC}"
                echo "    - Mint package manager: brew install mint"
                echo "    - mint install realm/SwiftLint"
                echo "    - mint install nicklockwood/SwiftFormat"
                echo ""
                ;;
            custom-js-script)
                echo -e "${BOLD}  JavaScript/TypeScript:${NC}"
                echo "    - Node.js and npm"
                echo "    - npm install --save-dev prettier eslint"
                echo ""
                ;;
            custom-php-script)
                echo -e "${BOLD}  PHP:${NC}"
                echo "    - PHP 7.4+ and Composer"
                echo "    - composer require --dev friendsofphp/php-cs-fixer phpstan/phpstan squizlabs/php_codesniffer phpunit/phpunit vimeo/psalm"
                echo ""
                ;;
            custom-python-script)
                echo -e "${BOLD}  Python:${NC}"
                echo "    - Python 3.x"
                echo "    - pip install black isort flake8 mypy bandit detect-secrets pytest"
                echo ""
                ;;
            custom-ror-script)
                echo -e "${BOLD}  Ruby on Rails:${NC}"
                echo "    - Ruby 2.5+ and Bundler"
                echo "    - Add rubocop, brakeman, bundler-audit, erb_lint to Gemfile"
                echo ""
                ;;
        esac
    done
    echo -e "${CYAN}──────────────────────────────────────${NC}"
}

# ─── Summary ──────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  Setup Complete!                        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}What happens next:${NC}"
    echo "    - Every time you run 'git commit', the pre-commit hooks"
    echo "      will automatically check your staged files."
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo "    pre-commit run --all-files    # Run hooks on all files"
    echo "    pre-commit autoupdate         # Update hook versions"
    echo "    git commit --no-verify        # Skip hooks (use sparingly)"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    print_banner
    detect_os
    check_git_repo
    check_python
    check_pre_commit
    check_existing_hook
    select_languages
    generate_config
    install_hook
    run_optional_check
    print_requirements
    print_summary
}

main
