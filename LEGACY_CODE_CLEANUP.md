# Legacy Code Cleanup Tracker

## 🗑️ Files and Code to Remove After Implementation

### ✅ IDENTIFIED LEGACY CODE TO REMOVE:

#### **1. Old Landing Page Generation Jobs**
- `app/jobs/simple_ai_landing_page_job.rb` - Raw HTML generation
- `app/jobs/generate_full_landing_page_job.rb` - Direct HTML generation
- `app/jobs/agent_generate_landing_page_job.rb` - Old agent system
- `app/jobs/generate_landing_page_content_job.rb` - OpenAI direct calls

#### **2. Legacy AI Agents (Raw HTML)**
- `app/services/ai_agents/orchestrator.rb` - Complex multi-agent system
- `app/services/ai_agents/prompt_agent.rb` - Raw HTML prompts
- `app/services/ai_agents/landing_page_edit_agent.rb` - Direct HTML editing

#### **3. Form Template Service (Replaced by DSL)**
- `app/services/landing_page_form_templates_service.rb` - Static HTML templates

#### **4. Rails Cache Usage (Replaced by TaskSession)**
- `scout_controller.rb`: All `Rails.cache.read/write` for task lists
- `scout_generic_tools_service.rb`: Cache-based task management

#### **5. Old Canvas Views (Can be consolidated)**
- Consider merging similar canvas views after workflow unification
- Remove wizard-specific JavaScript duplicates

#### **6. Direct HTML Generation Code**
- Any remaining `sanitize` calls for raw HTML
- Direct HTML string concatenation
- Unsafe HTML generation patterns

### Phase 1: Critical Removals (High Impact)
- **Old landing page jobs** - These create raw HTML unsafely
- **Rails cache usage** - Replaced by database-backed TaskSession
- **Legacy form templates** - Replaced by DSL form generation

### Phase 2: Agent System Cleanup  
- **Old AI agents** - Replaced by LandingPageDslAgent
- **Raw HTML generation** - All moved to DSL system
- **Unsafe HTML handling** - Replaced by sanitized compilation

### Phase 3: UI Consolidation
- **Duplicate canvas logic** - Merge similar views
- **Redundant JavaScript** - Consolidate workflow handling
- **Unused CSS** - Remove wizard-specific styles

### Phase 4: Final Polish
- **Commented code** - Remove old implementations
- **Unused imports** - Clean up require statements  
- **Dead routes** - Remove unused endpoints

## 🔍 Code Patterns to Search and Remove

```bash
# Find Rails cache usage for wizard/task state
grep -r "Rails.cache.*wizard" app/
grep -r "Rails.cache.*task_list" app/

# Find direct HTML generation
grep -r "generate.*html" app/services/
grep -r "sanitize.*html" app/

# Find wizard-specific code
grep -r "wizard_state" app/
grep -r "wizard_canvas" app/
```

## 📋 Cleanup Checklist

### Before Starting Cleanup:
- [ ] Ensure all tests pass with new implementation
- [ ] Verify feature parity in production
- [ ] Create backup branch: `git checkout -b pre-cleanup-backup`

### During Cleanup:
- [ ] Remove one category at a time
- [ ] Run tests after each removal
- [ ] Update documentation as needed
- [ ] Check for broken references

### After Cleanup:
- [ ] Run full test suite
- [ ] Manual QA of all workflows
- [ ] Update README files
- [ ] Remove this cleanup tracker file

## ⚠️ Dependencies to Check

### External Dependencies:
- Any JavaScript libraries only used by legacy wizard
- Gems that were wizard-specific
- CSS classes that will become unused

### Internal Dependencies:
- Other services calling removed methods
- Background jobs using old interfaces
- API endpoints that might expect old formats

## 🎯 Success Criteria

- [ ] No references to Rails cache for task state
- [ ] All HTML generation goes through DSL compiler
- [ ] Single unified workflow UI system
- [ ] All tools use contract validation
- [ ] Codebase is cleaner and more maintainable

---

*This cleanup will be performed incrementally as each phase of the new system is implemented and verified.*
