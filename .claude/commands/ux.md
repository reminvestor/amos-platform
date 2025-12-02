# /ux Command

Review UX implementation for the AMOS Rails application using the Rails UX Expert skill.

## Usage

```
/ux [file_path1] [file_path2] ...
```

Or paste code directly after the command.

## What This Command Does

Invokes the **Rails UX Expert** skill to analyze files or code snippets for:
- ✅ Rails ERB template best practices
- ✅ Dark theme utility class usage
- ✅ Stimulus controller patterns
- ✅ Accessibility (WCAG 2.1)
- ✅ AI chat interface UX (Scout-specific)
- ✅ Streaming response handling (SSE)
- ✅ Voice assistant UX patterns
- ✅ **NO inline styles** (except data-driven values)

## Examples

```
# Review Scout chat interface
/ux app/views/scout/index.html.erb

# Review page template
/ux app/views/admin/dashboard/index.html.erb

# Review stylesheet
/ux app/assets/stylesheets/admin_dark.scss

# Review Stimulus controller
/ux app/javascript/controllers/scout_controller.js

# Review multiple files
/ux app/views/scout/index.html.erb app/assets/stylesheets/scout.scss
```

## Instructions

When the user runs this command with file paths or code, use the Skill tool to invoke the `rails-ux-expert` skill to perform comprehensive UX analysis on the provided files or code snippets.
