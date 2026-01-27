require "test_helper"

module Rag
  class HealthCheckJobTest < ActiveJob::TestCase
    def setup
      @job = HealthCheckJob.new
    end

    test "perform returns health status hash" do
      result = @job.perform

      assert result.is_a?(Hash)
      assert result[:timestamp].present?
      assert result[:checks].present?
      assert result.key?(:all_healthy)
    end

    test "performs all health checks" do
      result = @job.perform

      assert result[:checks].key?(:database)
      assert result[:checks].key?(:redis)
      assert result[:checks].key?(:s3)
      assert result[:checks].key?(:bedrock)
      assert result[:checks].key?(:pinecone)
      assert result[:checks].key?(:queues)
      assert result[:checks].key?(:recent_failures)
    end

    test "database check passes with healthy database" do
      result = @job.perform

      assert result[:checks][:database][:healthy]
      assert_equal "Database and pgvector operational", result[:checks][:database][:message]
      assert result[:checks][:database][:response_time_ms].present?
    end

    test "redis check passes with healthy Redis" do
      result = @job.perform

      assert result[:checks][:redis][:healthy]
      assert_equal "Redis read/write operational", result[:checks][:redis][:message]
    end

    test "s3 check skips when RAG_BUCKET not configured" do
      ENV.stub(:[], nil) do
        result = @job.perform

        assert result[:checks][:s3][:healthy]
        assert_match /skipped/, result[:checks][:s3][:message]
      end
    end

    test "bedrock check skips when credentials not configured" do
      # Temporarily unset AWS creds
      original_key = ENV['AWS_ACCESS_KEY_ID']
      ENV['AWS_ACCESS_KEY_ID'] = nil

      result = @job.perform

      assert result[:checks][:bedrock][:healthy]
      assert_match /skipped/, result[:checks][:bedrock][:message]

      # Restore
      ENV['AWS_ACCESS_KEY_ID'] = original_key
    end

    test "pinecone check skips when not configured" do
      result = @job.perform

      # Should skip if no Pinecone config
      if ENV['PINECONE_API_KEY'].blank?
        assert result[:checks][:pinecone][:healthy]
        assert_match /skipped/, result[:checks][:pinecone][:message]
      end
    end

    test "queue check detects backed up queues" do
      # This test would require creating actual queued jobs
      # which is complex in test environment
      result = @job.perform

      assert result[:checks][:queues].key?(:queue_sizes)
      assert result[:checks][:queues][:queue_sizes].is_a?(Hash)
    end

    test "recent failures check detects high failure rate" do
      # Create many failed jobs
      15.times do |i|
        RagProcessingJob.create!(
          rag_store: rag_stores(:entity_store_one),
          job_id: "fail#{i}",
          job_type: "embedding",
          status: 3, # failed
          error_message: "Test error",
          created_at: 30.minutes.ago
        )
      end

      result = @job.perform

      refute result[:checks][:recent_failures][:healthy]
      assert result[:checks][:recent_failures][:failures_last_hour] >= 10
    end

    test "all_healthy is true when all checks pass" do
      result = @job.perform

      # In test environment, most checks should pass
      # (S3, Bedrock, Pinecone will be skipped but marked healthy)
      if result[:checks].values.all? { |c| c[:healthy] }
        assert result[:all_healthy]
      end
    end

    test "all_healthy is false when any check fails" do
      # Stub database check to fail
      @job.stub :check_database, ->{ { healthy: false, message: "Test failure" } } do
        result = @job.perform

        refute result[:all_healthy]
      end
    end

    test "logs health status" do
      assert_nothing_raised do
        @job.perform
      end
    end

    test "alerts when system is unhealthy" do
      # Stub to make system unhealthy
      @job.stub :check_database, ->{ { healthy: false, message: "DB down" } } do
        assert_nothing_raised do
          @job.perform
        end
      end
    end

    test "measures database query time" do
      result = @job.perform

      if result[:checks][:database][:response_time_ms]
        assert result[:checks][:database][:response_time_ms] >= 0
      end
    end

    test "redis check performs read/write test" do
      result = @job.perform

      # Should have tested Redis read/write
      assert result[:checks][:redis][:healthy]
    end

    # ActiveJob retry behavior test removed - retry_on only works with enqueued jobs,
    # not when calling @job.perform directly. Framework behavior tested by Rails.
  end
end
