# Font Awesome to Lucide Icon Mapping

Complete mapping for replacing Font Awesome icons with Lucide equivalents.

## Syntax Change

**Font Awesome:**
```erb
<i class="fas fa-check"></i>
<i class="far fa-user"></i>
```

**Lucide:**
```erb
<i data-lucide="check"></i>
<i data-lucide="user"></i>
```

## Common Icon Mappings

| Font Awesome | Lucide | Count |
|--------------|--------|-------|
| fa-check | check | 119 |
| fa-info-circle | info | 32 |
| fa-robot | bot | 26 |
| fa-edit | pencil / edit-2 | 24 |
| fa-chart-line | trending-up / line-chart | 24 |
| fa-arrow-left | arrow-left | 24 |
| fa-plus | plus | 21 |
| fa-exclamation-triangle | alert-triangle | 20 |
| fa-magic | wand-2 / sparkles | 19 |
| fa-eye | eye | 18 |
| fa-check-circle | check-circle | 18 |
| fa-save | save | 16 |
| fa-clock | clock | 16 |
| fa-envelope | mail | 15 |
| fa-users | users | 13 |
| fa-upload | upload | 13 |
| fa-times | x | 13 |
| fa-paper-plane | send | 13 |
| fa-globe | globe | 12 |
| fa-user-plus | user-plus | 10 |
| fa-key | key | 10 |
| fa-code | code | 10 |
| fa-link | link | 9 |
| fa-image | image | 9 |
| fa-download | download | 9 |
| fa-cog | settings | 9 |
| fa-trash | trash-2 | 8 |
| fa-search | search | 8 |
| fa-plug | plug | 8 |
| fa-file-alt | file-text | 8 |
| fa-user | user | 7 |
| fa-spinner | loader | 7 |
| fa-cube | box | 7 |
| fa-copy | copy | 7 |
| fa-arrow-right | arrow-right | 7 |
| fa-tasks | list-checks | 6 |
| fa-plus-circle | plus-circle | 6 |

## Additional Common Mappings

| Font Awesome | Lucide |
|--------------|--------|
| fa-home | home |
| fa-bars | menu |
| fa-calendar | calendar |
| fa-heart | heart |
| fa-star | star |
| fa-comment | message-square |
| fa-comments | messages-square |
| fa-bell | bell |
| fa-folder | folder |
| fa-file | file |
| fa-tag | tag |
| fa-refresh | refresh-cw |
| fa-sync | refresh-cw |
| fa-undo | undo |
| fa-redo | redo |
| fa-print | printer |
| fa-share | share-2 |
| fa-external-link | external-link |
| fa-lock | lock |
| fa-unlock | unlock |
| fa-filter | filter |
| fa-sort | arrow-up-down |
| fa-question-circle | help-circle |
| fa-lightbulb | lightbulb |
| fa-dashboard | layout-dashboard |
| fa-chart-bar | bar-chart |
| fa-chart-pie | pie-chart |
| fa-database | database |
| fa-server | server |
| fa-cloud | cloud |
| fa-bug | bug |
| fa-wrench | wrench |
| fa-palette | palette |
| fa-paint-brush | paintbrush |
| fa-shopping-cart | shopping-cart |
| fa-credit-card | credit-card |
| fa-building | building |
| fa-briefcase | briefcase |
| fa-phone | phone |
| fa-mobile | smartphone |
| fa-wifi | wifi |
| fa-rss | rss |
| fa-video | video |
| fa-camera | camera |
| fa-microphone | mic |

## Special Cases

### Spinning Icons
**Font Awesome:**
```erb
<i class="fas fa-spinner fa-spin"></i>
```

**Lucide (with CSS):**
```erb
<i data-lucide="loader" class="lucide-spin"></i>
```

Add to CSS:
```css
.lucide-spin {
  animation: spin 1s linear infinite;
}
@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
```

### Fixed Width Icons
**Font Awesome:**
```erb
<i class="fas fa-home fa-fw"></i>
```

**Lucide:**
```erb
<i data-lucide="home" style="width: 1.25rem; height: 1.25rem; display: inline-block;"></i>
```

### Icon Sizing
Font Awesome `fa-lg`, `fa-2x`, `fa-3x` should be replaced with inline styles or CSS classes:
```erb
<i data-lucide="user" style="width: 2rem; height: 2rem;"></i>
```

## After Replacement

Don't forget to initialize Lucide icons:
```javascript
document.addEventListener('DOMContentLoaded', () => {
  lucide.createIcons();
});

document.addEventListener('turbo:load', () => {
  lucide.createIcons();
});
```
