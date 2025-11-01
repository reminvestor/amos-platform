# Admin Page Redesign Skill

This skill redesigns admin pages (`/admin/*`) to match the dark theme design system with gradient accents, Lucide icons, and modern UI components.

## Color Palette

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

## Design Components

### 1. Page Structure

```erb
<div class="admin-content">
  <div style="padding: 2rem;">
    <%# Content here %>
  </div>
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
            <td>
              <%= link_to item.name, path(item), style: 'color: #22D3EE; text-decoration: none; font-weight: 600;' %>
            </td>
            <td style="color: white;"><%= item.value %></td>
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
  <p class="empty-title">No items yet</p>
  <p class="empty-description">
    Description of what will appear here
  </p>
  <%= link_to path, class: 'admin-btn admin-btn-primary', style: 'margin-top: 1rem;' do %>
    <i data-lucide="plus"></i>
    <span>Create First Item</span>
  <% end %>
</div>
```

### 7. Badges

```erb
<%# Online/Active state %>
<span class="admin-badge admin-badge-online">ONLINE</span>

<%# Offline/Error state %>
<span class="admin-badge admin-badge-offline">ERROR</span>

<%# Warning state %>
<span class="admin-badge admin-badge-warning">WARNING</span>

<%# Default/Neutral state %>
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
```

## Icons

Use **Lucide Icons** throughout (`data-lucide="icon-name"`):

Common icons:
- `layout-dashboard` - Dashboard
- `users` - Users
- `link` - Connections
- `activity` - Activity/Executions
- `git-branch` - Pipeline
- `bar-chart-3` - Observability
- `plug` - Integrations
- `eye` - View
- `pencil` - Edit
- `trash-2` - Delete
- `plus` - Add
- `check-circle` - Success
- `alert-circle` - Error
- `x-circle` - Close

Initialize icons at bottom of page:

```erb
<script>
  document.addEventListener('turbo:load', () => {
    lucide.createIcons();
  });

  document.addEventListener('DOMContentLoaded', () => {
    lucide.createIcons();
  });
</script>
```

## Redesign Process

When redesigning an admin page:

1. **Read the existing page** to understand structure and data
2. **Wrap content in** `<div class="admin-content">` with `padding: 2rem`
3. **Replace page header** with admin-page-header component
4. **Convert Bootstrap cards** to `admin-card` class
5. **Convert tables** to use `admin-table` class
6. **Update badges** to use admin-badge variants
7. **Replace buttons** with admin-btn classes
8. **Add Lucide icons** and initialization script
9. **Test in Docker** to verify styling

## Available CSS Classes

All classes defined in `app/assets/stylesheets/admin_dark.scss`:

- Layout: `.admin-dark`, `.admin-sidebar`, `.admin-content`
- Components: `.admin-card`, `.admin-btn`, `.admin-badge`, `.admin-alert`
- Structure: `.admin-page-header`, `.admin-tabs`, `.admin-table`
- Utilities: `.admin-detail-list`, `.admin-code-block`, `.admin-empty-state`

## Example Conversion

**Before** (Bootstrap light theme):
```erb
<div class="container-fluid py-4">
  <h1>Page Title</h1>

  <div class="card">
    <div class="card-body">
      <table class="table">
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
<div class="admin-content">
  <div style="padding: 2rem;">
    <div class="admin-page-header">
      <div class="header-left">
        <div class="header-icon">
          <i data-lucide="icon"></i>
        </div>
        <div class="header-text">
          <h1>Page Title</h1>
          <p>Description</p>
        </div>
      </div>
    </div>

    <div class="admin-card">
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
</div>

<script>
  document.addEventListener('turbo:load', () => {
    lucide.createIcons();
  });
</script>
```

## Notes

- Keep existing Rails logic (loops, conditionals, helpers)
- Only change HTML structure and CSS classes
- Test after each page to ensure functionality
- Maintain responsive design with inline styles where needed
- Always include Lucide icon initialization script
