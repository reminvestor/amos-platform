# RagProcessingJob - Tracks Sidekiq job execution for RAG processing
#
# Monitors the status of document processing pipeline jobs:
# - Document upload and S3 storage
# - Docling extraction
# - Chunking
# - Embedding generation
# - Pinecone synchronization
#
# Key features:
# - Job status tracking (pending, processing, completed, failed)
# - Error logging and retry tracking
# - Performance metrics (duration)
# - Job type classification

class RagProcessingJob < ApplicationRecord
  belongs_to :rag_store

  # Enums
  enum :status, {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, prefix: true

  # Validations
  validates :job_id, presence: true, uniqueness: true
  validates :job_type, presence: true
  validates :status, presence: true

  # Scopes
  scope :for_rag_store, ->(rag_store) { where(rag_store: rag_store) }
  scope :for_entity, ->(entity) { joins(:rag_store).where(rag_stores: { entity_id: entity.id }) }
  scope :by_type, ->(type) { where(job_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: [:pending, :processing]) }
  scope :finished, -> { where(status: [:completed, :failed]) }
  scope :in_progress, -> { where(status: [:pending, :processing]) }
  scope :failed_jobs, -> { where(status: :failed) }
  scope :with_errors, -> { where.not(error_message: [nil, '']) }

  # Job type scopes
  scope :pipeline_jobs, -> { where(job_type: "pipeline") }
  scope :docling_jobs, -> { where(job_type: "docling_extraction") }
  scope :chunking_jobs, -> { where(job_type: "chunking") }
  scope :embedding_jobs, -> { where(job_type: "embedding_batch") }
  scope :needs_retry, -> { where(status: :failed).where("retry_count < ?", 3) }

  # Performance metrics
  def duration_ms
    return nil unless started_at && completed_at
    ((completed_at - started_at) * 1000).round(0)
  end

  def duration_seconds
    return nil unless duration_ms
    (duration_ms.to_f / 1000).round(1)
  end

  def job_age
    (Time.current - created_at).to_i
  end

  def fast_job?
    return false unless duration_ms
    duration_ms < 5000  # Less than 5 seconds
  end

  def slow_job?
    return false unless duration_ms
    duration_ms > 30000  # More than 30 seconds
  end

  def duration_human
    return "N/A" unless duration_ms

    if duration_ms < 1000
      "#{duration_ms}ms"
    elsif duration_ms < 60000
      "#{(duration_ms / 1000.0).round(2)}s"
    else
      minutes = (duration_ms / 60000).floor
      seconds = ((duration_ms % 60000) / 1000.0).round(0)
      "#{minutes}m #{seconds}s"
    end
  end

  # Status helpers
  def in_progress?
    status_pending? || status_processing?
  end

  def successful?
    status_completed?
  end

  def has_errors?
    status_failed?
  end

  def has_error?
    error_message.present?
  end

  def finished?
    status_completed? || status_failed?
  end

  def can_retry?
    status_failed? && retry_count < 3
  end

  # Job type helpers
  def job_type_label
    case job_type
    when "pipeline" then "Document Pipeline"
    when "docling_extraction" then "Docling Extraction"
    when "chunking" then "Chunking"
    when "embedding_batch" then "Embedding Generation"
    when "fallback_processor" then "Fallback Processor"
    when "pinecone_sync" then "Pinecone Sync"
    when "archive" then "Archive"
    when "cleanup" then "Cleanup"
    else job_type.titleize
    end
  end

  def pipeline_job?
    job_type == "pipeline"
  end

  def docling_job?
    job_type == "docling_extraction"
  end

  def chunking_job?
    job_type == "chunking"
  end

  def embedding_job?
    job_type == "embedding_batch"
  end

  # Analytics methods
  def self.success_rate(job_type: nil, timeframe: 1.day)
    scope = where("created_at > ?", timeframe.ago)
    scope = scope.where(job_type: job_type) if job_type.present?

    total = scope.finished.count
    return 0 if total.zero?

    successes = scope.status_completed.count
    ((successes.to_f / total) * 100).round(2)
  end

  def self.average_duration(job_type: nil)
    scope = status_completed
    scope = scope.where(job_type: job_type) if job_type.present?

    jobs_with_duration = scope.where.not(started_at: nil, completed_at: nil)
    return 0 if jobs_with_duration.empty?

    durations = jobs_with_duration.map(&:duration_ms).compact
    return 0 if durations.empty?

    (durations.sum / durations.size).round(0)
  end

  def self.average_processing_time(job_type: nil)
    average_duration(job_type: job_type)
  end

  def self.failure_rate(job_type: nil, timeframe: 1.day)
    100 - success_rate(job_type: job_type, timeframe: timeframe)
  end

  def self.retry_count_stats
    completed_jobs = status_completed

    return { min: 0, max: 0, avg: 0 } if completed_jobs.empty?

    retry_counts = completed_jobs.pluck(:retry_count)
    {
      min: retry_counts.min,
      max: retry_counts.max,
      avg: (retry_counts.sum.to_f / retry_counts.length).round(2)
    }
  end

  # Retry tracking
  def retryable?
    status_failed? && retry_count < 3
  end

  def max_retries_exceeded?
    retry_count >= 3
  end

  # Error helpers
  def short_error_message(length = 100)
    return nil unless error_message
    return error_message if error_message.length <= length
    "#{error_message[0...length]}..."
  end

  def error_type
    return nil unless error_message
    # Extract error class name from message (e.g., "RuntimeError: something went wrong")
    error_message.split(':').first&.strip
  end

  # Job lifecycle tracking
  def mark_started!
    update!(
      status: :processing,
      started_at: Time.current
    )
  end
  alias_method :mark_as_started!, :mark_started!

  def mark_completed!
    update!(
      status: :completed,
      completed_at: Time.current
    )
  end
  alias_method :mark_as_completed!, :mark_completed!

  def mark_failed!(error)
    update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error.to_s,
      retry_count: retry_count + 1
    )
  end
  alias_method :mark_as_failed!, :mark_failed!

  def record_error(message)
    update!(
      status: :failed,
      error_message: message,
      completed_at: Time.current
    )
  end

  def increment_retry!
    increment!(:retry_count)
  end

  def processing?
    status_processing?
  end
end
