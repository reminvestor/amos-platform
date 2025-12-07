# ScoutLearning - Scout's own learning and meta-knowledge
#
# This stores things Scout learns about how to do tasks better for a specific entity.
# It's Scout's memory of what works and what doesn't.
#
# Learning Types:
# - task_pattern: Patterns in how to handle specific tasks
# - tool_usage: Best ways to use specific tools
# - delegation: Which agents work best for which tasks
# - error_recovery: How to recover from specific errors
# - user_pattern: Patterns in how users work/communicate
#
class ScoutLearning < ApplicationRecord
  belongs_to :entity

  # Learning types
  LEARNING_TYPES = %w[task_pattern tool_usage delegation error_recovery user_pattern optimization].freeze
  
  # Sources of learning
  SOURCES = %w[conversation feedback observation correction success failure].freeze

  validates :learning_type, presence: true, inclusion: { in: LEARNING_TYPES }
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :learning, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }

  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :by_type, ->(type) { where(learning_type: type) }
  scope :by_context, ->(context) { where("context ILIKE ?", "%#{context}%") }
  scope :active, -> { where(active: true) }
  scope :high_confidence, -> { where("confidence >= ?", 0.7) }
  scope :effective, -> { where("success_rate >= ?", 0.6) }

  # Record a new learning
  def self.learn!(entity:, learning_type:, learning:, context: nil, example: nil, source: 'observation', confidence: 0.5)
    create!(
      entity: entity,
      learning_type: learning_type,
      learning: learning,
      context: context,
      example: example,
      source: source,
      confidence: confidence
    )
  end

  # Record when a learning was applied
  def record_application!(successful:)
    self.apply_count += 1
    self.success_count += 1 if successful
    self.success_rate = success_count.to_f / apply_count
    self.last_applied_at = Time.current
    
    # Increase confidence if successful, decrease if not
    adjustment = successful ? 0.05 : -0.1
    self.confidence = (confidence + adjustment).clamp(0.0, 1.0)
    
    save!
  end

  # Deactivate learning that doesn't work
  def deactivate!(reason: nil)
    update!(active: false)
    Rails.logger.info "Scout learning deactivated: #{learning.truncate(50)} - #{reason}"
  end

  # Get learnings formatted for system prompt
  def self.for_prompt(entity:, limit: 8)
    learnings = where(entity: entity)
                  .active
                  .high_confidence
                  .effective
                  .order(success_rate: :desc, apply_count: :desc)
                  .limit(limit)
    
    return nil if learnings.empty?
    
    formatted = learnings.map do |l|
      context_note = l.context.present? ? " (for #{l.context})" : ""
      "• #{l.learning}#{context_note}"
    end.join("\n")
    
    <<~LEARNINGS
      ═══════════════════════════════════════════════════════════════
      🧠 WHAT I'VE LEARNED (from experience with this business)
      ═══════════════════════════════════════════════════════════════
      
      #{formatted}
    LEARNINGS
  end

  # Find relevant learnings for a context
  def self.find_relevant(entity:, context:, limit: 5)
    where(entity: entity)
      .active
      .by_context(context)
      .order(success_rate: :desc)
      .limit(limit)
  end

  # Record a delegation that worked well
  def self.remember_good_delegation(entity:, agent_slug:, task_type:)
    learn!(
      entity: entity,
      learning_type: 'delegation',
      learning: "For #{task_type} tasks, delegate to #{agent_slug}",
      context: task_type,
      source: 'success',
      confidence: 0.7
    )
  end

  # Record a tool usage pattern that works well
  def self.remember_tool_pattern(entity:, tool_name:, pattern:, context: nil)
    learn!(
      entity: entity,
      learning_type: 'tool_usage',
      learning: "#{tool_name}: #{pattern}",
      context: context,
      source: 'observation',
      confidence: 0.6
    )
  end
end
