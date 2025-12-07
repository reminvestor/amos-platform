# UserMemory - Cross-session learning about users
#
# Stores learned facts, preferences, and patterns about users that persist
# across sessions. This enables Scout to remember and personalize interactions.
#
# Memory Types:
# - preference: User preferences (e.g., "prefers brief responses")
# - fact: Learned facts about the user/business (e.g., "company has 50 employees")
# - decision: Important decisions made (e.g., "chose Stripe over PayPal")
# - goal: User's stated goals (e.g., "wants to increase email open rates")
# - pattern: Observed patterns (e.g., "usually asks about campaigns on Mondays")
#
class UserMemory < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # Memory types
  MEMORY_TYPES = %w[preference fact decision goal pattern].freeze
  
  # Categories for organization
  CATEGORIES = %w[communication workflow business personal product].freeze
  
  # Sources of memory
  SOURCES = %w[conversation explicit inferred observation feedback].freeze

  validates :memory_type, presence: true, inclusion: { in: MEMORY_TYPES }
  validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }, allow_nil: true
  validates :content, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }

  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_user, ->(user) { where(user: user) }
  scope :by_type, ->(type) { where(memory_type: type) }
  scope :by_category, ->(category) { where(category: category) }
  scope :high_confidence, -> { where("confidence >= ?", 0.7) }
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :preferences, -> { by_type('preference') }
  scope :facts, -> { by_type('fact') }
  scope :goals, -> { by_type('goal') }

  # Get or create a preference by key
  def self.set_preference(user:, entity:, key:, content:, source: 'conversation', confidence: 0.8)
    memory = find_or_initialize_by(user: user, entity: entity, key: key, memory_type: 'preference')
    memory.update!(
      content: content,
      source: source,
      confidence: confidence,
      category: 'communication'
    )
    memory
  end

  # Get a preference by key
  def self.get_preference(user:, entity:, key:)
    find_by(user: user, entity: entity, key: key, memory_type: 'preference')&.tap do |m|
      m.record_access! if m
    end
  end

  # Store a fact
  def self.remember_fact(user:, entity:, content:, category: 'business', source: 'conversation', confidence: 0.8)
    create!(
      user: user,
      entity: entity,
      memory_type: 'fact',
      category: category,
      content: content,
      source: source,
      confidence: confidence
    )
  end

  # Store a goal
  def self.remember_goal(user:, entity:, content:, source: 'conversation', confidence: 0.8)
    create!(
      user: user,
      entity: entity,
      memory_type: 'goal',
      category: 'business',
      content: content,
      source: source,
      confidence: confidence
    )
  end

  # Get formatted memories for system prompt
  def self.for_prompt(user:, entity:, limit: 10)
    memories = where(user: user, entity: entity)
                .active
                .high_confidence
                .order(access_count: :desc, created_at: :desc)
                .limit(limit)
    
    return nil if memories.empty?
    
    grouped = memories.group_by(&:memory_type)
    
    parts = []
    
    if grouped['preference']&.any?
      prefs = grouped['preference'].map { |m| "• #{m.content}" }.join("\n")
      parts << "PREFERENCES:\n#{prefs}"
    end
    
    if grouped['goal']&.any?
      goals = grouped['goal'].map { |m| "• #{m.content}" }.join("\n")
      parts << "GOALS:\n#{goals}"
    end
    
    if grouped['fact']&.any?
      facts = grouped['fact'].first(5).map { |m| "• #{m.content}" }.join("\n")
      parts << "KNOWN FACTS:\n#{facts}"
    end
    
    parts.join("\n\n")
  end

  # Record an access
  def record_access!
    update_columns(
      access_count: access_count + 1,
      last_accessed_at: Time.current
    )
  end

  # Check if expired
  def expired?
    expires_at.present? && expires_at < Time.current
  end
end
