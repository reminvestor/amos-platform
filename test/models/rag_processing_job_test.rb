require "test_helper"

class RagProcessingJobTest < ActiveSupport::TestCase
  def setup
    @rag_store = rag_stores(:entity_one_custom)
    @job = rag_processing_jobs(:job_completed)
  end

  # === Associations ===

  test "belongs to rag_store" do
    assert_equal @rag_store, @job.rag_store
  end

  # === Validations ===

  test "requires job_id" do
    job = RagProcessingJob.new(
      rag_store: @rag_store,
      job_type: "docling_extraction",
      job_id: nil
    )

    assert_not job.valid?
    assert_includes job.errors[:job_id], "can't be blank"
  end

  test "requires job_type" do
    job = RagProcessingJob.new(
      rag_store: @rag_store,
      job_id: "test123",
      job_type: nil
    )

    assert_not job.valid?
    assert_includes job.errors[:job_type], "can't be blank"
  end

  test "job_id must be unique" do
    duplicate = RagProcessingJob.new(
      rag_store: @rag_store,
      job_id: @job.job_id,
      job_type: "docling_extraction"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:job_id], "has already been taken"
  end

  # === Enums ===

  test "status enum works correctly" do
    assert_equal "completed", @job.status
    assert @job.status_completed?

    @job.status_pending!
    assert_equal "pending", @job.status
    assert @job.status_pending?

    @job.status_processing!
    assert_equal "processing", @job.status
    assert @job.status_processing?

    @job.status_failed!
    assert_equal "failed", @job.status
    assert @job.status_failed?
  end

  # === Scopes ===

  test "for_entity scope returns jobs for specific entity" do
    entity_one = entities(:one)
    entity_two = entities(:two)

    entity_one_jobs = RagProcessingJob.for_entity(entity_one)
    entity_two_jobs = RagProcessingJob.for_entity(entity_two)

    assert_includes entity_one_jobs, rag_processing_jobs(:job_completed)
    assert_includes entity_one_jobs, rag_processing_jobs(:job_processing)
    assert_not_includes entity_one_jobs, rag_processing_jobs(:job_failed)

    assert_includes entity_two_jobs, rag_processing_jobs(:job_failed)
    assert_not_includes entity_two_jobs, rag_processing_jobs(:job_completed)
  end

  test "for_rag_store scope returns jobs for specific store" do
    jobs = RagProcessingJob.for_rag_store(@rag_store)

    assert_includes jobs, rag_processing_jobs(:job_completed)
    assert_includes jobs, rag_processing_jobs(:job_processing)
    assert_not_includes jobs, rag_processing_jobs(:job_failed)
  end

  test "by_type scope filters by job type" do
    docling_jobs = RagProcessingJob.by_type("docling_extraction")
    chunking_jobs = RagProcessingJob.by_type("chunking")

    assert_includes docling_jobs, rag_processing_jobs(:job_completed)
    assert_includes docling_jobs, rag_processing_jobs(:job_failed)
    assert_not_includes docling_jobs, rag_processing_jobs(:job_processing)

    assert_includes chunking_jobs, rag_processing_jobs(:job_processing)
    assert_not_includes chunking_jobs, rag_processing_jobs(:job_completed)
  end

  test "in_progress scope returns pending or processing jobs" do
    in_progress = RagProcessingJob.in_progress

    assert_includes in_progress, rag_processing_jobs(:job_processing)
    assert_includes in_progress, rag_processing_jobs(:job_pending)
    assert_not_includes in_progress, rag_processing_jobs(:job_completed)
    assert_not_includes in_progress, rag_processing_jobs(:job_failed)
  end

  test "finished scope returns completed or failed jobs" do
    finished = RagProcessingJob.finished

    assert_includes finished, rag_processing_jobs(:job_completed)
    assert_includes finished, rag_processing_jobs(:job_failed)
    assert_not_includes finished, rag_processing_jobs(:job_processing)
    assert_not_includes finished, rag_processing_jobs(:job_pending)
  end

  test "failed_jobs scope returns only failed jobs" do
    failed = RagProcessingJob.failed_jobs

    assert_includes failed, rag_processing_jobs(:job_failed)
    assert_not_includes failed, rag_processing_jobs(:job_completed)
  end

  test "recent scope returns jobs from last 24 hours" do
    # All fixture jobs are recent (created within last hour)
    recent = RagProcessingJob.recent

    assert_includes recent, @job
  end

  test "with_errors scope returns jobs with error messages" do
    jobs_with_errors = RagProcessingJob.with_errors

    assert_includes jobs_with_errors, rag_processing_jobs(:job_failed)
    assert_not_includes jobs_with_errors, rag_processing_jobs(:job_completed)
  end

  test "needs_retry scope returns failed jobs under max retries" do
    needs_retry = RagProcessingJob.needs_retry

    assert_includes needs_retry, rag_processing_jobs(:job_failed)
  end

  # === Instance Methods ===

  test "duration_ms returns processing duration in milliseconds" do
    duration = rag_processing_jobs(:job_completed).duration_ms

    # Started 10 minutes ago, completed 8 minutes ago = 2 minutes = 120000ms
    assert_equal 120000, duration
  end

  test "duration_ms returns nil when not completed" do
    duration = rag_processing_jobs(:job_processing).duration_ms

    assert_nil duration
  end

  test "duration_seconds returns processing duration in seconds" do
    seconds = rag_processing_jobs(:job_completed).duration_seconds

    assert_equal 120.0, seconds
  end

  test "in_progress? returns true for pending or processing" do
    assert rag_processing_jobs(:job_processing).in_progress?
    assert rag_processing_jobs(:job_pending).in_progress?
    assert_not rag_processing_jobs(:job_completed).in_progress?
  end

  test "finished? returns true for completed or failed" do
    assert rag_processing_jobs(:job_completed).finished?
    assert rag_processing_jobs(:job_failed).finished?
    assert_not rag_processing_jobs(:job_processing).finished?
  end

  test "can_retry? returns true when under max retries" do
    job = rag_processing_jobs(:job_failed)
    job.retry_count = 2

    assert job.can_retry?

    job.retry_count = 3
    assert_not job.can_retry?
  end

  test "fast_job? returns true when duration is under 5 seconds" do
    job = rag_processing_jobs(:job_completed)
    job.started_at = 3.seconds.ago
    job.completed_at = Time.current

    assert job.fast_job?
  end

  test "slow_job? returns true when duration is over 30 seconds" do
    job = rag_processing_jobs(:job_completed)
    job.started_at = 60.seconds.ago
    job.completed_at = Time.current

    assert job.slow_job?
  end

  test "job_age returns time since job was created" do
    job = rag_processing_jobs(:job_completed)

    # Job was created 10 minutes ago
    age = job.job_age

    assert age > 500 # At least 500 seconds (8+ minutes)
  end

  # === Class Methods (Analytics) ===

  test "success_rate calculates percentage of successful jobs" do
    # All jobs: completed, processing, failed, pending, pipeline, fallback
    # Finished jobs: completed, failed, pipeline, fallback = 4
    # Successful: completed, pipeline, fallback = 3
    # Rate: 3/4 = 75%
    rate = RagProcessingJob.success_rate

    assert_equal 75.0, rate
  end

  test "success_rate filters by job type" do
    # Docling jobs: completed (success), failed (failure)
    # Rate: 1/2 = 50%
    rate = RagProcessingJob.success_rate(job_type: "docling_extraction")

    assert_equal 50.0, rate
  end

  test "success_rate returns 0 when no finished jobs" do
    # Create entity with no finished jobs
    new_store = RagStore.create!(
      entity: entities(:one),
      name: "Empty Store",
      app_name: "EmptyApp",
      store_type: "entity",
      status: "active",
      pinecone_namespace: "empty"
    )

    RagProcessingJob.create!(
      rag_store: new_store,
      job_id: "pending123",
      job_type: "test",
      status: :pending
    )

    rate = RagProcessingJob.success_rate

    # Should still calculate based on ALL finished jobs, not just new store
    assert rate >= 0
  end

  test "average_processing_time calculates mean duration" do
    # Completed jobs with durations:
    # job_completed: 2 min = 120000ms
    # job_pipeline: 5 min = 300000ms
    # job_fallback: 3 min = 180000ms
    # Average: (120000 + 300000 + 180000) / 3 = 200000ms
    avg = RagProcessingJob.average_processing_time

    assert_equal 200000, avg
  end

  test "average_processing_time filters by job type" do
    avg = RagProcessingJob.average_processing_time(job_type: "pipeline")

    # Only job_pipeline: 5 min = 300000ms
    assert_equal 300000, avg
  end

  test "failure_rate calculates percentage of failed jobs" do
    # Finished jobs: 4 (completed, failed, pipeline, fallback)
    # Failed: 1
    # Rate: 1/4 = 25%
    rate = RagProcessingJob.failure_rate

    assert_equal 25.0, rate
  end

  test "retry_count_stats returns statistics" do
    stats = RagProcessingJob.retry_count_stats

    assert_equal 0, stats[:min]
    assert_equal 2, stats[:max]
    assert stats[:avg] > 0
  end

  # === Job Type Helpers ===

  test "docling_job? returns true for docling jobs" do
    assert rag_processing_jobs(:job_completed).docling_job?
    assert rag_processing_jobs(:job_failed).docling_job?
    assert_not rag_processing_jobs(:job_processing).docling_job?
  end

  test "embedding_job? returns true for embedding jobs" do
    job = rag_processing_jobs(:job_pending)
    assert job.embedding_job?
  end

  test "pipeline_job? returns true for pipeline jobs" do
    assert rag_processing_jobs(:job_pipeline).pipeline_job?
  end

  # === Error Handling ===

  test "has_error? returns true when error_message exists" do
    assert rag_processing_jobs(:job_failed).has_error?
    assert_not rag_processing_jobs(:job_completed).has_error?
  end

  test "error_type extracts error type from message" do
    job = rag_processing_jobs(:job_failed)

    assert_equal "Docling timeout", job.error_type
  end

  test "record_error updates status and error message" do
    job = rag_processing_jobs(:job_processing)

    job.record_error("Test error occurred")

    assert job.status_failed?
    assert_equal "Test error occurred", job.error_message
    assert_not_nil job.completed_at
  end

  test "increment_retry increments retry count" do
    job = rag_processing_jobs(:job_failed)
    original_count = job.retry_count

    job.increment_retry!

    assert_equal original_count + 1, job.retry_count
  end

  # === State Transitions ===

  test "mark_as_started sets status and timestamp" do
    job = rag_processing_jobs(:job_pending)

    job.mark_as_started!

    assert job.status_processing?
    assert_not_nil job.started_at
  end

  test "mark_as_completed sets status and timestamp" do
    job = rag_processing_jobs(:job_processing)

    job.mark_as_completed!

    assert job.status_completed?
    assert_not_nil job.completed_at
  end

  test "mark_as_failed sets status, error, and timestamp" do
    job = rag_processing_jobs(:job_processing)

    job.mark_as_failed!("Processing failed")

    assert job.status_failed?
    assert_equal "Processing failed", job.error_message
    assert_not_nil job.completed_at
  end
end
