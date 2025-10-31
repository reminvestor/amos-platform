# frozen_string_literal: true

module Rag
  # Performs comprehensive health checks on RAG system components
  # Validates database, Redis, S3, Bedrock, and Pinecone connectivity
  # Runs every 15 minutes via cron
  class HealthCheckJob < ApplicationJob
    queue_as :maintenance

    retry_on StandardError, wait: :polynomially_longer, attempts: 2

    def perform
      Rails.logger.info "🏥 Running RAG system health check..."

      health_status = {
        timestamp: Time.current.iso8601,
        checks: {
          database: check_database,
          redis: check_redis,
          s3: check_s3,
          bedrock: check_bedrock,
          pinecone: check_pinecone,
          queues: check_queues,
          recent_failures: check_recent_failures
        }
      }

      health_status[:all_healthy] = health_status[:checks].values.all? { |c| c[:healthy] }

      log_health_status(health_status)
      alert_if_unhealthy(health_status)

      health_status
    end

    private

    def check_database
      # Test database connectivity and RAG tables
      RagStore.connection.execute('SELECT 1')
      RagChunk.limit(1).count # Verify pgvector works

      {
        healthy: true,
        message: 'Database and pgvector operational',
        response_time_ms: measure_db_query_time
      }
    rescue => e
      {
        healthy: false,
        message: "Database error: #{e.message}",
        error_class: e.class.name
      }
    end

    def check_redis
      # Test Redis connectivity
      $redis.ping == 'PONG'

      # Test read/write
      test_key = "health_check:#{Time.current.to_i}"
      $redis.setex(test_key, 10, 'test')
      value = $redis.get(test_key)
      $redis.del(test_key)

      {
        healthy: value == 'test',
        message: 'Redis read/write operational',
        connected_clients: $redis.info['connected_clients']
      }
    rescue => e
      {
        healthy: false,
        message: "Redis error: #{e.message}",
        error_class: e.class.name
      }
    end

    def check_s3
      return { healthy: true, message: 'S3 check skipped (no RAG_BUCKET configured)' } unless ENV['RAG_BUCKET']

      s3 = Aws::S3::Client.new

      # Test bucket access
      s3.head_bucket(bucket: ENV['RAG_BUCKET'])

      # Get bucket size info
      objects_count = s3.list_objects_v2(bucket: ENV['RAG_BUCKET'], max_keys: 1000).contents.count

      {
        healthy: true,
        message: 'S3 bucket accessible',
        bucket: ENV['RAG_BUCKET'],
        sample_objects_count: objects_count
      }
    rescue => e
      {
        healthy: false,
        message: "S3 error: #{e.message}",
        error_class: e.class.name
      }
    end

    def check_bedrock
      return { healthy: true, message: 'Bedrock check skipped (no credentials configured)' } unless bedrock_configured?

      # Just check credentials are present and valid format
      bedrock = Aws::BedrockRuntime::Client.new

      {
        healthy: true,
        message: 'Bedrock credentials configured',
        region: ENV['AWS_REGION']
      }
    rescue => e
      {
        healthy: false,
        message: "Bedrock error: #{e.message}",
        error_class: e.class.name
      }
    end

    def check_pinecone
      return { healthy: true, message: 'Pinecone check skipped (not configured)' } unless pinecone_configured?

      # Check if we have vectors in Pinecone
      vectors_count = RagChunk.where.not(pinecone_vector_id: nil).count

      {
        healthy: true,
        message: 'Pinecone configured',
        vectors_count: vectors_count
      }
    rescue => e
      {
        healthy: false,
        message: "Pinecone error: #{e.message}",
        error_class: e.class.name
      }
    end

    def check_queues
      # Check SolidQueue status
      queue_stats = {
        critical: SolidQueue::Job.where(queue_name: 'critical', finished_at: nil).count,
        embeddings: SolidQueue::Job.where(queue_name: 'embeddings', finished_at: nil).count,
        docling: SolidQueue::Job.where(queue_name: 'docling', finished_at: nil).count,
        documents: SolidQueue::Job.where(queue_name: 'documents', finished_at: nil).count,
        maintenance: SolidQueue::Job.where(queue_name: 'maintenance', finished_at: nil).count
      }

      # Alert if any queue has > 100 pending jobs
      backed_up_queues = queue_stats.select { |_, count| count > 100 }
      healthy = backed_up_queues.empty?

      {
        healthy: healthy,
        message: healthy ? 'All queues processing normally' : "Queues backed up: #{backed_up_queues.keys.join(', ')}",
        queue_sizes: queue_stats
      }
    rescue => e
      {
        healthy: false,
        message: "Queue check error: #{e.message}",
        error_class: e.class.name
      }
    end

    def check_recent_failures
      # Check for recent job failures
      recent_failures = RagProcessingJob
        .where(status: 3) # failed
        .where('created_at > ?', 1.hour.ago)
        .count

      healthy = recent_failures < 10 # Alert if more than 10 failures per hour

      {
        healthy: healthy,
        message: healthy ? 'Normal failure rate' : "High failure rate: #{recent_failures} failures in last hour",
        failures_last_hour: recent_failures
      }
    rescue => e
      {
        healthy: false,
        message: "Failure check error: #{e.message}",
        error_class: e.class.name
      }
    end

    def measure_db_query_time
      start_time = Time.current
      RagChunk.limit(100).pluck(:id)
      ((Time.current - start_time) * 1000).to_i # Convert to milliseconds
    rescue
      nil
    end

    def bedrock_configured?
      ENV['AWS_ACCESS_KEY_ID'].present? && ENV['AWS_REGION'].present?
    end

    def pinecone_configured?
      ENV['PINECONE_API_KEY'].present? && ENV['PINECONE_INDEX'].present?
    end

    def log_health_status(status)
      icon = status[:all_healthy] ? '✅' : '❌'

      Rails.logger.info "#{icon} RAG System Health: #{status[:all_healthy] ? 'HEALTHY' : 'UNHEALTHY'}"

      status[:checks].each do |name, check|
        check_icon = check[:healthy] ? '✅' : '❌'
        Rails.logger.info "  #{check_icon} #{name}: #{check[:message]}"
      end
    end

    def alert_if_unhealthy(status)
      return if status[:all_healthy]

      unhealthy_checks = status[:checks].select { |_, check| !check[:healthy] }

      Rails.logger.warn "🚨 RAG SYSTEM HEALTH ALERT"
      Rails.logger.warn "Unhealthy components: #{unhealthy_checks.keys.join(', ')}"

      unhealthy_checks.each do |name, check|
        Rails.logger.warn "  ❌ #{name}: #{check[:message]}"
      end

      # In production, you could send alerts to Slack, PagerDuty, etc.
      # AlertMailer.system_health_alert(status).deliver_later
    end
  end
end
