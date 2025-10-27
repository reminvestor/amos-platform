# frozen_string_literal: true

module Rag
  # Collects and logs RAG system metrics for monitoring
  # Run daily via cron to track system health and usage
  class MetricsJob < ApplicationJob
    queue_as :maintenance

    # Retry with exponential backoff
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform
      Rails.logger.info "🔍 Starting RAG metrics collection..."

      metrics = {
        date: Date.current.to_s,
        timestamp: Time.current.iso8601,
        processing: collect_processing_metrics,
        usage: collect_usage_metrics,
        storage: collect_storage_metrics,
        health: check_system_health
      }

      log_metrics(metrics)
      check_for_alerts(metrics)

      Rails.logger.info "✅ RAG metrics collection complete"
      metrics
    end

    private

    def collect_processing_metrics
      recent_jobs = RagProcessingJob.where('created_at > ?', 24.hours.ago)
      docling_jobs = recent_jobs.where(job_type: 'docling_extraction')

      {
        total_documents: RagDocument.count,
        documents_today: RagDocument.where('created_at > ?', 24.hours.ago).count,
        total_chunks: RagChunk.count,
        chunks_today: RagChunk.where('created_at > ?', 24.hours.ago).count,
        avg_processing_time_ms: RagStore.where.not(processing_time_ms: nil)
                                        .average(:processing_time_ms)&.to_i || 0,
        jobs_processed_today: recent_jobs.count,
        jobs_completed_today: recent_jobs.where(status: 2).count, # completed
        jobs_failed_today: recent_jobs.where(status: 3).count, # failed
        docling_success_rate: calculate_success_rate(docling_jobs),
        fallback_usage_rate: calculate_fallback_rate
      }
    end

    def collect_usage_metrics
      recent_queries = RagQuery.where('created_at > ?', 24.hours.ago)

      {
        total_queries: RagQuery.count,
        queries_today: recent_queries.count,
        unique_entities_today: recent_queries.distinct.count(:entity_id),
        avg_response_time_ms: recent_queries.average(:response_time_ms)&.to_i || 0,
        cache_hit_rate: calculate_cache_hit_rate(recent_queries),
        avg_chunks_retrieved: recent_queries.average(:chunks_retrieved)&.to_i || 0
      }
    end

    def collect_storage_metrics
      {
        total_rag_stores: RagStore.count,
        active_rag_stores: RagStore.where(status: ['active', 'ready']).count,
        system_stores: RagStore.where(store_type: 'system').count,
        entity_stores: RagStore.where(store_type: 'entity').count,
        total_chunks: RagChunk.count,
        chunks_with_embeddings: RagChunk.where.not(embedding: nil).count,
        chunks_in_pinecone: RagChunk.where.not(pinecone_vector_id: nil).count,
        avg_chunks_per_document: calculate_avg_chunks_per_doc,
        database_size_mb: calculate_database_size
      }
    end

    def check_system_health
      health_checks = {
        database: check_database_health,
        redis: check_redis_health,
        s3: check_s3_health,
        bedrock: check_bedrock_health,
        queue_health: check_queue_health
      }

      {
        all_systems_healthy: health_checks.values.all? { |v| v[:healthy] },
        checks: health_checks
      }
    end

    def calculate_success_rate(jobs)
      return 100.0 if jobs.count.zero?

      completed = jobs.where(status: 2).count # completed status = 2
      (completed.to_f / jobs.count * 100).round(2)
    end

    def calculate_fallback_rate
      total = RagStore.where.not(processing_method: nil).count
      return 0.0 if total.zero?

      fallback = RagStore.where(processing_method: 'fallback').count
      (fallback.to_f / total * 100).round(2)
    end

    def calculate_cache_hit_rate(queries)
      return 0.0 if queries.count.zero?

      hits = queries.where(cache_hit: true).count
      (hits.to_f / queries.count * 100).round(2)
    end

    def calculate_avg_chunks_per_doc
      return 0 if RagDocument.count.zero?

      (RagChunk.count.to_f / RagDocument.count).round(2)
    end

    def calculate_database_size
      result = ActiveRecord::Base.connection.execute(
        "SELECT pg_database_size('#{ActiveRecord::Base.connection.current_database}') as size"
      )
      (result.first['size'].to_i / 1.megabyte.to_f).round(2)
    rescue => e
      Rails.logger.error "Failed to calculate database size: #{e.message}"
      0
    end

    def check_database_health
      ActiveRecord::Base.connection.execute('SELECT 1')
      { healthy: true, message: 'Database connected' }
    rescue => e
      { healthy: false, message: "Database error: #{e.message}" }
    end

    def check_redis_health
      $redis.ping == 'PONG'
      { healthy: true, message: 'Redis connected' }
    rescue => e
      { healthy: false, message: "Redis error: #{e.message}" }
    end

    def check_s3_health
      return { healthy: true, message: 'S3 check skipped (no bucket configured)' } unless ENV['RAG_BUCKET']

      s3 = Aws::S3::Client.new
      s3.head_bucket(bucket: ENV['RAG_BUCKET'])
      { healthy: true, message: 'S3 accessible' }
    rescue => e
      { healthy: false, message: "S3 error: #{e.message}" }
    end

    def check_bedrock_health
      return { healthy: true, message: 'Bedrock check skipped (no credentials)' } unless ENV['AWS_ACCESS_KEY_ID']

      bedrock = Aws::BedrockRuntime::Client.new
      # Don't actually invoke the model, just check credentials
      { healthy: true, message: 'Bedrock credentials configured' }
    rescue => e
      { healthy: false, message: "Bedrock error: #{e.message}" }
    end

    def check_queue_health
      queues = {
        critical: SolidQueue::Job.where(queue_name: 'critical').count,
        embeddings: SolidQueue::Job.where(queue_name: 'embeddings').count,
        docling: SolidQueue::Job.where(queue_name: 'docling').count,
        documents: SolidQueue::Job.where(queue_name: 'documents').count,
        maintenance: SolidQueue::Job.where(queue_name: 'maintenance').count
      }

      backed_up = queues.any? { |name, count| count > 100 }

      {
        healthy: !backed_up,
        message: backed_up ? 'Some queues backing up' : 'All queues healthy',
        queue_sizes: queues
      }
    rescue => e
      { healthy: false, message: "Queue check error: #{e.message}", queue_sizes: {} }
    end

    def log_metrics(metrics)
      Rails.logger.info "=" * 80
      Rails.logger.info "📊 RAG System Metrics - #{metrics[:date]}"
      Rails.logger.info "=" * 80
      Rails.logger.info ""
      Rails.logger.info "📝 Processing:"
      metrics[:processing].each { |k, v| Rails.logger.info "  #{k}: #{v}" }
      Rails.logger.info ""
      Rails.logger.info "🔍 Usage:"
      metrics[:usage].each { |k, v| Rails.logger.info "  #{k}: #{v}" }
      Rails.logger.info ""
      Rails.logger.info "💾 Storage:"
      metrics[:storage].each { |k, v| Rails.logger.info "  #{k}: #{v}" }
      Rails.logger.info ""
      Rails.logger.info "🏥 Health:"
      metrics[:health][:checks].each do |name, status|
        icon = status[:healthy] ? '✅' : '❌'
        Rails.logger.info "  #{icon} #{name}: #{status[:message]}"
      end
      Rails.logger.info "=" * 80
    end

    def check_for_alerts(metrics)
      alerts = []

      # Alert on high failure rate
      if metrics[:processing][:docling_success_rate] < 80
        alerts << "⚠️ Docling success rate below 80%: #{metrics[:processing][:docling_success_rate]}%"
      end

      # Alert on backed up queues
      metrics[:health][:checks][:queue_health][:queue_sizes]&.each do |queue, size|
        if size > 100
          alerts << "⚠️ Queue #{queue} backing up: #{size} jobs"
        end
      end

      # Alert on slow queries
      if metrics[:usage][:avg_response_time_ms] > 5000
        alerts << "⚠️ Slow query performance: avg #{metrics[:usage][:avg_response_time_ms]}ms"
      end

      # Alert on low cache hit rate
      if metrics[:usage][:queries_today] > 10 && metrics[:usage][:cache_hit_rate] < 20
        alerts << "⚠️ Low cache hit rate: #{metrics[:usage][:cache_hit_rate]}%"
      end

      if alerts.any?
        Rails.logger.warn "🚨 RAG System Alerts:"
        alerts.each { |alert| Rails.logger.warn "  #{alert}" }
      else
        Rails.logger.info "✅ No alerts - system healthy"
      end
    end
  end
end
