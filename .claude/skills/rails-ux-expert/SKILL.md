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

**Dark Theme (Application-wide):**
```scss
$admin-bg-primary: #0A0E1A;      // Main background
$admin-bg-secondary: #1A1F35;    // Card backgrounds
$admin-bg-tertiary: #0F172A;     // Sidebar background
$admin-border: #1E293B;          // Borders
$admin-text-primary: #FFFFFF;    // Primary text
$admin-text-secondary: #94A3B8;  // Secondary text (slate-400)
$admin-text-muted: #64748B;      // Muted text (slate-500)
$admin-accent-start: #7C3AED;    // Purple gradient start
$admin-accent-end: #A78BFA;      // Purple gradient end
$admin-cyan: #22D3EE;            // Cyan accent
```

**Note**: Entire app uses dark theme with purple/cyan gradient accents.

### Layout
- **Theme**: Dark theme throughout the application
- **Accents**: Purple gradient (#7C3AED → #A78BFA) and cyan (#22D3EE)
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
├── admin_dark.scss              # Admin dark theme (1460+ lines)
├── admin/
│   ├── _variables.scss          # Dark theme variables
│   └── _utilities.scss          # Utility classes
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

<!-- ✅ Good - Use utility classes -->
<div class="admin-text-cyan admin-mb-lg">Text</div>
```

**Exception**: Data-driven values (e.g., `width: <%= percentage %>%`) are acceptable when values come from database/calculations.

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

## DARK THEME PATTERNS

### Available Utility Classes

Use these utility classes instead of inline styles throughout the application:

**Layout:**
- `.admin-dark` - Apply to `<body>` for dark theme
- `.admin-content` - Main content area (auto-adjusts for sidebar)
- `.admin-card` - Card component with dark background
- `.admin-page-header` - Page header with icon + title

**Typography:**
- `.admin-text-cyan` - Cyan accent color (#22D3EE)
- `.admin-text-error` - Error text color
- `.admin-text-right` - Right-aligned text
- `.admin-stat-label` - Stat card label styling
- `.admin-stat-value` - Stat card value styling

**Spacing:**
- `.admin-p-xl` / `.admin-p-lg` - Padding utilities
- `.admin-mb-xl` / `.admin-mb-lg` / `.admin-mt-xl` - Margin utilities

**Components:**
- `.admin-btn` / `.admin-btn-primary` / `.admin-btn-outline` / `.admin-btn-danger` / `.admin-btn-sm`
- `.admin-badge` / `.admin-badge-online` / `.admin-badge-offline` / `.admin-badge-warning` / `.admin-badge-cyan`
- `.admin-table` - Dark themed table
- `.admin-tabs` / `.admin-tab` / `.admin-tab-active` - Tab navigation
- `.admin-alert` / `.admin-alert-error` / `.admin-alert-success` - Alert banners
- `.admin-empty-state` - Empty state component
- `.admin-icon-sm` / `.admin-icon-md` / `.admin-icon-lg` / `.admin-icon-xl` - Icon sizing

**Grids:**
- `.admin-stats-grid` - Grid for stat cards (auto-fit, minmax(200px, 1fr))
- `.admin-content-grid` - Grid for content cards (auto-fit, minmax(400px, 1fr))

**Icons:**
- `.admin-stat-icon` - Stat card icon container
  - `.purple-gradient` / `.success` / `.error` / `.warning` / `.info` - Color variants

### Admin Helper Methods

Use these helpers instead of manual HTML:

```ruby
# Status badges with automatic color mapping
<%= admin_status_badge('active') %>  # Returns styled badge
<%= admin_status_badge('failed', 'Error') %>  # Custom text

# Type badges with custom mapping
<%= admin_type_badge('voice_immediate') %>

# Lucide icons with consistent sizing
<%= admin_icon('activity', size: :lg) %>
<%= admin_icon('trash-2', size: :sm, class: 'text-danger') %>

# Accessible table captions (screen-reader only)
<%= admin_table_caption('List of workflow executions') %>

# Format durations
<%= format_duration_ms(2500) %>  # "2.5s"

# Buttons with icons
<%= admin_button_with_icon('View Details', execution_path(execution),
    icon: 'eye', class: 'admin-btn-outline') %>
```

### Admin Component Patterns

**Page Structure:**
```erb
<div class="admin-content">
  <div class="admin-p-xl">
    <!-- Page header -->
    <div class="admin-page-header">
      <div class="header-left">
        <div class="header-icon">
          <%= admin_icon('activity', size: :lg) %>
        </div>
        <div class="header-text">
          <h1>Page Title</h1>
          <p>Page description</p>
        </div>
      </div>
      <div class="header-actions">
        <%= link_to new_item_path, class: 'admin-btn admin-btn-primary' do %>
          <%= admin_icon('plus', size: :sm) %>
          <span>New Item</span>
        <% end %>
      </div>
    </div>

    <!-- Stats grid -->
    <div class="admin-stats-grid">
      <%= render 'admin/shared/stat_card',
          label: 'Total Items',
          value: @items.count,
          icon: 'database',
          variant: 'purple-gradient' %>
    </div>

    <!-- Content -->
    <div class="admin-card">
      <table class="admin-table">
        <%= admin_table_caption 'List of items for accessibility' %>
        <thead>
          <tr>
            <th>Name</th>
            <th>Status</th>
            <th class="admin-text-right">Actions</th>
          </tr>
        </thead>
        <tbody>
          <% @items.each do |item| %>
            <tr>
              <td>
                <%= link_to item.name, item_path(item), class: 'admin-text-cyan' %>
              </td>
              <td><%= admin_status_badge(item.status) %></td>
              <td class="admin-text-right">
                <%= link_to item_path(item), class: 'admin-btn admin-btn-sm admin-btn-outline' do %>
                  <%= admin_icon('eye', size: :sm) %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  </div>
</div>

<script>
  document.addEventListener('turbo:load', () => {
    lucide.createIcons();
  });

  document.addEventListener('DOMContentLoaded', () => {
    lucide.createIcons();
  });
</script>
```

**Stat Card Partial** (`app/views/admin/shared/_stat_card.html.erb`):
```erb
<div class="admin-card">
  <div class="d-flex align-items-center gap-3">
    <div class="admin-stat-icon <%= variant %>">
      <%= admin_icon(icon, size: :lg) %>
    </div>
    <div>
      <p class="admin-stat-label"><%= label %></p>
      <h3 class="admin-stat-value"><%= value %></h3>
    </div>
  </div>
</div>
```

### Common Icons (Lucide)

Admin-specific icons:
- `layout-dashboard` - Dashboard
- `users` - Users
- `link` - Connections
- `activity` - Activity/Executions
- `git-branch` - Pipeline/Workflow
- `bar-chart-3` - Metrics/Analytics
- `database` - Data/Records
- `plug` - Integrations
- `brain` - AI/Lightning
- `zap` - Performance
- `eye` - View
- `pencil` - Edit
- `trash-2` - Delete
- `plus` - Add
- `check-circle` - Success
- `alert-circle` - Error/Warning
- `x-circle` - Close

### Dark Theme UX Best Practices

1. **No Inline Styles**: Use utility classes (`admin-*`) instead of inline styles
2. **Use Helpers**: Prefer `admin_status_badge()` over manual `<span>` tags
3. **Use Partials**: Extract repeated patterns (stat cards, detail lists)
4. **Accessibility**: Always include `admin_table_caption()` for tables
5. **Lucide Icons**: Initialize with `lucide.createIcons()` at page bottom
6. **Consistent Sizing**: Use `admin_icon(name, size:)` for predictable icon sizes
7. **Semantic Colors**: Use badge variants that match status meaning
8. **Responsive Grids**: Use `admin-stats-grid` / `admin-content-grid` for layouts

---

**Remember**: Always prioritize utility classes over inline styles, use helper methods for consistency, extract repeated patterns into partials, and ensure accessibility compliance with WCAG 2.1.
