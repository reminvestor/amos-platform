# UI/UX Style Guide

This guide documents best practices and conventions for all UI/UX development in the AMOS platform.

---

## Icon System (Lucide Icons)

### Best Practice: Always Use CSS Classes for Icon Sizing

**Rule**: All Lucide icons must use predefined sizing classes instead of inline styles.

**Why**:
- Consistent icon sizing across the application
- Easier to maintain and update globally
- Leverages application.scss predefined classes
- Better performance (smaller CSS footprint)
- Easier for developers to find and understand sizing

### Available Sizing Classes

The following predefined sizing classes are available in `app/assets/stylesheets/application.scss`:

```scss
.icon-xs   { width: 0.75rem;  height: 0.75rem;  }  /* 12px */
.icon-sm   { width: 0.875rem; height: 0.875rem; }  /* 14px */
.icon-md   { width: 1rem;     height: 1rem;     }  /* 16px */
.icon-lg   { width: 1.25rem;  height: 1.25rem; }  /* 20px */
.icon-xl   { width: 1.5rem;   height: 1.5rem;  }  /* 24px */
.icon-2x   { width: 2rem;     height: 2rem;    }  /* 32px */
.icon-3x   { width: 3rem;     height: 3rem;    }  /* 48px */
.icon-4x   { width: 4rem;     height: 4rem;    }  /* 64px */
```

### Do's and Don'ts

#### ❌ DON'T: Use inline styles for icon sizing

```erb
<!-- BAD -->
<i data-lucide="minimize-2" style="width: 1rem; height: 1rem;"></i>
<i data-lucide="settings" style="width: 1.25rem; height: 1.25rem; margin-right: 0.5rem;"></i>
```

#### ✅ DO: Use predefined classes

```erb
<!-- GOOD -->
<i data-lucide="minimize-2" class="icon-md"></i>
<i data-lucide="settings" class="icon-lg me-2"></i>
```

### Real-World Examples

#### Scout Layout Preset Buttons (16px icons in small buttons)
```erb
<button class="preset-btn">
  <i data-lucide="minimize-2" class="icon-md"></i>
</button>
```

#### Navigation Items (20px icons with spacing)
```erb
<a href="#" class="nav-item">
  <i data-lucide="home" class="icon-lg me-2"></i>
  Home
</a>
```

#### Card Headers (24px icons)
```erb
<div class="card-header">
  <h5 class="mb-0">
    <i data-lucide="settings" class="icon-xl me-2"></i>
    Settings
  </h5>
</div>
```

#### Page Headers (48px icons)
```erb
<h1 class="text-center mb-4">
  <i data-lucide="rocket" class="icon-3x mb-3 d-block"></i>
  Launch Campaign
</h1>
```

### Sizing Guidelines by Context

| Context | Size | Class | Usage |
|---------|------|-------|-------|
| Badges, small UI | 12-14px | `.icon-xs`, `.icon-sm` | Status badges, small indicators |
| Button icons | 16px | `.icon-md` | Buttons with icons (preset buttons, etc.) |
| Navigation items | 20px | `.icon-lg` | Menus, navigation items |
| Card headers | 24px | `.icon-xl` | Card titles, section headers |
| Large card icons | 32px | `.icon-2x` | Hero sections, stat cards |
| Page headers | 48-64px | `.icon-3x`, `.icon-4x` | Large hero areas, page intros |

### Colors with Icons

When combining colors with icons, use Bootstrap color utilities:

```erb
<!-- Good: Using Bootstrap utility classes -->
<i data-lucide="check-circle" class="icon-lg text-success"></i>
<i data-lucide="alert-circle" class="icon-lg text-danger"></i>

<!-- Also acceptable for custom colors (but prefer Bootstrap utilities) -->
<i data-lucide="star" class="icon-lg" style="color: #facc15;"></i>
```

### Icon with Spacing

Use Bootstrap margin utilities instead of inline styles:

```erb
<!-- Good: Using Bootstrap utilities -->
<i data-lucide="settings" class="icon-md me-2"></i>Settings

<!-- Bad: Using inline styles -->
<i data-lucide="settings" style="width: 1rem; height: 1rem; margin-right: 0.5rem;"></i>Settings
```

---

## Ludicendar Icon Migration

Lucide icons use the `data-lucide="icon-name"` attribute. All instances should have been migrated from Font Awesome. If you encounter Font Awesome icons:

**Report**: Please report any remaining Font Awesome icons (`fa-*`, `fas`, `far`, `fab`) in issue tickets for migration to Lucide.

---

## Button Styling

### Button Padding Guidelines

Scout buttons use compact padding for better UI density:

| Button Type | Padding | Font Size | Example |
|------------|---------|-----------|---------|
| Suggestion buttons | `0.375rem 0.75rem` | `0.8rem` | `.suggestion-btn` |
| Preset buttons | `0.375rem 0.5rem` | `0.75rem` | `.preset-btn` |
| Model preset buttons | `0.375rem 0.5rem` | `0.8rem` | `.model-preset-btn` |

Icons within these buttons should use `.icon-md` (16px) for proper proportions.

---

## Canvas Components

Scout canvas components should follow these styling conventions:

- Use inline styles only for **layout** (positioning, sizing containers)
- Use classes for **colors, typography, borders**
- Use icon sizing classes for **all icons**

Example:

```erb
<!-- Good: Layout inline, styling via classes -->
<div style="position: absolute; left: 1rem; top: 50%; transform: translateY(-50%);">
  <i data-lucide="search" class="icon-lg text-muted"></i>
</div>

<!-- Bad: Sizing inline -->
<i data-lucide="search" style="position: absolute; left: 1rem; top: 50%; transform: translateY(-50%); width: 1.25rem; height: 1.25rem;"></i>
```

---

## Resources

- **Icon Library**: [Lucide Icons](https://lucide.dev/) - Browse available icons
- **Bootstrap Utilities**: [Bootstrap Spacing](https://getbootstrap.com/docs/5.0/utilities/spacing/) - Margin/padding utilities
- **Application Stylesheet**: `app/assets/stylesheets/application.scss` - Icon class definitions
- **Scout Stylesheet**: `app/assets/stylesheets/scout.scss` - Scout-specific styles

---

## Checklist for UI/UX Changes

Before submitting a PR with UI/UX changes:

- [ ] All icons use `.icon-*` sizing classes, not inline styles
- [ ] No Font Awesome icons remain (`fa-*`, `fas`, `far`, `fab`)
- [ ] Button padding matches guidelines in scout.scss
- [ ] Spacing uses Bootstrap utilities (`.me-*`, `.ms-*`, `.mb-*`, etc.)
- [ ] Colors use Bootstrap utilities or theme variables when possible
- [ ] ARIA labels present for interactive icons
- [ ] Component tested in dark and light modes (if applicable)
