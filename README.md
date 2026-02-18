# wt-pre-commit-hooks

A collection of language-specific [pre-commit](https://pre-commit.com/) hooks for enforcing code quality, formatting, linting, security checks, and testing across multiple technology stacks.

## Supported Languages

| Language / Framework | Hook ID | File Types |
|---|---|---|
| [Android (Java/Kotlin)](#android-javakotlin) | `custom-android-script` | `.java`, `.kotlin` |
| [Java](#java) | `custom-java-script` | `.java` |
| [.NET (C#)](#net-c) | `custom-dot-net-script` | `.cs` |
| [Flutter (Dart)](#flutter-dart) | `custom-flutter-script` | `.dart` |
| [iOS (Swift)](#ios-swift) | `custom-ios-script` | `.swift` |
| [JavaScript / TypeScript](#javascript--typescript) | `custom-js-script` | `.js`, `.jsx`, `.ts`, `.tsx`, `.json`, `.md` |
| [PHP](#php) | `custom-php-script` | `.php` |
| [Python](#python) | `custom-python-script` | `.py` |
| [Ruby on Rails](#ruby-on-rails) | `custom-ror-script` | `.rb` |

---

## Quick Start (Recommended)

The easiest way to set up pre-commit hooks is using the interactive setup script. It handles everything automatically — detecting your OS, installing pre-commit, letting you pick languages, generating the config, and installing the git hook.

```bash
bash setup.sh
```

The setup script will:

1. Detect your operating system (Linux, macOS, or Windows via Git Bash / WSL / MSYS2)
2. Verify that Git and Python are installed
3. Install `pre-commit` if it's not already available (via Homebrew, pipx, or pip depending on your OS)
4. Check for an existing `.pre-commit-config.yaml` and offer to reconfigure
5. Present an interactive menu to select one or more language hooks
6. Generate the `.pre-commit-config.yaml` file (backing up any existing config)
7. Install the pre-commit git hook
8. Optionally run the hooks against all existing files
9. Print language-specific tool requirements for your selections

### Supported Languages in Setup Script

| # | Language / Framework | Hook ID |
|---|---|---|
| 1 | Android (Java/Kotlin) | `custom-android-script` |
| 2 | .NET (C#) | `custom-dot-net-script` |
| 3 | Flutter (Dart) | `custom-flutter-script` |
| 4 | iOS (Swift) | `custom-ios-script` |
| 5 | JavaScript / TypeScript | `custom-js-script` |
| 6 | PHP | `custom-php-script` |
| 7 | Python | `custom-python-script` |
| 8 | Ruby on Rails | `custom-ror-script` |
| 9 | Java | `custom-java-script` |

You can select multiple languages by entering comma-separated numbers (e.g., `5,7` for JavaScript + Python).

---

## Manual Setup

If you prefer to set things up manually:

1. Install [pre-commit](https://pre-commit.com/#install):

   ```bash
   pip install pre-commit
   ```

2. Create a `.pre-commit-config.yaml` file in your project root (see language-specific sections below).

3. Install the git hook:

   ```bash
   pre-commit install
   ```

4. (Optional) Run against all files manually:

   ```bash
   pre-commit run --all-files
   ```

---

## Android (Java/Kotlin)

### What It Does

Runs **Spotless** formatting checks via Gradle to ensure consistent code style across Java and Kotlin files.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Code formatting | `./gradlew spotlessCheck` | Yes |

### How to Fix Failures

```bash
./gradlew spotlessApply
```

### Requirements

- Gradle wrapper (`gradlew`) in project root
- [Spotless](https://github.com/diffplug/spotless) Gradle plugin configured in `build.gradle` or `build.gradle.kts`

### Setup

Copy `.pre-commit-config-android.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-android-script
```

---

## Java

### What It Does

Runs a comprehensive Java code quality pipeline including compilation, code style enforcement, static analysis, bug detection, and testing. Supports both **Maven** and **Gradle** projects, with automatic detection of the build tool.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Compilation | `mvn compile` / `gradle compileJava` | Yes |
| Code style enforcement | [Checkstyle](https://checkstyle.org/) | Yes |
| Bug detection | [SpotBugs](https://spotbugs.github.io/) | Yes |
| Code analysis | [PMD](https://pmd.github.io/) | Yes |
| Code formatting | [Spotless](https://github.com/diffplug/spotless) | Yes |
| Unit tests | `mvn test` / `gradle test` | Yes |
| Debug statement detection | `grep` (System.out.println, printStackTrace) | Warning only |
| Hardcoded secrets detection | `grep` (password, apiKey, secret, etc.) | Warning only |
| TODO/FIXME/HACK comments | `grep` | Info only |
| Large file detection | Files > 1MB | Warning only |
| Sensitive config detection | application.properties/yml | Warning only |
| Spring Boot best practices | @Autowired field injection detection | Info only |

### Requirements

- JDK 11+ (17+ recommended)
- [Maven](https://maven.apache.org/) or [Gradle](https://gradle.org/) build tool

#### Maven — Add plugins to `pom.xml`:

```xml
<build>
  <plugins>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-checkstyle-plugin</artifactId>
      <version>3.3.1</version>
    </plugin>
    <plugin>
      <groupId>com.github.spotbugs</groupId>
      <artifactId>spotbugs-maven-plugin</artifactId>
      <version>4.8.3.1</version>
    </plugin>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-pmd-plugin</artifactId>
      <version>3.21.2</version>
    </plugin>
  </plugins>
</build>
```

#### Gradle — Add plugins to `build.gradle`:

```groovy
plugins {
    id 'checkstyle'
    id 'pmd'
    id 'com.github.spotbugs' version '6.0.7'
}
```

### How to Fix Failures

```bash
# Maven
mvn checkstyle:check          # View Checkstyle violations
mvn spotbugs:check            # View SpotBugs issues
mvn pmd:check                 # View PMD issues
mvn spotless:apply            # Fix formatting (if Spotless configured)
mvn test                      # Run tests locally

# Gradle
./gradlew checkstyleMain      # View Checkstyle violations
./gradlew spotbugsMain        # View SpotBugs issues
./gradlew pmdMain             # View PMD issues
./gradlew spotlessApply       # Fix formatting (if Spotless configured)
./gradlew test                # Run tests locally
```

### Setup

Copy `.pre-commit-config-java.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-java-script
```

---

## .NET (C#)

### What It Does

Runs a comprehensive set of .NET code quality checks including formatting, building, static analysis, testing, and security scans. Compatible with .NET Framework, .NET Core, and .NET 5+.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| NuGet package restore | `dotnet restore` | Yes |
| Code formatting | `dotnet format` | Yes |
| Project build | `dotnet build --configuration Release` | Yes |
| Static code analysis | Built-in Roslyn analyzers | Yes |
| Unit tests | `dotnet test` | Yes |
| Debug statement detection | `grep` (Console.WriteLine, Debug.WriteLine) | Warning only |
| Hardcoded secrets detection | `grep` (connectionString, password, etc.) | Warning only |
| TODO/FIXME/HACK comments | `grep` | Info only |
| Large file detection | Files > 1MB | Warning only |
| Sensitive file detection | Production configs, certificates | Warning only |

### Requirements

- [.NET SDK](https://dotnet.microsoft.com/download) (6+ recommended for built-in `dotnet format`)
- For older .NET versions: `dotnet tool install -g dotnet-format`

### How to Fix Failures

```bash
dotnet format              # Fix formatting issues
dotnet build               # Check build errors
dotnet test                # Run and debug tests
```

### Setup

Copy `.pre-commit-config-dotnet.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-dot-net-script
```

---

## Flutter (Dart)

### What It Does

Runs Flutter/Dart code quality checks including dependency resolution, formatting, static analysis, and testing.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Dependency resolution | `flutter pub get` | Yes |
| Code formatting | `dart format --set-exit-if-changed` | Yes |
| Static analysis | `dart analyze` | Yes |
| Unit tests | `flutter test` | Yes |
| Debug print detection | `grep` (print() statements) | Warning only |
| TODO/FIXME comments | `grep` | Info only |

### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- `pubspec.yaml` in project root

### How to Fix Failures

```bash
dart format lib/ test/     # Fix formatting
dart analyze               # View analysis issues
flutter test               # Run tests locally
```

### Setup

Copy `.pre-commit-config-flutter.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-flutter-script
```

---

## iOS (Swift)

### What It Does

Runs **SwiftLint** and **SwiftFormat** via [Mint](https://github.com/yonaskolb/Mint) to enforce Swift coding standards and auto-correct formatting issues.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Linting & auto-correct | `mint run swiftlint autocorrect` | Yes |
| Code formatting | `mint run swiftformat . --autocorrect` | Yes |

### Requirements

- [Mint](https://github.com/yonaskolb/Mint) package manager
- [SwiftLint](https://github.com/realm/SwiftLint)
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)

Install via Mint:

```bash
brew install mint
mint install realm/SwiftLint
mint install nicklockwood/SwiftFormat
```

### Setup

Copy `.pre-commit-config-ios.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-ios-script
```

---

## JavaScript / TypeScript

### What It Does

Formats and lints staged JavaScript/TypeScript files using **Prettier** and **ESLint**, auto-fixing issues and re-staging corrected files.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Code formatting | `npx prettier --write` | Yes (auto-fixes) |
| Linting | `npx eslint --fix` | Yes (auto-fixes) |

Operates only on staged files matching `.ts`, `.tsx`, `.js`, `.jsx`, `.json`, `.md`.

### Requirements

- [Node.js](https://nodejs.org/) and npm
- [Prettier](https://prettier.io/) installed in the project
- [ESLint](https://eslint.org/) installed and configured in the project

```bash
npm install --save-dev prettier eslint
```

### Setup

Copy `.pre-commit-config-js.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-js-script
```

---

## PHP

### What It Does

Runs a comprehensive PHP code quality pipeline including syntax checking, formatting, static analysis, testing, and security scanning. Supports Laravel, Symfony, and other PHP frameworks.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Composer dependencies | `composer install` | Yes |
| PHP syntax check | `php -l` | Yes |
| Code formatting | [PHP CS Fixer](https://github.com/PHP-CS-Fixer/PHP-CS-Fixer) | Yes |
| Static analysis | [PHPStan](https://phpstan.org/) | Yes |
| Coding standards | [PHP CodeSniffer](https://github.com/PHPCSStandards/PHP_CodeSniffer) | Yes |
| Unit tests | [PHPUnit](https://phpunit.de/) | Yes |
| Static analysis (alt) | [Psalm](https://psalm.dev/) | Yes |
| Debug function detection | `grep` (var_dump, print_r, die, exit) | Warning only |
| Security-sensitive functions | `grep` (eval, exec, system, etc.) | Warning only |
| Hardcoded credentials | `grep` | Warning only |
| TODO/FIXME/HACK comments | `grep` | Info only |
| Large file detection | Files > 1MB | Warning only |
| Sensitive config files | `.env`, `config.php`, `database.php` | Warning only |
| Framework-specific checks | Laravel / Symfony detection | Info only |

### Requirements

- PHP 7.4+
- [Composer](https://getcomposer.org/)

Recommended dev dependencies:

```bash
composer require --dev friendsofphp/php-cs-fixer phpstan/phpstan squizlabs/php_codesniffer phpunit/phpunit vimeo/psalm
```

### How to Fix Failures

```bash
php-cs-fixer fix            # Fix formatting
phpcbf                      # Fix coding standard violations
vendor/bin/phpstan analyse   # View static analysis issues
vendor/bin/phpunit           # Run tests locally
```

### Setup

Copy `.pre-commit-config-php.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-php-script
```

---

## Python

### What It Does

Runs a full Python code quality pipeline on staged files including formatting, import sorting, linting, type checking, security scanning, secret detection, and testing.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Merge conflict markers | `grep` | Yes |
| Trailing whitespace & EOF fix | `sed` | Auto-fixes |
| YAML/JSON/TOML validation | Python stdlib | Yes |
| Code formatting | [Black](https://github.com/psf/black) | Auto-fixes |
| Import sorting | [isort](https://pycqa.github.io/isort/) | Auto-fixes |
| Linting | [Flake8](https://flake8.pycqa.org/) | Yes |
| Type checking | [mypy](https://mypy-lang.org/) | Warning only |
| Security analysis | [Bandit](https://bandit.readthedocs.io/) | Yes |
| Secret detection | [detect-secrets](https://github.com/Yelp/detect-secrets) | Yes |
| Unit tests | [pytest](https://docs.pytest.org/) | Yes |

### Requirements

- Python 3.x

Install the required tools:

```bash
pip install black isort flake8 mypy bandit detect-secrets pytest
```

### How to Fix Failures

```bash
black .                     # Fix formatting
isort --profile black .     # Fix import order
flake8                      # View lint issues
mypy .                      # View type errors
bandit -r .                 # View security issues
pytest                      # Run tests locally
```

### Setup

Copy `.pre-commit-config-python.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-python-script
```

---

## Ruby on Rails

### What It Does

Runs a comprehensive Ruby/Rails code quality pipeline including style enforcement, syntax checking, security scanning, dependency auditing, testing, and database migration checks. Compatible with both Rails and non-Rails Ruby projects.

### Checks Performed

| Check | Tool | Blocking |
|---|---|---|
| Gem dependencies | `bundle check` / `bundle install` | Yes |
| Code style & linting | [RuboCop](https://rubocop.org/) | Yes |
| Ruby syntax check | `ruby -c` | Yes |
| ERB template linting | [erb_lint](https://github.com/Shopify/erb-lint) | Yes |
| Security analysis (Rails) | [Brakeman](https://brakemanscanner.org/) | Yes |
| Dependency audit | [bundler-audit](https://github.com/rubysec/bundler-audit) | Yes |
| Rails best practices | [rails_best_practices](https://github.com/flyerhzm/rails_best_practices) | Warning only |
| Unit tests | RSpec / Minitest | Yes |
| Pending migrations (Rails) | Schema file comparison | Warning only |
| Debugger statements | `grep` (binding.pry, byebug, etc.) | Warning only |
| Debug output | `grep` (puts, p, pp in app/lib) | Warning only |
| Hardcoded secrets | `grep` | Warning only |
| TODO/FIXME/HACK comments | `grep` | Info only |
| Large file detection | Files > 1MB | Warning only |
| Sensitive files | `.pem`, `.key`, `master.key`, etc. | Warning only |
| .gitignore completeness | Common Rails patterns | Warning only |

### Requirements

- Ruby 2.5+
- [Bundler](https://bundler.io/)

Recommended gems in your `Gemfile`:

```ruby
group :development do
  gem 'rubocop', require: false
  gem 'rubocop-rails', require: false    # For Rails projects
  gem 'brakeman', require: false         # For Rails projects
  gem 'bundler-audit', require: false
  gem 'erb_lint', require: false
  gem 'rails_best_practices', require: false
end

group :test do
  gem 'rspec-rails'  # or use Minitest (built-in)
end
```

### How to Fix Failures

```bash
bundle exec rubocop -a       # Auto-fix RuboCop issues
bundle exec brakeman          # View security report
bundle exec bundle-audit      # View vulnerable gems
bundle exec rspec              # Run tests locally
rails db:migrate               # Apply pending migrations
```

### Setup

Copy `.pre-commit-config-ror.yaml` to your project root as `.pre-commit-config.yaml`, or add the following:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-ror-script
```

---

## Using Multiple Hooks

You can combine multiple hooks in a single `.pre-commit-config.yaml` if your project uses multiple languages:

```yaml
repos:
  - repo: https://github.com/wishtree-gmakwana/wt-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: custom-js-script
      - id: custom-python-script
```

---

## Skipping Hooks

To bypass hooks for a specific commit (use sparingly):

```bash
git commit --no-verify -m "your message"
```

To skip a specific hook:

```bash
SKIP=custom-js-script git commit -m "your message"
```

---

## Troubleshooting

| Issue | Solution |
|---|---|
| `pre-commit` command not found | Run `pip install pre-commit` or re-run `bash setup.sh` |
| Hook script permission denied | Run `chmod +x hooks/<script>.sh` |
| Hook fails on first run | Ensure all required tools for your language are installed (see language-specific Requirements sections) |
| Hook runs on wrong files | Verify `types` or `types_or` in `.pre-commit-hooks.yaml` match your file types |
| Setup script fails | Ensure you are running from within a git repository with `bash` available |

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add or modify hook scripts in the `hooks/` directory
4. Update `.pre-commit-hooks.yaml` with the new hook definition
5. Submit a pull request
