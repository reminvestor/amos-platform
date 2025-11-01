# Migration from Flask UX Expert to Rails UX Expert

## What Changed

### Application Context
- **Old**: SmileWise dental treatment planning app (Flask)
- **New**: AMOS AI agent platform (Rails 8)

### Tech Stack Updates

| Component | Flask Skill | Rails Skill |
|-----------|-------------|-------------|
| **Backend** | Flask + Jinja2 | Rails 8 + ERB |
| **Database** | PostgreSQL + SQLAlchemy | PostgreSQL + ActiveRecord |
| **Auth** | Flask-Login | Devise |
| **AI** | OpenAI API (gpt-4o-mini) | AWS Bedrock (Claude Sonnet 4.5) |
| **Jobs** | N/A | SolidQueue |
| **Frontend** | Jinja2 + selective React | ERB + Turbo/Stimulus |
| **CSS** | Custom dark theme | Bootstrap 5 (light theme) |
| **Icons** | Font Awesome 6.0 | Lucide (preferred) + Font Awesome (legacy) |
| **Streaming** | N/A | Server-Sent Events (SSE) + Action Cable |
| **Bundler** | N/A | esbuild + Sprockets |

### Focus Area Changes

#### Removed (Flask/Dental-specific)
- Dark theme compliance (custom color palette)
- 3D dental model visualization patterns
- Medical/dental UI patterns (PHI, tooth numbering, treatment plans)
- React 3D viewer integration
- Clinical data presentation

#### Added (Rails/AI Agent-specific)
- Rails helper usage (`link_to`, `form_with`, path helpers)
- Turbo Frame/Stream patterns
- Stimulus controller best practices
- Scout chat interface UX
- AI streaming response handling (SSE)
- Workflow progress visualization
- Tool execution visibility
- Model watermark badges
- Voice assistant UX (Action Cable)
- Multi-tenant entity scoping

### UX Pattern Changes

#### Template Rendering
```python
# Flask (Jinja2)
{{ url_for('static', filename='css/page.css') }}
{% if user.is_authenticated %}
```

```erb
# Rails (ERB)
<%= stylesheet_link_tag 'page' %>
<% if user_signed_in? %>
```

#### Styling Approach
```css
/* Flask: Custom dark theme */
background: #2A2A2A;
color: #FFFFFF;
border: 1px solid #555555;
```

```html
<!-- Rails: Bootstrap utilities -->
<div class="bg-light text-dark border">
```

#### Form Handling
```html
<!-- Flask -->
<form action="{{ url_for('treatment.create') }}" method="POST">
  {{ form.csrf_token }}
```

```erb
<!-- Rails -->
<%= form_with url: create_treatment_path, method: :post do |f| %>
```

### New UX Concerns

#### AI Agent Platform Specific
1. **Streaming Messages**: SSE event handling, reconnection logic
2. **Workflow Progress**: 3-phase visualization (gather, execute, validate)
3. **Tool Transparency**: Show which tools AI is using
4. **Model Selection**: Dropdown for Claude model selection
5. **Voice Assistant**: Real-time audio streaming feedback
6. **Thinking Indicators**: Animated dots during AI processing
7. **Transient Messages**: Progress updates that fade

#### Rails Conventions
1. **Asset Pipeline**: Sprockets + esbuild, not static file serving
2. **Turbo**: Partial page updates without JavaScript
3. **Stimulus**: Progressive enhancement, not SPA components
4. **Path Helpers**: Use `scout_path` not hardcoded `/scout`
5. **Flash Messages**: Rails flash with Bootstrap alert integration

## Validation Script Comparison

### Flask Skill
- `scripts/validate-ux.sh` - 7 violation types
- Focus: Dark theme compliance, embedded styles, inline colors
- Exit code: 0 = pass, 1 = violations

### Rails Skill
- No automated script yet (opportunity for future work)
- Manual review using `/ux` skill
- Focus: Bootstrap utility usage, Rails helpers, accessibility

## Usage Comparison

### Flask Skill
```bash
/ux templates/ai_treatment_review.html static/css/treatment.css
```
Output focused on:
- Dark theme violations
- Bootstrap 5.3 dark overrides
- Medical data presentation
- 3D viewer integration

### Rails Skill
```bash
/ux app/views/scout/index.html.erb app/assets/stylesheets/scout.scss
```
Output focuses on:
- Bootstrap utility class usage
- Rails helper adoption
- SSE streaming patterns
- AI operation visibility

## Recommendations for Further Customization

### Add to Rails Skill
1. **Validation Script**: Create `scripts/validate-rails-ux.sh` to check:
   - Inline styles in ERB
   - Hardcoded URLs instead of path helpers
   - Missing ARIA labels
   - Custom CSS that could use Bootstrap utilities

2. **AI-Specific Patterns Library**: Document reusable patterns:
   - Thinking indicator component
   - Transient message handling
   - SSE reconnection logic
   - Model watermark badge

3. **Turbo/Stimulus Checklist**: Add validation for:
   - Proper Turbo Frame usage
   - Stimulus controller conventions
   - Data attribute patterns
   - Event delegation best practices

4. **Accessibility Testing**: Integrate:
   - Axe DevTools checks
   - Lighthouse audit scores
   - Keyboard navigation testing
   - Screen reader compatibility

## Migration Checklist

If migrating another Flask skill to Rails:

- [ ] Update application context (name, purpose, users)
- [ ] Change template syntax (Jinja2 → ERB)
- [ ] Replace Flask helpers with Rails helpers
- [ ] Update CSS approach (custom theme → Bootstrap utilities)
- [ ] Change icon library references (if applicable)
- [ ] Update form handling patterns
- [ ] Add Turbo/Stimulus patterns
- [ ] Replace static file references with asset pipeline
- [ ] Update validation scripts and tools
- [ ] Test skill with actual project files

## Archived Files

Old Flask skill preserved at:
```
.claude/skills/flask-ux-expert.archived/
```

Can be restored if needed for reference or future Flask projects.
