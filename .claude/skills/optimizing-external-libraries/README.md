# Optimizing External Libraries and CDN Resources

This skill enforces Rails best practices for managing external JavaScript libraries and CDN resources to optimize application performance through consolidated loading and browser caching.

## Purpose

When working with external libraries (Chart.js, Bootstrap, Google Fonts, Lucide Icons, etc.), avoid duplicating script/link tags across multiple views. Instead, use Rails partials to consolidate external library imports into single, reusable files that enable global browser caching.

## Key Principles

### 1. **DRY (Don't Repeat Yourself)**
- Single source of truth for each external library
- One place to update library versions across the entire app
- Reduces maintenance burden

### 2. **Browser Caching**
- When the same CDN URL appears in multiple places, browsers can cache it globally
- Users only download libraries once, even across different pages
- Significantly improves performance

### 3. **Version Consistency**
- All pages using a library get the same version
- Prevents version mismatches and compatibility issues
- Easier to upgrade all at once

## Implementation Pattern

### Before (Anti-pattern - Don't Do This)
```erb
<!-- app/views/admin/page1.html.erb -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

<!-- app/views/admin/page2.html.erb -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

<!-- app/views/admin/page3.html.erb -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
```

### After (Best Practice - Do This)
```erb
<!-- app/views/admin/_chart_js.html.erb -->
<!-- Chart.js (consolidated from 6 admin pages) -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

<!-- app/views/admin/page1.html.erb -->
<%= render 'admin/chart_js' %>

<!-- app/views/admin/page2.html.erb -->
<%= render 'admin/chart_js' %>

<!-- app/views/admin/page3.html.erb -->
<%= render 'admin/chart_js' %>
```

## Consolidation Rules

### When to Consolidate
- Library appears **2 or more times** across the app
- Same library version used in multiple places
- Libraries used in multiple view files or layouts

### When NOT to Consolidate
- Library only used once (e.g., Summernote editor in email templates)
- Library used only in a specific namespace with no other occurrences
- Temporary or experimental libraries

## Common Libraries to Consolidate

| Library | Consolidation Level | Pattern |
|---------|-------------------|---------|
| Lucide Icons | Very High | Used in 7+ layouts → Single CDN URL |
| Bootstrap CSS/JS | Very High | Used in 4+ layouts → Partials |
| Google Fonts | High | Used in 4+ layouts → Partials |
| Chart.js | High | Used in 6+ admin pages → Admin partials |
| Summernote | Low | Used once only → No consolidation |

## Naming Convention

Follow Rails naming conventions for CDN consolidation partials:

```
app/views/
├── layouts/
│   ├── _lucide_icons.html.erb           # Global icon library
│   └── _bootstrap_js.html.erb          # Global JS framework
├── admin/
│   └── _chart_js.html.erb              # Admin-specific charting
└── landing_pages/
    ├── _head_libs.html.erb              # Head section libraries
    └── _bootstrap_js.html.erb           # Bootstrap JS (if used)
```

## Checklist for Library Consolidation

- [ ] Search the codebase for all occurrences of the library **in HTML/ERB files**
- [ ] **Also search Ruby services/tools for hardcoded icon classes or library references**
  - Look for: `"fa fa-"`, `'fa-'`, `class="icon`, `font-awesome` in `.rb` files
  - Check files that dynamically generate HTML with embedded styles/classes
  - Example: visualization tools, dynamic form builders, templating services
- [ ] Identify all files/layouts using the same library
- [ ] Check if versions are consistent (if not, upgrade all to latest)
- [ ] Create appropriate partial file(s)
- [ ] Replace all original imports with `<%= render 'path/to/partial' %>`
- [ ] **Update hardcoded references** - Replace FA icon classes in Ruby code with Lucide or mapped alternatives
- [ ] Verify all pages still load correctly
- [ ] Commit with clear message indicating consolidation

## Performance Impact Example

**Before Consolidation:**
- Chart.js downloaded 6 times (once per admin page per user session)
- Bootstrap downloaded 4 times (once per landing page variant)
- Google Fonts downloaded 4 times (once per landing page variant)

**After Consolidation:**
- Chart.js downloaded 1 time globally and cached
- Bootstrap downloaded 1 time globally and cached
- Google Fonts downloaded 1 time globally and cached

**Result:** 75-86% reduction in redundant requests per user

## Best Practices Applied

1. ✅ Use Rails partials for code reuse
2. ✅ Keep single source of truth for library versions
3. ✅ Leverage browser caching effectively
4. ✅ Follow DRY principle (Don't Repeat Yourself)
5. ✅ Maintain clear naming conventions
6. ✅ Document consolidated libraries with comments

## When Adding New External Libraries

Before adding `<script>` or `<link>` tags for external CDN resources:

1. **Check for existing usage** - Search if library is already used
2. **If found** - Use the existing consolidated partial
3. **If new library** - Create consolidation partial immediately if it will be used in multiple places
4. **Document** - Add comment indicating consolidation level and pages using it
5. **Update this guide** - Add to the consolidation checklist above

## Edge Cases & Advanced Scenarios

### Icon Libraries in Ruby Code

When icon libraries (Font Awesome, Material Icons, etc.) are **hardcoded in Ruby services**, tools, or dynamic HTML generators:

```ruby
# ❌ BAD: Hardcoded Font Awesome icon classes
def generate_widget(title, icon)
  "<i class='#{icon}'></i><span>#{title}</span>"
end

# ✅ GOOD: Use mapped icon alternatives or Lucide
def generate_widget(title, icon_name)
  lucide_icon = map_icon_to_lucide(icon_name)
  "<i data-lucide=\"#{lucide_icon}\"></i><span>#{title}</span>"
end
```

**Always check:**
- `app/services/**/*.rb` - Dynamic content generation
- `app/jobs/**/*.rb` - Background job outputs
- `app/lib/**/*.rb` - Utility functions generating HTML
- Any file with `"<i class="` or `'<i class='` patterns

### References

- Rails Guides: Asset Pipeline
- Rails Conventions: Partial Naming
- MDN: Browser Caching Strategies
- Performance Best Practices: Resource Consolidation
