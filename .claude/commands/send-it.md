# Send It - Automated GitHub PR Workflow

Create a branch, commit, push, and create a PR with optional linked issue.

## Arguments
- `$ARGUMENTS` - Branch name and commit message (e.g., "fix/bug-name Fix the bug description")

## Instructions

Execute the following workflow:

### 1. Parse Arguments
Extract from `$ARGUMENTS`:
- **Branch name**: First word (e.g., `fix/bug-name`)
- **Commit message**: Remaining text (e.g., `Fix the bug description`)

If no arguments provided, ask the user for:
- Branch name (suggest based on recent changes)
- Brief description of the changes

### 2. Ensure on Main and Up-to-Date
```bash
git checkout main
git pull origin main
```

### 3. Create Feature Branch
```bash
git checkout -b <branch-name>
```

### 4. Stage and Commit Changes
```bash
git add -A
git status
```

Review the changes, then commit with the provided message:
```bash
git commit -m "<commit-message>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### 5. Push Branch
```bash
git push -u origin <branch-name>
```

### 6. Create GitHub Issue (Optional)
If the user wants to link an issue, create one:
```bash
gh issue create \
  --title "<commit-message>" \
  --body "Created via Claude Code send-it workflow" \
  --label "enhancement"
```

Store the issue number for the next step. Skip if user doesn't want an issue.

### 7. Create Pull Request
```bash
gh pr create \
  --base main \
  --head <branch-name> \
  --title "<commit-message>" \
  --body "## Summary
<brief description of changes based on git diff>

## Changes
<list key files changed>

## Test plan
- [ ] Verify changes work as expected
- [ ] Run tests: \`rails test\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

If an issue was created, add `Closes #<issue-number>` to the PR body.

### 8. Report Success
Output a summary:
- Branch name
- PR number and URL
- Issue number and URL (if created)

Example output:
```
✅ Send it complete!

Branch: fix/remove-mailgun
PR: #105 - https://github.com/NuvolaNetworks/agent_marketing/pull/105
Issue: #42 - https://github.com/NuvolaNetworks/agent_marketing/issues/42
```

## Quick Examples

```bash
# Full workflow with branch and message
/send-it feature/add-dark-mode Add dark mode toggle to settings

# Just branch name (will prompt for message)
/send-it feature/refactor-auth

# Interactive (prompts for everything)
/send-it
```

## Prerequisites

- GitHub CLI installed: `brew install gh`
- Authenticated: `gh auth login`
- On a git repository with GitHub remote

## Safety Features

- Starts from main to ensure clean branch
- Shows staged changes before committing
- Creates regular PR (not draft) for visibility
- Links issues for traceability
