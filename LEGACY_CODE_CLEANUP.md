# Legacy Code Cleanup Tracker

## 🗑️ Files and Code to Remove After Implementation

### Phase 1: After TaskSession Implementation
- **Remove Rails Cache Usage**:
  - `scout_controller.rb`: Remove all `Rails.cache.read/write` for wizard state
  - `scout_generic_tools_service.rb`: Remove cache-based task list storage
  
### Phase 2: After DSL Implementation  
- **Remove Direct HTML Generation**:
  - `landing_page_agent.rb`: Remove raw HTML generation code
  - `email_template_agent.rb`: Consider migrating to DSL pattern
  - Remove any `sanitize` calls that won't be needed with DSL

### Phase 3: After Workflow Engine
- **Consolidate Canvas Views**:
  - Merge `_task_progress.html.erb` and `_interactive_wizard.html.erb`
  - Remove wizard-specific JavaScript in favor of unified workflow UI
  - Consolidate `wizard_controller.js` and `scout_controller.js`

### Phase 4: After Tool Contracts
- **Remove Unvalidated Tool Calls**:
  - Direct tool invocations without schema validation
  - Manual parameter checking code
  - Ad-hoc retry logic

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
