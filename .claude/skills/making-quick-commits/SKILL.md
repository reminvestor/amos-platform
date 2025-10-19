# Making Quick Commits

**Smart commit message generation based on git diff analysis**

Generate contextual commit messages by analyzing staged/unstaged changes, automatically categorizing changes by file type and scope. Optionally push to remote after committing.

## When to Use

- Quick commits with AI-generated messages based on changed files
- Custom commit messages with automatic push
- Staging and committing all changes at once
- Smart categorization of changes (models, controllers, tools, migrations, docs, etc.)

## Usage

```bash
# Quick commit with AI-generated message (with push)
./.claude/skills/making-quick-commits/scripts/quick-commit.sh

# Commit with custom message
./.claude/skills/making-quick-commits/scripts/quick-commit.sh "Fix authentication bug"

# Commit without pushing
./.claude/skills/making-quick-commits/scripts/quick-commit.sh "" false

# Custom message without push
./.claude/skills/making-quick-commits/scripts/quick-commit.sh "Update user model" false
```

## How It Works

1. **Check Git Status**: Detects staged and unstaged changes
2. **Smart Staging**: Prompts to stage all if mixed changes exist
3. **Change Analysis**: Categorizes changes by file patterns:
   - Database migrations → "Add database migration"
   - Models → "Update {model} model"
   - Controllers → "Update {controller} controller"
   - Services/Tools → "Update {tool} tool"
   - Tests → "Add tests"
   - Documentation → "Update documentation"
   - Dependencies → "Update dependencies"
4. **Message Generation**: Suggests contextual commit message
5. **Confirmation**: Use suggested message or provide custom
6. **Commit & Push**: Creates commit with Claude attribution, optionally pushes

## Examples

**Scenario 1: Multiple model changes**
```bash
$ ./.claude/skills/making-quick-commits/scripts/quick-commit.sh
🔍 Checking git status...
✅ Staged changes found

Changes:
 app/models/affiliate.rb | 2 +-
 app/models/user.rb      | 8 ++++++++
 2 files changed, 9 insertions(+), 1 deletion(-)

💡 Suggested: "Update user model"
✅ Commit created: abc1234 Update user model
📤 Pushed to origin/feature-branch
```

**Scenario 2: Custom message**
```bash
$ ./.claude/skills/making-quick-commits/scripts/quick-commit.sh "Refactor authentication logic"
📝 Creating commit...
   Message: Refactor authentication logic
✅ Commit created!
```

**Scenario 3: Migration + model**
```bash
💡 Suggested: "Add database migration"
# Detects migrations as highest priority
```

## Script Reference

### `quick-commit.sh [message] [push]`

**Parameters**:
- `message` (optional): Custom commit message (skips AI generation)
- `push` (optional): Push after commit (default: true)

**Exit Codes**:
- `0`: Success
- `1`: No changes to commit
- `1`: Git operation failed
