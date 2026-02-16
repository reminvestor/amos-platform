# frozen_string_literal: true

# AmosWorkingMemory - Persistent thought continuity for AMOS
#
# This is not conversation history or log data. This is AMOS's own internal
# "train of thought" — observations, hypotheses, concerns, and curiosities
# that persist across thinking sessions.
#
# Think of it as a researcher's notebook: ideas that get revisited,
# refined, connected, and eventually acted on or archived.
#
# Thought lifecycle:
#   1. AMOS observes something interesting → creates thought (salience: 0.5)
#   2. Next session, AMOS revisits → updates salience based on new evidence
#   3. Thought gains evidence/connections → salience increases
#   4. AMOS acts on it (creates bounty, evolves skill, etc.) → marked resolved
#   5. Thoughts that go stale (not revisited, no evidence) → salience decays → archived
#
class AmosWorkingMemory < ApplicationRecord
  belongs_to :entity
  belongs_to :parent_thought, class_name: 'AmosWorkingMemory', optional: true
  has_many :child_thoughts, class_name: 'AmosWorkingMemory', foreign_key: :parent_thought_id, dependent: :nullify

  # Thought types - what kind of thinking is this?
  THOUGHT_TYPES = %w[
    observation     # Something AMOS noticed in the data
    hypothesis      # A theory about why something is happening
    concern         # Something that might be going wrong
    curiosity       # Something AMOS wants to investigate further
    goal            # Something AMOS wants to achieve
    insight         # A conclusion drawn from multiple observations
    question        # Something AMOS needs more data to answer
    plan            # A concrete plan of action
  ].freeze

  STATUSES = %w[active resolved archived superseded].freeze

  validates :thought_type, inclusion: { in: THOUGHT_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :topic, presence: true
  validates :content, presence: true
  validates :salience, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :by_salience, -> { order(salience: :desc) }
  scope :by_type, ->(type) { where(thought_type: type) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :stale, -> { active.where('last_revisited_at < ? OR (last_revisited_at IS NULL AND created_at < ?)', 7.days.ago, 7.days.ago) }
  scope :high_salience, -> { where('salience >= ?', 0.7) }
  scope :unresolved_concerns, -> { active.where(thought_type: 'concern').by_salience }

  before_create :set_first_thought_at

  # ═══════════════════════════════════════════════════════════════════════════
  # THOUGHT OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  # AMOS revisits this thought with new information
  def revisit!(new_evidence: nil, updated_content: nil, salience_delta: 0)
    attrs = {
      times_revisited: times_revisited + 1,
      last_revisited_at: Time.current,
      salience: [(salience + salience_delta).round(3), 1.0].min
    }

    attrs[:content] = updated_content if updated_content.present?

    if new_evidence.present?
      attrs[:evidence] = (evidence || []) + [
        { added_at: Time.current.iso8601, data: new_evidence }
      ]
    end

    update!(attrs)
  end

  # AMOS acted on this thought
  def record_action!(action_type:, description:, result: nil)
    action = {
      type: action_type,
      description: description,
      result: result,
      taken_at: Time.current.iso8601
    }

    update!(
      actions_taken: (actions_taken || []) + [action],
      last_revisited_at: Time.current
    )
  end

  # Mark as resolved (thought has been fully addressed)
  def resolve!(resolution: nil)
    record_action!(action_type: 'resolved', description: resolution) if resolution
    update!(status: 'resolved', resolved_at: Time.current)
  end

  # Mark as superseded by a newer thought
  def supersede!(new_thought)
    update!(
      status: 'superseded',
      metadata: (metadata || {}).merge('superseded_by' => new_thought.id)
    )
  end

  # Connect this thought to another
  def connect_to!(other_thought)
    return if related_thought_ids.include?(other_thought.id)

    update!(related_thought_ids: related_thought_ids + [other_thought.id])
    other_thought.update!(related_thought_ids: other_thought.related_thought_ids + [id]) unless other_thought.related_thought_ids.include?(id)
  end

  # Spawn a child thought (one thought leading to another)
  def spawn!(thought_type:, topic:, content:, salience: nil)
    child = self.class.create!(
      entity: entity,
      parent_thought: self,
      thought_type: thought_type,
      topic: topic,
      content: content,
      salience: salience || self.salience * 0.8,
      confidence: 0.3 # New thoughts start uncertain
    )

    connect_to!(child)
    child
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SALIENCE MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  # Natural decay - thoughts that aren't reinforced fade
  def self.apply_salience_decay!(entity)
    active.where(entity: entity).find_each do |thought|
      days_since_touch = if thought.last_revisited_at
        (Time.current - thought.last_revisited_at) / 1.day
      else
        (Time.current - thought.created_at) / 1.day
      end

      # Decay rate: lose ~10% salience per day of not being revisited
      # But thoughts with lots of evidence decay slower
      evidence_count = thought.evidence&.count || 0
      decay_rate = 0.1 / (1 + evidence_count * 0.2)  # More evidence = slower decay
      new_salience = [thought.salience * (1 - decay_rate * [days_since_touch, 1].max), 0.01].max

      if new_salience < 0.05
        thought.update!(status: 'archived', salience: 0)
      else
        thought.update!(salience: new_salience.round(3))
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # QUERY HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  # Get the "top of mind" thoughts for AMOS (what should it think about?)
  def self.top_of_mind(entity, limit: 10)
    active
      .where(entity: entity)
      .by_salience
      .limit(limit)
  end

  # Get related thoughts as a graph
  def thought_network
    ids = [id] + (related_thought_ids || [])
    ids += child_thoughts.pluck(:id)
    ids << parent_thought_id if parent_thought_id

    self.class.where(id: ids.compact.uniq)
  end

  # Summary for LLM context
  def to_context_summary
    age = ((Time.current - created_at) / 1.day).round(1)
    revisits = times_revisited

    "#{thought_type.upcase}: #{topic} (salience: #{salience}, confidence: #{confidence}, " \
      "age: #{age}d, revisited: #{revisits}x)\n#{content}"
  end

  private

  def set_first_thought_at
    self.first_thought_at ||= Time.current
  end
end
