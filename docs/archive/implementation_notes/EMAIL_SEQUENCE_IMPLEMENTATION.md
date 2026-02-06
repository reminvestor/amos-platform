# Email Sequence Implementation Guide

## Executive Summary

This document outlines the complete implementation requirements for the **Automated Email Sequence** feature in AMOS V2. The workflow template has been created at `./app/workflow_templates/email_sequence_v2.yml`.

## Design Overview

### User Flow
1. User requests to create an email sequence conversationally
2. AI gathers requirements: sequence name, goal, target audience, content strategy, timing
3. System creates sequence in **draft status** with all steps and contact enrollments configured
4. User reviews and activates sequence separately (not part of this workflow)
5. Background job processes enrollments and sends emails based on timing

### Key Design Decisions

#### 1. **Structured Execution Strategy**
- Uses structured data mapping for predictable, reliable sequence creation
- Direct tool invocations ensure consistency
- Reduces complexity compared to adaptive approach

#### 2. **Draft-First Approach**
- Sequences created in "draft" status by default
- Contacts enrolled immediately but emails don't send until activated
- Allows user review before any emails go out

#### 3. **Time-Based Delays Only (MVP)**
- Simple `delay_hours` field on each step
- No action-based triggers (opened, clicked, etc.) in MVP
- Sequential flow: Email 1 → wait → Email 2 → wait → Email 3...

#### 4. **Flexible Content Strategy**
- Option 1: Use existing EmailTemplate records
- Option 2: AI generates new templates based on sequence goal
- Both approaches create SequenceStep records linked to EmailTemplate

#### 5. **Automatic Enrollment**
- All contacts in selected ContactGroup enrolled immediately
- SequenceEnrollment tracks progress for each contact
- Background job manages actual sending based on delays

---

## Required Database Models

### 1. EmailSequence Model

**Purpose**: Parent record that defines the sequence configuration

**File**: `./app/models/email_sequence.rb`

**Migration**: `db/migrate/[timestamp]_create_email_sequences.rb`

```ruby
class CreateEmailSequences < ActiveRecord::Migration[8.0]
  def change
    create_table :email_sequences do |t|
      t.string :name, null: false
      t.text :goal
      t.string :status, default: 'draft', null: false
      t.string :tags, array: true, default: []

      # Associations
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :contact_group, null: false, foreign_key: true

      # Statistics (cached counts)
      t.integer :total_enrollments, default: 0, null: false
      t.integer :active_enrollments, default: 0, null: false
      t.integer :completed_enrollments, default: 0, null: false

      # Activation tracking
      t.datetime :activated_at
      t.datetime :deactivated_at

      t.timestamps
    end

    add_index :email_sequences, :status
    add_index :email_sequences, :entity_id
    add_index :email_sequences, :contact_group_id
  end
end
```

**Model Implementation**:

```ruby
class EmailSequence < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :contact_group

  has_many :sequence_steps, -> { order(step_number: :asc) }, dependent: :destroy
  has_many :sequence_enrollments, dependent: :destroy

  # Status options
  STATUSES = %w[draft active paused completed archived].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :name, presence: true

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :draft, -> { where(status: 'draft') }
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }

  # Methods
  def activate!
    return false unless draft?

    transaction do
      update!(status: 'active', activated_at: Time.current)
      # Enqueue job to start processing enrollments
      ProcessSequenceEnrollmentsJob.perform_later(id)
    end

    true
  end

  def pause!
    update(status: 'paused')
  end

  def draft?
    status == 'draft'
  end

  def active?
    status == 'active'
  end

  # Statistics
  def completion_rate
    return 0 if total_enrollments.zero?
    (completed_enrollments.to_f / total_enrollments * 100).round(2)
  end

  def step_count
    sequence_steps.count
  end
end
```

---

### 2. SequenceStep Model

**Purpose**: Individual email in the sequence with timing configuration

**File**: `./app/models/sequence_step.rb`

**Migration**: `db/migrate/[timestamp]_create_sequence_steps.rb`

```ruby
class CreateSequenceSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :sequence_steps do |t|
      t.references :email_sequence, null: false, foreign_key: true
      t.references :email_template, null: false, foreign_key: true

      # Step configuration
      t.integer :step_number, null: false
      t.integer :delay_hours, default: 0, null: false

      # Statistics (cached)
      t.integer :sent_count, default: 0, null: false
      t.integer :opened_count, default: 0, null: false
      t.integer :clicked_count, default: 0, null: false

      t.timestamps
    end

    add_index :sequence_steps, [:email_sequence_id, :step_number], unique: true
    add_index :sequence_steps, :email_template_id
  end
end
```

**Model Implementation**:

```ruby
class SequenceStep < ApplicationRecord
  belongs_to :email_sequence
  belongs_to :email_template

  validates :step_number, presence: true,
    uniqueness: { scope: :email_sequence_id }
  validates :delay_hours, presence: true,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2160 }

  # Scopes
  scope :ordered, -> { order(step_number: :asc) }

  # Methods
  def delay_in_words
    if delay_hours.zero?
      "Immediately"
    elsif delay_hours < 24
      "#{delay_hours} #{'hour'.pluralize(delay_hours)}"
    else
      days = delay_hours / 24
      "#{days} #{'day'.pluralize(days)}"
    end
  end

  def open_rate
    return 0 if sent_count.zero?
    (opened_count.to_f / sent_count * 100).round(2)
  end

  def click_rate
    return 0 if sent_count.zero?
    (clicked_count.to_f / sent_count * 100).round(2)
  end
end
```

---

### 3. SequenceEnrollment Model

**Purpose**: Tracks each contact's progress through the sequence

**File**: `./app/models/sequence_enrollment.rb`

**Migration**: `db/migrate/[timestamp]_create_sequence_enrollments.rb`

```ruby
class CreateSequenceEnrollments < ActiveRecord::Migration[8.0]
  def change
    create_table :sequence_enrollments do |t|
      t.references :email_sequence, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :current_step, foreign_key: { to_table: :sequence_steps }, null: true

      # Status tracking
      t.string :status, default: 'pending', null: false
      t.datetime :enrolled_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :next_send_at

      # Progress tracking
      t.integer :current_step_number, default: 0, null: false
      t.integer :emails_sent, default: 0, null: false

      t.timestamps
    end

    add_index :sequence_enrollments, [:email_sequence_id, :contact_id],
      unique: true, name: 'index_enrollments_on_sequence_and_contact'
    add_index :sequence_enrollments, :status
    add_index :sequence_enrollments, :next_send_at
  end
end
```

**Model Implementation**:

```ruby
class SequenceEnrollment < ApplicationRecord
  belongs_to :email_sequence
  belongs_to :contact
  belongs_to :current_step, class_name: 'SequenceStep', optional: true

  # Status options
  STATUSES = %w[pending active paused completed cancelled].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :enrolled_at, presence: true

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :active, -> { where(status: 'active') }
  scope :ready_to_send, -> {
    where(status: 'active')
      .where('next_send_at <= ?', Time.current)
  }

  # Methods
  def start!
    return false unless pending?

    update!(
      status: 'active',
      started_at: Time.current,
      next_send_at: Time.current
    )
  end

  def advance_to_next_step!
    next_step_number = current_step_number + 1
    next_step = email_sequence.sequence_steps.find_by(step_number: next_step_number)

    if next_step
      update!(
        current_step_number: next_step_number,
        current_step: next_step,
        next_send_at: Time.current + next_step.delay_hours.hours,
        emails_sent: emails_sent + 1
      )
    else
      # No more steps, mark complete
      update!(
        status: 'completed',
        completed_at: Time.current,
        current_step: nil
      )
    end
  end

  def progress_percentage
    total_steps = email_sequence.sequence_steps.count
    return 0 if total_steps.zero?

    (current_step_number.to_f / total_steps * 100).round(2)
  end
end
```

---

## Required Tools

### 1. CreateObjectTool Enhancement

**File**: `./app/services/tools/create_object_tool.rb`

**Changes Required**: Add support for new object types

```ruby
# In CreateObjectTool class

def execute(args)
  # ... existing code ...

  # Update valid_types array
  valid_types = [
    'campaigns',
    'contacts',
    'contact_groups',
    'email_templates',
    'email_sequences',      # NEW
    'sequence_steps',       # NEW
    'sequence_enrollments'  # NEW
  ]

  # ... existing code ...

  result = case object_type
  when 'campaigns'
    create_campaign(data)
  when 'contacts'
    create_contact(data)
  when 'contact_groups'
    create_contact_group(data)
  when 'email_templates'
    create_email_template(data)
  when 'email_sequences'
    create_email_sequence(data)      # NEW
  when 'sequence_steps'
    create_sequence_step(data)       # NEW
  when 'sequence_enrollments'
    create_sequence_enrollment(data) # NEW
  end

  # ... existing code ...
end

private

def create_email_sequence(data)
  data = data.symbolize_keys
  data[:status] ||= 'draft'

  sequence = EmailSequence.new(data)
  sequence.user = user
  sequence.entity = entity
  sequence.save!

  Rails.logger.info "✅ Created email sequence: #{sequence.name} (ID: #{sequence.id})"
  sequence
end

def create_sequence_step(data)
  data = data.symbolize_keys

  # Validate required fields
  unless data[:email_sequence_id] && data[:email_template_id] && data[:step_number]
    raise ArgumentError, "Missing required fields: email_sequence_id, email_template_id, step_number"
  end

  # Default delay to 0 hours (immediate)
  data[:delay_hours] ||= 0

  step = SequenceStep.new(data)
  step.save!

  Rails.logger.info "✅ Created sequence step #{step.step_number} (ID: #{step.id})"
  step
end

def create_sequence_enrollment(data)
  data = data.symbolize_keys

  # Set enrolled_at if not provided
  data[:enrolled_at] ||= Time.current
  data[:status] ||= 'pending'
  data[:current_step_number] ||= 0

  enrollment = SequenceEnrollment.new(data)
  enrollment.save!

  Rails.logger.info "✅ Enrolled contact #{enrollment.contact_id} in sequence #{enrollment.email_sequence_id}"
  enrollment
end

def serialize_record(record)
  # ... existing cases ...

  case record
  when EmailSequence
    {
      id: record.id,
      name: record.name,
      goal: record.goal,
      status: record.status,
      contact_group_id: record.contact_group_id,
      step_count: record.sequence_steps.count,
      total_enrollments: record.total_enrollments,
      created_at: record.created_at
    }
  when SequenceStep
    {
      id: record.id,
      email_sequence_id: record.email_sequence_id,
      email_template_id: record.email_template_id,
      step_number: record.step_number,
      delay_hours: record.delay_hours,
      delay_in_words: record.delay_in_words
    }
  when SequenceEnrollment
    {
      id: record.id,
      email_sequence_id: record.email_sequence_id,
      contact_id: record.contact_id,
      status: record.status,
      current_step_number: record.current_step_number,
      progress: "#{record.progress_percentage}%"
    }
  else
    # ... existing cases ...
  end
end
```

---

### 2. UpdateObjectTool Enhancement

**File**: `./app/services/tools/update_object_tool.rb`

**Changes Required**: Add support for sequence activation/deactivation

```ruby
# Add to valid_types array
valid_types = [
  'campaigns',
  'email_templates',
  'contacts',
  'landing_pages',
  'email_sequences',      # NEW
  'sequence_steps',       # NEW
  'sequence_enrollments'  # NEW
]

# Add case handlers
case object_type
when 'email_sequences'
  update_email_sequence(id, data)
when 'sequence_steps'
  update_sequence_step(id, data)
when 'sequence_enrollments'
  update_sequence_enrollment(id, data)
end

private

def update_email_sequence(id, data)
  sequence = EmailSequence.find(id)

  # Handle special actions
  if data[:activate] == true
    sequence.activate!
    return sequence
  elsif data[:pause] == true
    sequence.pause!
    return sequence
  end

  # Standard update
  sequence.update!(data)
  Rails.logger.info "✅ Updated email sequence #{id}"
  sequence
end
```

---

### 3. GetDataTool Enhancement

**File**: `./app/services/tools/get_data_tool.rb`

**Changes Required**: Add query support for sequence models

```ruby
# Add to valid_types
valid_types = [
  'campaigns',
  'contacts',
  'contact_groups',
  'email_templates',
  'landing_pages',
  'email_sequences',      # NEW
  'sequence_steps',       # NEW
  'sequence_enrollments'  # NEW
]

# Add case handlers for fetching
when 'email_sequences'
  EmailSequence.by_entity(entity.id).where(filters)
when 'sequence_steps'
  SequenceStep.joins(:email_sequence)
              .where(email_sequences: { entity_id: entity.id })
              .where(filters)
when 'sequence_enrollments'
  SequenceEnrollment.joins(:email_sequence)
                    .where(email_sequences: { entity_id: entity.id })
                    .where(filters)
```

---

### 4. NEW: EnrollContactsInSequenceTool (Optional Helper)

**File**: `./app/services/tools/enroll_contacts_in_sequence_tool.rb`

**Purpose**: Batch-create enrollments for all contacts in a group

```ruby
module Tools
  class EnrollContactsInSequenceTool < BaseTool
    def self.metadata
      {
        name: 'enroll_contacts_in_sequence',
        description: 'Enroll all contacts from a contact group into an email sequence',
        category: 'sequence_management',
        input_schema: {
          type: 'object',
          properties: {
            email_sequence_id: {
              type: 'integer',
              description: 'The ID of the email sequence'
            },
            contact_group_id: {
              type: 'integer',
              description: 'The ID of the contact group (optional, uses sequence default if not provided)'
            },
            auto_start: {
              type: 'boolean',
              description: 'Whether to automatically start enrollments (set status to active)',
              default: false
            }
          },
          required: ['email_sequence_id']
        }
      }
    end

    def execute(args)
      log_execution(args)

      sequence_id = get_arg(args, :email_sequence_id)
      group_id = get_arg(args, :contact_group_id)
      auto_start = get_arg(args, :auto_start, false)

      # Validate sequence exists and belongs to entity
      sequence = EmailSequence.find_by(id: sequence_id, entity_id: entity.id)
      unless sequence
        return error_response("Email sequence not found or doesn't belong to this entity")
      end

      # Use provided group or sequence's default group
      group_id ||= sequence.contact_group_id
      contact_group = ContactGroup.find_by(id: group_id, entity_id: entity.id)

      unless contact_group
        return error_response("Contact group not found or doesn't belong to this entity")
      end

      # Get all contacts in the group
      contacts = contact_group.contacts

      if contacts.empty?
        return error_response("Contact group is empty - no contacts to enroll")
      end

      # Create enrollments
      enrolled_count = 0
      already_enrolled = 0
      errors = []

      contacts.each do |contact|
        # Skip if already enrolled
        if SequenceEnrollment.exists?(email_sequence_id: sequence_id, contact_id: contact.id)
          already_enrolled += 1
          next
        end

        begin
          enrollment = SequenceEnrollment.create!(
            email_sequence: sequence,
            contact: contact,
            enrolled_at: Time.current,
            status: auto_start ? 'active' : 'pending',
            current_step_number: 0
          )

          # Set next_send_at if auto-starting
          if auto_start
            first_step = sequence.sequence_steps.find_by(step_number: 1)
            if first_step
              enrollment.update!(
                next_send_at: Time.current + first_step.delay_hours.hours,
                started_at: Time.current
              )
            end
          end

          enrolled_count += 1
        rescue => e
          errors << { contact_id: contact.id, error: e.message }
        end
      end

      # Update sequence statistics
      sequence.update!(
        total_enrollments: sequence.sequence_enrollments.count,
        active_enrollments: sequence.sequence_enrollments.active.count
      )

      success_response(
        message: "Enrolled #{enrolled_count} contacts into sequence",
        enrolled_count: enrolled_count,
        already_enrolled: already_enrolled,
        total_contacts: contacts.count,
        errors: errors,
        sequence_id: sequence.id,
        sequence_name: sequence.name,
        auto_started: auto_start
      )
    end
  end
end
```

---

## Background Jobs Required

### 1. ProcessSequenceEnrollmentsJob

**File**: `./app/jobs/process_sequence_enrollments_job.rb`

**Purpose**: Process pending enrollments when sequence is activated

```ruby
class ProcessSequenceEnrollmentsJob < ApplicationJob
  queue_as :default

  def perform(email_sequence_id)
    sequence = EmailSequence.find(email_sequence_id)

    # Only process if active
    return unless sequence.active?

    # Start all pending enrollments
    sequence.sequence_enrollments.pending.each do |enrollment|
      enrollment.start!
    end

    # Schedule the send job to run immediately
    SendSequenceEmailsJob.perform_later(email_sequence_id)
  end
end
```

---

### 2. SendSequenceEmailsJob

**File**: `./app/jobs/send_sequence_emails_job.rb`

**Purpose**: Send emails for enrollments that are ready

```ruby
class SendSequenceEmailsJob < ApplicationJob
  queue_as :default

  def perform(email_sequence_id)
    sequence = EmailSequence.find(email_sequence_id)

    # Only process if active
    return unless sequence.active?

    # Find enrollments ready to send
    ready_enrollments = sequence.sequence_enrollments.ready_to_send

    Rails.logger.info "Processing #{ready_enrollments.count} ready enrollments for sequence #{sequence.name}"

    ready_enrollments.each do |enrollment|
      process_enrollment(enrollment)
    end

    # If there are still active enrollments, schedule next run
    if sequence.sequence_enrollments.active.any?
      # Check again in 1 hour
      SendSequenceEmailsJob.set(wait: 1.hour).perform_later(email_sequence_id)
    end
  end

  private

  def process_enrollment(enrollment)
    next_step_number = enrollment.current_step_number + 1
    step = enrollment.email_sequence.sequence_steps.find_by(step_number: next_step_number)

    return unless step

    # Send the email
    begin
      # Create email delivery record
      delivery = EmailDelivery.create!(
        contact: enrollment.contact,
        email_template: step.email_template,
        campaign: nil, # Not associated with a campaign
        status: 'pending',
        metadata: {
          email_sequence_id: enrollment.email_sequence_id,
          sequence_step_id: step.id,
          enrollment_id: enrollment.id
        }
      )

      # Send via Mailgun
      MailgunService.send_email(
        to: enrollment.contact.email,
        subject: step.email_template.subject,
        body: step.email_template.body,
        metadata: {
          sequence_enrollment_id: enrollment.id,
          sequence_step_id: step.id
        }
      )

      delivery.update!(status: 'sent', sent_at: Time.current)

      # Update step statistics
      step.increment!(:sent_count)

      # Advance enrollment to next step
      enrollment.advance_to_next_step!

      Rails.logger.info "✅ Sent step #{step.step_number} to contact #{enrollment.contact.email}"
    rescue => e
      Rails.logger.error "❌ Failed to send sequence email: #{e.message}"
      delivery&.update(status: 'failed', error_message: e.message)
    end
  end
end
```

---

## Database Migrations Summary

Create these migrations in order:

```bash
# 1. Create email_sequences table
rails generate migration CreateEmailSequences

# 2. Create sequence_steps table
rails generate migration CreateSequenceSteps

# 3. Create sequence_enrollments table
rails generate migration CreateSequenceEnrollments

# Run migrations
rails db:migrate
```

---

## Testing Recommendations

### 1. Model Tests

**File**: `test/models/email_sequence_test.rb`

```ruby
require 'test_helper'

class EmailSequenceTest < ActiveSupport::TestCase
  test "should create valid sequence" do
    sequence = EmailSequence.create!(
      name: "Test Sequence",
      entity: entities(:one),
      user: users(:one),
      contact_group: contact_groups(:one)
    )

    assert sequence.persisted?
    assert_equal 'draft', sequence.status
  end

  test "should activate sequence" do
    sequence = email_sequences(:draft_sequence)

    assert sequence.activate!
    assert_equal 'active', sequence.status
    assert_not_nil sequence.activated_at
  end

  test "should calculate completion rate" do
    sequence = email_sequences(:active_sequence)
    # Add test logic for completion rate
  end
end
```

### 2. Tool Tests

**File**: `test/services/tools/create_object_tool_test.rb`

Add test cases for email sequence creation.

### 3. Workflow Integration Test

**File**: `test/system/email_sequence_workflow_test.rb`

```ruby
require 'application_system_test_case'

class EmailSequenceWorkflowTest < ApplicationSystemTestCase
  test "creates email sequence via workflow" do
    # Test the complete V2 workflow execution
    # Verify sequence created, steps configured, enrollments created
  end
end
```

---

## Implementation Checklist

### Phase 1: Database Setup
- [ ] Create EmailSequence migration
- [ ] Create SequenceStep migration
- [ ] Create SequenceEnrollment migration
- [ ] Run migrations
- [ ] Create model files with validations and associations
- [ ] Add fixtures for testing

### Phase 2: Tool Updates
- [ ] Update CreateObjectTool with sequence support
- [ ] Update UpdateObjectTool with sequence support
- [ ] Update GetDataTool with sequence queries
- [ ] (Optional) Create EnrollContactsInSequenceTool
- [ ] Test all tools in isolation

### Phase 3: Background Jobs
- [ ] Create ProcessSequenceEnrollmentsJob
- [ ] Create SendSequenceEmailsJob
- [ ] Test job execution
- [ ] Configure SolidQueue for sequence jobs

### Phase 4: Workflow Testing
- [ ] Test workflow template detection (keywords)
- [ ] Test gather_context phase
- [ ] Test execute_goal phase
- [ ] Test validation phase
- [ ] Test end-to-end flow

### Phase 5: UI (Future)
- [ ] Create sequences index page
- [ ] Create sequence detail/edit page
- [ ] Add activation controls
- [ ] Show enrollment statistics
- [ ] Display sequence performance metrics

---

## Key Architectural Patterns

### 1. Entity Scoping
All models are entity-scoped:
- `EmailSequence` belongs to entity
- All queries filtered by entity_id
- Tools respect entity boundaries

### 2. Enrollment State Machine
```
pending → active → completed
            ↓
          paused
            ↓
        cancelled
```

### 3. Step Progression
```
Enrollment created (step 0)
  ↓
Step 1 sent (delay: 0 hours)
  ↓ wait delay_hours
Step 2 sent (delay: 72 hours)
  ↓ wait delay_hours
Step 3 sent (delay: 168 hours)
  ↓
Enrollment completed
```

### 4. Background Processing
- Sequences activated → start all pending enrollments
- Hourly job checks for enrollments ready to send
- Sends emails and advances enrollment state
- Reschedules itself if active enrollments remain

---

## Future Enhancements (Post-MVP)

1. **Action-Based Triggers**
   - Send next email if previous was opened
   - Branch based on link clicks
   - Skip steps based on conditions

2. **A/B Testing**
   - Multiple variants per step
   - Automatic winner selection

3. **Advanced Timing**
   - Send at optimal times (based on open history)
   - Timezone-aware scheduling
   - Business hours only option

4. **Analytics Dashboard**
   - Funnel visualization
   - Drop-off analysis
   - Revenue attribution

5. **Template Marketplace**
   - Pre-built sequence templates
   - Industry-specific sequences
   - One-click import

---

## Summary

The email sequence workflow is designed to integrate seamlessly with existing AMOS V2 patterns:

- **Conversational**: Natural language gathering of requirements
- **Structured Execution**: Predictable tool invocations
- **Entity-Scoped**: Multi-tenant isolation
- **Draft-First**: Safe user review before activation
- **Self-Healing**: Validation with auto-fix capabilities

**Total New Code Required**:
- 3 database models
- 3 migrations
- 2 background jobs
- Tool enhancements (existing files)
- 1 workflow template (already created)

**Estimated Implementation Time**: 8-12 hours for experienced Rails developer

**Files Created**:
1. `./app/workflow_templates/email_sequence_v2.yml` ✅
2. This design document

**Next Steps**: Follow the implementation checklist to build the feature incrementally.
