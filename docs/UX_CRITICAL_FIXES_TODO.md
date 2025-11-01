# UX Critical Fixes - TODO Checklist

> **Generated**: 2025-10-29
> **Priority**: Critical issues affecting performance, accessibility, and maintainability

---

## 🚨 CRITICAL PRIORITY

### 1. Move Inline Styles from application.html.erb to SCSS

**File**: `app/views/layouts/application.html.erb` (Lines 31-146)

**Problem**: 115 lines of CSS embedded directly in HTML template
- Cannot be cached by browser
- Increases page size on every request
- Difficult to maintain
- Violates separation of concerns

**Action Items**:
- [ ] Create new file: `app/assets/stylesheets/layout.scss`
- [ ] Move sidebar styles (`.sidebar`, `.sidebar-collapsed`, `.sidebar-header`, `.sidebar-link`, `.sidebar-toggle`)
- [ ] Move main content styles (`.main-content`, `.main-content-expanded`)
- [ ] Move responsive styles (`@media` queries)
- [ ] Import in `app/assets/stylesheets/application.scss`
- [ ] Delete lines 31-146 from `application.html.erb`
- [ ] Test sidebar functionality still works

**Estimated Time**: 2 hours
**Impact**: High - improves caching, page load speed, maintainability

---

### 2. Fix Flash Message Inline Styles

**File**: `app/views/layouts/application.html.erb` (Lines 367-384)

**Problem**: Flash alerts use hardcoded inline positioning instead of Bootstrap utilities

**Action Items**:
- [ ] Replace notice flash message with Bootstrap utility classes
- [ ] Replace alert flash message with Bootstrap utility classes
- [ ] Remove all inline `style=""` attributes
- [ ] Use: `position-fixed`, `top-0`, `start-50`, `translate-middle-x`, `mt-5`, `w-90`
- [ ] Test flash messages display correctly on all screen sizes

**Estimated Time**: 30 minutes
**Impact**: Medium - better maintainability, consistent with Bootstrap patterns

---

### 3. Create Stimulus Controller for Sidebar Toggle

**File**: `app/views/layouts/application.html.erb` (Lines 391-415)

**Problem**: JavaScript embedded in ERB template instead of proper Stimulus controller

**Action Items**:
- [ ] Create new file: `app/javascript/controllers/sidebar_controller.js`
- [ ] Implement `connect()` method to restore state from localStorage
- [ ] Implement `toggle()` action
- [ ] Implement `collapse()` and `expand()` helper methods
- [ ] Update `application.html.erb` to use `data-controller="sidebar"`
- [ ] Add `data-sidebar-target="sidebar"` to sidebar div
- [ ] Add `data-sidebar-target="content"` to main-content div
- [ ] Add `data-action="click->sidebar#toggle"` to toggle button
- [ ] Delete JavaScript block (lines 391-415) from ERB
- [ ] Test sidebar toggle works with localStorage persistence

**Estimated Time**: 1.5 hours
**Impact**: High - follows Rails/Stimulus best practices, easier to maintain

---

### 4. Add Missing ARIA Labels (Accessibility)

**Files**: Multiple locations in `app/views/layouts/application.html.erb`

**Problem**: Icon-only buttons missing accessibility labels (WCAG violation)

**Action Items**:

#### Sidebar Toggle Button (Line 157)
- [ ] Add `aria-label="Toggle sidebar navigation"`
- [ ] Add `aria-expanded="false"` (update dynamically via Stimulus)
- [ ] Add `aria-hidden="true"` to the `<i>` icon element

#### User Dropdown (Line 169)
- [ ] Add `aria-haspopup="true"` to dropdown toggle
- [ ] Add `aria-label="User account menu"`
- [ ] Verify `aria-expanded` toggles correctly

#### All Icon-Only Buttons in Sidebar
- [ ] Audit all sidebar links for icon-only instances
- [ ] Add descriptive `aria-label` attributes
- [ ] Add `aria-hidden="true"` to all decorative icons

**Estimated Time**: 2 hours
**Impact**: Critical - accessibility compliance (WCAG 2.1 AA requirement)

---

### 5. Replace Inline Style Manipulation in Voice Assistant

**File**: `app/javascript/controllers/voice_assistant_controller.js` (Lines 977-996)

**Problem**: JavaScript directly manipulating `element.style` instead of CSS classes

**Action Items**:
- [ ] Create CSS classes in SCSS: `.voice-active`, `.voice-continuous`
- [ ] Define `@keyframes pulse` animation in SCSS
- [ ] Update `updateButton(state)` method to use `classList.toggle()`
- [ ] Remove all `this.buttonTarget.style.animation = ...` lines
- [ ] Add SCSS to `app/assets/stylesheets/scout.scss` or new `voice_assistant.scss`
- [ ] Test voice button animations work correctly

**Before** (Lines 985-989):
```javascript
if (this.continuousMode) {
  this.buttonTarget.style.animation = "pulse 2s infinite"
} else {
  this.buttonTarget.style.animation = ""
}
```

**After**:
```javascript
this.buttonTarget.classList.toggle("voice-continuous", this.continuousMode)
```

**Estimated Time**: 1 hour
**Impact**: Medium - follows best practices, easier to maintain/theme

---

## 📊 SUMMARY

| Fix | Files | Time | Impact |
|-----|-------|------|--------|
| Inline styles → SCSS | 1 | 2h | High |
| Flash message styles | 1 | 0.5h | Medium |
| Sidebar Stimulus controller | 2 | 1.5h | High |
| ARIA labels | 1 | 2h | Critical |
| Voice button styles | 2 | 1h | Medium |
| **TOTAL** | **5-7** | **7 hours** | **Accessibility + Performance** |

---

## ✅ VERIFICATION CHECKLIST

After completing all fixes:

- [ ] Run `bin/dev` and verify no CSS errors
- [ ] Test sidebar toggle on desktop
- [ ] Test sidebar toggle on mobile (responsive behavior)
- [ ] Test flash messages display correctly
- [ ] Test voice assistant button states and animations
- [ ] Run accessibility audit: `pa11y http://localhost:3000`
- [ ] Test keyboard navigation (Tab, Enter, Escape)
- [ ] Verify localStorage persistence for sidebar state
- [ ] Check browser console for any JavaScript errors
- [ ] Test with screen reader (VoiceOver on Mac, NVDA on Windows)

---

## 📚 REFERENCES

- [Bootstrap 5 Utilities](https://getbootstrap.com/docs/5.3/utilities/api/)
- [Stimulus Handbook](https://stimulus.hotwired.dev/)
- [WCAG 2.1 Quick Reference](https://www.w3.org/WAI/WCAG21/quickref/)
- [Rails Asset Pipeline](https://guides.rubyonrails.org/asset_pipeline.html)

---

## 🎯 NEXT STEPS AFTER CRITICAL FIXES

See `docs/UX_IMPROVEMENTS_NEEDED.md` for non-critical enhancements:
- Mobile offcanvas sidebar implementation
- Icon library standardization
- Visual waveform for voice assistant
- Navigation loading states
- SCSS file organization/splitting
