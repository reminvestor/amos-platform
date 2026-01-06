# frozen_string_literal: true

# ErrorLogEntry - Captured errors from application logs
#
# The Log Monitor service writes entries here, and they get
# processed into support tickets when patterns are detected.
#
class ErrorLogEntry < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :support_ticket, optional: true

  LOG_LEVELS = %w[error fatal warn].freeze

  validates :log_level, inclusion: { in: LOG_LEVELS }
  validates :occurred_at, presence: true

  before_create :generate_error_signature

  scope :unprocessed, -> { where(processed: false) }
  scope :errors, -> { where(log_level: 'error') }
  scope :fatal, -> { where(log_level: 'fatal') }
  scope :recent, -> { order(occurred_at: :desc) }
  scope :without_ticket, -> { where(ticket_created: false) }
  scope :today, -> { where('occurred_at > ?', 24.hours.ago) }

  # ═══════════════════════════════════════════════════════════════════════════
  # CREATION
  # ═══════════════════════════════════════════════════════════════════════════

  def self.capture_error!(
    error_class:,
    error_message:,
    stack_trace: nil,
    entity: nil,
    log_level: 'error',
    context: {}
  )
    # Parse source location from stack trace
    first_app_frame = stack_trace&.lines&.find { |l| l.include?('app/') || l.include?('lib/') }
    source_file = nil
    source_line = nil
    source_method = nil

    if first_app_frame
      match = first_app_frame.match(/(.+):(\d+):in `(.+)'/)
      if match
        source_file = match[1]
        source_line = match[2].to_i
        source_method = match[3]
      end
    end

    create!(
      entity: entity,
      log_level: log_level,
      error_class: error_class,
      error_message: error_message,
      stack_trace: stack_trace,
      source_file: source_file,
      source_line: source_line,
      source_method: source_method,
      context: context,
      occurred_at: Time.current,
      first_occurrence: Time.current,
      last_occurrence: Time.current
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # AGGREGATION
  # ═══════════════════════════════════════════════════════════════════════════

  def self.grouped_by_signature(since: 24.hours.ago)
    where('occurred_at > ?', since)
      .group(:error_signature)
      .select(
        'error_signature',
        'MAX(error_class) as error_class',
        'MAX(error_message) as error_message',
        'COUNT(*) as occurrence_count',
        'MIN(occurred_at) as first_occurrence',
        'MAX(occurred_at) as last_occurrence'
      )
      .order('occurrence_count DESC')
  end

  def similar_entries
    ErrorLogEntry.where(error_signature: error_signature)
      .where.not(id: id)
      .order(occurred_at: :desc)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PROCESSING
  # ═══════════════════════════════════════════════════════════════════════════

  def mark_processed!
    update!(processed: true)
  end

  def create_ticket!
    return support_ticket if support_ticket.present?

    ticket = SupportTicket.create_from_error!(
      entity: entity || Entity.first,
      error_class: error_class,
      error_message: error_message,
      stack_trace: stack_trace,
      context: context
    )

    update!(support_ticket: ticket, ticket_created: true, processed: true)
    ticket
  end

  def to_context
    {
      log_level: log_level,
      error_class: error_class,
      error_message: error_message,
      stack_trace: stack_trace&.first(2000),
      source_file: source_file,
      source_line: source_line,
      occurred_at: occurred_at,
      occurrence_count: occurrence_count
    }
  end

  private

  def generate_error_signature
    return if error_signature.present?

    content = "#{error_class}|#{error_message&.gsub(/\d+/, 'N')}|#{source_file}:#{source_line}"
    self.error_signature = Digest::SHA256.hexdigest(content)[0..16]
  end
end


