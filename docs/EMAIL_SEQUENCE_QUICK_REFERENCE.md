# Email Sequence Feature - Quick Reference

## What Was Created

### 1. V2 Workflow Template ✅
**File**: `./app/workflow_templates/email_sequence_v2.yml`

**Trigger Keywords**:
- "email sequence"
- "automated sequence"
- "drip campaign"
- "follow up sequence"
- "email series"
- "nurture sequence"

**Workflow Flow**:
1. **Gather Context**: Collect sequence name, goal, target group, content strategy, timing
2. **Execute Goal**: Create EmailSequence + SequenceSteps + SequenceEnrollments (structured approach)
3. **Validate**: Check minimum 2 steps, valid delays, content present, reasonable timing

---

## Database Models Needed

### EmailSequence
**Purpose**: Parent record for the sequence

**Key Fields**:
- `name` (string, required)
- `goal` (text, optional)
- `status` (string: draft/active/paused/completed/archived)
- `entity_id`, `user_id`, `contact_group_id` (associations)
- `total_enrollments`, `active_enrollments`, `completed_enrollments` (cached counts)

**Methods**: `activate!`, `pause!`, `completion_rate`, `step_count`

---

### SequenceStep
**Purpose**: Individual email with timing

**Key Fields**:
- `email_sequence_id` (association)
- `email_template_id` (association)
- `step_number` (integer, unique per sequence)
- `delay_hours` (integer, 0-2160)
- `sent_count`, `opened_count`, `clicked_count` (statistics)

**Methods**: `delay_in_words`, `open_rate`, `click_rate`

---

### SequenceEnrollment
**Purpose**: Track each contact's progress

**Key Fields**:
- `email_sequence_id`, `contact_id` (associations)
- `current_step_id` (nullable)
- `status` (pending/active/paused/completed/cancelled)
- `enrolled_at`, `started_at`, `completed_at`, `next_send_at`
- `current_step_number`, `emails_sent`

**Methods**: `start!`, `advance_to_next_step!`, `progress_percentage`

---

## Tools Required

### 1. Enhance CreateObjectTool
Add support for:
- `email_sequences`
- `sequence_steps`
- `sequence_enrollments`

Add methods:
- `create_email_sequence(data)`
- `create_sequence_step(data)`
- `create_sequence_enrollment(data)`

### 2. Enhance UpdateObjectTool
Add support for:
- `email_sequences` (with `activate!` and `pause!` actions)
- `sequence_steps`
- `sequence_enrollments`

### 3. Enhance GetDataTool
Add query support for all three new models with entity scoping.

### 4. Optional: EnrollContactsInSequenceTool
Batch enrollment helper (simplifies workflow execution).

---

## Background Jobs Required

### ProcessSequenceEnrollmentsJob
**Triggered**: When sequence is activated
**Purpose**: Start all pending enrollments

```ruby
# Set all pending enrollments to active
# Schedule SendSequenceEmailsJob
```

### SendSequenceEmailsJob
**Triggered**: By ProcessSequenceEnrollmentsJob, then self-schedules hourly
**Purpose**: Send emails for ready enrollments

```ruby
# Find enrollments where next_send_at <= now
# Send email via Mailgun
# Advance enrollment to next step
# Reschedule if active enrollments remain
```

---

## Implementation Steps

```bash
# 1. Create migrations
rails generate migration CreateEmailSequences
rails generate migration CreateSequenceSteps
rails generate migration CreateSequenceEnrollments

# 2. Edit migration files (see EMAIL_SEQUENCE_IMPLEMENTATION.md)

# 3. Create model files
touch app/models/email_sequence.rb
touch app/models/sequence_step.rb
touch app/models/sequence_enrollment.rb

# 4. Create job files
touch app/jobs/process_sequence_enrollments_job.rb
touch app/jobs/send_sequence_emails_job.rb

# 5. Update tool files (existing)
# - app/services/tools/create_object_tool.rb
# - app/services/tools/update_object_tool.rb
# - app/services/tools/get_data_tool.rb

# 6. Run migrations
rails db:migrate

# 7. Test
rails test
```

---

## Data Flow Example

### User Request
"Create an email sequence for new subscribers with 3 welcome emails spaced 3 days apart"

### Workflow Execution

**Phase 1: Gather Context**
- AI asks: sequence name, confirms 3 emails, confirms timing
- AI fetches contact groups: `get_data(object_type: "contact_groups")`
- User selects "Newsletter Subscribers" group

**Phase 2: Execute Goal**
1. Create EmailSequence:
   ```ruby
   create_object(
     object_type: "email_sequences",
     data: {
       name: "Welcome Series",
       goal: "Welcome new subscribers",
       status: "draft",
       contact_group_id: 5
     }
   )
   # Returns: { id: 10 }
   ```

2. Create 3 SequenceSteps:
   ```ruby
   # Step 1: Immediate
   create_object(
     object_type: "sequence_steps",
     data: {
       email_sequence_id: 10,
       email_template_id: 15,
       step_number: 1,
       delay_hours: 0
     }
   )

   # Step 2: 3 days later
   create_object(
     object_type: "sequence_steps",
     data: {
       email_sequence_id: 10,
       email_template_id: 16,
       step_number: 2,
       delay_hours: 72
     }
   )

   # Step 3: 6 days from start
   create_object(
     object_type: "sequence_steps",
     data: {
       email_sequence_id: 10,
       email_template_id: 17,
       step_number: 3,
       delay_hours: 72
     }
   )
   ```

3. Enroll all contacts:
   ```ruby
   # Get contacts from group
   contacts = get_data(
     object_type: "contacts",
     filters: { contact_group_id: 5 }
   )

   # Create enrollment for each
   contacts.each do |contact|
     create_object(
       object_type: "sequence_enrollments",
       data: {
         email_sequence_id: 10,
         contact_id: contact.id,
         status: "pending",
         enrolled_at: Time.current
       }
     )
   end
   ```

**Phase 3: Validation**
- Verify sequence has 3 steps ✓
- Verify all steps have email templates ✓
- Verify delays are reasonable ✓
- Verify contact group has contacts ✓

**Result**:
- EmailSequence created (status: "draft")
- 3 SequenceSteps configured
- 250 contacts enrolled (status: "pending")
- Ready for user to activate

---

## User Activation Flow (Future UI)

```ruby
# When user clicks "Activate" button:
sequence = EmailSequence.find(10)
sequence.activate!

# This triggers:
# 1. Update status to 'active'
# 2. ProcessSequenceEnrollmentsJob.perform_later(10)
#    - Sets all enrollments to 'active'
#    - Calculates next_send_at for each
# 3. SendSequenceEmailsJob runs every hour
#    - Sends emails for ready enrollments
#    - Advances enrollments to next step
```

---

## Key Design Principles

1. **Draft First**: Sequences created in draft, user activates manually
2. **Time-Based Only**: MVP uses simple hour delays (no action triggers)
3. **Structured Execution**: Predictable tool sequence, not AI-planned
4. **Entity Scoped**: All data isolated by entity_id
5. **Background Processing**: Jobs handle email sending asynchronously
6. **State Tracking**: Enrollments track exact progress for each contact

---

## Testing Workflow

```ruby
# In Rails console
entity = Entity.first
user = entity.users.first
group = entity.contact_groups.first

# Create sequence
sequence = EmailSequence.create!(
  name: "Test Sequence",
  entity: entity,
  user: user,
  contact_group: group,
  status: "draft"
)

# Add steps
step1 = SequenceStep.create!(
  email_sequence: sequence,
  email_template: EmailTemplate.first,
  step_number: 1,
  delay_hours: 0
)

step2 = SequenceStep.create!(
  email_sequence: sequence,
  email_template: EmailTemplate.second,
  step_number: 2,
  delay_hours: 72
)

# Enroll contacts
group.contacts.each do |contact|
  SequenceEnrollment.create!(
    email_sequence: sequence,
    contact: contact,
    enrolled_at: Time.current,
    status: "pending"
  )
end

# Activate
sequence.activate!

# Check enrollments
sequence.sequence_enrollments.active.count
# => 10

# Check next send times
sequence.sequence_enrollments.active.pluck(:next_send_at)
```

---

## Files Reference

### Created
- `./app/workflow_templates/email_sequence_v2.yml`
- `./EMAIL_SEQUENCE_IMPLEMENTATION.md` (detailed guide)
- `./EMAIL_SEQUENCE_QUICK_REFERENCE.md` (this file)

### To Create (Implementation)
- `app/models/email_sequence.rb`
- `app/models/sequence_step.rb`
- `app/models/sequence_enrollment.rb`
- `app/jobs/process_sequence_enrollments_job.rb`
- `app/jobs/send_sequence_emails_job.rb`
- `db/migrate/[timestamp]_create_email_sequences.rb`
- `db/migrate/[timestamp]_create_sequence_steps.rb`
- `db/migrate/[timestamp]_create_sequence_enrollments.rb`

### To Modify (Enhancement)
- `app/services/tools/create_object_tool.rb`
- `app/services/tools/update_object_tool.rb`
- `app/services/tools/get_data_tool.rb`

---

## Estimated Effort

- **Database Models**: 2-3 hours
- **Tool Enhancements**: 1-2 hours
- **Background Jobs**: 2-3 hours
- **Testing**: 2-3 hours
- **Total**: 8-12 hours

---

## Questions?

Refer to:
1. **EMAIL_SEQUENCE_IMPLEMENTATION.md** - Complete implementation guide with code
2. **app/workflow_templates/email_sequence_v2.yml** - Workflow template
3. **Existing patterns**:
   - `app/workflow_templates/landing_page_creation_v2.yml`
   - `app/workflow_templates/email_campaign_v2.yml`
   - `app/models/campaign.rb` (similar pattern)
