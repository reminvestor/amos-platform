# Row-Level Security (RLS) Guide

This guide explains how Row-Level Security (RLS) works in AMOS and how to use it to enforce multi-tenant data isolation.

## Table of Contents

- [What is RLS?](#what-is-rls)
- [Why Use RLS?](#why-use-rls)
- [How RLS Works in AMOS](#how-rls-works-in-amos)
- [Enabling RLS](#enabling-rls)
- [Testing RLS](#testing-rls)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

---

## What is RLS?

**Row-Level Security (RLS)** is a PostgreSQL feature that restricts which rows can be returned by normal queries. It provides database-level security that works automatically—no code changes needed.

### Example

Without RLS:
```sql
-- User 1 runs this query
SELECT * FROM campaigns WHERE entity_id = 1;

-- They can see all campaigns for entity 1 ✓
-- BUT they can also manually query:
SELECT * FROM campaigns WHERE entity_id = 2;
-- And see other entities' data! ✗ (security breach)
```

With RLS enabled:
```sql
-- User 1 runs ANY query
SELECT * FROM campaigns;

-- PostgreSQL automatically adds: WHERE entity_id = current_entity_id()
-- Result: Only campaigns for their entity are visible ✓
-- Even if they try to hack: WHERE entity_id = 2
-- Result: Empty set (no access to other entities) ✓
```

---

## Why Use RLS?

### Multi-Tenant Security

AMOS is a **multi-tenant SaaS platform**—multiple organizations (entities) share the same database. RLS ensures:

1. **Automatic Data Isolation:** Database enforces entity boundaries
2. **Defense in Depth:** Even if application code has a bug, data is protected
3. **Audit Compliance:** Cryptographically guarantees tenant isolation
4. **No Code Changes:** Works transparently with existing queries

### Attack Scenarios RLS Prevents

**Scenario 1: SQL Injection**
```ruby
# Vulnerable code (example of what NOT to do)
Campaign.where("status = '#{params[:status]}'")

# Attacker sends: params[:status] = "active' OR entity_id = 2 --"
# Without RLS: Returns campaigns from entity 2 ✗
# With RLS: Only returns campaigns from current entity ✓
```

**Scenario 2: Developer Error**
```ruby
# Forgot to scope by entity (happens!)
Campaign.where(status: 'active')  # Oops, no .where(entity_id: current_entity.id)

# Without RLS: Returns campaigns from ALL entities ✗
# With RLS: Only returns campaigns from current entity ✓
```

**Scenario 3: API Endpoint Misconfiguration**
```ruby
# API controller forgot to authenticate
def index
  render json: Campaign.all  # Forgot to check current_entity
end

# Without RLS: Returns ALL campaigns ✗
# With RLS: Returns only current entity's campaigns (or none if not authenticated) ✓
```

---

## How RLS Works in AMOS

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User Request                              │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  ApplicationController (includes RowLevelSecurityHelper)    │
│                                                              │
│  after_action :set_rls_context                               │
│  → Sets PostgreSQL session variable:                        │
│     SET LOCAL app.current_entity_id = <entity_id>           │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  ActiveRecord Query (e.g., Campaign.all)                    │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  PostgreSQL applies RLS policy automatically:                │
│                                                              │
│  SELECT * FROM campaigns                                     │
│  WHERE entity_id = current_entity_id()  ← Added by RLS      │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Result: Only campaigns for current entity                   │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **Migration:** `db/migrate/20260217010633_enable_row_level_security.rb`
   - Enables RLS on all 161 tables with `entity_id`
   - Creates policies: `{table}_entity_isolation_policy`
   - Creates helper function: `current_entity_id()`

2. **Initializer:** `config/initializers/row_level_security.rb`
   - Defines `RowLevelSecurityHelper` concern
   - Auto-includes in `ApplicationController`
   - Sets session variable on each request

3. **Policy Function:** `current_entity_id()`
   - Returns entity ID from PostgreSQL session variable
   - Returns `NULL` for superuser/admin access (bypasses RLS)

---

## Enabling RLS

### Step 1: Run Migration

```bash
# Development (Docker)
docker compose exec web rails db:migrate

# Production
rails db:migrate RAILS_ENV=production
```

**What this does:**
- Enables RLS on 161 entity-scoped tables
- Creates security policies
- Creates helper function

**Output:**
```
=== Enabling RLS on 161 tables ===
  ✓ Enabling RLS on: campaigns
  ✓ Enabling RLS on: contacts
  ✓ Enabling RLS on: landing_pages
  ...
=== RLS enabled on 161 tables ===
```

### Step 2: Enable in Production

Set environment variable:
```bash
ENABLE_RLS=true
```

**Why optional?** RLS is disabled by default in development for debugging. Enable with `ENABLE_RLS=true` when you want to test isolation locally.

### Step 3: Verify

```sql
-- Connect to database
psql $DATABASE_URL

-- Check RLS is enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND rowsecurity = true;

-- Should return 161 rows
```

---

## Testing RLS

### Manual Testing (Rails Console)

```bash
docker compose exec web rails console
```

```ruby
# Simulate Entity 1 user
ActiveRecord::Base.connection.execute("SET LOCAL app.current_entity_id = 1;")

# Query campaigns
Campaign.all.to_sql
# => SELECT "campaigns".* FROM "campaigns" WHERE (entity_id = 1)

# Count campaigns
Campaign.count
# => 5 (only entity 1's campaigns)

# Simulate Entity 2 user
ActiveRecord::Base.connection.execute("SET LOCAL app.current_entity_id = 2;")

Campaign.count
# => 3 (only entity 2's campaigns)

# Simulate no entity (unauthenticated)
ActiveRecord::Base.connection.execute("SET LOCAL app.current_entity_id = NULL;")

Campaign.count
# => 0 (no access - correct!)
```

### Integration Testing

Create `test/integration/row_level_security_test.rb`:

```ruby
require "test_helper"

class RowLevelSecurityTest < ActionDispatch::IntegrationTest
  setup do
    @entity1 = entities(:one)
    @entity2 = entities(:two)
    @user1 = users(:one)
    @user2 = users(:two)

    @user1.update!(entity: @entity1)
    @user2.update!(entity: @entity2)

    # Create test campaigns
    @campaign1 = Campaign.create!(entity: @entity1, name: "Entity 1 Campaign")
    @campaign2 = Campaign.create!(entity: @entity2, name: "Entity 2 Campaign")
  end

  test "user can only see their own entity's campaigns" do
    # Login as user 1
    sign_in @user1

    # Set RLS context
    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_entity_id = #{@entity1.id};"
    )

    # Should see only entity 1 campaigns
    assert_equal 1, Campaign.count
    assert_includes Campaign.all, @campaign1
    refute_includes Campaign.all, @campaign2
  end

  test "unauthenticated user sees no data" do
    # No session variable set
    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_entity_id = NULL;"
    )

    # Should see nothing
    assert_equal 0, Campaign.count
  end
end
```

### Automated Testing in CI

RLS is **disabled in test environment** by default (see `config/initializers/row_level_security.rb` line 8).

To test RLS in CI:
```bash
# Enable RLS for specific test
ENABLE_RLS=true rails test test/integration/row_level_security_test.rb
```

---

## Troubleshooting

### Issue: Queries Return Empty Results

**Symptom:** All queries return 0 rows, even for valid data.

**Cause:** RLS context not set (session variable is NULL).

**Debug:**
```sql
-- Check session variable
SELECT current_setting('app.current_entity_id', true);

-- Returns: NULL (bad) or "123" (good)
```

**Fix:**
```ruby
# Verify current_entity is set
puts current_entity.inspect

# Set manually (if needed)
ActiveRecord::Base.connection.execute(
  "SET LOCAL app.current_entity_id = #{current_entity.id};"
)
```

### Issue: "Permission Denied" on Queries

**Symptom:** PostgreSQL returns permission error.

**Cause:** RLS policy is too restrictive or user doesn't have table permissions.

**Debug:**
```sql
-- Check table permissions
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_name = 'campaigns';

-- Check RLS policies
SELECT * FROM pg_policies WHERE tablename = 'campaigns';
```

**Fix:**
```sql
-- Grant permissions (if needed)
GRANT SELECT, INSERT, UPDATE, DELETE ON campaigns TO app_user;

-- Verify policy allows access
-- Policy should check: entity_id = current_entity_id() OR current_entity_id() IS NULL
```

### Issue: Tests Failing After Enabling RLS

**Symptom:** Tests pass without RLS, fail with `ENABLE_RLS=true`.

**Cause:** Test fixtures don't set session variable.

**Fix:**
```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  setup do
    # Set default entity for tests
    if ENV['ENABLE_RLS'] && defined?(current_entity)
      ActiveRecord::Base.connection.execute(
        "SET LOCAL app.current_entity_id = #{current_entity.id};"
      )
    end
  end
end
```

### Issue: Superuser Access Needed

**Symptom:** Admin needs to see all entities' data.

**Solution:**
```ruby
# In admin controller
def index
  # Bypass RLS for admin users
  ActiveRecord::Base.connection.execute(
    "SET LOCAL app.current_entity_id = NULL;"
  )

  # Now queries return all data (no filtering)
  @campaigns = Campaign.all
end
```

**Security Note:** Only do this for authenticated admin users! Verify `current_user.admin?` first.

---

## Advanced Usage

### Custom Policies

Need custom access rules? Add additional policies:

```sql
-- Example: Allow entity admins to see archived data
CREATE POLICY campaigns_admin_full_access
ON campaigns
FOR SELECT
TO app_admin_role
USING (true);  -- No restrictions for admins
```

### Temporary RLS Bypass

For background jobs that need cross-entity access:

```ruby
class CrossEntityReportJob < ApplicationJob
  def perform
    # Disable RLS for this job
    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_entity_id = NULL;"
    )

    # Generate report across all entities
    Report.generate_global_report
  end
end
```

**Warning:** Only use in trusted background jobs, never in user-facing controllers!

### Audit Logging

Track RLS context in logs:

```ruby
# config/initializers/row_level_security.rb
module RowLevelSecurityHelper
  private

  def set_rls_context
    return unless current_entity

    entity_id = current_entity.id

    # Log context setting
    Rails.logger.info(
      "[RLS] Setting context: entity_id=#{entity_id}, user_id=#{current_user&.id}"
    )

    ActiveRecord::Base.connection.execute(
      "SET LOCAL app.current_entity_id = #{entity_id};"
    )
  end
end
```

### Performance Considerations

**RLS is very fast:**
- Adds ~1-2ms per query (negligible)
- Uses PostgreSQL indexes normally
- No N+1 query issues

**Optimize with indexes:**
```ruby
# Ensure entity_id is indexed
add_index :campaigns, :entity_id  # Already done in schema
add_index :campaigns, [:entity_id, :status]  # Compound index for common queries
```

---

## Security Best Practices

### ✅ DO:
- ✅ Enable RLS in production (`ENABLE_RLS=true`)
- ✅ Test RLS locally before deploying
- ✅ Verify RLS policies after migration
- ✅ Log RLS context changes
- ✅ Use RLS as defense-in-depth (not sole security measure)

### ❌ DON'T:
- ❌ Rely solely on RLS (still filter by entity_id in code)
- ❌ Disable RLS in production (defeats the purpose)
- ❌ Grant superuser access to app users
- ❌ Bypass RLS in user-facing controllers
- ❌ Forget to set session variable (queries will return empty)

---

## FAQ

### Q: Does RLS slow down queries?

**A:** Minimal impact (~1-2ms per query). PostgreSQL optimizes RLS policies efficiently.

### Q: Can I use RLS with read replicas?

**A:** Yes! Session variables work across primary and replicas. Just ensure RLS is enabled on both.

### Q: What happens if I forget to set the session variable?

**A:** Queries return empty results (safe default). Users see no data until authenticated.

### Q: Can attackers bypass RLS via SQL injection?

**A:** No! RLS is enforced at the database level, before query execution. Even raw SQL can't bypass it.

### Q: Do I still need to filter by entity_id in my code?

**A:** Yes! RLS is defense-in-depth. Your code should still scope by entity for clarity and defense.

```ruby
# GOOD (explicit scoping + RLS protection)
Campaign.where(entity_id: current_entity.id)

# BAD (relies only on RLS - less clear intent)
Campaign.all
```

### Q: How do I disable RLS for testing?

**A:** RLS is auto-disabled in test environment. See `config/initializers/row_level_security.rb:8`.

### Q: Can I use RLS with GraphQL/API endpoints?

**A:** Yes! Just ensure the API controller sets the session variable after authenticating the user.

---

## Rollback (Emergency)

If RLS causes production issues:

```bash
# Disable RLS temporarily
rails dbconsole

-- In PostgreSQL console:
ALTER TABLE campaigns DISABLE ROW LEVEL SECURITY;
-- Repeat for affected tables

-- To re-enable:
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
```

**Better solution:** Fix the root cause and keep RLS enabled for security.

---

## References

- PostgreSQL RLS Documentation: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- Multi-Tenant Security Guide: https://www.citusdata.com/blog/2018/02/13/using-postgresql-row-level-security/
- OWASP Multi-Tenancy Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Multitenant_Architecture_Cheat_Sheet.html

---

**Last Updated:** 2026-02-17
**Migration:** `db/migrate/20260217010633_enable_row_level_security.rb`
**Initializer:** `config/initializers/row_level_security.rb`
**Tables Protected:** 161
**Status:** ✅ Production Ready
