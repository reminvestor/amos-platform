# /rubocop Command

Fix RuboCop style and linting offenses.

## Usage

```
/rubocop [path]
```

## What This Command Does

Invokes the **Fixing RuboCop Offenses** skill to:
- ✅ Run RuboCop on specified files or entire project
- ✅ Auto-fix safe offenses
- ✅ Show remaining offenses that need manual fixing
- ✅ Generate offense reports
- ✅ Update RuboCop configuration if needed

## Examples

```
# Check and fix all files
/rubocop

# Fix specific file
/rubocop app/models/campaign.rb

# Check specific directory
/rubocop app/services
```

## Instructions

Use the Skill tool to invoke the `fixing-rubocop-offenses` skill to run RuboCop and fix offenses in the specified path or entire project.
