# UserCommunicationPreference
#
# Tracks learned communication preferences for adapting Amos's style to each user.
# These preferences are learned over time based on user interactions.
#
class UserCommunicationPreference < ApplicationRecord
  belongs_to :user

  # Validations
  validates :user_id, uniqueness: true
  validates :formality_level, inclusion: { in: 1..5 }
  validates :verbosity_level, inclusion: { in: 1..5 }
  validates :proactivity_level, inclusion: { in: 1..5 }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Get preference description for system prompt
  def to_prompt_description
    parts = []

    # Formality
    formality_desc = case formality_level
    when 1..2 then "casual and relaxed"
    when 3 then "balanced"
    when 4..5 then "formal and professional"
    end
    parts << "Communication style: #{formality_desc}"

    # Verbosity
    verbosity_desc = case verbosity_level
    when 1..2 then "Keep responses brief and to the point"
    when 3 then "Provide moderate detail"
    when 4..5 then "Provide thorough, detailed explanations"
    end
    parts << verbosity_desc

    # Humor
    parts << "Light humor is welcome" if humor_enabled

    # Proactivity
    proactivity_desc = case proactivity_level
    when 1..2 then "Wait for explicit requests before suggesting"
    when 3 then "Occasionally suggest next steps"
    when 4..5 then "Proactively suggest improvements and next steps"
    end
    parts << proactivity_desc

    parts.join(". ")
  end

  # Learn from interaction (called after conversations)
  def learn_from_interaction(feedback_data)
    patterns = learned_patterns || {}
    
    # Track feedback patterns
    patterns['interactions'] ||= 0
    patterns['interactions'] += 1
    
    # Store specific feedback if provided
    if feedback_data[:too_verbose]
      self.verbosity_level = [verbosity_level - 1, 1].max
    elsif feedback_data[:too_brief]
      self.verbosity_level = [verbosity_level + 1, 5].min
    end

    if feedback_data[:too_formal]
      self.formality_level = [formality_level - 1, 1].max
    elsif feedback_data[:too_casual]
      self.formality_level = [formality_level + 1, 5].min
    end

    self.learned_patterns = patterns
    self.last_learning_update = Time.current
    save
  end

  # Class method to get or create preferences for a user
  def self.for_user(user)
    find_or_create_by(user: user)
  end

  private

  def set_defaults
    self.formality_level ||= 3
    self.verbosity_level ||= 2  # Default to concise
    self.humor_enabled ||= false
    self.proactivity_level ||= 3
    self.learned_patterns ||= {}
  end
end
