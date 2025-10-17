# Agent Skills Migration Status

## Overview

This document tracks the migration of custom YAML-based skills to the proper Claude Code Agent Skills format with three-level progressive disclosure (metadata, instructions, resources).

## Migration Progress

### ✅ Completed Migrations (6 of 15)

| Skill Name | Directory | Scripts | Resources | Notes |
|------------|-----------|---------|-----------|-------|
| Running Tests | `running-tests/` | 3 | 1 | Full test suite management |
| Building Skills | `building-skills/` | 2 | 1 | Meta-skill for creating/migrating |
| Starting Features | `starting-features/` | 3 | 1 | GitHub issue workflow with AMOS patterns |
| Managing Docker Development | `managing-docker-development/` | 3 | 0 | Complete Docker Compose management |
| Fixing RuboCop Offenses | `fixing-rubocop-offenses/` | 1 | 0 | Auto-fix linting (safe/unsafe modes) |
| **Running Workflows** | `running-workflows/` | 1 | 0 | **NEW**: Chains multiple skills together |

### 🔄 Pending Migrations (9 of 15)

| Skill Name | Priority | Complexity | YAML File | Target Directory |
|------------|----------|-----------|-----------|------------------|
| quick-commit | High | Low | `quick-commit.yaml` | `making-quick-commits/` |
| db-reset-demo | Medium | Low | `db-reset-demo.yaml` | `resetting-demo-database/` |
| db-snapshot | Medium | Low | `db-snapshot.yaml` | `managing-database-snapshots/` |
| check-health | Medium | Medium | `check-health.yaml` | `checking-application-health/` |
| cleanup-branch | Medium | Low | `cleanup-branch.yaml` | `cleaning-up-git-branches/` |
| check-deploy | Medium | High | `check-deploy.yaml` | `checking-deployments/` |
| fix-pr | Low | Medium | `fix-pr.yaml` | `fixing-pull-requests/` |
| explain-feature | Low | Low | `explain-feature.yaml` | `explaining-features/` |
| add-entity | Low | Medium | `add-entity.yaml` | `adding-entities/` |
| test-tool | Low | Low | `test-tool.yaml` | `testing-tools/` |
| test-workflow | Low | Medium | `test-workflow.yaml` | `testing-workflows/` |
| update-docs | Low | Low | `update-docs.yaml` | `updating-documentation/` |

**Note**: Directories have been created for all pending skills, only need SKILL.md + scripts extraction.

## Proper Agent Skills Format

### Directory Structure

```
skill-name/
├── SKILL.md              # Main instructions
├── scripts/              # Executable bash scripts
│   └── *.sh
└── resources/            # Reference materials
    └── *.md
```

### SKILL.md Three-Level Structure

**Level 1: Metadata** (~100 tokens, always loaded)
- Skill name (gerund form: "Running Tests", "Building Skills")
- One-sentence description
- When to use it

**Level 2: Instructions** (<5k tokens, loaded when triggered)
- Detailed step-by-step guidance
- Examples and usage patterns
- Troubleshooting

**Level 3: Resources** (loaded as needed)
- Scripts in scripts/ directory (executed, not in context)
- Reference docs in resources/ directory (loaded on demand)

### Naming Conventions

- **Skill names**: Gerund form (verb + -ing)
  - ✅ "Building Skills", "Running Tests", "Managing Docker Development"
  - ❌ "Skill Builder", "Test Runner", "Docker Manager"

- **Directories**: Lowercase with hyphens, NO -skill suffix
  - ✅ `building-skills/`, `running-tests/`, `managing-docker-development/`
  - ❌ `building-skills-skill/`, `BuildSkills/`, `build_skills/`

### Best Practices

1. **Be Concise** - Keep SKILL.md under 500 lines
2. **Progressive Disclosure** - Reference resources/ for details
3. **Clear Instructions** - Sequential steps with validation
4. **Executable Scripts** - Extract bash to scripts/, make executable

## Migration Tools

### Validate a Skill

```bash
.claude/skills/building-skills/scripts/validate-skill.sh .claude/skills/<skill-directory>
```

### Migrate from YAML

```bash
.claude/skills/building-skills/scripts/migrate-yaml-skill.sh .claude/skills/<yaml-file>
```

Or use Claude Code:
```
Use building-skills to migrate <yaml-file>
```

## New Feature: Running Workflows

The `running-workflows` skill provides predefined sequences of multiple skills:

- **feature-start** - Complete feature kickoff from GitHub issue
- **pre-commit** - Quality checks before committing (RuboCop + tests)
- **pre-deploy** - Deployment readiness validation
- **dev-reset** - Reset development environment completely
- **quality-check** - Comprehensive code quality audit
- **quick-pr** - Fast PR creation workflow

Example:
```
Use running-workflows with workflow=pre-commit
```

## Next Steps

1. **Immediate**: Migrate `quick-commit` (simple, frequently used)
2. **Short-term**: Migrate database skills (`db-reset-demo`, `db-snapshot`)
3. **Medium-term**: Migrate health/deploy check skills
4. **Long-term**: Migrate remaining documentation/testing skills
5. **Cleanup**: Archive old YAML files after migration complete

## References

- [Claude Code Agent Skills Documentation](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
- [Best Practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices)
- [Quickstart Guide](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/quickstart)
