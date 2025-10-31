# Rails UX Expert Skill

A Claude Code skill for analyzing and improving UX in the AMOS Rails 8 application.

## Usage

Invoke with `/ux` or `/ux-review` followed by file paths or code snippets:

```bash
# Review a template
/ux app/views/scout/index.html.erb

# Review stylesheet
/ux app/assets/stylesheets/scout.scss

# Review Stimulus controller
/ux app/javascript/controllers/scout_controller.js

# Review multiple files
/ux app/views/scout/index.html.erb app/assets/stylesheets/scout.scss
```

## What It Analyzes

- ✅ Rails ERB template best practices
- ✅ Bootstrap 5 component usage
- ✅ Stimulus controller patterns
- ✅ Accessibility (WCAG 2.1)
- ✅ AI chat interface UX (Scout-specific)
- ✅ Streaming response handling (SSE)
- ✅ Voice assistant UX
- ✅ Workflow progress visualization
- ✅ SCSS/CSS optimization
- ✅ Performance and loading states

## Focus Areas

### AI Agent Platform UX
- Scout chat interface patterns
- Streaming message updates
- Tool execution visibility
- Workflow phase progress
- Model watermark badges
- Thinking indicators

### Rails Best Practices
- Use of Rails helpers (`link_to`, `form_with`)
- Turbo Frame/Stream usage
- Bootstrap utility classes over custom CSS
- Proper Stimulus controller patterns
- Asset pipeline optimization

### Common Violations Detected
- Inline styles in ERB templates
- Hardcoded URLs instead of path helpers
- Custom CSS that could use Bootstrap utilities
- Missing ARIA labels on icon buttons
- Poor SSE error handling
- JavaScript inline style manipulation
- Accessibility issues

## Output Format

The skill provides:

1. **Critical Issues** - Functionality/accessibility blockers
2. **UX Improvements** - Better component choices, layout improvements
3. **Best Practices** - Rails/AI-specific patterns
4. **Bootstrap Recommendations** - Utility class suggestions

Each recommendation includes:
- Specific line numbers
- Before/after code examples
- Links to documentation
- Explanation of why it matters

## Tech Stack Context

This skill is specifically configured for:
- **Rails 8** with ERB templates
- **Bootstrap 5** (not custom themes)
- **Turbo/Stimulus** (not React/Vue)
- **AWS Bedrock Claude** for AI
- **Server-Sent Events** for streaming
- **Action Cable** for WebSockets
- **Lucide Icons** (preferred) + Font Awesome (legacy)

## Related Documentation

- Main project guide: `CLAUDE.md`
- UX improvements needed: `docs/UX_IMPROVEMENTS_NEEDED.md`
- Implementing UX designs: `.claude/skills/implementing-ux-designs/`

## Examples

### Example 1: Review Scout Chat Interface

```bash
/ux app/views/scout/index.html.erb
```

Output might include:
- "Replace Font Awesome robot icon with Lucide bot icon for modern look"
- "Add `aria-label` to mic button for screen readers"
- "Use `spinner-border spinner-border-sm` for thinking indicator"
- "Replace inline `style='display: none'` with Bootstrap `d-none` class"

### Example 2: Review Stylesheet

```bash
/ux app/assets/stylesheets/scout.scss
```

Output might include:
- "Replace hardcoded `#6c757d` with Bootstrap variable `$text-muted`"
- "Use Bootstrap spacing utility `mt-3` instead of `margin-top: 1rem`"
- "Reduce SCSS nesting from 4 levels to max 3"

### Example 3: Review Stimulus Controller

```bash
/ux app/javascript/controllers/voice_assistant_controller.js
```

Output might include:
- "Use `this.element.classList.toggle('active')` instead of inline style"
- "Add proper error handling for EventSource connection failures"
- "Extract magic number (500ms) to Stimulus value for configurability"

## Notes

- The skill prioritizes **Bootstrap utilities** over custom CSS
- Focus is on **accessibility** (WCAG 2.1 compliance)
- Specific to **AI agent platform UX patterns** (not generic Rails)
- Updated for **Rails 8** conventions (not older Rails versions)
