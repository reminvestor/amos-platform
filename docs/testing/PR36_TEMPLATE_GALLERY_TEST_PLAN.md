# PR #36: Template Gallery - Manual Testing Plan

## Overview
PR #36 introduces a browsable template gallery in the Scout canvas for discovering workflow templates, with entity scoping to support multi-tenant isolation.

## Key Changes
- **New Controller**: `WorkflowTemplatesController` - handles CRUD operations for templates
- **New Canvas**: `_template_gallery.html.erb` - browsable UI for workflow templates
- **New Stimulus Controller**: `template_gallery_controller.js` - client-side filtering and workflow launching
- **Database Migration**: Adds `entity_id`, `tags`, `industry`, and `shared` columns to `workflow_templates` table
- **Model Enhancement**: `WorkflowTemplate` now supports entity scoping with `for_entity` scope
- **Template Metadata**: All workflow YAML files updated with `industry` and `tags` fields

## Prerequisites
- [ ] Database migrations have been run: `docker compose exec web rails db:migrate`
- [ ] Server is running: `docker compose up -d`
- [ ] Test user account created with access to multiple entities (for scoping tests)
- [ ] Browser console open for JavaScript debugging

## Test Cases

### 1. Database Migration Testing
**Objective**: Verify the migration adds required columns correctly

- [ ] **1.1** Run migration in test environment
  ```bash
  docker compose exec web rails db:migrate RAILS_ENV=test
  ```
  - Expected: Migration runs without errors

- [ ] **1.2** Check schema for new columns
  ```bash
  docker compose exec web rails dbconsole
  \d workflow_templates
  ```
  - Expected columns present:
    - `entity_id` (integer, nullable, with foreign key)
    - `tags` (jsonb, default [])
    - `industry` (string)
    - `shared` (boolean, default false)
  - Expected indexes:
    - `index_workflow_templates_on_entity_id`
    - `index_workflow_templates_on_industry`
    - `index_workflow_templates_on_shared`
    - `index_workflow_templates_on_tags` (GIN index)

### 2. Model Testing (WorkflowTemplate)

#### 2.1 Entity Scoping
- [ ] **2.1.1** System templates (entity_id = nil) are visible to all entities
- [ ] **2.1.2** Entity-specific templates are only visible to that entity
- [ ] **2.1.3** Shared templates (shared = true) are visible to all entities
- [ ] **2.1.4** `for_entity(id)` scope returns correct subset

#### 2.2 Template Duplication
- [ ] **2.2.1** Can duplicate a system template for an entity
  - Creates new record with entity_id set
  - Sets `is_system = false`, `shared = false`
  - Appends " (Custom)" to name
  - Generates unique slug with entity ID and random hex

- [ ] **2.2.2** Can duplicate a shared template
- [ ] **2.2.3** Cannot duplicate an entity-specific template (should error)

#### 2.3 File-Based Template Loading
- [ ] **2.3.1** `WorkflowTemplate.active_with_files` returns both DB and file templates
- [ ] **2.3.2** File templates have correct metadata from YAML (industry, tags)
- [ ] **2.3.3** Deduplication works (DB templates preferred over file-based)

### 3. Controller Testing (WorkflowTemplatesController)

#### 3.1 Index Action
- [ ] **3.1.1** GET `/workflow_templates` returns templates for current entity
  - System templates included
  - Entity-owned templates included
  - Shared templates included
  - Other entities' private templates excluded

- [ ] **3.1.2** Filter by category works: `GET /workflow_templates?category=campaign_creation`
- [ ] **3.1.3** Filter by industry works: `GET /workflow_templates?industry=ecommerce`
- [ ] **3.1.4** Filter by tag works: `GET /workflow_templates?tag=marketing`
- [ ] **3.1.5** JSON response format correct

#### 3.2 Show Action
- [ ] **3.2.1** GET `/workflow_templates/:id` returns template details
- [ ] **3.2.2** Returns 404 for non-existent template

#### 3.3 Duplicate Action
- [ ] **3.3.1** POST `/workflow_templates/:id/duplicate` creates entity copy of system template
  - Returns 201 status
  - New template has correct entity_id
  - New template has " (Custom)" suffix

- [ ] **3.3.2** Cannot duplicate entity-specific templates (returns 422)
- [ ] **3.3.3** Duplicate includes error handling for invalid operations

#### 3.4 Update Action
- [ ] **3.4.1** PUT `/workflow_templates/:id` updates entity-owned template
- [ ] **3.4.2** Cannot update system templates (returns 403)
- [ ] **3.4.3** Cannot update templates from other entities (returns 403)
- [ ] **3.4.4** Validates permitted parameters (name, description, category, industry, shared, tags)

#### 3.5 Destroy Action
- [ ] **3.5.1** DELETE `/workflow_templates/:id` deletes entity-owned template
- [ ] **3.5.2** Cannot delete system templates (returns 403)
- [ ] **3.5.3** Cannot delete templates from other entities (returns 403)

### 4. UI Testing (Template Gallery Canvas)

#### 4.1 Canvas Loading
- [ ] **4.1.1** Template gallery loads in Scout canvas
  - Navigate to Scout chat interface
  - Trigger template gallery (via chat command or menu)
  - Canvas displays without errors

- [ ] **4.1.2** All templates display with correct metadata
  - Template cards show name, description, category badge
  - Industry badge displays if present
  - System badge displays for system templates
  - Usage counts display for templates with executions
  - Tags display (max 4 visible, "+N" for additional)

#### 4.2 Filtering
- [ ] **4.2.1** Search input filters by name
  - Type "email" → Only email-related templates visible

- [ ] **4.2.2** Search input filters by description
  - Type "campaign" → Templates with "campaign" in description visible

- [ ] **4.2.3** Search input filters by tags
  - Type "marketing" → Templates tagged with "marketing" visible

- [ ] **4.2.4** Category dropdown filters templates
  - Select "Campaign Creation" → Only campaign templates visible

- [ ] **4.2.5** Industry dropdown filters templates
  - Select "ecommerce" → Only ecommerce templates visible

- [ ] **4.2.6** Multiple filters work together (AND logic)
  - Search "email" + Category "Campaign Creation"

- [ ] **4.2.7** Result count updates dynamically as filters change

#### 4.3 Template Actions
- [ ] **4.3.1** Click "Start" button on template
  - Sends chat message: `Run the "[Template Name]" workflow`
  - Message appears in chat history
  - Planner agent picks up the workflow

- [ ] **4.3.2** Workflow launches successfully
  - Gather Context phase starts
  - Context questions asked if needed
  - Execution proceeds

#### 4.4 Styling & Responsiveness
- [ ] **4.4.1** Dark mode styles applied correctly
  - Canvas background, text colors, borders correct
  - Card hover effects work
  - Badges have correct colors

- [ ] **4.4.2** Light mode styles applied correctly
  - Switch to light mode (if theme toggle available)
  - All colors readable and appropriate

- [ ] **4.4.3** Responsive grid layout
  - Cards resize appropriately on different screen widths
  - Mobile view works (cards stack vertically)

- [ ] **4.4.4** Icons render correctly (Lucide icons)
  - Header icon, search icon, category icons
  - Activity icon for usage stats
  - Play icon in Start button

#### 4.5 Empty States
- [ ] **4.5.1** Empty state displays when no templates match filters
  - Message: "No Templates Available"
  - Inbox icon visible

- [ ] **4.5.2** Hint bar displays at bottom
  - Message suggests typing custom workflow description

### 5. Integration Testing

#### 5.1 Entity Isolation
- [ ] **5.1.1** Create custom template for Entity A
- [ ] **5.1.2** Switch to Entity B
- [ ] **5.1.3** Verify Entity A's custom template NOT visible in Entity B's gallery
- [ ] **5.1.4** Verify system templates visible to both entities

#### 5.2 Workflow Execution from Gallery
- [ ] **5.2.1** Start "Email Campaign Builder" from gallery
- [ ] **5.2.2** Complete workflow end-to-end
- [ ] **5.2.3** Verify WorkflowExecution record created with correct template_id
- [ ] **5.2.4** Return to gallery, verify usage count incremented

#### 5.3 Routes & Authentication
- [ ] **5.3.1** Verify routes work:
  - `/workflow_templates` (index)
  - `/workflow_templates/:id` (show)
  - `/workflow_templates/:id/duplicate` (duplicate)
  - `/workflow_templates/:id` (update via PUT)
  - `/workflow_templates/:id` (destroy via DELETE)

- [ ] **5.3.2** All routes require authentication
  - Logged-out user redirected to login

- [ ] **5.3.3** Template gallery accessible via Scout canvas
  - Load from chat: "Show template gallery"
  - Or via available_canvases API

### 6. Performance Testing

- [ ] **6.1** Gallery loads quickly with 20+ templates
- [ ] **6.2** Client-side filtering is instant (no lag)
- [ ] **6.3** No N+1 queries when loading templates
  - Check Rails logs for query count
- [ ] **6.4** GIN index on tags improves tagged_with query speed

### 7. Security Testing

- [ ] **7.1** Entity scoping enforced in controller
  - User from Entity A cannot update/delete Entity B's templates

- [ ] **7.2** System template protection
  - Cannot update system templates (is_system = true)
  - Cannot delete system templates

- [ ] **7.3** SQL injection protection
  - Search input properly escaped
  - Filter parameters properly escaped

- [ ] **7.4** XSS protection
  - Template name/description with HTML/JS renders safely

### 8. Edge Cases

- [ ] **8.1** Template with no tags
- [ ] **8.2** Template with no industry
- [ ] **8.3** Template with very long name (truncation)
- [ ] **8.4** Template with very long description (truncation in cards)
- [ ] **8.5** Template with special characters in name/slug
- [ ] **8.6** Duplicate template with same slug (should generate unique)
- [ ] **8.7** File-based template missing required fields (should handle gracefully)

## Test Data Setup

### Create Test Templates via Rails Console
```ruby
# docker compose exec web rails console

entity = Entity.first
user = entity.users.first

# Create an entity-specific template
WorkflowTemplate.create!(
  entity: entity,
  name: "Custom Lead Scoring",
  slug: "custom_lead_scoring_#{entity.id}",
  description: "Score leads based on custom criteria",
  category: "customer_analysis",
  industry: "saas",
  tags: ["leads", "scoring", "analytics"],
  is_system: false,
  is_active: true,
  template_spec: { phases: [] }
)

# Create a shared template (visible to all)
WorkflowTemplate.create!(
  entity: nil,
  name: "Industry Best Practices",
  slug: "industry_best_practices",
  description: "Shared across all entities",
  category: "content_generation",
  industry: "general",
  tags: ["shared", "templates"],
  is_system: false,
  shared: true,
  is_active: true,
  template_spec: { phases: [] }
)
```

## Known Issues / Expected Behavior

1. **File-based templates**: V2 YAML templates are loaded from disk and merged with DB templates. They cannot be edited via UI.
2. **Duplicate slugs**: When duplicating, slug gets entity ID and random hex appended to ensure uniqueness.
3. **Usage counts**: Based on `WorkflowExecution.workflow_template_id` matching template slug.

## Success Criteria

- All database migrations run without errors
- Entity scoping correctly isolates templates
- Template gallery UI displays and filters work
- Workflows can be launched from gallery via chat
- No security vulnerabilities (entity isolation enforced)
- Tests pass (automated tests)
- Performance is acceptable (gallery loads < 1s)

## Test Environment Notes

- Browser: Chrome/Safari (test both)
- Database: PostgreSQL with GIN index support
- Rails environment: Development (via Docker)
- Test users: At least 2 different entities for isolation testing

## Automated Test Coverage

See automated tests in:
- `test/models/workflow_template_test.rb`
- `test/controllers/workflow_templates_controller_test.rb`
- `test/integration/template_gallery_integration_test.rb`

## Sign-off

- [ ] All manual tests completed
- [ ] All automated tests passing
- [ ] No regressions identified
- [ ] PR approved for merge

---

**Tested by**: _________________
**Date**: _________________
**Notes**:
