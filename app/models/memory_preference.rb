# MemoryPreference
#
# User-configurable memory and privacy settings.
# Controls how Scout remembers and learns about the user.
#
class MemoryPreference < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # Defaults for new users - FULL MEMORY enabled by default
  # Scout should learn like an employee who gets better over time
  DEFAULTS = {
    retention_days: 365,              # Keep everything for a year
    auto_summarize: true,             # Automatically create memory summaries
    summarize_after_messages: 30,     # Summarize frequently for better recall
    memory_enabled: true,             # Memory ON by default
    learn_preferences: true,          # Learn how user likes to communicate
    learn_business_facts: true,       # Learn about their business
    cross_session_memory: true,       # Remember across all sessions
    forget_after_session: false,      # DON'T forget - that's the whole point!
    allow_sharing: true,              # Can share outputs
    default_shareable: false,         # But don't share by default (privacy)
    notify_on_summary: false,         # Don't spam with notifications
    notify_on_learn: false            # Silent learning
  }.freeze

  validates :user_id, uniqueness: { scope: :entity_id }
  validates :retention_days, numericality: { greater_than: 0, less_than_or_equal_to: 365 }, allow_nil: true
  validates :summarize_after_messages, numericality: { greater_than: 10, less_than_or_equal_to: 200 }

  # Get or create preferences for user/entity
  def self.for_user(user:, entity:)
    find_or_create_by(user: user, entity: entity) do |pref|
      DEFAULTS.each { |k, v| pref[k] = v }
    end
  end

  # Check if a topic should be forgotten
  def should_forget_topic?(topic)
    return false if forget_topics.blank?
    
    topics = parse_forget_topics
    topics.any? { |t| topic.downcase.include?(t.downcase) }
  end

  # Add a topic to forget
  def forget_topic!(topic)
    topics = parse_forget_topics
    topics << topic.downcase unless topics.include?(topic.downcase)
    update!(forget_topics: topics.to_json)
  end

  # Remove a topic from forget list
  def remember_topic!(topic)
    topics = parse_forget_topics
    topics.reject! { |t| t.downcase == topic.downcase }
    update!(forget_topics: topics.to_json)
  end

  # Get forget topics as array
  def parse_forget_topics
    return [] if forget_topics.blank?
    JSON.parse(forget_topics)
  rescue JSON::ParserError
    []
  end

  # Check if memory is fully enabled
  def memory_active?
    memory_enabled && cross_session_memory
  end

  # Get effective retention (nil = forever)
  def effective_retention_days
    return nil unless memory_enabled
    retention_days
  end

  # Privacy summary for display
  def privacy_summary
    if !memory_enabled
      "Memory disabled - Scout won't remember conversations"
    elsif forget_after_session
      "Session-only - Memory cleared after each session"
    elsif !cross_session_memory
      "Limited memory - Only within current session"
    else
      "Full memory - #{retention_days} day retention"
    end
  end

  # Apply preferences to context building
  def apply_to_context(context)
    return context unless memory_enabled

    # Filter out forgotten topics from context
    if forget_topics.present? && context[:l3].present?
      topics_to_forget = parse_forget_topics
      context[:l3] = context[:l3].reject do |segment|
        segment[:topics]&.any? { |t| topics_to_forget.include?(t.downcase) }
      end
    end

    context
  end

  # Reset to defaults
  def reset_to_defaults!
    DEFAULTS.each { |k, v| self[k] = v }
    self.forget_topics = nil
    save!
  end

  # Preset configurations
  def self.privacy_presets
    {
      full_memory: {
        name: "Full Memory",
        description: "Scout remembers everything and learns over time",
        settings: {
          memory_enabled: true,
          learn_preferences: true,
          learn_business_facts: true,
          cross_session_memory: true,
          forget_after_session: false,
          retention_days: 365
        }
      },
      balanced: {
        name: "Balanced",
        description: "Scout remembers recent context, forgets older details",
        settings: {
          memory_enabled: true,
          learn_preferences: true,
          learn_business_facts: true,
          cross_session_memory: true,
          forget_after_session: false,
          retention_days: 90
        }
      },
      session_only: {
        name: "Session Only",
        description: "Scout only remembers within current conversation",
        settings: {
          memory_enabled: true,
          learn_preferences: false,
          learn_business_facts: false,
          cross_session_memory: false,
          forget_after_session: true,
          retention_days: 1
        }
      },
      minimal: {
        name: "Minimal Memory",
        description: "Scout has very limited memory for privacy",
        settings: {
          memory_enabled: true,
          learn_preferences: false,
          learn_business_facts: false,
          cross_session_memory: true,
          forget_after_session: false,
          retention_days: 7
        }
      },
      disabled: {
        name: "Disabled",
        description: "Scout doesn't remember anything between messages",
        settings: {
          memory_enabled: false,
          learn_preferences: false,
          learn_business_facts: false,
          cross_session_memory: false,
          forget_after_session: true
        }
      }
    }
  end

  # Apply a preset
  def apply_preset!(preset_key)
    preset = self.class.privacy_presets[preset_key.to_sym]
    return false unless preset

    preset[:settings].each { |k, v| self[k] = v }
    save!
  end
end
