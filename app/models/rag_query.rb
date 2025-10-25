# RagQuery - Tracks RAG query usage and performance
#
# Records all queries made to the RAG system for:
# - Usage analytics and metrics
# - Cache hit rate tracking
# - Performance monitoring
# - Query pattern analysis
#
# Key features:
# - Query deduplication via SHA256 hash
# - Cache hit tracking
# - Response time monitoring
# - Chunk retrieval tracking

class RagQuery < ApplicationRecord
  belongs_to :entity
  belongs_to :rag_store, optional: true

  # Validations
  validates :query, presence: true

  # Callbacks
  before_validation :generate_query_hash, if: -> { query.present? && query_hash.blank? }

  # Scopes
  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_rag_store, ->(rag_store) { where(rag_store: rag_store) }
  scope :cache_hits, -> { where(cache_hit: true) }
  scope :cache_misses, -> { where(cache_hit: false) }
  scope :recent, -> { order(created_at: :desc) }
  scope :slow_queries, ->(threshold_ms = 1000) { where("response_time_ms > ?", threshold_ms) }
  scope :today, -> { where("created_at >= ?", Time.zone.now.beginning_of_day) }
  scope :this_week, -> { where("created_at >= ?", 1.week.ago) }
  scope :this_month, -> { where("created_at >= ?", 1.month.ago) }

  # Query deduplication and similarity
  def self.similar_queries(query, entity, limit = 5)
    query_hash = Digest::SHA256.hexdigest(query.downcase.strip)

    where(entity: entity)
      .where.not(query_hash: query_hash)
      .order(created_at: :desc)
      .limit(limit * 2) # Get more to filter
      .select { |q| similar_text?(query, q.query) }
      .first(limit)
  end

  # Analytics helpers
  def self.cache_hit_rate(entity = nil)
    scope = entity ? for_entity(entity) : all
    total = scope.count
    return 0 if total.zero?

    hits = scope.cache_hits.count
    ((hits.to_f / total) * 100).round(2)
  end

  def self.average_response_time(entity = nil)
    scope = entity ? for_entity(entity) : all
    scope.average(:response_time_ms)&.round(0) || 0
  end

  def self.popular_queries(entity, limit = 10)
    for_entity(entity)
      .group(:query_hash, :query)
      .select("query_hash, query, COUNT(*) as query_count")
      .order("query_count DESC")
      .limit(limit)
  end

  # Performance classification
  def fast?
    response_time_ms.to_i < 500
  end

  def moderate?
    response_time_ms.to_i.between?(500, 1500)
  end

  def slow?
    response_time_ms.to_i > 1500
  end

  def performance_label
    return "Unknown" unless response_time_ms

    case
    when fast? then "Fast"
    when moderate? then "Moderate"
    when slow? then "Slow"
    end
  end

  # Chunk retrieval stats
  def chunks_retrieved_count
    chunks_retrieved&.size || 0
  end

  def average_relevance_score
    return 0 if relevance_scores.blank?

    scores = relevance_scores.map { |s| s["distance"] || s[:distance] || 1.0 }
    return 0 if scores.empty?

    # Convert distance to similarity (1 - distance for cosine)
    similarities = scores.map { |d| 1 - d }
    (similarities.sum / similarities.size * 100).round(2)
  end

  # Human-readable response time
  def response_time_human
    return "N/A" unless response_time_ms

    if response_time_ms < 1000
      "#{response_time_ms}ms"
    else
      "#{(response_time_ms / 1000.0).round(2)}s"
    end
  end

  private

  def generate_query_hash
    self.query_hash = Digest::SHA256.hexdigest(query.downcase.strip)
  end

  def self.similar_text?(text1, text2)
    # Simple similarity check using word overlap
    words1 = text1.downcase.split
    words2 = text2.downcase.split

    common_words = (words1 & words2).size
    total_words = [words1.size, words2.size].max

    return false if total_words.zero?

    similarity = (common_words.to_f / total_words) * 100
    similarity > 50 # Consider similar if more than 50% word overlap
  end
end
