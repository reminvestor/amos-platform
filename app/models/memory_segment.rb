# MemorySegment
#
# Stores summarized conversation segments for L3 memory layer.
# These are created automatically by the memory system when conversations
# exceed certain thresholds.
#
# Types:
# - daily: End-of-day summary
# - weekly: Weekly rollup
# - topic: Topic-specific summary
# - milestone: User-marked important points
#
class MemorySegment < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  SEGMENT_TYPES = %w[daily weekly topic milestone].freeze

  validates :segment_type, presence: true, inclusion: { in: SEGMENT_TYPES }
  validates :summary, presence: true

  scope :active, -> { where(active: true) }
  scope :for_user_entity, ->(user, entity) { where(user: user, entity: entity) }
  scope :by_recency, -> { order(period_end: :desc) }
  scope :daily, -> { where(segment_type: 'daily') }
  scope :weekly, -> { where(segment_type: 'weekly') }
  scope :topics, -> { where(segment_type: 'topic') }

  # Apply relevance decay (called periodically)
  def self.apply_decay!
    # Reduce relevance of older segments
    where("period_end < ?", 7.days.ago).update_all("relevance_decay = relevance_decay * 0.9")
    where("period_end < ?", 30.days.ago).update_all("relevance_decay = relevance_decay * 0.8")
  end

  # Mark as retrieved (for tracking usefulness)
  def mark_retrieved!
    increment!(:retrieval_count)
    update!(last_retrieved_at: Time.current)
  end

  # Parse JSON helper methods
  def topics_array
    parse_json(key_topics)
  end

  def decisions_array
    parse_json(key_decisions)
  end

  def action_items_array
    parse_json(action_items)
  end

  # Format for display
  def to_summary_hash
    {
      id: id,
      type: segment_type,
      period: period_label,
      summary: summary,
      topics: topics_array,
      decisions: decisions_array,
      action_items: action_items_array,
      relevance: relevance_decay
    }
  end

  def period_label
    if period_start && period_end
      if period_start.to_date == period_end.to_date
        period_start.strftime('%B %d, %Y')
      else
        "#{period_start.strftime('%b %d')} - #{period_end.strftime('%b %d, %Y')}"
      end
    else
      created_at.strftime('%B %d, %Y')
    end
  end

  private

  def parse_json(json_string)
    return [] if json_string.blank?
    JSON.parse(json_string)
  rescue JSON::ParserError
    []
  end
end
