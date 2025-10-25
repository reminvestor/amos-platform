# /test-feature Command

Comprehensive testing workflow for AMOS features, tools, and workflows.

## Usage

```
/test-feature [workflow_name]
```

## What This Command Does

Chains testing skills together for comprehensive feature validation:

1. **testing-tools-manually** - Test Scout AI tools individually
2. **testing-workflows-manually** - Test workflow end-to-end
3. **running-tests** - Run automated test suite
4. **Generate summary report** - Show test results

## Examples

```
/test-feature create_campaign
```

```
/test-feature landing_page_generation
```

## Testing Flow

### Phase 1: Tool Testing (testing-tools-manually skill)
For each tool in the workflow:
- Test with example parameters
- Test with edge cases
- Verify success/error responses
- Check entity scoping
- Validate tool registration

### Phase 2: Workflow Testing (testing-workflows-manually skill)
Test the complete workflow:
- Manual browser testing (Scout UI)
- Programmatic testing (console)
- View execution logs
- Check all phases execute correctly
- Verify context persistence

### Phase 3: Automated Tests (running-tests skill)
Run the test suite:
- Unit tests (models, services, tools)
- System tests (end-to-end flows)
- Integration tests
- Check test coverage

### Phase 4: Summary Report
Generate comprehensive report:
- Tool test results
- Workflow execution status
- Test suite results
- Coverage metrics
- Issues found

## Test Modes

**Quick Test** (during development):
```
Use testing-tools-manually with tool_name=your_tool
Use testing-workflows-manually with workflow=your_workflow
```

**Comprehensive Test** (before PR):
```
/test-feature your_workflow
```

## Success Criteria

- ✅ All tools tested individually
- ✅ Workflow executes successfully
- ✅ All phases complete
- ✅ Automated tests pass
- ✅ Coverage meets threshold
- ✅ No entity isolation issues

## Uses Skills

- **testing-tools-manually** - Individual tool validation
- **testing-workflows-manually** - Workflow execution testing
- **running-tests** - Automated test suite

## Tips

**Test as you build:**
- Test tools immediately after creation
- Test workflows before adding complexity
- Fix issues before moving to next phase

**Use specific skills for targeted testing:**
- Just tool testing: Use `testing-tools-manually` directly
- Just workflow testing: Use `testing-workflows-manually` directly
- Just automated tests: Use `running-tests` directly

**Use /test-feature when:**
- Before creating a pull request
- After major changes
- Before deployment
- Need comprehensive validation
