# Code Linting & Formatting Setup

This project uses automated linting and formatting to maintain code quality and consistency.

## Quick Start

**First-time setup:**
```bash
bin/setup-hooks
```

This installs git hooks that automatically format your code before every commit.

## Installed Linters

### 1. RuboCop (Ruby)
- **Config**: Uses `rubocop-rails-omakase` preset
- **Scope**: All `.rb` and `.rake` files
- **Auto-fixes**: Most style issues

### 2. ERB Lint (Templates)
- **Config**: `.erb-lint.yml`
- **Scope**: All `.html.erb` files
- **Auto-fixes**: Whitespace, tag formatting, etc.

## Git Hooks (Automatic)

**Install hooks:** Run `bin/setup-hooks` to install pre-commit and post-commit hooks.

**Hook files:** Stored in `hooks/` directory (tracked by git) and copied to `.git/hooks/` by setup script.

### Pre-Commit Hook
**Location**: `.git/hooks/pre-commit` (installed from `hooks/pre-commit`)

**What it does:**
1. Runs RuboCop on staged Ruby files with auto-correct (`-A`)
2. Runs ERB Lint on staged ERB files with auto-correct
3. Re-stages the auto-corrected files
4. Checks for remaining issues
5. **Blocks commit** if unfixable issues remain

**Flow:**
```
Stage files → Pre-commit hook runs → Auto-corrections applied → Files re-staged → Commit proceeds
```

### Post-Commit Hook
**Location**: `.git/hooks/post-commit` (installed from `hooks/post-commit`)

**What it does:**
- Detects if linters made changes AFTER commit
- Warns you with clear instructions to amend the commit
- **This is your safety net** if pre-commit hook didn't catch something

## Manual Linting

### Run All Linters
```bash
# Safe auto-correct (recommended)
bin/lint

# Aggressive auto-correct (fixes more issues)
bin/lint --auto-correct

# Check only (no fixes)
bin/lint --check-only
```

### Run Individual Linters

**RuboCop:**
```bash
# Auto-correct safe issues
bundle exec rubocop -a

# Auto-correct all issues (aggressive)
bundle exec rubocop -A

# Check specific file
bundle exec rubocop app/models/user.rb

# Check only (no fixes)
bundle exec rubocop
```

**ERB Lint:**
```bash
# Auto-correct all templates
bundle exec erblint --autocorrect --lint-all

# Check specific file
bundle exec erblint --autocorrect app/views/admin/users/index.html.erb

# Check only (no fixes)
bundle exec erblint --lint-all
```

## Workflow Examples

### Before Making Changes
```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make your changes
# ... edit files ...

# 3. Run linters (optional, pre-commit hook will do this)
bin/lint

# 4. Commit - pre-commit hook runs automatically
git add .
git commit -m "Add new feature"

# 5. If post-commit hook warns about changes:
git diff              # Review changes
git add -A           # Stage linter changes
git commit --amend --no-edit  # Amend the commit
```

### Fixing Legacy Code
```bash
# Run linters on all files and fix everything
bundle exec rubocop -A
bundle exec erblint --autocorrect --lint-all

# Review and commit
git add .
git commit -m "Fix linting issues across codebase"
```

## Configuration Files

### `.rubocop.yml` (if needed)
Create this file to customize RuboCop rules:
```yaml
inherit_gem:
  rubocop-rails-omakase: rubocop.yml

# Add custom overrides here
# Example:
# Style/StringLiterals:
#   Enabled: false
```

### `.erb-lint.yml`
Already configured! Edit to customize ERB linting rules.

## Troubleshooting

### Pre-commit hook not running
```bash
# Re-run the setup script
bin/setup-hooks

# Or manually install
chmod +x .git/hooks/pre-commit .git/hooks/post-commit
```

### Linter conflicts with my code style
1. Add exception to `.rubocop.yml` or `.erb-lint.yml`
2. Use inline comments to disable specific rules:
   ```ruby
   # rubocop:disable Style/StringLiterals
   bad_code_here
   # rubocop:enable Style/StringLiterals
   ```

### Want to skip hooks temporarily (NOT RECOMMENDED)
```bash
# Only use in emergencies
git commit --no-verify -m "Emergency fix"
```

## Benefits

✅ **Consistent code style** across the team
✅ **Catch issues before they reach CI/CD**
✅ **Auto-fix most style issues** (saves time)
✅ **Prevent post-commit linter changes** (like you experienced)
✅ **Better code reviews** (focus on logic, not style)

## CI/CD Integration

Add this to your CI pipeline (`.github/workflows/*.yml` or similar):
```yaml
- name: Run Linters
  run: bin/lint --check-only
```

This ensures all PRs pass linting before merge.
