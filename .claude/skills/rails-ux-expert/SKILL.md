# Rails UX Expert Skill

**Command**: `/ux` or `/ux-review`

Provides UX analysis and recommendations specifically for the AMOS AI agent platform built with Rails 8.

---

## APPLICATION CONTEXT

- **Name**: AMOS (Agent Marketing Operating System)
- **Purpose**: Conversational AI platform for orchestrating workflows via AWS Bedrock Claude
- **User Base**: Marketers, business users, developers using AI agents
- **Key Features**: Scout chat interface, workflow execution, AI tool orchestration, landing page generation, campaign management, RAG document library, voice assistant

## TECH STACK

### Backend & Templates:
- **Rails 8** with **ERB templates** (primary rendering)
- PostgreSQL database with ActiveRecord ORM
- Devise for authentication
- AWS Bedrock (Claude Sonnet 4.5) for AI processing
- SolidQueue for background jobs
- Action Cable for WebSocket streaming (voice assistant)
- Docker development environment

### Frontend:
- **Server-side rendering**: ERB templates with Turbo/Stimulus for interactivity
- **Streaming**: Server-Sent Events (SSE) for chat streaming
- Bootstrap 5 (via importmaps and Sprockets)
- esbuild for JavaScript bundling
- Lucide Icons (modern) + Font Awesome (legacy)
- SCSS compilation via Propshaft
- Stimulus controllers for interactive components

**Note**: This is primarily a Rails/Turbo app with selective Stimulus controllers for interactivity.

## DESIGN SYSTEM

### Color Palette
Based on Bootstrap 5 with custom overrides:
- Primary: Bootstrap primary (blue shades)
- Success: `#28a745`
- Warning: `#ffc107`
- Danger: `#dc3545`
- Muted text: `#6c757d`
- Background: White/light gray (default Bootstrap theme)
- Cards/surfaces: White with borders

### Layout
- **Theme**: Light theme (Bootstrap default)
- **Scout Interface**: Full-height chat interface with sidebar
- **Responsive**: Bootstrap grid system (container-fluid)
- **Typography**: System font stack (Bootstrap default)
- **Mobile**: Responsive with Bootstrap utilities

### Stylesheet Architecture
```
app/assets/stylesheets/
├── application.css              # Manifest file
├── application.scss             # Base Rails styles
├── application.bootstrap.scss   # Bootstrap overrides
├── scout.scss                   # Scout chat interface (22KB+)
├── toast.scss                   # Toast notifications
├── marketing_home.scss          # Public homepage
├── actiontext.css               # Rich text editor
└── trix.css                     # Trix editor styles
```

## YOUR TASK

When I use `/ux` or `/ux-review` followed by a file path or code snippet, analyze it for:

### 1. **Rails Template Best Practices** (ERB)
   - Proper use of Rails helpers (`link_to`, `form_with`, `content_for`)
   - Turbo Frame/Stream usage for dynamic updates
   - Bootstrap 5 component implementation
   - Grid system usage (`container`, `row`, `col-*`)
   - Spacing utilities (`mt-*`, `mb-*`, `p-*`) consistency
   - Form components (`form-control`, `form-label`, `was-validated`)
   - Modal implementations with proper data attributes
   - Navigation patterns (navbar, breadcrumbs)
   - Button hierarchy (`btn-primary` vs `btn-secondary`)
   - Alert/toast messaging with Bootstrap

### 2. **Stimulus Controller Patterns**
   - Proper controller setup (targets, values, actions)
   - Event handling and delegation
   - CSS class toggling vs inline styles
   - DOM manipulation best practices
   - Connection to Rails conventions
   - Data attribute usage (`data-controller`, `data-action`)
   - Lifecycle callbacks (connect, disconnect)

### 3. **AI Chat Interface UX** (Scout-specific)
   - Clear visual hierarchy for messages
   - User vs assistant message differentiation
   - Streaming message updates (SSE handling)
   - Thinking indicators during AI processing
   - Tool execution visibility (progress updates)
   - Workflow phase progress display
   - Transient message handling (fade after completion)
   - Model watermark badges (showing which Claude model was used)
   - Message avatars (user vs bot icons)
   - Scroll behavior (auto-scroll to latest message)
   - Loading states for file uploads
   - Error handling and retry mechanisms

### 4. **Icon and Visual Elements**
   - Lucide Icons (modern, preferred) vs Font Awesome (legacy)
   - Icon + text combinations for clarity
   - Loading states (`spinner-border` for processing)
   - Visual feedback for selections
   - Consistent icon sizing and colors
   - Proper icon initialization (`lucide.createIcons()`)

### 5. **Rails-Specific UX Patterns**
   - Flash message integration with Bootstrap alerts
   - Form validation (server-side + Bootstrap's `was-validated`)
   - Error handling with user-friendly error pages
   - Redirect flows after form submissions
   - Turbo Frame error handling
   - Asset pipeline usage (Sprockets + esbuild)
   - Multi-tenancy (entity scoping) in UI

### 6. **Streaming and Real-Time UX**
   - Server-Sent Events (SSE) implementation
   - EventSource error handling and reconnection
   - Streaming message append vs replace
   - Canvas loading (dynamic UI components)
   - Action Cable WebSocket connections (voice assistant)
   - Real-time transcript display
   - Audio streaming feedback

### 7. **AI Features UX**
   - Clear indication of AI-generated content
   - Workflow progress visualization
   - Phase execution feedback (gather context → execute → validate)
   - Tool usage transparency (which tools were called)
   - Model selection UI (dropdown for Claude models)
   - Token usage and cost display (optional)
   - Thinking indicators (animated dots)
   - Transient progress messages (fade after completion)
   - Error recovery flows for failed AI operations

### 8. **Accessibility (WCAG 2.1)**
   - Semantic HTML5 elements
   - ARIA labels (especially for icon-only buttons)
   - Keyboard navigation (tab order, focus states)
   - Color contrast (minimum 4.5:1 for text)
   - Form labels and error associations
   - Skip links and landmark regions
   - Alt text for images
   - Screen reader-friendly dynamic updates

### 9. **SCSS/CSS Review**
   - Use of Bootstrap variables and mixins
   - Avoid hardcoded colors (use Bootstrap theme colors)
   - Check consistency with Bootstrap utilities
   - Identify specificity issues
   - Suggest Bootstrap utilities before custom CSS
   - Proper SCSS nesting (max 3 levels deep)
   - CSS variable usage for theming

### 10. **Performance and Loading States**
   - Proper loading indicators for async operations
   - Skeleton screens vs spinners
   - Image lazy loading
   - Turbo Frame lazy loading
   - Minimize layout shifts (CLS)
   - Smooth transitions and animations
   - Debouncing user input

## OUTPUT FORMAT

Provide your analysis in this structure:

### 1. **Critical Issues** (breaks functionality or accessibility)
   - Specific line numbers/code snippets
   - Bootstrap component misuse
   - Accessibility blockers (contrast, missing labels)
   - Rails anti-patterns
   - Security concerns (XSS, CSRF)

### 2. **UX Improvements** (usability for AI agent platform)
   - Better Bootstrap component choices
   - Improved spacing/layout with Bootstrap utilities
   - Enhanced visual feedback for AI operations
   - Streaming message handling improvements
   - Code examples (before/after)

### 3. **Best Practices** (Rails/AI-specific)
   - Consistent icon usage (Lucide preferred)
   - Better use of Bootstrap's utility classes
   - SCSS optimization
   - Mobile-first responsive improvements
   - Stimulus controller patterns
   - Turbo Frame/Stream usage

### 4. **Bootstrap-Specific Recommendations**
   - Suggest appropriate Bootstrap 5 components
   - Show utility class combinations instead of custom CSS
   - Reference Bootstrap documentation
   - Avoid deprecated patterns

## EXAMPLE INSIGHTS TO PROVIDE

- "Use `btn btn-primary` instead of custom button styles"
- "Replace `margin-left: 20px` with Bootstrap's `ms-3` utility class"
- "This inline style should use Bootstrap utility class `text-muted`"
- "Font Awesome icons without text need `aria-label` for screen readers"
- "AI-generated content should have clear visual indicator (e.g., bot icon + model badge)"
- "Streaming messages need proper SSE error handling and reconnection logic"
- "This modal is missing `data-bs-dismiss` attribute for close button"
- "Form needs `novalidate` on `<form>` tag for Bootstrap validation"
- "Thinking indicator should use Bootstrap spinner: `spinner-border spinner-border-sm`"
- "Replace Font Awesome icon with Lucide for modern look: `<i data-lucide='bot'></i>`"
- "Stimulus controller should use `this.element.classList.toggle()` instead of inline styles"
- "ERB should use `link_to` helper instead of raw `<a>` tags"
- "Use Turbo Frame for dynamic content loading instead of full page reload"

## AI AGENT PLATFORM-SPECIFIC PATTERNS TO VALIDATE

### Scout Chat Interface
- User messages aligned right, assistant messages aligned left
- Clear visual differentiation (background colors, avatars)
- Model watermark badges showing which Claude model responded
- Thinking indicators during AI processing (animated dots)
- Tool execution feedback (e.g., "🔧 Creating landing page...")
- Workflow phase progress (e.g., "🔄 Gathering context...")
- Transient messages that fade after completion
- Proper scroll behavior (auto-scroll to latest)

### Streaming Response Handling
- EventSource connection with error handling
- Reconnection logic for dropped connections
- Message chunking (append vs replace)
- Canvas loading for dynamic UI components
- Status indicators (connecting, streaming, complete)

### AI Tool Visibility
- Tool start/end indicators in chat
- Progress messages for long-running operations
- Error handling with user-friendly messages
- Retry mechanisms for failed tool calls
- Clear separation of AI actions vs human input

### Voice Assistant UX
- Mic button states (idle, listening, processing)
- Real-time transcript display (interim vs final)
- Audio streaming feedback
- Wake word detection indicators
- Continuous listening mode visuals
- Error states (mic permission denied, connection lost)

### Multi-Tenant UI
- Entity scoping is invisible to users
- No entity_id in URLs (handled in backend)
- User sees only their entity's data
- Admin controls only for admin role

### Workflow Progress Visualization
- Phase-based progress display (3 phases: gather, execute, validate)
- Clear success/failure indicators
- Validation error reporting with actionable feedback
- Auto-retry mechanisms with user notification

## USAGE EXAMPLES

```bash
# Review a specific template
/ux app/views/scout/index.html.erb

# Review multiple related files
/ux app/views/scout/index.html.erb app/assets/stylesheets/scout.scss

# Review a Stimulus controller
/ux app/javascript/controllers/scout_controller.js

# Quick review with inline code
/ux
<paste code snippet>
```

---

## COMMON RAILS UX VIOLATIONS

### 1. **Inline Styles in ERB**
```erb
<!-- ❌ Bad -->
<div style="color: #0FC2C0; margin: 20px;">Text</div>

<!-- ✅ Good -->
<div class="text-primary ms-3">Text</div>
```

### 2. **Not Using Rails Helpers**
```erb
<!-- ❌ Bad -->
<a href="/scout">Scout</a>

<!-- ✅ Good -->
<%= link_to 'Scout', scout_path, class: 'btn btn-primary' %>
```

### 3. **Hardcoded URLs**
```erb
<!-- ❌ Bad -->
<form action="/scout/chat" method="post">

<!-- ✅ Good -->
<%= form_with url: chat_scout_path, method: :post do |f| %>
```

### 4. **JavaScript Inline Styles (Stimulus)**
```javascript
// ❌ Bad
this.element.style.color = '#FFFFFF';
this.element.style.display = 'none';

// ✅ Good
this.element.classList.add('text-white');
this.element.classList.add('d-none');
```

### 5. **Missing ARIA Labels**
```erb
<!-- ❌ Bad -->
<button><i data-lucide="mic"></i></button>

<!-- ✅ Good -->
<button aria-label="Start voice recording">
  <i data-lucide="mic"></i>
</button>
```

### 6. **Not Using Turbo Frames**
```erb
<!-- ❌ Bad: Full page reload for dynamic content -->
<div id="results">
  <%= render partial: 'results' %>
</div>

<!-- ✅ Good: Turbo Frame for partial updates -->
<%= turbo_frame_tag 'results' do %>
  <%= render partial: 'results' %>
<% end %>
```

### 7. **Poor SSE Error Handling**
```javascript
// ❌ Bad
const eventSource = new EventSource('/stream');

// ✅ Good
const eventSource = new EventSource('/stream');
eventSource.onerror = (error) => {
  console.error('SSE error:', error);
  eventSource.close();
  showReconnectUI();
};
```

---

## RAILS + BOOTSTRAP UTILITY REFERENCE

### Spacing (use these instead of custom CSS)
- `m-{0-5}` - margin (0.25rem to 3rem)
- `p-{0-5}` - padding
- `mt-*`, `mb-*`, `ms-*`, `me-*` - margin top/bottom/start/end
- `gap-{1-5}` - flexbox/grid gap

### Colors
- `text-primary`, `text-secondary`, `text-success`, `text-danger`, `text-muted`
- `bg-primary`, `bg-light`, `bg-white`
- `border-primary`, `border-secondary`

### Display
- `d-none`, `d-block`, `d-flex`, `d-grid`
- `d-{sm|md|lg|xl}-{none|block|flex}` - responsive display

### Flexbox
- `d-flex`, `align-items-center`, `justify-content-between`
- `flex-grow-1`, `flex-shrink-0`

### Typography
- `fs-{1-6}` - font size
- `fw-{light|normal|bold}` - font weight
- `text-{start|center|end}` - text alignment

---

## RAILS DEVELOPMENT WORKFLOW

### Adding New UI Components

1. **Create ERB template** in `app/views/`
2. **Add SCSS** to appropriate file in `app/assets/stylesheets/`
3. **Add Stimulus controller** (if needed) in `app/javascript/controllers/`
4. **Use Bootstrap utilities** first, custom CSS only when necessary
5. **Test responsive behavior** at breakpoints (sm, md, lg, xl)
6. **Verify accessibility** (keyboard nav, screen reader, contrast)

### Testing UX Changes

```bash
# Start dev server (Rails + assets)
bin/dev

# Run tests
docker compose exec web rails test

# Check for JavaScript errors in browser console
# Test on mobile device or browser dev tools
# Verify WCAG compliance with Lighthouse
```

---

## REFERENCES

- **Bootstrap 5 Docs**: https://getbootstrap.com/docs/5.3/
- **Turbo Handbook**: https://turbo.hotwired.dev/
- **Stimulus Handbook**: https://stimulus.hotwired.dev/
- **Rails Guides**: https://guides.rubyonrails.org/
- **Lucide Icons**: https://lucide.dev/icons/
- **WCAG Guidelines**: https://www.w3.org/WAI/WCAG21/quickref/
- **Project UX Improvements**: `docs/UX_IMPROVEMENTS_NEEDED.md`

---

**Remember**: Always prioritize Bootstrap utilities over custom CSS, accessibility compliance, and clear AI operation feedback for users.
