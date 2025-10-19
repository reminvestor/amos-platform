# Fixing Pull Requests

**Automatically resolve common PR issues: conflicts, linting, failing tests**

Analyzes GitHub PRs and automatically fixes merge conflicts, RuboCop offenses, and provides guidance for test failures.

## When to Use

- PR has merge conflicts
- PR failing RuboCop checks
- PR failing tests
- Quick PR fixes before review

## Usage

```bash
# Fix current branch's PR (interactive)
./.claude/skills/fixing-pull-requests/scripts/fix-pr.sh

# Fix specific PR
./.claude/skills/fixing-pull-requests/scripts/fix-pr.sh --pr 123

# Fix conflicts only
./.claude/skills/fixing-pull-requests/scripts/fix-pr.sh --fix-type conflicts

# Fix linting only
./.claude/skills/fixing-pull-requests/scripts/fix-pr.sh --fix-type lint

# Fix all issues automatically
./.claude/skills/fixing-pull-requests/scripts/fix-pr.sh --fix-type all
```

## How It Works

1. **Get PR Info**: Fetches PR details from GitHub (or finds PR for current branch)
2. **Check Status**: Analyzes mergeable state and failing checks
3. **Resolve Conflicts**: Merges base branch, auto-resolves lockfiles/schema
4. **Fix Linting**: Runs RuboCop with auto-correct
5. **Run Tests**: Identifies test failures and provides fix suggestions
6. **Push Changes**: Automatically pushes fixes to PR branch

## Auto-Resolution Strategies

**Merge Conflicts**:
- Gemfile.lock → Use theirs, regenerate with `bundle install`
- package-lock.json/yarn.lock → Use theirs, regenerate
- db/schema.rb → Use theirs (regenerated from migrations)
- Other files → Manual resolution required

**Linting**:
- Runs `rubocop -A` (auto-correct with unsafe fixes)
- Commits and pushes if changes made

**Tests**:
- Runs full test suite
- Provides common fix suggestions (migrations, schema reset, fixtures)

## Script Reference

### `fix-pr.sh [--pr NUMBER] [--fix-type TYPE]`

**Options**:
- `--pr NUMBER`: Specific PR number (default: current branch's PR)
- `--fix-type TYPE`: What to fix (all, conflicts, lint, tests)

**Exit Codes**:
- `0`: PR fixed successfully
- `1`: PR not found or fixes failed
