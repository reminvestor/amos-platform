# Manual Testing Guide - All PRs in Docker

This guide walks you through manually testing each PR locally using Docker.

## Prerequisites

- Docker and docker-compose installed
- Repository cloned locally
- At least one entity and user in the database

## General Workflow for Each PR

```bash
# 1. Checkout the PR branch
git checkout <branch-name>

# 2. Restart Docker services to pick up code changes
docker compose down
docker compose up -d

# 3. Run migrations (if any)
docker compose exec web rails db:migrate

# 4. Check logs for any errors
docker compose logs -f web

# 5. Test the feature (see specific instructions below)
```

---

## PR #35 - Row-Level Security (RLS)

### Checkout and Setup
```bash
git checkout security/row-level-security
docker compose down && docker compose up -d
docker compose exec web rails db:migrate
```

### What to Test
RLS is a backend security feature - no UI changes to test visually.

**Database-Level Testing:**
```bash
# Open Rails console
docker compose exec web rails console

# Test 1: Verify RLS policies exist
ActiveRecord::Base.connection.execute("SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' LIMIT 10;").to_a

# Test 2: Test entity isolation
entity1 = Entity.first
entity2 = Entity.second
user1 = entity1.users.first
user2 = entity2.users.first

# Set RLS context for entity1
RowLevelSecurity.with_context(entity_id: entity1.id) do
  # Should only see entity1's users
  puts User.count  # Count of entity1 users only
end

# Set RLS context for entity2
RowLevelSecurity.with_context(entity_id: entity2.id) do
  # Should only see entity2's users
  puts User.count  # Count of entity2 users only
end
```

**Expected Results:**
- ✅ RLS policies created on 176 tables
- ✅ Queries filtered by entity_id automatically
- ✅ Cross-entity data leakage prevented

---

## PR #39 - User Event Tracking

### Checkout and Setup
```bash
git checkout feature/user-event-tracking
docker compose down && docker compose up -d
docker compose exec web rails db:migrate
```

### What to Test

**1. Rails Console - Create Events:**
```bash
docker compose exec web rails console

# Get a user and entity
user = User.first
entity = user.entity

# Test 1: Track an event
UserEvent.create!(
  user: user,
  entity: entity,
  event_name: "test_button_click",
  event_category: "feature",
  properties: { button: "save", page: "/dashboard" }
)

# Test 2: Verify event was created
UserEvent.last

# Test 3: Test scopes
UserEvent.for_category("feature")
UserEvent.for_event("test_button_click")
UserEvent.recent.limit(5)

# Test 4: Test funnel analysis
# Create funnel events
5.times do |i|
  UserEvent.create!(user: user, entity: entity, event_name: "signup_started", event_category: "onboarding")
end

3.times do |i|
  UserEvent.create!(user: user, entity: entity, event_name: "signup_completed", event_category: "conversion")
end

# Calculate conversion rate
UserEvent.conversion_rate("signup_started", "signup_completed")
# Should return 60.0 (3/5 = 60%)
```

**2. Background Job Testing:**
```bash
# In Rails console
TrackUserEventJob.perform_later(
  user_id: user.id,
  entity_id: entity.id,
  event_name: "async_test",
  event_category: "feature",
  properties: { test: true }
)

# Wait a moment, then check
UserEvent.where(event_name: "async_test").count
# Should be 1
```

**Expected Results:**
- ✅ Events created successfully
- ✅ All scopes work correctly
- ✅ Conversion rate calculation accurate
- ✅ Background jobs process events

---

## PR #38 - Feedback Admin Dashboard

### Checkout and Setup
```bash
git checkout feature/feedback-system
docker compose down && docker compose up -d
docker compose exec web rails db:migrate
```

### What to Test

**1. Create Sample Feedback Data:**
```bash
docker compose exec web rails console

# Get a user and entity
user = User.first
entity = user.entity

# Create positive feedback
10.times do |i|
  UserEvent.create!(
    user: user,
    entity: entity,
    rating: 1,
    feedbackable_type: "WorkflowExecution",
    feedbackable_id: 1,
    event_category: "feature",
    comment: nil
  )
end

# Create negative feedback with comments
5.times do |i|
  UserEvent.create!(
    user: user,
    entity: entity,
    rating: -1,
    feedbackable_type: "ScoutMessage",
    feedbackable_id: 1,
    event_category: "feature",
    comment: "This didn't work as expected - error #{i}"
  )
end

# Create neutral feedback
2.times do
  UserEvent.create!(
    user: user,
    entity: entity,
    rating: 0,
    feedbackable_type: "ToolExecution",
    feedbackable_id: 1,
    event_category: "feature"
  )
end
```

**2. Visit Admin Dashboard:**

Open browser and navigate to:
```
http://localhost:3000/admin/feedbacks
```

**What to Check:**
- ✅ **Statistics Cards**:
  - Total Feedback: 17
  - Positive: 10 (58.8%)
  - Negative: 5 (29.4%)
  - Satisfaction Score: ~66.7% (10/(10+5))
  - With Comments: 5

- ✅ **Date Range Filter**:
  - Change dates and click "Filter"
  - Verify stats update
  - Click "Reset" - returns to last 30 days

- ✅ **Daily Trend Chart**:
  - Chart.js line chart visible
  - Green line for positive feedback
  - Red line for negative feedback
  - Hover shows tooltips

- ✅ **Feedback by Type Table**:
  - Shows WorkflowExecution, ScoutMessage, ToolExecution
  - Shows count and satisfaction score per type
  - Color-coded satisfaction (green/yellow/red)

- ✅ **Negative Comments Section**:
  - Shows 5 feedback items with comments
  - User email visible
  - Comment text shown
  - "Time ago" format

- ✅ **Recent Feedback Table**:
  - Shows all 17 feedback items
  - Rating emoji (👍/👎/😐)
  - User, Type, Comment, Date columns

---

## PR #37 - Template Analytics & Observability

### Checkout and Setup
```bash
git checkout feature/observability-enhancements
docker compose down && docker compose up -d
docker compose exec web rails db:migrate
```

### What to Test

**1. Create Sample Data:**
```bash
docker compose exec web rails console

# Get a workflow template
template = WorkflowTemplate.first
entity = Entity.first

# Create successful executions
5.times do
  WorkflowExecution.create!(
    workflow_template: template,
    entity: entity,
    status: "completed",
    started_at: 2.hours.ago,
    completed_at: 1.hour.ago
  )
end

# Create failed executions
2.times do
  WorkflowExecution.create!(
    workflow_template: template,
    entity: entity,
    status: "failed",
    started_at: 3.hours.ago,
    completed_at: 2.hours.ago
  )
end
```

**2. Visit Observability Dashboard:**

Open browser:
```
http://localhost:3000/admin/observability
```

Click on **"Workflows"** tab.

**What to Check:**
- ✅ **Template Analytics Table**:
  - Shows workflow templates with stats
  - Total Runs: 7 for your test template
  - Success Rate: ~71.4% (5/7)
  - Average Duration: ~1 hour
  - Unique Entities: 1
  - Color-coded success rate badges

- ✅ **Templates Sorted**:
  - Most-used templates at top
  - Least-used at bottom

**3. Test Async Event Persistence:**
```bash
# In Rails console
ObservabilityEvent.create!(
  entity: entity,
  event_type: "workflow_started",
  event_data: { workflow_id: 1 }
)

# Verify events are being persisted
ObservabilityEvent.count
```

**Expected Results:**
- ✅ Template analytics display correctly
- ✅ Stats are accurate
- ✅ Events persist asynchronously

---

## PR #36 - Template Gallery

### Checkout and Setup
```bash
git checkout feature/template-gallery
docker compose down && docker compose up -d
docker compose exec web rails db:migrate
```

### What to Test

**1. Seed Template Data:**
```bash
docker compose exec web rails console

# Create sample templates
entity = Entity.first

# System template (entity_id: nil)
WorkflowTemplate.create!(
  name: "Email Campaign Template",
  slug: "email-campaign",
  category: "marketing",
  industry: "E-commerce",
  tags: ["email", "automation", "drip"],
  shared: false,
  description: "3-email welcome sequence for new customers",
  template_spec: { phases: [] }
)

# Entity-owned template
WorkflowTemplate.create!(
  entity: entity,
  name: "Custom Sales Funnel",
  slug: "custom-sales-funnel",
  category: "sales",
  industry: "SaaS",
  tags: ["leads", "conversion"],
  shared: true,
  description: "Our custom sales process",
  template_spec: { phases: [] }
)
```

**2. Visit Template Gallery:**

Open Scout chat interface:
```
http://localhost:3000/scout
```

Click **"Templates"** tab or button in Scout canvas.

**What to Check:**
- ✅ **Gallery UI**:
  - Template cards display in grid
  - Template name, description, category visible
  - Industry and tags shown
  - "Use Template" button on each card

- ✅ **Search**:
  - Type "email" in search box
  - Verify email template appears
  - Clear search - all templates show

- ✅ **Filter by Category**:
  - Select "Marketing" category
  - Only marketing templates show
  - Select "All Categories" - all show

- ✅ **Filter by Industry**:
  - Select "E-commerce"
  - Only e-commerce templates show

- ✅ **Template Sections**:
  - "System Templates" section
  - "My Templates" section (entity-owned)
  - "Shared Templates" section

- ✅ **Use Template**:
  - Click "Use Template" on a template
  - Verify workflow loads with template settings
  - User can customize before running

- ✅ **Duplicate Template**:
  - Click "Duplicate" on a system template
  - Verify copy created in "My Templates"
  - Verify slug is unique (e.g., "email-campaign-copy")

**3. Test Entity Scoping:**

Log in as different entity users and verify they only see their own templates + system templates.

---

## Quick Test All PRs Script

```bash
#!/bin/bash
# Save as test_all_prs.sh

echo "Testing PR #35 - RLS"
git checkout security/row-level-security
docker compose down && docker compose up -d
docker compose exec web rails db:migrate
echo "✅ PR #35 ready - Run manual tests from guide"
read -p "Press enter to continue to next PR..."

echo "Testing PR #39 - User Events"
git checkout feature/user-event-tracking
docker compose restart web
docker compose exec web rails db:migrate
echo "✅ PR #39 ready - Visit console to test events"
read -p "Press enter to continue to next PR..."

echo "Testing PR #38 - Feedback Dashboard"
git checkout feature/feedback-system
docker compose restart web
docker compose exec web rails db:migrate
echo "✅ PR #38 ready - Visit http://localhost:3000/admin/feedbacks"
read -p "Press enter to continue to next PR..."

echo "Testing PR #37 - Observability"
git checkout feature/observability-enhancements
docker compose restart web
docker compose exec web rails db:migrate
echo "✅ PR #37 ready - Visit http://localhost:3000/admin/observability"
read -p "Press enter to continue to next PR..."

echo "Testing PR #36 - Template Gallery"
git checkout feature/template-gallery
docker compose restart web
docker compose exec web rails db:migrate
echo "✅ PR #36 ready - Visit http://localhost:3000/scout and click Templates"

echo "All PRs loaded! Use the manual testing guide for each."
```

---

## Troubleshooting

### Docker Issues
```bash
# Full reset
docker compose down -v
docker compose up -d

# View logs
docker compose logs -f web

# Restart single service
docker compose restart web
```

### Database Issues
```bash
# Reset database
docker compose exec web rails db:reset

# Re-run migrations
docker compose exec web rails db:migrate

# Check migration status
docker compose exec web rails db:migrate:status
```

### Asset Issues
```bash
# Rebuild assets
docker compose exec web yarn build

# Clear cache
docker compose exec web rails tmp:cache:clear
```

---

## Testing Checklist

### PR #35 - RLS
- [ ] RLS policies created on tables
- [ ] Entity isolation works in console
- [ ] No cross-tenant data leakage

### PR #39 - User Events
- [ ] Events created successfully
- [ ] Scopes filter correctly
- [ ] Conversion rate calculation accurate
- [ ] Background jobs work

### PR #38 - Feedback Dashboard
- [ ] Dashboard loads at /admin/feedbacks
- [ ] Statistics display correctly
- [ ] Date filtering works
- [ ] Chart renders properly
- [ ] Negative comments section shows
- [ ] Recent feedback table displays

### PR #37 - Observability
- [ ] Template analytics table shows
- [ ] Stats are accurate
- [ ] Success rate color-coded
- [ ] Events persist asynchronously

### PR #36 - Template Gallery
- [ ] Gallery loads in Scout
- [ ] Search works
- [ ] Category filter works
- [ ] Industry filter works
- [ ] Use template loads workflow
- [ ] Duplicate creates copy
- [ ] Entity scoping enforced
