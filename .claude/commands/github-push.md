# GitHub Push & Draft PR

Stages changes, pushes to GitHub, and creates a draft pull request.

## Usage

```
/github-push [pr-title]
```

## What It Does

Automated workflow for pushing feature branches:

1. **Checks branch** - Ensures not on main/master
2. **Shows changes** - Displays what will be staged
3. **Stages files** - Adds all changes (respects .gitignore)
4. **Gets commit message** - Uses provided PR title or prompts
5. **Commits changes** - Creates commit with Claude Code signature
6. **Pushes to remote** - Forces push if branch exists
7. **Creates draft PR** - Opens pull request against main in draft mode
8. **Shows PR URL** - Returns link to the draft PR

## Examples

```bash
# With PR title
/github-push "Add RAG testing suite and documentation"

# Interactive (prompts for title)
/github-push

# Results in:
# - All changes committed
# - Branch pushed to origin
# - Draft PR created on GitHub
# - PR URL displayed
```

## What Gets Committed

**Included:**
- All modified files
- New files (untracked)
- Deleted files

**Excluded:**
- Files in `.gitignore`
- Temporary files
- Build artifacts

## Draft PR Details

**Target Branch:** `main` (configurable)

**PR Body Includes:**
- Summary of changes (auto-generated from commit)
- File count and line changes
- Checklist for review
- Claude Code attribution

**Status:** Draft (can be marked ready later)

## Safety Features

- ✅ Won't run on main/master branch
- ✅ Shows what will be committed first
- ✅ Asks for confirmation before push
- ✅ Creates draft (not ready for review)
- ✅ Preserves git history

## Behind the Scenes

Executes:
1. Check current branch
2. `git add -A`
3. `git status` (for confirmation)
4. `git commit -m "message"`
5. `git push -u origin <branch>`
6. `gh pr create --draft --base main`

## When to Use

**Use github-push when:**
- Ready to share work-in-progress
- Want to create PR for discussion
- Need to backup feature branch
- Collaborating on feature

**Don't use when:**
- On main/master branch
- Want to review changes first
- Need selective staging
- PR should be ready (not draft)

## Manual Alternative

If you prefer manual control:

```bash
# Stage and commit
git add -A
git commit -m "Your message"

# Push
git push -u origin feature-branch

# Create draft PR
gh pr create --draft --base main --title "Title" --body "Description"
```

## Configuration

Edit command script to change:
- Target branch (default: `main`)
- Commit message format
- PR template
- Auto-merge rules

## Related Commands

- `/quick-commit` - Fast commit without PR
- `/finishing-feature-work` - Complete feature with full checks

## Notes

- Creates draft PR (mark ready when done)
- Uses GitHub CLI (`gh`) for PR creation
- Requires GitHub authentication
- Safe to run multiple times (updates PR)
- Branch must have upstream commits

## Troubleshooting

**"gh: command not found"**
```bash
brew install gh
gh auth login
```

**"Not on a feature branch"**
→ Switch to feature branch first: `git checkout -b feature/my-feature`

**"No changes to commit"**
→ All changes already committed, just run: `git push`

**"PR already exists"**
→ Command will show existing PR URL instead
