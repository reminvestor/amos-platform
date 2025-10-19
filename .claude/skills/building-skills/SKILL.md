# Building Skills

Create and migrate Agent Skills to the proper Claude Code format.

## Description

This skill helps you create new Agent Skills or migrate existing YAML-based skills to the proper three-level Agent Skills format (metadata, instructions, resources). It follows best practices from the Claude Code documentation including progressive disclosure, concise instructions, and proper file organization.

**Use this skill when:**
- Creating a new custom skill
- Migrating YAML skills to proper format
- Updating existing skill documentation
- Organizing skill resources and scripts

## Instructions

### Agent Skills Format

Agent Skills use a three-level progressive disclosure system:

**Level 1: Metadata** (Always loaded, ~100 tokens)
- Name and description
- Helps Claude decide when to use the skill

**Level 2: Instructions** (Loaded when triggered, <5k tokens)
- Step-by-step guidance in SKILL.md
- Concise, focused on what Claude doesn't already know
- Written in third person for descriptions

**Level 3: Resources** (Loaded as needed)
- Scripts in `scripts/` directory
- Reference materials in `resources/` directory
- Executed without consuming context window

### Directory Structure

```
skill-name-skill/
├── SKILL.md              # Main instructions (Levels 1 & 2)
├── scripts/              # Executable bash scripts
│   ├── script1.sh
│   └── script2.sh
└── resources/            # Reference materials
    ├── reference1.md
    └── reference2.md
```

### Naming Conventions

- **Skill names**: Use gerund form (verb + -ing)
  - ✅ "Building Skills", "Running Tests", "Processing PDFs"
  - ❌ "Skill Builder", "Test Runner", "PDF Processor"

- **Directories**: Lowercase with hyphens, end with `-skill`
  - ✅ `building-skills-skill/`
  - ❌ `BuildSkills/` or `skill-builder/`

### SKILL.md Structure

```markdown
# Skill Name

Brief one-sentence summary.

## Description

2-3 paragraph description including:
- What the skill does
- When to use it
- Key capabilities

## Instructions

Detailed step-by-step instructions. Keep under 500 lines total.

### Section 1
...

### Section 2
...

## Examples

Concrete usage examples with expected inputs/outputs.

## Resources

Optional references to scripts/ and resources/ files.
```

### Best Practices

1. **Be Concise**
   - Only include what Claude doesn't already know
   - Challenge every sentence: "Does Claude really need this?"
   - Keep SKILL.md under 500 lines

2. **Progressive Disclosure**
   - Put detailed reference in resources/
   - Keep main instructions focused
   - Reference additional files only when needed

3. **Clear Instructions**
   - Write sequential steps
   - Include validation checkpoints
   - Provide concrete examples

4. **Executable Scripts**
   - Place in scripts/ directory
   - Make executable with `chmod +x`
   - Include error handling
   - Add descriptive comments

### Migration Process

When migrating from YAML format:

1. **Create Directory Structure**
   ```bash
   mkdir -p .claude/skills/{skill-name}-skill/{scripts,resources}
   ```

2. **Extract Components**
   - Metadata → SKILL.md header
   - Steps → SKILL.md instructions
   - Bash commands → scripts/*.sh files
   - Documentation → resources/*.md files

3. **Write SKILL.md**
   - Level 1: Name + description at top
   - Level 2: Instructions and examples
   - Level 3: References to scripts/resources

4. **Create Scripts**
   - Extract bash code blocks
   - Add error handling
   - Make executable

5. **Test the Skill**
   - Verify skill is discoverable
   - Test script execution
   - Validate instructions are clear

## Examples

### Creating a New Skill

```
Use building-skills skill to create new-feature-skill for deploying features
```

### Migrating an Existing Skill

```
Use building-skills skill to migrate .claude/skills/run-tests.yaml
```

### Updating Skill Documentation

```
Use building-skills skill to update running-tests-skill documentation
```

## Resources

- [Skill Template](resources/skill-template.md) - Blank skill template
- [Migration Script](scripts/migrate-yaml-skill.sh) - Automate YAML migration
- [Validation Script](scripts/validate-skill.sh) - Check skill format
