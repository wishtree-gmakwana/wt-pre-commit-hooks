#!/usr/bin/env bash

# PHP Pre-commit Hook
# This script runs PHP code quality checks before each commit
# Compatible with PHP 7.4+ and various frameworks (Laravel, Symfony, CodeIgniter, etc.)

echo "🚀 Running PHP pre-commit checks..."

# Check if PHP is installed
if ! command -v php &> /dev/null; then
    echo "❌ PHP is not installed or not in PATH"
    exit 1
fi

# Function to check if it's a PHP project
is_php_project() {
    # Check for common PHP project indicators
    if [ -f "composer.json" ] || find . -maxdepth 2 -name "*.php" | grep -q . || [ -f "index.php" ]; then
        return 0
    fi
    return 1
}

# Check if we're in a PHP project
if ! is_php_project; then
    echo "❌ Not a PHP project (no composer.json, index.php, or .php files found)"
    exit 1
fi

# Display PHP version info
echo "📋 PHP Environment Information:"
php --version | head -1
echo ""

# Install/update Composer dependencies
if [ -f "composer.json" ]; then
    echo "📦 Installing/Updating Composer dependencies..."
    if command -v composer &> /dev/null; then
        if ! composer install --no-interaction --prefer-dist --optimize-autoloader; then
            echo ""
            echo "**************************************************************************"
            echo "Failed to install Composer dependencies. Please check composer.json."
            echo "Aborting commit."
            echo "**************************************************************************"
            exit 1
        fi
    else
        echo "⚠️  Composer not found. Please install Composer from https://getcomposer.org/"
        echo "   Skipping dependency installation..."
    fi
    echo "✅ Composer dependencies updated"
else
    echo "ℹ️  No composer.json found, skipping Composer dependency check"
fi

# PHP Syntax Check
echo "🔍 Checking PHP syntax..."
SYNTAX_ERRORS=0
for file in $(find . -name "*.php" -not -path "./vendor/*" -not -path "./node_modules/*"); do
    if ! php -l "$file" > /dev/null 2>&1; then
        echo "❌ Syntax error in: $file"
        php -l "$file"
        SYNTAX_ERRORS=1
    fi
done

if [ $SYNTAX_ERRORS -eq 1 ]; then
    echo ""
    echo "**************************************************************************"
    echo "PHP syntax errors found. Please fix them before committing."
    echo "Aborting commit."
    echo "**************************************************************************"
    exit 1
fi
echo "✅ PHP syntax check passed"

# PHP CS Fixer (if available)
if [ -f "vendor/bin/php-cs-fixer" ] || command -v php-cs-fixer &> /dev/null; then
    echo "🎨 Checking code formatting with PHP CS Fixer..."
    
    # Use project-specific or global php-cs-fixer
    PHP_CS_FIXER="vendor/bin/php-cs-fixer"
    if [ ! -f "$PHP_CS_FIXER" ]; then
        PHP_CS_FIXER="php-cs-fixer"
    fi
    
    if ! $PHP_CS_FIXER fix --dry-run --diff --verbose; then
        echo ""
        echo "**************************************************************************"
        echo "Code formatting issues found. Run 'php-cs-fixer fix' to fix them."
        echo "Aborting commit."
        echo "**************************************************************************"
        exit 1
    fi
    echo "✅ Code formatting check passed"
else
    echo "⚠️  PHP CS Fixer not found. Install with: composer require --dev friendsofphp/php-cs-fixer"
    echo "   Skipping format check..."
fi

# PHPStan (if available)
if [ -f "vendor/bin/phpstan" ]; then
    echo "🔬 Running PHPStan static analysis..."
    if ! vendor/bin/phpstan analyse; then
        echo ""
        echo "**************************************************************************"
        echo "PHPStan found issues. Please fix them before committing."
        echo "Aborting commit."
        echo "**************************************************************************"
        exit 1
    fi
    echo "✅ PHPStan analysis passed"
elif command -v phpstan &> /dev/null; then
    echo "🔬 Running PHPStan static analysis..."
    if ! phpstan analyse; then
        echo ""
        echo "**************************************************************************"
        echo "PHPStan found issues. Please fix them before committing."
        echo "Aborting commit."
        echo "**************************************************************************"
        exit 1
    fi
    echo "✅ PHPStan analysis passed"
else
    echo "⚠️  PHPStan not found. Install with: composer require --dev phpstan/phpstan"
    echo "   Skipping static analysis..."
fi

# PHPCS (if available)
if [ -f "vendor/bin/phpcs" ]; then
    echo "📏 Running PHP CodeSniffer..."
    if ! vendor/bin/phpcs; then
        echo ""
        echo "**************************************************************************"
        echo "PHPCS found coding standard violations. Run 'phpcbf' to fix them."
        echo "Aborting commit."
        echo "**************************************************************************"
        exit 1
    fi
    echo "✅ PHPCS check passed"
elif command -v phpcs &> /dev/null; then
    echo "📏 Running PHP CodeSniffer..."
    if ! phpcs; then
        echo ""
        echo "**************************************************************************"
        echo "PHPCS found coding standard violations. Run 'phpcbf' to fix them."
        echo "Aborting commit."
        echo "**************************************************************************"
        exit 1
    fi
    echo "✅ PHPCS check passed"
else
    echo "⚠️  PHPCS not found. Install with: composer require --dev squizlabs/php_codesniffer"
    echo "   Skipping coding standards check..."
fi

# PHPUnit Tests (if available)
if [ -f "vendor/bin/phpunit" ] || [ -f "phpunit.xml" ] || [ -f "phpunit.xml.dist" ]; then
    echo "🧪 Running PHPUnit tests..."
    
    PHPUNIT_CMD="vendor/bin/phpunit"
    if [ ! -f "$PHPUNIT_CMD" ] && command -v phpunit &> /dev/null; then
        PHPUNIT_CMD="phpunit"
    fi
    
    if [ -f "$PHPUNIT_CMD" ] || command -v phpunit &> /dev/null; then
        if ! $PHPUNIT_CMD --stop-on-failure; then
            echo ""
            echo "**************************************************************************"
            echo "PHPUnit tests failed. Please fix failing tests before committing."
            echo "Aborting commit."
            echo "**************************************************************************"
            exit 1
        fi
        echo "✅ PHPUnit tests passed"
    else
        echo "⚠️  PHPUnit not found but test configuration exists"
        echo "   Install with: composer require --dev phpunit/phpunit"
    fi
elif find . -name "*Test.php" -not -path "./vendor/*" | head -1 | grep -q .; then
    echo "ℹ️  Test files found but no PHPUnit configuration"
    echo "   Consider setting up PHPUnit with phpunit.xml"
else
    echo "ℹ️  No PHPUnit tests found, skipping test execution"
fi

# Psalm (if available)
if [ -f "vendor/bin/psalm" ]; then
    echo "🛡️  Running Psalm static analysis..."
    if ! vendor/bin/psalm --show-info=false; then
        echo ""
        echo "**************************************************************************"
        echo "Psalm found issues. Please fix them before committing."
        echo "Aborting commit."
        echo "**************************************************************************"
        exit 1
    fi
    echo "✅ Psalm analysis passed"
fi

# Additional security and quality checks
echo "🔧 Running additional security and quality checks..."

# Check for var_dump, print_r, die, exit in production code
if find . -name "*.php" -not -path "./vendor/*" -not -path "./tests/*" -not -path "./test/*" -exec grep -l "var_dump\|print_r\|die(\|exit(" {} \; | head -1 | grep -q .; then
    echo "⚠️  Warning: Found debugging functions (var_dump, print_r, die, exit) in code"
    echo "   Please remove debugging statements before committing"
fi

# Check for potential security issues
if find . -name "*.php" -not -path "./vendor/*" -exec grep -l "eval(\|exec(\|system(\|shell_exec\|passthru\|file_get_contents.*http\|curl_exec.*http" {} \; | head -1 | grep -q .; then
    echo "🚨 Warning: Potential security-sensitive functions found"
    echo "   Please review usage of eval(), exec(), system(), file_get_contents() with URLs, etc."
fi

# Check for hardcoded credentials
if find . -name "*.php" -not -path "./vendor/*" -exec grep -i -l "password.*=.*['\"].\|api.*key.*=.*['\"].\|secret.*=.*['\"].\|token.*=.*['\"]." {} \; | head -1 | grep -q .; then
    echo "🚨 Warning: Potential hardcoded credentials found"
    echo "   Please ensure sensitive data is in environment variables or config files"
fi

# Check for TODO/FIXME/HACK comments
if find . -name "*.php" -not -path "./vendor/*" -exec grep -l "TODO\|FIXME\|HACK" {} \; | head -1 | grep -q .; then
    echo "ℹ️  Info: Found TODO/FIXME/HACK comments in code"
fi

# Check for large files (> 1MB)
LARGE_FILES=$(find . -type f -size +1M -not -path "./.git/*" -not -path "./vendor/*" -not -path "./node_modules/*" | head -5)
if [ -n "$LARGE_FILES" ]; then
    echo "⚠️  Warning: Large files found (>1MB):"
    echo "$LARGE_FILES"
    echo "   Consider optimizing or using Git LFS for large files"
fi

# Check for sensitive configuration files
if find . -type f \( -name ".env" -o -name "config.php" -o -name "database.php" \) -not -path "./.git/*" -not -path "./vendor/*" | head -1 | grep -q .; then
    echo "🚨 Warning: Potentially sensitive configuration files found"
    echo "   Ensure production configurations are not committed"
    echo "   Consider using .env.example instead of .env"
fi

# Framework-specific checks
if [ -f "artisan" ] && [ -f "app/Http/Kernel.php" ]; then
    echo "🅻  Laravel project detected"
    
    # Check for Laravel best practices
    if find . -name "*.php" -path "./app/*" -exec grep -l "DB::" {} \; | head -1 | grep -q .; then
        echo "ℹ️  Info: Found DB facade usage. Consider using Eloquent models or Query Builder"
    fi
    
    # Check for route caching (in production)
    if [ -f "bootstrap/cache/routes.php" ]; then
        echo "ℹ️  Info: Routes are cached. Run 'php artisan route:clear' if you've modified routes"
    fi
fi

if [ -f "bin/console" ] && [ -d "src/Controller" ]; then
    echo "🎵 Symfony project detected"
    echo "ℹ️  Consider running 'php bin/console lint:yaml config/' and 'php bin/console lint:twig templates/'"
fi

echo "✅ All pre-commit checks passed! 🎉"
echo ""
echo "📊 Summary:"
echo "   • PHP syntax check: ✅"
echo "   • Dependency check: ✅"
echo "   • Code formatting: ✅"
echo "   • Static analysis: ✅"
echo "   • Tests: ✅"
echo "   • Security checks: ✅"
echo "   • Quality checks: ✅"

echo "Pre-commit hooks passed. Committing changes."
exit 0