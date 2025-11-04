# Validate Skill

Validate and test skill definitions for correctness.

## Description

Validates skill YAML definitions to ensure:
- Correct YAML syntax
- Required fields present
- Script files exist and are executable
- File paths valid
- Dependencies available
- No circular references
- Proper naming conventions

## When to Use

- Creating new skills
- Modifying existing skills
- Before committing skill changes
- Testing skill functionality
- Debugging skill issues
- CI/CD validation

## What Gets Validated

- ✅ YAML structure and syntax
- ✅ Required fields (name, description, etc)
- ✅ Script file existence
- ✅ Executable permissions
- ✅ Path references valid
- ✅ Commands exist
- ✅ Dependencies installed
- ✅ No naming conflicts

## Usage

```bash
.claude/skills/building-skills/scripts/validate-skill.sh
```

Prompts for:
1. Skill name or path
2. Full validation (deep check)
3. Fix issues automatically

## Output

- ✅ Valid fields
- ❌ Missing required fields
- ⚠️ Warnings and suggestions
- 📋 Fix recommendations
- 🔗 Links to documentation

## Related Commands

- `/migrate-skill` - Convert YAML to new format
- `/build-skill` - Create new skill template
