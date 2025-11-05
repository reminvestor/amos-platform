# /build-feature Command

Complete end-to-end feature development workflow using Claude Code skills.

## Usage

```
/build-feature [description]
```

## What This Command Does

Orchestrates multiple skills to build a complete feature from GitHub issue to tested implementation:

1. **starting-features** - Create feature branch and implementation plan
2. **starting-features** - Build workflow template, tools, and integrations
3. **testing-tools-manually** - Test individual tools
4. **testing-workflows-manually** - Test end-to-end workflow
5. **running-tests** - Run full test suite
6. **finishing-feature-work** - Final quality checks

## Examples

```
/build-feature Create a workflow that generates Instagram posts from blog content
```

```
/build-feature Build a campaign analytics dashboard
```

## Workflow

### Phase 1: Planning (starting-features skill)
- Select GitHub issue or describe feature
- Generate comprehensive implementation plan
- Create feature branch
- Identify tools, workflows, and integrations needed

### Phase 2: Implementation (starting-features skill)
Build each component:
- Create V2 workflow template (if needed)
- Implement Scout AI tools (for each tool)
- Set up integrations (if external APIs needed)
- Create models, controllers, views
- Follow AMOS patterns (entity scoping, tool catalog)

### Phase 3: Tool Testing (testing-tools-manually skill)
For each new tool:
- Test with example parameters
- Verify tool registration in catalog
- Check entity scoping works
- Validate success/error responses

### Phase 4: Workflow Testing (testing-workflows-manually skill)
- Test workflow phases execute correctly
- Verify planner matches keywords
- Check context persistence
- Validate end-to-end flow

### Phase 5: Test Suite (running-tests skill)
- Run all tests (unit + system)
- Fix any failures
- Verify coverage
- Ensure tests pass

### Phase 6: Quality Checks (finishing-feature-work skill)
- Run full test suite
- Fix RuboCop offenses
- Update documentation
- Ready for PR

## Success Criteria

- ✅ Feature branch created with implementation plan
- ✅ Workflow template created and loads (if applicable)
- ✅ All tools implemented and tested
- ✅ Integrations configured and working (if applicable)
- ✅ Manual tool tests pass
- ✅ Workflow tests pass
- ✅ Full test suite passes
- ✅ Code quality checks pass
- ✅ Ready for pull request

## Uses Skills

- **starting-features** - Feature planning and implementation
- **testing-tools-manually** - Individual tool validation
- **testing-workflows-manually** - End-to-end workflow testing
- **running-tests** - Test suite execution
- **finishing-feature-work** - Final quality checks

## Tips

**Start with smaller commands:**
- Use `/add-workflow` for just workflow creation
- Use `/add-tool` for just tool creation
- Use `/add-integration` for just integration setup

**Use /build-feature when:**
- Building complete features from scratch
- Working from GitHub issues
- Need comprehensive testing
- Want full quality checks before PR
