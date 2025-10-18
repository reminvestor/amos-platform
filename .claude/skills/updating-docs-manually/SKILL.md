# Updating Docs Manually

Auto-update documentation based on code changes.

## Description

This skill automatically syncs code changes with documentation files. It generates up-to-date documentation for Scout AI tools, workflow templates, and Rails models by inspecting the codebase and producing formatted markdown files.

**Use this skill when:**
- Tools have been added or modified
- Workflow templates have changed
- Model schema or relationships updated
- Documentation is out of sync with code

## Instructions

### Documentation Scope

The skill can update three main documentation areas:

**1. Scout Tools** (`docs/SCOUT_TOOLS.md`)
- Auto-generates from `app/services/tools/` directory
- Lists all available tools with descriptions and parameters
- Includes file references and usage guidance

**2. Workflow Templates** (`docs/WORKFLOW_TEMPLATES.md`)
- Scans `app/workflow_templates/*_v2.yml` files
- Documents phases, keywords, and descriptions
- Provides creation guidance

**3. Models** (`docs/MODELS_REFERENCE.md`)
- Inspects ActiveRecord models
- Documents associations, validations, and table names
- Includes entity scoping pattern

### Update Process

1. **Determine Scope**
   - Choose specific area (tools, workflows, models)
   - Or update all documentation
   - Interactive mode prompts for choice

2. **Generate Documentation**
   - Runs Rails runner scripts to introspect code
   - Formats output as markdown
   - Updates timestamp

3. **Review Changes**
   - Shows git diff of updated files
   - Indicates what was modified

4. **Optional Commit**
   - Can automatically commit changes
   - Uses standardized commit message
   - Includes Claude Code attribution

### Usage Patterns

**Interactive Mode:**
```
Use updating-docs-manually
```
Prompts for which documentation to update.

**Update All:**
```
Use updating-docs-manually with scope=all
```

**Update Specific Area:**
```
Use updating-docs-manually with scope=tools
Use updating-docs-manually with scope=workflows
Use updating-docs-manually with scope=models
```

**Preview Without Committing:**
```
Use updating-docs-manually with scope=all commit=false
```

### Parameters

- `scope` - What to update: `tools`, `workflows`, `models`, `all`, or `ask` (default: `ask`)
- `commit` - Commit changes after updating: `true` or `false` (default: `true`)

## Examples

### Update All Documentation

```
Use updating-docs-manually with scope=all
```

Generates/updates:
- `docs/SCOUT_TOOLS.md`
- `docs/WORKFLOW_TEMPLATES.md`
- `docs/MODELS_REFERENCE.md`

Then commits changes automatically.

### Review Changes Without Committing

```
Use updating-docs-manually with scope=all commit=false
```

Updates documentation files but doesn't commit. Allows manual review before committing.

### Update Only Tools Documentation

```
Use updating-docs-manually with scope=tools
```

Updates only `docs/SCOUT_TOOLS.md` based on current tools in `app/services/tools/`.

## Resources

- [Update Script](scripts/update-docs.sh) - Main documentation update script
