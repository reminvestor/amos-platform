class DocumentAnalytics < ApplicationRecord
  belongs_to :rag_document
  
  validates :date, presence: true, uniqueness: { scope: :rag_document_id }
  
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :recent, -> { order(date: :desc) }
  
  # Get analytics for a specific document
  def self.for_document(document, date_range = 30.days.ago..Date.current)
    where(rag_document: document, date: date_range)
  end
  
  # Aggregate stats for a document
  def self.aggregate_for_document(document, date_range = 30.days.ago..Date.current)
    stats = for_document(document, date_range)
    
    {
      total_views: stats.sum(:view_count),
      total_queries: stats.sum(:query_count),
      total_downloads: stats.sum(:download_count),
      unique_users: stats.sum(:unique_users),
      avg_relevance: stats.average(:relevance_score_avg)&.round(2) || 0,
      total_retrievals: stats.sum(:chunk_retrieval_count),
      popular_queries: extract_popular_queries(stats),
      daily_average: {
        views: (stats.sum(:view_count).to_f / stats.count).round(1),
        queries: (stats.sum(:query_count).to_f / stats.count).round(1)
      }
    }
  end
  
  # Track a view
  def self.track_view(document, user)
    analytics = find_or_create_for_today(document)
    
    analytics.increment!(:view_count)
    
    # Update unique users
    user_breakdown = analytics.user_breakdown
    user_breakdown[user.id.to_s] ||= 0
    user_breakdown[user.id.to_s] += 1
    
    analytics.update!(
      user_breakdown: user_breakdown,
      unique_users: user_breakdown.keys.count
    )
  end
  
  # Track a query that retrieved this document
  def self.track_query(document, query, relevance_score = nil)
    analytics = find_or_create_for_today(document)
    
    analytics.increment!(:query_count)
    
    # Track search queries
    queries = analytics.search_queries || []
    queries << {
      query: query.truncate(200),
      timestamp: Time.current.iso8601,
      relevance: relevance_score
    }
    
    # Keep only last 100 queries
    queries = queries.last(100)
    
    # Update average relevance score
    if relevance_score
      scores = queries.map { |q| q['relevance'] }.compact
      avg_relevance = scores.any? ? (scores.sum.to_f / scores.count).round(3) : nil
    end
    
    analytics.update!(
      search_queries: queries,
      relevance_score_avg: avg_relevance
    )
  end
  
  # Track a download
  def self.track_download(document, user)
    analytics = find_or_create_for_today(document)
    analytics.increment!(:download_count)
    track_user_action(analytics, user, 'download')
  end
  
  # Track chunk retrievals
  def self.track_chunk_retrieval(document, chunk_count = 1)
    analytics = find_or_create_for_today(document)
    analytics.increment!(:chunk_retrieval_count, chunk_count)
  end
  
  # Top documents by metric
  ALLOWED_METRICS = %i[view_count search_hit_count citation_count chunk_retrieval_count].freeze

  def self.top_documents(entity, metric: :view_count, limit: 10, date_range: 30.days.ago..Date.current)
    # Whitelist metrics to prevent SQL injection
    sanitized_metric = metric.to_sym
    unless ALLOWED_METRICS.include?(sanitized_metric)
      raise ArgumentError, "Invalid metric: #{metric}. Allowed: #{ALLOWED_METRICS.join(', ')}"
    end

    joins(rag_document: :rag_store)
      .where(rag_stores: { entity_id: entity.id })
      .where(date: date_range)
      .group(:rag_document_id)
      .order(Arel.sql("SUM(#{sanitized_metric}) DESC"))
      .limit(limit)
      .pluck(:rag_document_id, Arel.sql("SUM(#{sanitized_metric})"))
  end
  
  # Knowledge gaps - queries with low relevance
  def self.knowledge_gaps(entity, threshold: 0.5, limit: 20)
    low_relevance_queries = joins(rag_document: :rag_store)
      .where(rag_stores: { entity_id: entity.id })
      .where.not(search_queries: nil)
      .where.not(search_queries: [])
      .pluck(:search_queries)
      .flatten
      .select { |q| q['relevance'].to_f < threshold }
      .group_by { |q| q['query'] }
      .transform_values(&:count)
      .sort_by { |_, count| -count }
      .first(limit)
    
    low_relevance_queries.map { |query, count| { query: query, occurrences: count } }
  end
  
  private
  
  def self.find_or_create_for_today(document)
    find_or_create_by(
      rag_document: document,
      date: Date.current
    )
  end
  
  def self.track_user_action(analytics, user, action)
    user_breakdown = analytics.user_breakdown
    user_key = "#{user.id}_#{action}"
    user_breakdown[user_key] ||= 0
    user_breakdown[user_key] += 1
    
    unique_user_ids = user_breakdown.keys.map { |k| k.split('_').first }.uniq
    
    analytics.update!(
      user_breakdown: user_breakdown,
      unique_users: unique_user_ids.count
    )
  end
  
  def self.extract_popular_queries(stats)
    all_queries = stats.flat_map { |s| s.search_queries || [] }
    
    all_queries
      .group_by { |q| q['query'] }
      .transform_values(&:count)
      .sort_by { |_, count| -count }
      .first(10)
      .map { |query, count| { query: query, count: count } }
  end
end
