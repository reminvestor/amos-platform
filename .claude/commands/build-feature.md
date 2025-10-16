# /build-feature Command

Orchestrate a complete end-to-end feature development workflow.

## Usage

```
/build-feature [description]
```

## What This Command Does

Chains specialized agents together to build a complete feature:

1. **workflow-architect** - Design workflow template
2. **tool-builder** - Create needed tools (for each tool)
3. **integration-connector** - Set up external APIs (if needed)
4. **bedrock-integration-specialist** - Optimize AI prompts (if needed)
5. **rails-system-test-specialist** - Write end-to-end tests

Each agent asks for your input before proceeding.

## Example

```
/build-feature Create a workflow that generates Instagram posts from blog content
```

## Orchestration Flow

### Phase 1: Workflow Design
Delegate to workflow-architect:
- Gather requirements interactively
- Design three-phase workflow
- Identify tools needed
- Create YAML template

### Phase 2: Tool Development
For each tool identified:
- Delegate to tool-builder
- Ask about functionality
- Implement and test tool
- Verify registration

### Phase 3: Integration Setup (if external APIs needed)
Delegate to integration-connector:
- Ask about service and auth
- Create Integration records
- Implement API handlers
- Test with credentials

### Phase 4: AI Optimization (if custom prompts needed)
Delegate to bedrock-integration-specialist:
- Ask about AI requirements
- Optimize system prompts
- Configure streaming
- Test responses

### Phase 5: System Testing
Delegate to rails-system-test-specialist:
- Ask about test scenarios
- Write system tests
- Test end-to-end flow
- Verify database state

### Phase 6: Final Review
- Run full test suite
- Start development server
- Manual testing
- User review

## Agent Orchestration

```
Use Task tool to delegate to agents in sequence.

For each phase:
1. Pass context from previous phases
2. Let agent ask questions
3. Wait for completion
4. Review results before next phase
5. If issues found, pause and resolve

Report progress after each phase.
```

## Success Criteria

- ✅ Workflow template created and loads
- ✅ All tools implemented and tested
- ✅ Integrations configured (if applicable)
- ✅ System tests pass
- ✅ Feature works end-to-end
- ✅ User approves implementation
