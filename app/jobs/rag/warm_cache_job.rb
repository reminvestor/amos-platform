# frozen_string_literal: true

module Rag
  # Pre-caches popular RAG queries to improve response times
  # Identifies frequently-used queries and pre-computes results
  # Runs every 6 hours via cron
  class WarmCacheJob < ApplicationJob
    queue_as :maintenance

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    # Minimum query frequency to be considered "popular"
    MIN_QUERY_FREQUENCY = 3

    # How many popular queries to cache per entity
    CACHE_LIMIT = 50

    def perform
      Rails.logger.info "🔥 Starting cache warming for popular RAG queries..."

      popular_queries = find_popular_queries

      Rails.logger.info "Found #{popular_queries.length} popular queries across #{popular_queries.map(&:entity_id).uniq.length} entities"

      warmed_count = 0
      errors = []

      popular_queries.each do |query_record|
        begin
          warm_query_cache(query_record)
          warmed_count += 1
        rescue => e
          error_msg = "Failed to warm cache for query '#{query_record.query}': #{e.message}"
          Rails.logger.error error_msg
          errors << error_msg
        end
      end

      result = {
        date: Date.current.to_s,
        timestamp: Time.current.iso8601,
        popular_queries_found: popular_queries.length,
        cache_warmed_count: warmed_count,
        errors: errors
      }

      log_summary(result)
      result
    end

    private

    def find_popular_queries
      # Find queries that have been run multiple times in the last 7.days
      # Group by query_hash to handle identical queries

      RagQuery
        .select('query_hash, query, entity_id, COUNT(*) as frequency')
        .where('created_at > ?', 7.days.ago)
        .group(:query_hash, :query, :entity_id)
        .having("COUNT(*) >= ?", MIN_QUERY_FREQUENCY)
        .order(Arel.sql('COUNT(*) DESC'))
        .limit(CACHE_LIMIT)
    end

    def warm_query_cache(query_record)
      entity = Entity.find(query_record.entity_id)

      Rails.logger.info "  🔥 Warming cache for: '#{query_record.query.truncate(50)}' (entity: #{entity.name}, frequency: #{query_record.frequency})"

      # Use HybridRagQueryService to execute query
      service = HybridRagQueryService.new(entity)
      result = service.query(query_record.query, top_k: 5)

      # Cache key matches what HybridRagQueryService uses
      cache_key = "rag:query:#{entity.id}:#{query_record.query_hash}"

      # Cache for 1 hour (same as normal queries)
      Rails.cache.write(
        cache_key,
        result,
        expires_in: 1.hour
      )

      Rails.logger.info "    ✅ Cached #{result[:chunks].length} chunks for query"
    rescue => e
      Rails.logger.error "    ❌ Failed to warm cache: #{e.message}"
      raise
    end

    def log_summary(result)
      Rails.logger.info "=" * 80
      Rails.logger.info "🔥 Cache Warming Summary - #{result[:date]}"
      Rails.logger.info "=" * 80
      Rails.logger.info "Popular Queries Found: #{result[:popular_queries_found]}"
      Rails.logger.info "Caches Warmed: #{result[:cache_warmed_count]}"
      Rails.logger.info "Errors: #{result[:errors].length}"

      if result[:errors].any?
        Rails.logger.info ""
        Rails.logger.info "Errors:"
        result[:errors].each { |error| Rails.logger.info "  - #{error}" }
      end

      Rails.logger.info "=" * 80
    end
  end
end
