# TDD Anti-Patterns Reference

## Common Anti-Patterns and Solutions

### 1. Test-After (The Biggest Sin)

**Problem:** Writing implementation first, then adding tests to cover it.

**Why it's bad:**
- Tests become biased toward implementation details
- You can't verify the test actually catches bugs
- Missed edge cases since you "know" the code works

**Solution:** Always write the test first. Watch it fail. Then implement.

---

### 2. The Giant Test

**Problem:** One test that asserts 10+ things.

```ruby
# BAD
test "subscription workflow" do
  assert @subscription.create
  assert @subscription.valid?
  assert_equal "pro", @subscription.plan
  assert @subscription.entity.premium?
  assert_emails 1
  assert @subscription.invoice.present?
  # ... 10 more assertions
end
```

**Why it's bad:**
- When it fails, which assertion broke?
- Hard to understand what's being tested
- Encourages testing implementation, not behavior

**Solution:** One assertion per test (or one logical assertion group).

```ruby
# GOOD
test "creating subscription sets plan" do
  @subscription.create
  assert_equal "pro", @subscription.plan
end

test "creating subscription sends confirmation email" do
  assert_emails 1 do
    @subscription.create
  end
end
```

---

### 3. Testing Private Methods

**Problem:** Writing tests that call private methods directly.

```ruby
# BAD
test "private helper formats date correctly" do
  tool = Tools::ReportTool.new
  result = tool.send(:format_date_for_display, Time.now)
  assert_match /\d{4}-\d{2}-\d{2}/, result
end
```

**Why it's bad:**
- Implementation detail, not behavior
- Brittle - breaks when you refactor
- Private methods can change freely

**Solution:** Test through the public interface.

```ruby
# GOOD
test "report includes formatted date in output" do
  result = @tool.execute(report_type: "monthly")
  assert_match /\d{4}-\d{2}-\d{2}/, result[:data][:date]
end
```

---

### 4. Mock Mania

**Problem:** Mocking every dependency.

```ruby
# BAD - Testing nothing real
test "creates subscription" do
  mock_entity = mock()
  mock_subscription = mock()
  mock_entity.expects(:create_subscription!).returns(mock_subscription)
  mock_subscription.expects(:valid?).returns(true)

  result = tool.execute(entity: mock_entity)
  assert result[:success]
end
```

**Why it's bad:**
- Tests don't verify actual behavior
- Mocks can be wrong without detection
- Refactoring breaks tests even when behavior is unchanged

**Solution:** Use real objects from fixtures, mock only external services.

```ruby
# GOOD - Real objects, real verification
test "creates subscription" do
  entity = entities(:demo)
  tool = Tools::CreateSubscriptionTool.new(entity: entity)

  result = tool.execute(plan: "pro")

  assert result[:success]
  assert entity.reload.subscription.present?
end
```

---

### 5. Skipping the RED Phase

**Problem:** Writing a test that passes immediately.

**Why it's bad:**
- No proof the test catches bugs
- Might be testing the wrong thing
- False confidence

**Solution:** If your new test passes immediately, either:
1. The feature already exists (check!)
2. Your test is wrong (fix it!)
3. You're testing a tautology (delete it!)

---

### 6. Over-Engineering in GREEN

**Problem:** Adding features "while you're there" during GREEN phase.

```ruby
# You need: create a subscription
# You add: logging, metrics, retry logic, caching, webhooks...
```

**Why it's bad:**
- New code has no tests
- Violates YAGNI (You Ain't Gonna Need It)
- Creates technical debt

**Solution:** Only write code to make the current test pass. New features need their own RED-GREEN-REFACTOR cycle.

---

### 7. Integration Tests Only

**Problem:** No unit tests, only full system tests.

**Why it's bad:**
- Slow feedback loop
- Hard to pinpoint failures
- Can miss edge cases

**Solution:** Pyramid - many unit tests, fewer integration, even fewer E2E.

---

### 8. Test Pollution

**Problem:** Tests that depend on order or shared state.

```ruby
# BAD - Test 2 depends on Test 1's side effects
test "first: create record" do
  Record.create(name: "test")
end

test "second: count records" do
  assert_equal 1, Record.count  # Fails when run alone!
end
```

**Why it's bad:**
- Flaky tests
- Can't run tests in isolation
- Debugging nightmare

**Solution:** Each test sets up its own state, uses transactions or database cleaner.

---

### 9. Ignoring Fixtures/Factories

**Problem:** Creating complex object graphs in every test.

```ruby
# BAD - Repeated setup in every test
test "example" do
  entity = Entity.create!(name: "Test", slug: "test", ...)
  user = User.create!(entity: entity, email: "test@test.com", ...)
  campaign = Campaign.create!(entity: entity, user: user, ...)
  # ... 20 more lines of setup

  assert campaign.send!
end
```

**Why it's bad:**
- Verbose, hard to read
- Setup bugs duplicated
- Changes require updating many tests

**Solution:** Use fixtures or factories.

```ruby
# GOOD
test "example" do
  campaign = campaigns(:demo_active)
  assert campaign.send!
end
```

---

## Quick Reference Card

| Do This | Not This |
|---------|----------|
| Write test first | Write code first |
| One assertion per test | Giant test files |
| Test public interface | Test private methods |
| Use real objects | Mock everything |
| Watch test fail (RED) | Skip to GREEN |
| Minimal GREEN code | Over-engineer |
| Unit + integration tests | Integration only |
| Isolated tests | Dependent tests |
| Use fixtures/factories | Manual object creation |
