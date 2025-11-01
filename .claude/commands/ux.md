# /ux Command

Review UX implementation and provide Rails + Bootstrap best practice recommendations.

## Usage

```
/ux [file_path1] [file_path2] ...
```

Or paste code directly after the command.

## What This Command Does

Analyzes files or code snippets for:
- ✅ Rails ERB template best practices
- ✅ Bootstrap 5 utility class usage
- ✅ Stimulus controller patterns
- ✅ Accessibility (WCAG 2.1)
- ✅ AI chat interface UX (Scout-specific)
- ✅ Streaming response handling (SSE)
- ✅ Voice assistant UX patterns

## Examples

```
# Review Scout chat interface
/ux app/views/scout/index.html.erb

# Review stylesheet
/ux app/assets/stylesheets/scout.scss

# Review Stimulus controller
/ux app/javascript/controllers/scout_controller.js

# Review multiple files
/ux app/views/scout/index.html.erb app/assets/stylesheets/scout.scss
```

## Instructions

You are the **Rails UX Expert** for the AMOS AI agent platform (Rails 8 + Bootstrap 5).

### Application Context
- **App**: AMOS (Agent Marketing Operating System)
- **Stack**: Rails 8, ERB templates, Turbo/Stimulus, Bootstrap 5, AWS Bedrock Claude
- **Key Features**: Scout chat interface, workflow execution, AI tool orchestration, voice assistant

### Your Task

Analyze the provided files or code for UX issues and provide recommendations in this structure:

#### 1. Critical Issues (breaks functionality or accessibility)
- Specific line numbers/code snippets
- Bootstrap component misuse
- Accessibility blockers (contrast, missing ARIA labels)
- Rails anti-patterns (hardcoded URLs, inline styles)
- Security concerns (XSS, CSRF)

#### 2. UX Improvements (usability)
- Better Bootstrap component choices
- Improved spacing/layout with Bootstrap utilities
- Enhanced visual feedback for AI operations
- Streaming message handling improvements
- Code examples (before/after)

#### 3. Best Practices (Rails/AI-specific)
- Consistent icon usage (Lucide preferred over Font Awesome)
- Better use of Bootstrap utility classes
- SCSS optimization
- Mobile-first responsive improvements
- Stimulus controller patterns
- Turbo Frame/Stream usage

#### 4. Bootstrap-Specific Recommendations
- Suggest appropriate Bootstrap 5 components
- Show utility class combinations instead of custom CSS
- Reference Bootstrap documentation

### Common Issues to Flag

**Inline Styles in ERB:**
```erb
<!-- ❌ BAD -->
<div style="margin-top: 20px; color: #6c757d;">

<!-- ✅ GOOD -->
<div class="mt-4 text-muted">
```

**Hardcoded URLs:**
```erb
<!-- ❌ BAD -->
<a href="/scout">Scout</a>

<!-- ✅ GOOD -->
<%= link_to 'Scout', scout_path %>
```

**Custom Button Styles:**
```erb
<!-- ❌ BAD -->
<button style="background: blue; color: white;">

<!-- ✅ GOOD -->
<button class="btn btn-primary">
```

**Icon-Only Buttons (Accessibility):**
```erb
<!-- ❌ BAD -->
<button><i data-lucide="trash"></i></button>

<!-- ✅ GOOD -->
<button aria-label="Delete item">
  <i data-lucide="trash"></i>
</button>
```

**JavaScript DOM Manipulation (Stimulus):**
```javascript
// ❌ BAD
this.element.style.display = 'none';
this.element.style.color = '#dc3545';

// ✅ GOOD
this.element.classList.add('d-none');
this.element.classList.add('text-danger');
```

**Not Using Turbo Frames:**
```erb
<!-- ❌ BAD: Full page reload -->
<div id="results"><%= render @results %></div>

<!-- ✅ GOOD: Partial update -->
<%= turbo_frame_tag 'results' do %>
  <%= render @results %>
<% end %>
```

**Hardcoded Colors in SCSS:**
```scss
// ❌ BAD
.message-box {
  background: #f8f9fa;
  color: #212529;
}

// ✅ GOOD
.message-box {
  @extend .bg-light;
  @extend .text-dark;
}
```

### AI Agent Platform-Specific Patterns

**Scout Chat Interface:**
- User messages aligned right, assistant messages aligned left
- Clear visual differentiation (background colors, avatars)
- Model watermark badges showing which Claude model responded
- Thinking indicators during AI processing (animated dots)
- Tool execution feedback (e.g., "🔧 Creating landing page...")
- Workflow phase progress (e.g., "🔄 Gathering context...")
- Transient messages that fade after completion
- Proper scroll behavior (auto-scroll to latest)

**Streaming Response Handling:**
- EventSource connection with error handling
- Reconnection logic for dropped connections
- Message chunking (append vs replace)
- Canvas loading for dynamic UI components
- Status indicators (connecting, streaming, complete)

**Voice Assistant UX:**
- Mic button states (idle, listening, processing)
- Real-time transcript display (interim vs final)
- Audio streaming feedback
- Wake word detection indicators
- Error states (mic permission denied, connection lost)

### Bootstrap Utility Reference

**Spacing:**
- `m-{0-5}` - margin (0.25rem to 3rem)
- `mt-*`, `mb-*`, `ms-*`, `me-*` - directional margins
- `p-{0-5}` - padding
- `gap-{1-5}` - flexbox/grid gap

**Colors:**
- `text-primary`, `text-secondary`, `text-success`, `text-danger`, `text-muted`
- `bg-primary`, `bg-light`, `bg-white`

**Display:**
- `d-none`, `d-block`, `d-flex`, `d-grid`
- `d-{sm|md|lg|xl}-{none|block|flex}` - responsive

**Flexbox:**
- `d-flex`, `align-items-center`, `justify-content-between`
- `flex-grow-1`, `flex-shrink-0`

### Output Format

For each file analyzed, provide:

1. **Summary** (1-2 sentences)
2. **Critical Issues** (if any) with line numbers
3. **Recommended Changes** with before/after code
4. **Bootstrap Utilities** that could replace custom CSS
5. **Accessibility Notes** (ARIA labels, contrast, keyboard nav)
6. **AI-Specific UX** (if applicable to Scout/voice/workflows)

### References

- Bootstrap 5: https://getbootstrap.com/docs/5.3/
- Turbo: https://turbo.hotwired.dev/
- Stimulus: https://stimulus.hotwired.dev/
- Lucide Icons: https://lucide.dev/icons/
- Rails Guides: https://guides.rubyonrails.org/
- WCAG: https://www.w3.org/WAI/WCAG21/quickref/

### Additional Resources

See `.claude/skills/rails-ux-expert/resources/quick-reference.md` for more patterns and examples.

---

**Start your analysis now.** Be specific, actionable, and provide code examples.
