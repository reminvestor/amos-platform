class EmailSequence < ApplicationRecord
  include EntityShareable

  belongs_to :entity
  belongs_to :contact_group
  belongs_to :created_by, class_name: 'User', optional: true

  # Associations
  has_many :sequence_steps, dependent: :destroy
  has_many :sequence_enrollments, dependent: :destroy
  has_many :sequence_email_deliveries, dependent: :destroy
  has_many :contacts, through: :sequence_enrollments

  # JSONB metadata handling - Rails 8.0 compatible
  attribute :metadata, :json

  # Status options
  STATUSES = %w[draft active paused completed].freeze

  attribute :status, :string, default: "draft"
  attribute :enrolled_count, :integer, default: 0
  attribute :completed_count, :integer, default: 0
  attribute :active_count, :integer, default: 0

  # Validations
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :contact_group_id, presence: true
  validates :entity_id, presence: true

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :draft, -> { where(status: 'draft') }
  scope :paused, -> { where(status: 'paused') }
  scope :completed, -> { where(status: 'completed') }
  scope :by_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_create :update_enrollment_counts

  # Methods
  def activate!
    return false unless status == 'draft'
    return false unless sequence_steps.any?

    transaction do
      update!(status: 'active')
    end

    # Queue background job to process enrollments
    # This handles setting next_send_at and starting email delivery
    ProcessSequenceEnrollmentsJob.perform_later(id)

    true
  end

  def pause!
    return false unless status == 'active'
    update!(status: 'paused')
  end

  def resume!
    return false unless status == 'paused'
    update!(status: 'active')
  end

  def complete!
    update!(status: 'completed')
  end

  def step_count
    sequence_steps.count
  end

  def update_enrollment_counts
    update_columns(
      enrolled_count: sequence_enrollments.count,
      active_count: sequence_enrollments.active.count,
      completed_count: sequence_enrollments.completed.count
    )
  end

  def enroll_contacts!
    return 0 if contact_group.nil?

    enrolled = 0
    contact_group.contacts.each do |contact|
      # Skip if already enrolled
      next if sequence_enrollments.exists?(contact_id: contact.id)

      sequence_enrollments.create!(
        contact: contact,
        entity: entity,
        status: 'pending',
        current_step_number: 0
      )
      enrolled += 1
    end

    update_enrollment_counts
    enrolled
  end

  # Performance metrics
  def total_sent
    sequence_steps.sum(:sent_count)
  end

  def total_opened
    sequence_steps.sum(:opened_count)
  end

  def total_clicked
    sequence_steps.sum(:clicked_count)
  end

  def open_rate
    return 0 if total_sent.zero?
    (total_opened.to_f / total_sent * 100).round(2)
  end

  def click_rate
    return 0 if total_sent.zero?
    (total_clicked.to_f / total_sent * 100).round(2)
  end

  def completion_rate
    return 0 if enrolled_count.zero?
    (completed_count.to_f / enrolled_count * 100).round(2)
  end
end
