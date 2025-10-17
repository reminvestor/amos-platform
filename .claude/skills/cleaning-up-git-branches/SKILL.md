# Cleaning Up Git Branches

**Delete merged branches and prune remote references**

Safely remove local and remote branches that have been merged to main, keeping your repository clean and organized.

## When to Use

- After PR merge to clean up feature branches
- Periodic repository maintenance
- Before starting new work
- Removing stale development branches

## Usage

```bash
# Clean both local and remote (with confirmations)
./.claude/skills/cleaning-up-git-branches/scripts/cleanup-branches.sh

# Clean local branches only
./.claude/skills/cleaning-up-git-branches/scripts/cleanup-branches.sh --scope local

# Clean remote branches only
./.claude/skills/cleaning-up-git-branches/scripts/cleanup-branches.sh --scope remote

# Force cleanup without confirmations
./.claude/skills/cleaning-up-git-branches/scripts/cleanup-branches.sh --force
```

## How It Works

1. **Fetch & Prune**: Updates remote refs and removes stale tracking branches
2. **Find Merged Branches**: Identifies branches merged to main (excludes main/master/develop)
3. **Confirm Deletion**: Prompts for confirmation unless `--force` used
4. **Delete Local**: Removes merged local branches with `git branch -d`
5. **Delete Remote**: Pushes deletions to origin with `git push origin --delete`
6. **Show Summary**: Lists remaining branches

## Safety Features

- Never deletes main, master, develop, or current branch
- Requires confirmation by default
- Uses safe delete (`-d`) which prevents deleting unmerged branches
- Shows list of branches before deletion

## Script Reference

### `cleanup-branches.sh [--scope SCOPE] [--force]`

**Options**:
- `--scope local|remote|both`: What to clean (default: both)
- `--force`: Skip all confirmations

**Exit Codes**:
- `0`: Cleanup completed successfully
- `0`: No branches to clean (success)
