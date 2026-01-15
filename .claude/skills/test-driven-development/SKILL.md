# Test-Driven Development (TDD)

Enforces disciplined RED-GREEN-REFACTOR cycles for building reliable, well-tested code.

## Description

This skill implements strict Test-Driven Development methodology. It ensures tests are written BEFORE implementation code, prevents skipping steps, and maintains a clean separation between the three TDD phases. This is especially critical for AI agent code where bugs can cascade unpredictably.

**Use this skill when:**
- Implementing new features or tools
- Fixing bugs (write failing test first)
- Refactoring code (ensure tests pass before and after)
- Building Scout AI tools
- Creating workflow executors

## Instructions

### The TDD Cycle (MANDATORY)

```
┌─────────────────────────────────────────────┐
│  1. RED    → Write failing test first       │
│  2. GREEN  → Write minimal code to pass     │
│  3. REFACTOR → Clean up, tests still pass   │
│  └──────────────────────────────────────────│
│             REPEAT                          │
└─────────────────────────────────────────────┘
```

### Phase 1: RED (Write Failing Test)

**Before writing ANY implementation code:**

1. Create a test file if it doesn't exist
2. Write a test that describes the expected behavior
3. Run the test - **IT MUST FAIL**
4. If it passes, the test is wrong or feature already exists

```ruby
# Example: Testing a new Scout tool
test "create_subscription_tool creates subscription for entity" do
  entity = entities(:demo)
  tool = Tools::CreateSubscriptionTool.new(user: users(:demo), entity: entity)

  result = tool.execute(plan: "pro", billing_cycle: "monthly")

  assert result[:success]
  assert_equal "pro", entity.reload.subscription.plan
end
```

**Run the test:**
```bash
docker-compose run --rm web rails test test/services/tools/create_subscription_tool_test.rb
```

**Expected output:** Test fails (class doesn't exist yet)

### Phase 2: GREEN (Minimal Implementation)

Write the **minimum code** to make the test pass:

```ruby
module Tools
  class CreateSubscriptionTool < BaseTool
    def self.definition
      { name: 'create_subscription', description: 'Create subscription', parameters: {} }
    end

    def execute(args)
      @entity.create_subscription!(plan: args[:plan], billing_cycle: args[:billing_cycle])
      success_response(message: "Subscription created")
    end
  end
end
```

**Rules:**
- Only write code that makes the current test pass
- No extra features "while you're there"
- No premature optimization
- No handling edge cases not covered by tests

**Run the test again:**
```bash
docker-compose run --rm web rails test test/services/tools/create_subscription_tool_test.rb
```

**Expected output:** Test passes (GREEN)

### Phase 3: REFACTOR (Clean Up)

Now improve the code quality while **keeping tests passing**:

- Extract methods/classes if needed
- Improve naming
- Remove duplication
- Add proper error handling (with tests!)
- Optimize if necessary

**After each refactor:**
```bash
docker-compose run --rm web rails test test/services/tools/create_subscription_tool_test.rb
```

Tests must remain GREEN throughout refactoring.

### TDD Anti-Patterns (AVOID THESE)

| Anti-Pattern | Why It's Bad | Correct Approach |
|--------------|--------------|------------------|
| Writing tests after code | Tests might be biased to implementation | Write test FIRST |
| Testing private methods | Creates brittle tests | Test public interface |
| Large tests | Hard to debug failures | One assertion focus |
| Mocking everything | Tests don't verify real behavior | Prefer real objects |
| Skipping RED phase | Can't verify test catches bugs | Must see test fail first |
| Over-engineering in GREEN | Adds untested complexity | Minimum to pass only |

### AMOS-Specific Testing Patterns

**Entity Scoping Tests:**
```ruby
test "tool only accesses own entity data" do
  other_entity = entities(:other)
  tool = Tools::GetDataTool.new(user: users(:demo), entity: entities(:demo))

  # Attempt to access other entity's data should fail
  result = tool.execute(entity_id: other_entity.id)

  assert_not result[:success]
  assert_match /not authorized/i, result[:error]
end
```

**Tool Catalog Registration:**
```ruby
test "tool is auto-registered in catalog" do
  catalog = Tools::ToolCatalog.instance
  assert catalog.all_tools.key?('create_subscription')
end
```

**Workflow Executor Tests:**
```ruby
test "gather_context phase collects required information" do
  workflow = workflow_executions(:active)
  executor = Agents::GatherContextExecutor.new(workflow)

  result = executor.execute

  assert result[:context][:customer_info].present?
end
```

### Command Integration

Use with the testing skill:
```bash
# Run TDD cycle for affected tests only
/run-tests affected

# Run specific test during TDD
/run-tests file path=test/services/tools/my_tool_test.rb
```

## Examples

**Starting a new tool with TDD:**
```
Use test-driven-development skill for "subscription management tool"
```

**Bug fix with TDD:**
```
Use test-driven-development skill to fix "campaigns not filtering by entity"
```

**Refactoring session:**
```
Use test-driven-development skill to refactor "bedrock_service"
```

## Verification Checklist

Before marking a TDD cycle complete:

- [ ] Test was written BEFORE implementation
- [ ] Test failed initially (verified RED phase)
- [ ] Implementation is minimal (no extras)
- [ ] Test passes (verified GREEN phase)
- [ ] Code is clean (refactored)
- [ ] All tests still pass after refactor
- [ ] Entity scoping is tested (if applicable)
- [ ] Edge cases have their own test-first cycles

## Resources

- [Running Tests Skill](../running-tests/SKILL.md) - Test execution
- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html) - Rails testing docs
- [Test Anti-Patterns](resources/tdd-anti-patterns.md) - Common mistakes
