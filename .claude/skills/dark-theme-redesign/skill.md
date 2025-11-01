# Dark Theme Redesign Skill

This skill redesigns application pages to match the dark theme design system with gradient accents, Lucide icons, and modern UI components.

## Color Palette

```scss
$bg-primary: #0A0E1A;      // Main background
$bg-secondary: #1A1F35;    // Card backgrounds
$bg-tertiary: #0F172A;     // Sidebar background
$border: #1E293B;          // Borders
$text-primary: #FFFFFF;    // Primary text
$text-secondary: #94A3B8;  // Secondary text (slate-400)
$text-muted: #64748B;      // Muted text (slate-500)
$accent-start: #7C3AED;    // Purple gradient start
$accent-end: #A78BFA;      // Purple gradient end
$cyan: #22D3EE;            // Cyan accent
$green: rgb(74, 222, 128); // Green for success
$red: rgb(248, 113, 113);  // Red for errors
```

## Design Components

### 1. Page Structure

**For Admin Pages** (with left sidebar):
```erb
<div class="admin-content">
  <div style="padding: 2rem;">
    <%# Content here %>
  </div>
</div>
```

**For Non-Admin Pages** (no sidebar):
```erb
<div class="container-fluid py-4" style="background-color: #0A0E1A; min-height: 100vh; color: #FFFFFF;">
  <%# Content here %>
</div>
```

### 2. Page Header

```erb
<div class="admin-page-header">
  <div class="header-left">
    <div class="header-icon">
      <i data-lucide="icon-name"></i>
    </div>
    <div class="header-text">
      <h1>Page Title</h1>
      <p>Page description</p>
    </div>
  </div>

  <%# Optional actions %>
  <div class="header-actions">
    <%= link_to path, class: 'admin-btn admin-btn-primary' do %>
      <i data-lucide="plus"></i>
      <span>New Item</span>
    <% end %>
  </div>
</div>
```

### 3. Stats Cards

**4-Column Grid:**
```erb
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
  <div class="admin-card">
    <div style="display: flex; align-items: center; gap: 1rem;">
      <div style="width: 3rem; height: 3rem; border-radius: 0.75rem; background: linear-gradient(135deg, #7C3AED 0%, #A78BFA 100%); display: flex; align-items: center; justify-content: center;">
        <i data-lucide="icon-name" style="width: 1.5rem; height: 1.5rem; color: white;"></i>
      </div>
      <div>
        <p style="color: #94A3B8; font-size: 0.875rem; margin: 0;">Label</p>
        <h3 style="color: white; font-size: 1.875rem; font-weight: 600; margin: 0;"><%= value %></h3>
      </div>
    </div>
  </div>
</div>
```

**Colored Icon Variants:**
- **Purple Gradient**: `background: linear-gradient(135deg, #7C3AED 0%, #A78BFA 100%);`
- **Green**: `background: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.2);` with `color: rgb(74, 222, 128);`
- **Cyan**: `background: rgba(34, 211, 238, 0.1); border: 1px solid rgba(34, 211, 238, 0.2);` with `color: #22D3EE;`
- **Red**: `background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.2);` with `color: rgb(248, 113, 113);`
- **Yellow**: `background: rgba(234, 179, 8, 0.1); border: 1px solid rgba(234, 179, 8, 0.2);` with `color: rgb(250, 204, 21);`

### 4. Filter Tabs

```erb
<div class="admin-tabs" style="margin-bottom: 2rem;">
  <%= link_to 'All', path, class: "admin-tab #{active ? 'admin-tab-active' : ''}" %>
  <%= link_to 'Filter 1', path, class: "admin-tab" %>
  <%= link_to 'Filter 2', path, class: "admin-tab" %>
</div>
```

### 5. Data Table

```erb
<div class="admin-card">
  <h3 class="card-title">
    <i data-lucide="icon" style="width: 1.25rem; height: 1.25rem; display: inline-block; vertical-align: middle; margin-right: 0.5rem;"></i>
    Table Title
  </h3>

  <div style="overflow-x: auto;">
    <table class="admin-table">
      <thead>
        <tr>
          <th>Column 1</th>
          <th>Column 2</th>
          <th style="text-align: right;">Actions</th>
        </tr>
      </thead>
      <tbody>
        <% items.each do |item| %>
          <tr>
            <td style="color: white;"><%= item.name %></td>
            <td style="color: #94A3B8;"><%= item.value %></td>
            <td style="text-align: right;">
              <div style="display: inline-flex; gap: 0.5rem;">
                <%= link_to path(item), class: 'admin-btn admin-btn-sm admin-btn-outline' do %>
                  <i data-lucide="eye"></i>
                <% end %>
                <%= link_to edit_path(item), class: 'admin-btn admin-btn-sm admin-btn-outline' do %>
                  <i data-lucide="pencil"></i>
                <% end %>
              </div>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

### 6. Empty State

```erb
<div class="admin-empty-state">
  <div class="empty-icon">
    <i data-lucide="icon-name"></i>
  </div>
  <h3>No items yet</h3>
  <p>Description of what will appear here</p>
  <%= link_to path, class: 'admin-btn admin-btn-primary', style: 'margin-top: 1rem;' do %>
    <i data-lucide="plus"></i>
    <span>Create First Item</span>
  <% end %>
</div>
```

### 7. Badges

```erb
<%# Online/Active state - Green with glow %>
<span class="admin-badge admin-badge-online">ACTIVE</span>

<%# Offline/Error state - Red with glow %>
<span class="admin-badge admin-badge-offline">ERROR</span>

<%# Warning state - Yellow with glow %>
<span class="admin-badge admin-badge-warning">WARNING</span>

<%# Cyan accent %>
<span class="admin-badge admin-badge-cyan">INFO</span>

<%# Default/Neutral state - Gray %>
<span class="admin-badge admin-badge-default">DEFAULT</span>
```

### 8. Alert Banners

```erb
<%# Success %>
<div class="admin-alert admin-alert-success">
  <div class="alert-content">
    <i data-lucide="check-circle"></i>
    <span>Success message</span>
  </div>
  <button class="alert-close" onclick="this.parentElement.remove()">×</button>
</div>

<%# Error %>
<div class="admin-alert admin-alert-error">
  <div class="alert-content">
    <i data-lucide="alert-circle"></i>
    <span>Error message</span>
  </div>
  <button class="alert-close" onclick="this.parentElement.remove()">×</button>
</div>

<%# Warning %>
<div class="admin-alert admin-alert-warning">
  <div class="alert-content">
    <i data-lucide="alert-triangle"></i>
    <span>Warning message</span>
  </div>
  <button class="alert-close" onclick="this.parentElement.remove()">×</button>
</div>
```

### 9. Buttons

```erb
<%# Primary (Cyan) %>
<%= link_to path, class: 'admin-btn admin-btn-primary' do %>
  <i data-lucide="icon"></i>
  <span>Primary</span>
<% end %>

<%# Outline %>
<%= link_to path, class: 'admin-btn admin-btn-outline' do %>
  <i data-lucide="icon"></i>
  <span>Outline</span>
<% end %>

<%# Small size %>
<%= link_to path, class: 'admin-btn admin-btn-sm admin-btn-outline' do %>
  <i data-lucide="icon"></i>
<% end %>

<%# Danger/Delete %>
<%= button_to path, method: :delete, class: 'admin-btn admin-btn-outline', style: 'color: rgb(248, 113, 113); border-color: rgb(248, 113, 113);' do %>
  <i data-lucide="trash-2"></i>
  <span>Delete</span>
<% end %>
```

### 10. Form Inputs

```erb
<div>
  <label style="color: #94A3B8; font-size: 0.875rem; margin-bottom: 0.5rem; display: block;">Label</label>
  <%= text_field_tag :name, value, style: 'width: 100%; padding: 0.5rem; background: #0F172A; border: 1px solid #1E293B; border-radius: 0.5rem; color: white;' %>
</div>

<div>
  <label style="color: #94A3B8; font-size: 0.875rem; margin-bottom: 0.5rem; display: block;">Select</label>
  <%= select_tag :name, options, style: 'width: 100%; padding: 0.5rem; background: #0F172A; border: 1px solid #1E293B; border-radius: 0.5rem; color: white;' %>
</div>

<div>
  <label style="color: #94A3B8; font-size: 0.875rem; margin-bottom: 0.5rem; display: block;">Textarea</label>
  <%= text_area_tag :name, value, rows: 4, style: 'width: 100%; padding: 0.5rem; background: #0F172A; border: 1px solid #1E293B; border-radius: 0.5rem; color: white;' %>
</div>
```

### 11. Chart.js Integration (Dark Theme)

For pages with charts, add this configuration:

```erb
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script>
  function initializeCharts() {
    // Dark theme colors
    Chart.defaults.color = '#94A3B8';
    Chart.defaults.borderColor = '#1E293B';

    // Get canvas elements
    const chartCanvas = document.getElementById('chartId');

    // Destroy existing chart if it exists
    if (chartCanvas && Chart.getChart(chartCanvas)) {
      Chart.getChart(chartCanvas).destroy();
    }

    // Create chart
    if (chartCanvas) {
      new Chart(chartCanvas, {
        type: 'bar', // or 'line', 'doughnut', etc.
        data: <%= raw @chart_data.to_json %>,
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { grid: { color: '#1E293B' } },
            y: {
              beginAtZero: true,
              grid: { color: '#1E293B' }
            }
          },
          plugins: {
            legend: {
              position: 'bottom',
              labels: { color: '#94A3B8' }
            }
          }
        }
      });
    }

    // Initialize Lucide icons
    if (typeof lucide !== 'undefined') {
      lucide.createIcons();
    }
  }

  // Run on both DOMContentLoaded and turbo:load
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeCharts);
  } else {
    initializeCharts();
  }

  document.addEventListener('turbo:load', initializeCharts);
</script>
```

**Important**: For chart pages, add `data-turbo-cache="false"` to the main wrapper div.

## Icons

Use **Lucide Icons** throughout (`data-lucide="icon-name"`):

**Common icons:**
- `layout-dashboard` - Dashboard
- `users` - Users
- `link` - Connections
- `activity` - Activity/Executions
- `git-branch` - Pipeline
- `bar-chart-3` - Charts/Analytics
- `plug` - Integrations
- `eye` - View
- `pencil` / `edit` - Edit
- `trash-2` - Delete
- `plus` - Add
- `check-circle` - Success
- `alert-circle` - Error
- `alert-triangle` - Warning
- `x-circle` - Close
- `search` - Search
- `filter` - Filter
- `download` - Download
- `upload` - Upload
- `mail` - Email
- `phone` - Phone
- `cpu` - Processing
- `coins` - Tokens/Cost
- `clock` - Time
- `dollar-sign` - Money
- `trending-up` - Growth

Initialize icons at bottom of page:

```erb
<script>
  document.addEventListener('turbo:load', () => {
    if (typeof lucide !== 'undefined') {
      lucide.createIcons();
    }
  });

  document.addEventListener('DOMContentLoaded', () => {
    if (typeof lucide !== 'undefined') {
      lucide.createIcons();
    }
  });
</script>
```

## Redesign Process

When redesigning a page:

1. **Read the existing page** to understand structure and data
2. **Choose page wrapper**:
   - Admin pages: `<div class="admin-content">` with `padding: 2rem`
   - Non-admin pages: `<div class="container-fluid py-4">` with inline dark styles
3. **Replace page header** with admin-page-header component
4. **Convert Bootstrap cards** to `admin-card` class
5. **Convert tables** to use `admin-table` class
6. **Update badges** to use admin-badge variants
7. **Replace buttons** with admin-btn classes
8. **Replace Bootstrap/FontAwesome icons** with Lucide icons
9. **Add Lucide icon initialization script**
10. **Add Chart.js dark theme** configuration if charts are present
11. **Test in Docker** to verify styling

## Available CSS Classes

All classes defined in `app/assets/stylesheets/admin_dark.scss` (can be used on any page):

- Layout: `.admin-dark`, `.admin-sidebar`, `.admin-content`
- Components: `.admin-card`, `.admin-btn`, `.admin-badge`, `.admin-alert`
- Structure: `.admin-page-header`, `.admin-tabs`, `.admin-table`
- Utilities: `.admin-detail-list`, `.admin-code-block`, `.admin-empty-state`

## Asset Loading

**Admin pages** automatically load `admin_dark.css` via admin layout.

**Non-admin pages** need to load the stylesheet manually:
```erb
<%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
<link rel="stylesheet" href="/assets/admin_dark.css" data-turbo-track="reload">
```

Or link directly in the page:
```erb
<link rel="stylesheet" href="/assets/admin_dark.css">
```

## Example Conversion

**Before** (Bootstrap light theme):
```erb
<div class="container-fluid py-4">
  <h1>📊 Analytics Dashboard</h1>

  <div class="row">
    <div class="col-md-3">
      <div class="card">
        <div class="card-body">
          <p class="text-muted">Active Campaigns</p>
          <h3><%= @metrics[:campaigns] %></h3>
        </div>
      </div>
    </div>
  </div>

  <div class="card">
    <div class="card-body">
      <table class="table table-dark">
        <thead>
          <tr><th>Name</th></tr>
        </thead>
        <tbody>
          <tr><td><a href="#">Item</a></td></tr>
        </tbody>
      </table>
    </div>
  </div>
</div>
```

**After** (Dark theme):
```erb
<link rel="stylesheet" href="/assets/admin_dark.css">

<div class="container-fluid py-4" style="background-color: #0A0E1A; min-height: 100vh; color: #FFFFFF;">
  <div class="admin-page-header">
    <div class="header-left">
      <div class="header-icon">
        <i data-lucide="bar-chart-3"></i>
      </div>
      <div class="header-text">
        <h1>Analytics Dashboard</h1>
        <p>Real-time performance metrics</p>
      </div>
    </div>
  </div>

  <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
    <div class="admin-card">
      <div style="display: flex; align-items: center; gap: 1rem;">
        <div style="width: 3rem; height: 3rem; border-radius: 0.75rem; background: linear-gradient(135deg, #7C3AED 0%, #A78BFA 100%); display: flex; align-items: center; justify-content: center;">
          <i data-lucide="mail" style="width: 1.5rem; height: 1.5rem; color: white;"></i>
        </div>
        <div>
          <p style="color: #94A3B8; font-size: 0.875rem; margin: 0;">Active Campaigns</p>
          <h3 style="color: white; font-size: 1.875rem; font-weight: 600; margin: 0;"><%= @metrics[:campaigns] %></h3>
        </div>
      </div>
    </div>
  </div>

  <div class="admin-card">
    <h3 class="card-title">
      <i data-lucide="list" style="width: 1.25rem; height: 1.25rem; display: inline-block; vertical-align: middle; margin-right: 0.5rem;"></i>
      Items
    </h3>
    <div style="overflow-x: auto;">
      <table class="admin-table">
        <thead>
          <tr><th>Name</th></tr>
        </thead>
        <tbody>
          <tr>
            <td>
              <%= link_to 'Item', path, style: 'color: #22D3EE; text-decoration: none; font-weight: 600;' %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</div>

<script>
  document.addEventListener('turbo:load', () => {
    if (typeof lucide !== 'undefined') {
      lucide.createIcons();
    }
  });

  document.addEventListener('DOMContentLoaded', () => {
    if (typeof lucide !== 'undefined') {
      lucide.createIcons();
    }
  });
</script>
```

## Notes

- Keep existing Rails logic (loops, conditionals, helpers)
- Only change HTML structure and CSS classes
- Test after each page to ensure functionality
- Maintain responsive design with inline styles where needed
- Always include Lucide icon initialization script
- For chart pages, add proper initialization and cleanup
- Use consistent color palette across all pages
