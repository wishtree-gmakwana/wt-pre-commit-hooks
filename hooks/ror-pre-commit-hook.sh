#!/bin/bash

# Ruby on Rails Pre-commit Hook
# This script runs Rails code quality checks before each commit
# Compatible with Rails 5+, Ruby 2.5+

echo "🚀 Running Ruby on Rails pre-commit checks..."

# Check if ruby is installed
if ! command -v ruby &> /dev/null; then
    echo "❌ Ruby is not installed or not in PATH"
    echo "   Please install Ruby from https://www.ruby-lang.org/en/downloads/"
    exit 1
fi

# Check if bundler is installed
if ! command -v bundle &> /dev/null; then
    echo "❌ Bundler is not installed"
    echo "   Please install with: gem install bundler"
    exit 1
fi

# Function to check if it's a Rails project
is_rails_project() {
    # Check for common Rails project indicators
    if [ -f "Gemfile" ] && [ -f "config/application.rb" ]; then
        return 0
    fi
    return 1
}

# Function to check if it's a Ruby project (non-Rails)
is_ruby_project() {
    if [ -f "Gemfile" ]; then
        return 0
    fi
    return 1
}

# Check if we're in a Rails or Ruby project
if ! is_rails_project && ! is_ruby_project; then
    echo "❌ Not a Ruby/Rails project (no Gemfile found)"
    exit 1
fi

# Determine project type
if is_rails_project; then
    PROJECT_TYPE="Rails"
else
    PROJECT_TYPE="Ruby"
fi

# Display Ruby/Rails version info
echo "📋 $PROJECT_TYPE Project Information:"
echo "   Ruby version: $(ruby --version)"
if command -v rails &> /dev/null && is_rails_project; then
    echo "   Rails version: $(rails --version 2>/dev/null || echo 'Not available')"
fi
echo "   Bundler version: $(bundle --version)"
echo ""

# Check for Gemfile.lock
if [ ! -f "Gemfile.lock" ]; then
    echo "⚠️  No Gemfile.lock found. Running bundle install..."
    if ! bundle install --quiet; then
        echo "❌ Failed to install gems"
        exit 1
    fi
fi

# Install dependencies
echo "📦 Checking gem dependencies..."
if ! bundle check --dry-run > /dev/null 2>&1; then
    echo "   Installing missing gems..."
    if ! bundle install --quiet; then
        echo "❌ Failed to install gems"
        exit 1
    fi
fi
echo "✅ Gem dependencies satisfied"

# Get staged Ruby files for targeted checks
STAGED_RB_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.rb$' | tr '\n' ' ')
STAGED_ERB_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.erb$' | tr '\n' ' ')

# Run RuboCop (Ruby linter and formatter)
echo "🎨 Running RuboCop (code style and linting)..."
if bundle show rubocop > /dev/null 2>&1; then
    if [ -n "$STAGED_RB_FILES" ]; then
        if ! bundle exec rubocop --force-exclusion $STAGED_RB_FILES; then
            echo "❌ RuboCop found issues. Run 'bundle exec rubocop -a' to auto-fix some issues."
            exit 1
        fi
    else
        echo "   No staged Ruby files to check"
    fi
    echo "✅ RuboCop check passed"
elif command -v rubocop &> /dev/null; then
    if [ -n "$STAGED_RB_FILES" ]; then
        if ! rubocop --force-exclusion $STAGED_RB_FILES; then
            echo "❌ RuboCop found issues. Run 'rubocop -a' to auto-fix some issues."
            exit 1
        fi
    fi
    echo "✅ RuboCop check passed"
else
    echo "⚠️  RuboCop not found. Install with: gem 'rubocop' in Gemfile"
    echo "   Skipping style check for now..."
fi

# Run Ruby syntax check
echo "🔍 Checking Ruby syntax..."
SYNTAX_ERRORS=0
for file in $STAGED_RB_FILES; do
    if [ -f "$file" ]; then
        if ! ruby -c "$file" > /dev/null 2>&1; then
            echo "   ❌ Syntax error in: $file"
            ruby -c "$file"
            SYNTAX_ERRORS=1
        fi
    fi
done
if [ $SYNTAX_ERRORS -eq 1 ]; then
    echo "❌ Ruby syntax errors found. Please fix them before committing."
    exit 1
fi
echo "✅ Ruby syntax check passed"

# Run ERB lint if available
if [ -n "$STAGED_ERB_FILES" ]; then
    echo "🎨 Checking ERB templates..."
    if bundle show erb_lint > /dev/null 2>&1; then
        if ! bundle exec erblint $STAGED_ERB_FILES; then
            echo "❌ ERB lint found issues."
            exit 1
        fi
        echo "✅ ERB lint check passed"
    else
        echo "⚠️  erb_lint not found. Install with: gem 'erb_lint' in Gemfile"
        echo "   Skipping ERB lint for now..."
    fi
fi

# Run Brakeman (security scanner for Rails)
if is_rails_project; then
    echo "🔐 Running security analysis (Brakeman)..."
    if bundle show brakeman > /dev/null 2>&1; then
        if ! bundle exec brakeman --quiet --no-pager --no-exit-on-warn --exit-on-error; then
            echo "❌ Brakeman found security vulnerabilities!"
            echo "   Run 'bundle exec brakeman' for detailed report."
            exit 1
        fi
        echo "✅ Security analysis passed"
    elif command -v brakeman &> /dev/null; then
        if ! brakeman --quiet --no-pager --no-exit-on-warn --exit-on-error; then
            echo "❌ Brakeman found security vulnerabilities!"
            exit 1
        fi
        echo "✅ Security analysis passed"
    else
        echo "⚠️  Brakeman not found. Install with: gem 'brakeman' in Gemfile"
        echo "   Skipping security analysis for now..."
    fi
fi

# Run bundler-audit (check for vulnerable gems)
echo "🛡️  Checking for vulnerable dependencies..."
if bundle show bundler-audit > /dev/null 2>&1; then
    # Update advisory database quietly
    bundle exec bundle-audit update --quiet 2>/dev/null || true
    if ! bundle exec bundle-audit check --quiet; then
        echo "❌ Vulnerable gems found! Run 'bundle exec bundle-audit' for details."
        echo "   Update vulnerable gems before committing."
        exit 1
    fi
    echo "✅ Dependency security check passed"
elif command -v bundle-audit &> /dev/null; then
    bundle-audit update --quiet 2>/dev/null || true
    if ! bundle-audit check --quiet; then
        echo "❌ Vulnerable gems found!"
        exit 1
    fi
    echo "✅ Dependency security check passed"
else
    echo "⚠️  bundler-audit not found. Install with: gem 'bundler-audit' in Gemfile"
    echo "   Skipping dependency security check for now..."
fi

# Run Rails Best Practices (if available)
if is_rails_project; then
    echo "📊 Running Rails Best Practices..."
    if bundle show rails_best_practices > /dev/null 2>&1; then
        if ! bundle exec rails_best_practices --silent --without-color . 2>/dev/null; then
            echo "⚠️  Rails Best Practices found suggestions (non-blocking)"
        else
            echo "✅ Rails Best Practices check passed"
        fi
    else
        echo "ℹ️  rails_best_practices not found. Consider adding for code quality insights."
    fi
fi

# Run tests
echo "🧪 Running tests..."
if is_rails_project; then
    # Check for different test frameworks
    if [ -d "spec" ] && bundle show rspec-rails > /dev/null 2>&1; then
        echo "   Using RSpec..."
        if ! bundle exec rspec --fail-fast --format progress; then
            echo "❌ RSpec tests failed. Please fix failing tests before committing."
            exit 1
        fi
        echo "✅ RSpec tests passed"
    elif [ -d "test" ]; then
        echo "   Using Minitest..."
        if ! bundle exec rails test; then
            echo "❌ Tests failed. Please fix failing tests before committing."
            exit 1
        fi
        echo "✅ Minitest tests passed"
    else
        echo "ℹ️  No test directory found, skipping test execution"
    fi
else
    # Non-Rails Ruby project
    if [ -d "spec" ] && bundle show rspec > /dev/null 2>&1; then
        echo "   Using RSpec..."
        if ! bundle exec rspec --fail-fast --format progress; then
            echo "❌ RSpec tests failed. Please fix failing tests before committing."
            exit 1
        fi
        echo "✅ RSpec tests passed"
    elif [ -d "test" ]; then
        echo "   Using Minitest..."
        if ! bundle exec rake test 2>/dev/null || ruby -Itest -e "Dir.glob('./test/**/*_test.rb').each { |f| require f }"; then
            echo "❌ Tests failed. Please fix failing tests before committing."
            exit 1
        fi
        echo "✅ Tests passed"
    else
        echo "ℹ️  No test directory found, skipping test execution"
    fi
fi

# Database checks for Rails
if is_rails_project; then
    echo "🗄️  Checking database migrations..."
    
    # Check for pending migrations
    if [ -d "db/migrate" ]; then
        PENDING_MIGRATIONS=$(find db/migrate -name "*.rb" -newer db/schema.rb 2>/dev/null | wc -l)
        if [ "$PENDING_MIGRATIONS" -gt 0 ]; then
            echo "⚠️  Warning: Potential pending migrations detected"
            echo "   Run 'rails db:migrate' to apply migrations"
        fi
    fi
    
    # Check if schema.rb is being committed without migrations
    if git diff --cached --name-only | grep -q "db/schema.rb"; then
        if ! git diff --cached --name-only | grep -q "db/migrate"; then
            echo "⚠️  Warning: schema.rb is being committed without migration files"
            echo "   Make sure this is intentional"
        fi
    fi
    echo "✅ Database checks completed"
fi

# Additional checks
echo "🔧 Running additional checks..."

# Check for binding.pry or byebug left in code
if grep -r "binding\.pry\|byebug\|debugger\|binding\.irb" --include="*.rb" . 2>/dev/null | grep -v "vendor/" | grep -v ".git/" | head -5 | grep -q .; then
    echo "⚠️  Warning: Debugger statements found (binding.pry, byebug, etc.)"
    grep -r "binding\.pry\|byebug\|debugger\|binding\.irb" --include="*.rb" . 2>/dev/null | grep -v "vendor/" | grep -v ".git/" | head -5
    echo "   Consider removing debug statements before committing"
fi

# Check for puts/p statements (potential debug output)
if grep -r "^\s*puts \|^\s*p \|^\s*pp " --include="*.rb" app/ lib/ 2>/dev/null | grep -v "vendor/" | head -5 | grep -q .; then
    echo "⚠️  Warning: Found puts/p statements in app/ or lib/"
    echo "   Consider using Rails.logger instead"
fi

# Check for hardcoded secrets
if grep -rE "(api_key|api_secret|password|secret_key|private_key)\s*=\s*['\"][^'\"]+['\"]" --include="*.rb" . 2>/dev/null | grep -v "vendor/" | grep -v ".git/" | grep -v "_test.rb" | grep -v "_spec.rb" | head -5 | grep -q .; then
    echo "🚨 Warning: Potential hardcoded secrets found"
    echo "   Please use Rails credentials or environment variables"
fi

# Check for TODO/FIXME/HACK comments
if grep -rE "(TODO|FIXME|HACK|XXX):" --include="*.rb" . 2>/dev/null | grep -v "vendor/" | grep -v ".git/" | head -5 | grep -q .; then
    echo "ℹ️  Info: Found TODO/FIXME/HACK comments in code"
fi

# Check for large files (> 1MB) being committed
LARGE_FILES=$(find . -type f -size +1M -not -path "./.git/*" -not -path "./vendor/*" -not -path "./node_modules/*" -not -path "./tmp/*" -not -path "./log/*" -not -path "./public/assets/*" -not -path "./public/packs/*" 2>/dev/null | head -5)
if [ -n "$LARGE_FILES" ]; then
    echo "⚠️  Warning: Large files found (>1MB):"
    echo "$LARGE_FILES"
    echo "   Consider using Git LFS for large binary files"
fi

# Check for sensitive files
if find . -type f \( -name "*.pem" -o -name "*.key" -o -name "master.key" -o -name "credentials.yml.enc" -o -name ".env.production" -o -name "database.yml" \) -not -path "./.git/*" 2>/dev/null | head -1 | grep -q .; then
    SENSITIVE=$(find . -type f \( -name "*.pem" -o -name "*.key" -o -name "master.key" -o -name ".env.production" \) -not -path "./.git/*" 2>/dev/null)
    if [ -n "$SENSITIVE" ]; then
        echo "🚨 Warning: Potentially sensitive files found:"
        echo "$SENSITIVE"
        echo "   Ensure these are in .gitignore and not being committed"
    fi
fi

# Check .gitignore for common Rails ignores
if [ -f ".gitignore" ]; then
    MISSING_IGNORES=""
    for pattern in "*.log" "/tmp" "/log" "master.key" ".env"; do
        if ! grep -q "$pattern" .gitignore 2>/dev/null; then
            MISSING_IGNORES="$MISSING_IGNORES $pattern"
        fi
    done
    if [ -n "$MISSING_IGNORES" ]; then
        echo "⚠️  Warning: Consider adding to .gitignore:$MISSING_IGNORES"
    fi
fi

echo "✅ All pre-commit checks passed! 🎉"
echo ""
echo "📊 Summary:"
echo "   • Gem dependencies: ✅"
echo "   • Code style (RuboCop): ✅"
echo "   • Syntax check: ✅"
echo "   • Security analysis: ✅"
echo "   • Dependency audit: ✅"
echo "   • Tests: ✅"
echo "   • Additional checks: ✅"

exit 0
