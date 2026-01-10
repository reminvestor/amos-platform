# Merge Plan: feature/scout-ui-redesign → feature/ux-improvements

**Date**: October 31, 2025
**Branches**: `feature/scout-ui-redesign` → `feature/ux-improvements`
**Common Ancestor**: `8780738` (Improve .gitignore and .dockerignore)
**Overlapping Files**: 182 out of 185 files

---

## Executive Summary

Both branches have extensive changes (182 overlapping files). The `scout-ui-redesign` branch focuses on **Scout chat UI improvements and model selection**, while `ux-improvements` focuses on **accessibility, Bootstrap compliance, and Font Awesome→Lucide migration**.

**Strategy**: **Three-way merge with manual conflict resolution** for critical Scout files, automated merge for non-conflicting changes.

---

## Branch Analysis

### feature/scout-ui-redesign (19 Scout-specific commits)
**Focus**: Scout chat interface redesign and functionality

**Key Changes**:
1. **Model Selection UI** - Claude model picker (Sonnet 4.5, Haiku 3.5, etc.)
2. **Brain Icon Model Selector** - Moved to input area with power slider
3. **Chat Avatars** - Square with rounded corners, gradient backgrounds
4. **Modern Dark Theme** - Updated Scout layout and styling
5. **Source Citations** - RAG query transparency
6. **Document Query Improvements** - Better RAG integration
7. **Font Awesome → Lucide** - Partial migration (Part 1 & 2)

**Critical Files**:
- `app/views/scout/index.html.erb` - Chat UI structure
- `app/assets/stylesheets/scout.scss` - Scout-specific styles
- `app/javascript/controllers/scout_controller.js` - Chat logic & model selection
- `app/views/layouts/scout.html.erb` - Scout layout
- `app/controllers/scout_controller.rb` - Backend logic

### feature/ux-improvements (7 commits today + 41 earlier)
**Focus**: Accessibility, maintainability, icon migration

**Key Changes**:
1. **230+ ARIA Labels** - WCAG 2.1 compliance
2. **200+ Inline Styles Removed** - Bootstrap utilities
3. **68 Font Awesome → Lucide** - Including 3 Scout canvas files
4. **3 CSS Component Systems** - `.stat-card`, icon sizing, dropdown themes
5. **Form Validation Controller** - Reusable Stimulus controller
6. **Theme System** - Light/dark mode infrastructure
7. **Comprehensive Documentation** - UX_IMPROVEMENTS_SUMMARY.md

**Critical Files** (Same as scout-ui-redesign):
- `app/views/scout/index.html.erb` - Added aria-labels
- `app/assets/stylesheets/scout.scss` - Icon utilities
- `app/javascript/controllers/scout_controller.js` - Lucide migration
- `app/views/layouts/scout.html.erb` - Lucide initialization
- `app/controllers/scout_controller.rb` - Minimal changes

---

## Conflict Prediction

### High-Risk Files (Manual Resolution Required)

| File | scout-ui-redesign Changes | ux-improvements Changes | Conflict Type |
|------|---------------------------|------------------------|---------------|
| **scout/index.html.erb** | Model selector UI, avatar redesign, layout changes | ARIA labels, Lucide icons | **HIGH - Structure & Functionality** |
| **scout.scss** | Avatar styles, model selector styles, dark theme | Icon utilities, theme variables | **MEDIUM - Styles can coexist** |
| **scout_controller.js** | Model selection logic, avatar rendering | Lucide icon initialization | **MEDIUM - Logic + UI** |
| **layouts/scout.html.erb** | Layout updates, CDN changes | Lucide CDN, initialization | **LOW - CDN consolidation** |
| **scout_controller.rb** | Model selection backend | Minimal changes | **LOW - Backend logic** |

### Medium-Risk Files (Likely Auto-Merge)

| File | Reason |
|------|--------|
| `admin/observability_controller.rb` | Different sections modified |
| `admin/system_documents_controller.rb` | Different methods modified |
| `bedrock_service.rb` | Model selection vs general improvements |

### Low-Risk Files (Should Auto-Merge)

- Config files (Gemfile, routes, etc.) - Different sections
- Documentation files - Non-overlapping content
- RAG-related files - scout-ui-redesign has more RAG improvements
- Admin views - ux-improvements has more changes

---

## Merge Strategy

### Phase 1: Preparation (SAFETY FIRST)

```bash
# 1. Ensure clean working directory
git status

# 2. Create backup branch
git checkout feature/ux-improvements
git branch backup/ux-improvements-before-scout-merge

# 3. Fetch latest from both branches
git fetch origin feature/scout-ui-redesign
git fetch origin feature/ux-improvements

# 4. Ensure we're up to date
git pull origin feature/ux-improvements
```

### Phase 2: Attempt Automatic Merge

```bash
# Try automatic merge
git merge feature/scout-ui-redesign --no-commit --no-ff

# Check what conflicts arise
git status
```

**Expected Output**: ~5-10 merge conflicts, primarily in Scout files

### Phase 3: Resolve Conflicts (Priority Order)

#### 3.1. scout/index.html.erb (CRITICAL)

**Conflict Areas**:
- Model selector UI (scout-ui-redesign) vs ARIA labels (ux-improvements)
- Avatar structure changes vs accessibility improvements

**Resolution Strategy**: **KEEP BOTH**
1. Take scout-ui-redesign's model selector HTML structure
2. Add ux-improvements' ARIA labels to all buttons
3. Ensure Lucide icons from ux-improvements are used (not Font Awesome)
4. Test that model selector works + accessible

**Manual Steps**:
```bash
# Open file for manual merge
code app/views/scout/index.html.erb

# Strategy:
# - Keep scout-ui-redesign structure (model selector, avatars)
# - Add aria-label to every <button> and icon-only element
# - Replace any remaining fa-* with data-lucide equivalents
# - Add aria-hidden="true" to all decorative icons
```

#### 3.2. scout.scss (MEDIUM)

**Conflict Areas**:
- Avatar gradient styles (scout-ui-redesign)
- Icon sizing utilities (ux-improvements)
- Model selector styles (scout-ui-redesign)

**Resolution Strategy**: **MERGE BOTH SETS**
1. Keep scout-ui-redesign's avatar & model selector styles
2. Keep ux-improvements' `.icon-sm`, `.icon-md`, `.icon-xl`, `.icon-spin`
3. Merge without loss

**Manual Steps**:
```bash
code app/assets/stylesheets/scout.scss

# Strategy:
# - Combine both sets of styles
# - scout-ui-redesign styles first
# - ux-improvements utilities at end
# - No conflicts expected (different sections)
```

#### 3.3. scout_controller.js (MEDIUM)

**Conflict Areas**:
- Model selection logic (scout-ui-redesign)
- Lucide icon initialization (ux-improvements)
- Avatar rendering (scout-ui-redesign) vs icon changes (ux-improvements)

**Resolution Strategy**: **FUNCTIONAL MERGE**
1. Keep scout-ui-redesign's model selection functions
2. Keep ux-improvements' Lucide initialization
3. Update avatar rendering to use Lucide (not Font Awesome)
4. Ensure lucide.createIcons() is called after dynamic content

**Manual Steps**:
```bash
code app/javascript/controllers/scout_controller.js

# Strategy:
# - Keep all model selection code from scout-ui-redesign
# - Ensure Lucide initialization from ux-improvements is present
# - Replace fa-robot, fa-user with data-lucide="bot", data-lucide="user"
# - Add lucide.createIcons() after avatar creation
```

#### 3.4. layouts/scout.html.erb (LOW)

**Conflict Areas**:
- Lucide CDN link (both branches have it)
- Initialization scripts (both branches have them)

**Resolution Strategy**: **CONSOLIDATE**
1. Single Lucide CDN link (avoid duplicates)
2. Single initialization script (DOMContentLoaded + turbo:load)
3. Keep scout-ui-redesign's layout changes

**Manual Steps**:
```bash
code app/views/layouts/scout.html.erb

# Strategy:
# - Keep scout-ui-redesign structure
# - Ensure only ONE Lucide CDN link
# - Ensure only ONE initialization block
# - Remove duplicates
```

#### 3.5. scout_controller.rb (LOW)

**Conflict Areas**:
- Model selection backend (scout-ui-redesign)
- Minimal changes (ux-improvements)

**Resolution Strategy**: **TAKE scout-ui-redesign**
1. Scout-ui-redesign has more substantive backend changes
2. ux-improvements has minimal or no conflicting changes

**Manual Steps**:
```bash
code app/controllers/scout_controller.rb

# Strategy:
# - Accept scout-ui-redesign version
# - Verify no critical ux-improvements changes are lost
```

### Phase 4: Verify Non-Conflicting Files

```bash
# After resolving conflicts, check status
git status

# Look for files marked as "both modified"
# These need manual review even if auto-merged
```

**Files to Review** (even if auto-merged):
- `app/views/scout/canvas/_campaign_viewer.html.erb` - ux-improvements replaced FA icons
- `app/views/scout/canvas/_landing_page_viewer.html.erb` - ux-improvements replaced FA icons
- `app/views/scout/canvas/_email_template_editor.html.erb` - ux-improvements replaced FA icons

**Verification**: Ensure scout-ui-redesign didn't add new FA icons that conflict with our Lucide migration.

### Phase 5: Testing

```bash
# 1. Stage all resolved files
git add .

# 2. Run tests
docker compose exec web rails test

# 3. Start dev server
docker compose up -d

# 4. Manual testing checklist:
```

**Manual Testing Checklist**:
- [ ] Scout chat loads without errors
- [ ] Model selector UI appears and works
- [ ] Brain icon shows in input area
- [ ] Messages display with correct avatars (square, rounded)
- [ ] Lucide icons render correctly (no FA icons)
- [ ] ARIA labels present on all buttons (test with screen reader)
- [ ] Dark theme applied correctly
- [ ] Source citations appear in responses
- [ ] RAG document queries work
- [ ] Canvas components load (campaign viewer, etc.)
- [ ] Theme toggle works (if applicable)

### Phase 6: Commit & Document

```bash
# Create merge commit
git commit -m "Merge feature/scout-ui-redesign into feature/ux-improvements

**Strategy**: Manual resolution of Scout UI conflicts + automatic merge

**Major Changes from scout-ui-redesign:**
- Model selection UI with brain icon and power slider
- Square avatars with rounded corners and gradients
- Source citations for RAG queries
- Document query improvements
- Modern dark theme for Scout

**Preserved from ux-improvements:**
- 230+ ARIA labels (added to new UI elements)
- Lucide icons (replaced any remaining Font Awesome)
- Icon sizing utilities (.icon-sm, .icon-md, etc.)
- Form validation controller
- CSS component systems

**Conflicts Resolved:**
- scout/index.html.erb: Combined model selector + ARIA labels
- scout.scss: Merged avatar styles + icon utilities
- scout_controller.js: Model selection logic + Lucide init
- layouts/scout.html.erb: Consolidated CDN & initialization

**Testing:**
- ✅ Model selector functional
- ✅ Avatars render correctly
- ✅ All buttons have ARIA labels
- ✅ Lucide icons working
- ✅ RAG queries functional"

# Push to remote
git push origin feature/ux-improvements
```

---

## Risk Assessment

### Low Risk (90% confidence)
- Config files (routes, Gemfile, etc.) - Different sections modified
- Documentation files - Non-conflicting content
- Admin views - ux-improvements has more extensive changes
- RAG backend services - scout-ui-redesign has more changes

### Medium Risk (70% confidence)
- Scout SCSS - Both add styles, but different sections
- Scout JS controller - Different functions modified
- Bedrock service - Model selection vs general improvements

### High Risk (50% confidence)
- scout/index.html.erb - Significant structural changes in both branches
  - **Mitigation**: Manual line-by-line merge, extensive testing

---

## Rollback Plan

If merge causes issues:

```bash
# Option 1: Abort merge (before commit)
git merge --abort

# Option 2: Reset to pre-merge state (after commit)
git reset --hard backup/ux-improvements-before-scout-merge

# Option 3: Revert merge commit (after push)
git revert -m 1 <merge-commit-hash>
```

---

## Alternative Strategies

### Strategy A: Cherry-Pick Specific Commits (SAFER but TEDIOUS)

Instead of full merge, cherry-pick scout-ui-redesign commits one by one:

```bash
# List scout-ui-redesign commits
git log feature/scout-ui-redesign --oneline --not main

# Cherry-pick individually
git cherry-pick <commit-hash>

# Resolve conflicts per commit
# More granular but time-consuming (19 commits)
```

**Pros**:
- More control over each change
- Easier to identify what broke
- Can skip problematic commits

**Cons**:
- Extremely tedious (19 commits × manual resolution)
- May lose commit history context
- Takes 3-5x longer

### Strategy B: Merge Scout Features into New Branch (SAFEST)

Create a new integration branch:

```bash
# Create fresh branch from main
git checkout main
git checkout -b feature/integrated-ux-and-scout

# Merge ux-improvements first (our work is preserved)
git merge feature/ux-improvements

# Then merge scout-ui-redesign
git merge feature/scout-ui-redesign

# Resolve conflicts in new branch
# If it works, replace ux-improvements
# If it fails, discard integration branch
```

**Pros**:
- Original ux-improvements branch preserved
- Easy to discard if merge fails
- Can compare side-by-side

**Cons**:
- Creates third branch to manage
- Eventually need to consolidate

---

## Recommendation

**RECOMMENDED APPROACH**: **Phase 2-6 (Automatic Merge with Manual Resolution)**

**Rationale**:
1. **Efficiency**: Handles 90% of files automatically
2. **Control**: Manual resolution for critical 5-10 Scout files
3. **Preservation**: Keeps both branches' improvements
4. **Testability**: Can verify immediately
5. **Rollback**: Backup branch allows easy revert

**Timeline Estimate**:
- Phase 1 (Prep): 5 minutes
- Phase 2 (Auto-merge): 2 minutes
- Phase 3 (Resolve conflicts): 30-45 minutes
- Phase 4 (Review): 15 minutes
- Phase 5 (Testing): 20-30 minutes
- Phase 6 (Commit): 5 minutes

**Total**: ~1.5-2 hours

---

## Success Criteria

Merge is successful if:
- ✅ All tests pass
- ✅ Scout UI loads without errors
- ✅ Model selector works
- ✅ Lucide icons render (no Font Awesome)
- ✅ ARIA labels present on all buttons
- ✅ Dark theme applied correctly
- ✅ RAG queries functional
- ✅ Source citations appear
- ✅ No visual regressions
- ✅ No accessibility regressions

---

## Post-Merge Tasks

After successful merge:

1. **Update Documentation**:
   - Update UX_IMPROVEMENTS_SUMMARY.md with Scout UI changes
   - Document model selection feature
   - Update FA_TO_LUCIDE_MAPPING.md if new icons added

2. **Run Full Lighthouse Audit**:
   - Verify accessibility score still 92-95+
   - Check performance impact of model selector

3. **Create PR**:
   - Title: "Integrate Scout UI redesign with UX improvements"
   - Link to both original branches
   - Highlight merge strategy

4. **Clean Up**:
   ```bash
   # After successful PR merge to main
   git branch -d feature/scout-ui-redesign
   git push origin --delete feature/scout-ui-redesign
   ```

---

**Author**: Claude (Sonnet 4.5)
**Date**: October 31, 2025
**Status**: READY FOR EXECUTION
