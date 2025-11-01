# Rails UX Expert - Quick Reference

## Most Common Issues & Fixes

### 1. Inline Styles in ERB
```erb
<!-- ❌ WRONG -->
<div style="margin-top: 20px; color: #6c757d;">

<!-- ✅ CORRECT -->
<div class="mt-4 text-muted">
```

### 2. Hardcoded URLs
```erb
<!-- ❌ WRONG -->
<a href="/scout">Scout</a>

<!-- ✅ CORRECT -->
<%= link_to 'Scout', scout_path %>
```

### 3. Custom Button Styles
```erb
<!-- ❌ WRONG -->
<button style="background: blue; color: white;">

<!-- ✅ CORRECT -->
<button class="btn btn-primary">
```

### 4. Icon-Only Buttons (Accessibility)
```erb
<!-- ❌ WRONG -->
<button><i data-lucide="trash"></i></button>

<!-- ✅ CORRECT -->
<button aria-label="Delete item">
  <i data-lucide="trash"></i>
</button>
```

### 5. JavaScript DOM Manipulation (Stimulus)
```javascript
// ❌ WRONG
this.element.style.display = 'none';
this.element.style.color = '#dc3545';

// ✅ CORRECT
this.element.classList.add('d-none');
this.element.classList.add('text-danger');
```

### 6. Missing Form Validation
```erb
<!-- ❌ WRONG -->
<%= form_with model: @campaign do |f| %>

<!-- ✅ CORRECT -->
<%= form_with model: @campaign, html: { novalidate: true, class: 'needs-validation' } do |f| %>
```

### 7. Poor SSE Error Handling
```javascript
// ❌ WRONG
const eventSource = new EventSource('/scout/stream');

// ✅ CORRECT
const eventSource = new EventSource('/scout/stream');
eventSource.onerror = (error) => {
  console.error('Connection lost:', error);
  eventSource.close();
  this.reconnectWithBackoff();
};
```

### 8. Thinking Indicators
```html
<!-- ❌ WRONG -->
<div class="loading">Processing...</div>

<!-- ✅ CORRECT -->
<div class="d-flex align-items-center">
  <div class="spinner-border spinner-border-sm text-primary me-2" role="status">
    <span class="visually-hidden">Processing...</span>
  </div>
  <span>Processing...</span>
</div>
```

### 9. Not Using Turbo Frames
```erb
<!-- ❌ WRONG: Full page reload -->
<div id="results">
  <%= render @results %>
</div>

<!-- ✅ CORRECT: Partial update -->
<%= turbo_frame_tag 'results' do %>
  <%= render @results %>
<% end %>
```

### 10. Hardcoded Colors in SCSS
```scss
// ❌ WRONG
.message-box {
  background: #f8f9fa;
  color: #212529;
  border: 1px solid #dee2e6;
}

// ✅ CORRECT
.message-box {
  @extend .bg-light;
  @extend .text-dark;
  @extend .border;
}

// OR
.message-box {
  background: var(--bs-light);
  color: var(--bs-dark);
  border: var(--bs-border-width) solid var(--bs-border-color);
}
```

## Bootstrap Utility Class Cheat Sheet

### Spacing
| Custom CSS | Bootstrap Utility |
|------------|-------------------|
| `margin-top: 0.5rem` | `mt-2` |
| `margin-top: 1rem` | `mt-3` |
| `margin-top: 1.5rem` | `mt-4` |
| `padding: 1rem` | `p-3` |
| `margin-left: auto` | `ms-auto` |
| `gap: 0.5rem` | `gap-2` |

### Colors
| Custom CSS | Bootstrap Utility |
|------------|-------------------|
| `color: #6c757d` | `text-muted` |
| `color: #0d6efd` | `text-primary` |
| `color: #dc3545` | `text-danger` |
| `background: #f8f9fa` | `bg-light` |
| `background: white` | `bg-white` |

### Display
| Custom CSS | Bootstrap Utility |
|------------|-------------------|
| `display: none` | `d-none` |
| `display: flex` | `d-flex` |
| `display: grid` | `d-grid` |
| `flex-direction: column` | `flex-column` |
| `align-items: center` | `align-items-center` |
| `justify-content: space-between` | `justify-content-between` |

### Typography
| Custom CSS | Bootstrap Utility |
|------------|-------------------|
| `font-weight: bold` | `fw-bold` |
| `font-size: 1.5rem` | `fs-4` |
| `text-align: center` | `text-center` |
| `text-decoration: none` | `text-decoration-none` |

### Borders & Radius
| Custom CSS | Bootstrap Utility |
|------------|-------------------|
| `border: 1px solid` | `border` |
| `border-radius: 0.25rem` | `rounded` |
| `border-radius: 50%` | `rounded-circle` |
| `border-top: 0` | `border-top-0` |

## Rails Helper Reference

### Links
```erb
# Basic link
<%= link_to 'Home', root_path %>

# Link with class
<%= link_to 'Scout', scout_path, class: 'btn btn-primary' %>

# Link with data attributes
<%= link_to 'Delete', campaign_path(@campaign),
    method: :delete,
    data: { confirm: 'Are you sure?' } %>

# Link with Turbo Frame target
<%= link_to 'Edit', edit_campaign_path(@campaign),
    data: { turbo_frame: 'modal' } %>
```

### Forms
```erb
# Model form
<%= form_with model: @campaign do |f| %>
  <%= f.label :name %>
  <%= f.text_field :name, class: 'form-control' %>
  <%= f.submit 'Save', class: 'btn btn-primary' %>
<% end %>

# URL form (not model-based)
<%= form_with url: search_path, method: :get do |f| %>
  <%= f.text_field :query, class: 'form-control' %>
  <%= f.submit 'Search', class: 'btn btn-primary' %>
<% end %>

# Form with validation
<%= form_with model: @campaign,
    html: { novalidate: true, class: 'needs-validation' } do |f| %>
  <%= f.text_field :name, required: true, class: 'form-control' %>
  <div class="invalid-feedback">Name is required</div>
<% end %>
```

### Assets
```erb
# Stylesheet
<%= stylesheet_link_tag 'scout' %>

# JavaScript
<%= javascript_include_tag 'scout' %>

# Image
<%= image_tag 'logo.png', alt: 'AMOS Logo', class: 'logo' %>
```

### Turbo Frames
```erb
# Basic frame
<%= turbo_frame_tag 'results' do %>
  <%= render @results %>
<% end %>

# Lazy-loaded frame
<%= turbo_frame_tag 'results', src: results_path, loading: :lazy %>

# Frame with custom target
<%= turbo_frame_tag 'modal', target: '_top' do %>
  <%= render 'form' %>
<% end %>
```

## Stimulus Controller Template

```javascript
// app/javascript/controllers/example_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Define targets
  static targets = [ "output", "input" ]

  // Define values
  static values = {
    url: String,
    timeout: { type: Number, default: 5000 }
  }

  // Define classes
  static classes = [ "active", "hidden" ]

  // Lifecycle
  connect() {
    console.log("Controller connected")
  }

  disconnect() {
    console.log("Controller disconnected")
  }

  // Actions
  handleClick(event) {
    event.preventDefault()

    // Use targets
    this.outputTarget.textContent = this.inputTarget.value

    // Use values
    console.log(this.urlValue, this.timeoutValue)

    // Use classes
    this.element.classList.add(this.activeClass)
    this.element.classList.remove(this.hiddenClass)
  }

  // Private methods
  #privateMethod() {
    // Implementation
  }
}
```

```erb
<!-- Usage in ERB -->
<div data-controller="example"
     data-example-url-value="<%= search_path %>"
     data-example-timeout-value="3000"
     data-example-active-class="bg-primary"
     data-example-hidden-class="d-none">

  <input type="text" data-example-target="input">
  <button data-action="click->example#handleClick">
    Submit
  </button>
  <div data-example-target="output"></div>
</div>
```

## AI Chat Interface Patterns

### Message Display
```erb
<div class="message <%= message.role %>-message">
  <div class="d-flex align-items-start gap-2">
    <div class="message-avatar">
      <% if message.role == 'user' %>
        <i data-lucide="user"></i>
      <% else %>
        <i data-lucide="bot"></i>
      <% end %>
    </div>
    <div class="message-content flex-grow-1">
      <%= simple_format message.content %>
    </div>
  </div>

  <% if message.model_used.present? %>
    <div class="model-watermark mt-1">
      <small class="text-muted">
        <i data-lucide="bot" class="icon-xs"></i>
        <%= message.model_used %>
      </small>
    </div>
  <% end %>
</div>
```

### Thinking Indicator
```erb
<div id="thinking-indicator" class="message assistant-message d-none">
  <div class="d-flex align-items-start gap-2">
    <div class="message-avatar">
      <i data-lucide="bot"></i>
    </div>
    <div class="thinking-dots">
      <span></span><span></span><span></span>
    </div>
  </div>
</div>
```

```scss
.thinking-dots {
  display: inline-flex;
  gap: 4px;

  span {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--bs-secondary);
    animation: thinking 1.4s ease-in-out infinite;

    &:nth-child(1) { animation-delay: 0s; }
    &:nth-child(2) { animation-delay: 0.2s; }
    &:nth-child(3) { animation-delay: 0.4s; }
  }
}

@keyframes thinking {
  0%, 80%, 100% { transform: scale(0.8); opacity: 0.5; }
  40% { transform: scale(1); opacity: 1; }
}
```

### SSE Connection
```javascript
connect() {
  this.eventSource = new EventSource('/scout/stream')
  this.setupEventHandlers()
}

setupEventHandlers() {
  this.eventSource.addEventListener('content', (event) => {
    this.appendMessage(JSON.parse(event.data))
  })

  this.eventSource.addEventListener('error', (event) => {
    console.error('SSE error:', event)
    this.handleConnectionError()
  })

  this.eventSource.addEventListener('complete', (event) => {
    this.eventSource.close()
    this.hideThinkingIndicator()
  })
}

handleConnectionError() {
  this.eventSource.close()
  this.retryCount = (this.retryCount || 0) + 1

  if (this.retryCount < 3) {
    const delay = Math.pow(2, this.retryCount) * 1000 // Exponential backoff
    setTimeout(() => this.connect(), delay)
  } else {
    this.showErrorMessage('Connection lost. Please refresh.')
  }
}
```

## Testing Checklist

Before committing UI changes:

- [ ] No inline styles in ERB
- [ ] No hardcoded URLs (use path helpers)
- [ ] All buttons have accessible labels
- [ ] Forms have proper validation attributes
- [ ] Responsive at all breakpoints (sm, md, lg, xl, xxl)
- [ ] Keyboard navigation works
- [ ] Screen reader friendly (ARIA labels)
- [ ] Color contrast meets WCAG 2.1 (4.5:1 minimum)
- [ ] Loading states for async operations
- [ ] Error handling with user-friendly messages
- [ ] JavaScript console has no errors
- [ ] Lucide icons initialized (`lucide.createIcons()`)
- [ ] Stimulus controllers properly scoped

## Resources

- Bootstrap 5: https://getbootstrap.com/docs/5.3/
- Turbo: https://turbo.hotwired.dev/
- Stimulus: https://stimulus.hotwired.dev/
- Lucide Icons: https://lucide.dev/icons/
- Rails Guides: https://guides.rubyonrails.org/
- WCAG: https://www.w3.org/WAI/WCAG21/quickref/
