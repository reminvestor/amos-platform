# Styling Cleanup Plan

**Created**: 2025-11-18
**Status**: Planning Phase
**Estimated Effort**: 40-60 hours

## Executive Summary

The application has **systemic styling issues** that need comprehensive cleanup:

- **1,536 inline `style=` attributes** across 100+ ERB files (34% of all templates)
- **85 `!important` tags** in SCSS files
- **1,780 `!important` tags** in CSS (mostly vendor files)
- Inconsistent use of utility classes vs custom CSS
- Lack of reusable component patterns

## Problem Breakdown

### 1. Inline Styles by Area

| Area | Inline Styles | Files | Priority |
|------|--------------|-------|----------|
| **Scout Canvases** | 1,013 (66%) | 23 | 🔴 Critical |
| **Admin Pages** | 836 (54%) | 55 | 🟡 High |
| **Landing Pages** | 109 (7%) | 5 | 🟢 Medium |
| **Other** | ~600 (39%) | ~20 | 🟢 Low |

### 2. Top Offenders (Files with Most Inline Styles)

**Scout Canvases:**
- `_analytics_dashboard.html.erb` - 123 instances
- `_campaign_viewer.html.erb` - 124 instances
- `_contact_viewer.html.erb` - 116 instances
- `_email_template_editor.html.erb` - 98 instances
- `_integrations_manager.html.erb` - 94 instances
- `_landing_page_viewer.html.erb` - 83 instances
- `_email_template_viewer.html.erb` - 65 instances
- `_default.html.erb` - 63 instances
- `_integration_operations.html.erb` - 62 instances

**Admin Pages:**
- `agent_lightning/dashboard.html.erb` - 145 instances
- `agent_lightning/metrics.html.erb` - 82 instances
- `agent_lightning/models_performance.html.erb` - 58 instances
- `users/show.html.erb` - 50 instances
- `observability/ai_usage.html.erb` - 46 instances
- `dashboard/index.html.erb` - 41 instances

**Landing Pages:**
- `edit.html.erb` - 64 instances
- `new.html.erb` - 30 instances

### 3. `!important` Usage

**SCSS Files:**
- `scout.scss` - 33 instances
- `admin_dark.scss` - 52 instances

**CSS Files** (compiled/vendor):
- `application.css` - 1,722 instances (vendor code)
- `admin_dark.css` - 54 instances
- `actiontext.css`, `trix.css` - 4 instances (vendor)

## Root Causes

1. **No Utility Class System**: Before recent work, no comprehensive utility classes existed
2. **Component Duplication**: Same patterns (stat cards, tables, buttons) implemented differently across files
3. **No Style Guidelines**: Developers defaulted to inline styles for quick fixes
4. **Canvas Complexity**: Scout canvases are dynamically loaded, leading to self-contained styling
5. **Legacy Bootstrap Migration**: Mixing Bootstrap 3/4/5 patterns
6. **No Linting**: No automated checks to prevent inline styles

## Solution Strategy

### Phase 1: Foundation (Completed ✅)
- [x] Create dark theme utility class system (`admin_dark.scss`)
- [x] Create reusable helpers (`admin_helper.rb`)
- [x] Create stat card partial (`admin/shared/_stat_card.html.erb`)
- [x] Document patterns in Rails UX Expert skill
- [x] Update 5 admin pages as proof of concept

### Phase 2: Admin Pages Cleanup (High Priority)
**Estimated**: 15-20 hours

**Approach**:
1. Identify common patterns (cards, tables, forms, badges)
2. Create partials for repeated components
3. Systematically replace inline styles with utility classes
4. Use helpers (`admin_status_badge`, `admin_icon`, etc.)

**Files** (55 total):
- Dashboard pages (3 files, ~217 inline styles)
- Agent Lightning pages (3 files, ~285 inline styles)
- Observability pages (4 files, ~93 inline styles)
- User management (3 files, ~112 inline styles)
- Integrations/Connections (10 files, ~200 inline styles)
- Others (32 files, ~100 inline styles)

**Expected Outcome**:
- 836 inline styles → 0-50 (data-driven only)
- Consistent dark theme application
- Reusable components extracted

### Phase 3: Scout Canvases Cleanup (Critical Priority)
**Estimated**: 20-25 hours

**Challenge**: Scout canvases are dynamically loaded via SSE/Turbo Streams, requiring special handling.

**Approach**:
1. Create canvas-specific utility classes
2. Extract common canvas patterns:
   - Data viewers (contact, document, landing page, campaign)
   - Editors (email template, landing page)
   - Managers (integrations, analytics)
   - Progress indicators (task progress, parallel tasks)
3. Create canvas component partials
4. Ensure Turbo/SSE compatibility

**Files** (23 total):
- Viewers (8 files, ~450 inline styles)
- Editors (3 files, ~158 inline styles)
- Managers/Dashboards (4 files, ~268 inline styles)
- Wizards/Forms (5 files, ~50 inline styles)
- Miscellaneous (3 files, ~87 inline styles)

**Expected Outcome**:
- 1,013 inline styles → 50-100 (data-driven/dynamic only)
- Consistent canvas styling
- Better loading performance (less HTML overhead)

### Phase 4: Landing Pages Cleanup (Medium Priority)
**Estimated**: 5-8 hours

**Files** (5 total, ~109 inline styles):
- `edit.html.erb` - 64 instances
- `new.html.erb` - 30 instances
- `index.html.erb` - 8 instances
- `chat.html.erb` - 6 instances
- `inline_edit.html.erb` - 1 instance

**Approach**:
1. Create landing page specific utilities
2. Standardize form layouts
3. Extract editor components

**Expected Outcome**:
- 109 inline styles → 10-20 (data-driven only)

### Phase 5: Other Pages Cleanup (Low Priority)
**Estimated**: 8-10 hours

**Areas**:
- Campaigns (2 files, ~77 inline styles)
- Contacts (4 files, ~45 inline styles)
- Documents (9 files, ~50 inline styles)
- User settings (3 files, ~24 inline styles)
- Entity management (3 files, ~116 inline styles)
- Mailers (7 files, ~30 inline styles)
- Others (~20 files, ~258 inline styles)

**Expected Outcome**:
- ~600 inline styles → 50-100 (data-driven only)

### Phase 6: SCSS Cleanup
**Estimated**: 3-5 hours

**Tasks**:
1. Remove `!important` from `scout.scss` (33 instances)
2. Remove `!important` from `admin_dark.scss` (52 instances)
3. Refactor specificity issues causing need for `!important`
4. Document when `!important` is acceptable (vendor overrides only)

**Expected Outcome**:
- 85 SCSS `!important` → 5-10 (vendor overrides only)

### Phase 7: Prevention & Documentation
**Estimated**: 2-3 hours

**Tasks**:
1. Add ERB linting rules (rubocop-rails, erb-lint)
2. Add SCSS linting rules (stylelint)
3. Create PR template checklist
4. Document style guide in `/docs/STYLE_GUIDE.md`
5. Add pre-commit hooks

**Linting Rules**:
```ruby
# .erb-lint.yml
ERBLint:
  linters:
    NoInlineStyles:
      enabled: true
      exceptions:
        - "width: <%= " # Allow data-driven values
        - "height: <%= "
```

```scss
// .stylelintrc
rules:
  declaration-no-important: true
  selector-max-specificity: "0,3,2"
```

## Implementation Phases

### Recommended Order

1. **Week 1**: Admin Pages Cleanup (Phase 2)
   - Highest ROI
   - Already have utilities/helpers
   - Clear patterns established

2. **Week 2-3**: Scout Canvases Cleanup (Phase 3)
   - Most complex
   - Highest inline style count
   - Requires canvas-specific utilities

3. **Week 4**: Landing Pages + Other Pages (Phases 4-5)
   - Lower priority
   - Can batch similar patterns

4. **Week 5**: SCSS Cleanup + Prevention (Phases 6-7)
   - Final polish
   - Set up guardrails

## Success Metrics

### Before Cleanup:
- **1,536** inline `style=` attributes
- **85** SCSS `!important` tags
- **0** linting rules
- **Inconsistent** component patterns

### After Cleanup:
- **100-200** inline styles (data-driven values only)
- **5-10** SCSS `!important` (vendor overrides only)
- **100%** linting coverage
- **Consistent** component library

### Quality Indicators:
- [ ] All pages use utility classes
- [ ] Reusable components extracted
- [ ] Helpers used consistently
- [ ] Linting prevents regressions
- [ ] Documentation complete
- [ ] Zero accessibility violations

## Utility Classes Needed

Based on analysis, we need to add:

**Layout**:
- `.canvas-container`, `.canvas-header`, `.canvas-body`
- `.form-grid-2col`, `.form-grid-3col`

**Spacing** (expand current):
- `.admin-p-sm`, `.admin-p-md`
- `.admin-m-{size}` for all directions
- `.admin-gap-{size}` for flexbox gaps

**Typography**:
- `.admin-text-xs`, `.admin-text-sm`, `.admin-text-lg`
- `.admin-font-mono` for code blocks

**Display**:
- `.admin-flex`, `.admin-flex-col`, `.admin-flex-row`
- `.admin-grid-2`, `.admin-grid-3`, `.admin-grid-4`
- `.admin-nowrap`, `.admin-truncate`

**Components**:
- `.admin-code-block`, `.admin-pre`
- `.admin-divider-h`, `.admin-divider-v`
- `.admin-loading-spinner`

## Risk Mitigation

1. **Testing Strategy**:
   - Visual regression testing (Percy/BackstopJS)
   - Manual QA on all updated pages
   - Selenium tests for critical flows

2. **Rollback Plan**:
   - Git branching: `feature/styling-cleanup-phase-{n}`
   - Deploy incrementally (1 phase per week)
   - Feature flags for canvas changes

3. **Documentation**:
   - Before/after screenshots
   - Component usage examples
   - Migration guide for team

## Resources Required

- **Developer Time**: 40-60 hours (1-2 developers, 5-6 weeks)
- **QA Time**: 15-20 hours (visual regression + manual testing)
- **Design Review**: 5-8 hours (verify dark theme consistency)

## Next Steps

1. **Immediate**: Review and approve this plan
2. **Week 1 Prep**:
   - Add missing utility classes to `admin_dark.scss`
   - Create canvas-specific utilities file
   - Set up visual regression testing
3. **Week 1 Execution**: Start Phase 2 (Admin Pages)

---

**Questions?** Contact the development team for clarification or adjustments to this plan.
