# Fixing RuboCop Offenses

Automatically fix Ruby linting issues with RuboCop safe auto-correct.

## Description

This skill runs RuboCop with auto-correction to fix linting issues in Ruby code. It supports both safe and unsafe auto-correction modes, can target specific files or directories, and optionally commits the changes with a standardized commit message.

**Use this skill when:**
- RuboCop CI checks are failing
- Code has linting violations
- Need to clean up code style before committing
- Working with legacy code that needs formatting
- Before creating a pull request

The skill follows a safe-by-default approach, only running unsafe auto-correct when explicitly requested.

## Instructions

### Auto-Correction Modes

**Safe Mode** (default):
- Fixes only safe, non-behavior-changing issues
- Examples: whitespace, quotes, trailing commas
- Uses `rubocop -a` flag
- Always safe to run

**Unsafe Mode** (opt-in):
- Fixes potentially behavior-changing issues
- Examples: performance optimizations, syntax modernization
- Uses `rubocop -A` flag
- Review changes carefully before committing

### Workflow

1. **Check Current State** - Run RuboCop to identify offenses
2. **Auto-Correct** - Apply fixes based on mode (safe/unsafe)
3. **Final Check** - Verify remaining offenses
4. **Show Changes** - Display git diff stats
5. **Commit** - Auto-commit with standard message (optional)
6. **Summary** - Report results and any manual fixes needed

### Targeting Specific Paths

**All files** (default):
```
Target: .
```

**Specific file**:
```
Target: app/models/campaign.rb
```

**Specific directory**:
```
Target: app/services/tools
```

### Commit Behavior

By default, the skill commits changes automatically with this message format:
```
Fix RuboCop offenses

Auto-corrected linting issues

🤖 Generated with Claude Code
```

Disable commits with `commit=false` to review changes first.

### Results

**Success** - All auto-correctable offenses fixed:
- Code is RuboCop compliant
- Changes committed (if enabled)
- Ready to push

**Partial** - Some offenses remain:
- Auto-correctable issues fixed
- Manual fixes still needed
- Shows remaining offenses
- Provides guidance on common manual fixes

**No Changes** - Code already compliant:
- No offenses found
- Nothing to commit

### Common Manual Fixes

Some offenses cannot be auto-corrected:
- Complex code style issues
- Metrics violations (method length, class length, cyclomatic complexity)
- Security concerns flagged by RuboCop
- Disabled cops in specific files (rubocop:disable comments)

The skill provides a simplified offense list when manual fixes are needed.

## Examples

### Fix All Offenses (Safe Mode)

```
Use fixing-rubocop-offenses
```

**Flow**:
1. Checks entire codebase
2. Applies safe auto-correct
3. Commits changes
4. Shows summary

### Fix Specific File

```
Use fixing-rubocop-offenses with path=app/models/campaign.rb
```

**Flow**:
1. Checks only campaign.rb
2. Applies safe fixes to that file
3. Commits changes
4. Shows summary

### Fix Directory

```
Use fixing-rubocop-offenses with path=app/services/tools
```

**Flow**:
1. Checks all files in app/services/tools/
2. Applies safe fixes
3. Commits changes

### Unsafe Auto-Correct

```
Use fixing-rubocop-offenses with unsafe=true
```

**Flow**:
1. Runs with unsafe auto-correct (-A flag)
2. May change code behavior
3. Review changes carefully
4. Commits if requested

### Fix Without Committing

```
Use fixing-rubocop-offenses with commit=false
```

**Flow**:
1. Applies fixes
2. Shows changes
3. Does NOT commit
4. Allows manual review before commit

## Resources

- [RuboCop Common Fixes](resources/rubocop-common-fixes.md) - Quick reference for fixing common offenses
