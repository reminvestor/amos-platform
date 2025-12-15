# AmosIdentity
#
# Defines the core, immutable identity of Amos - the AI assistant.
# This identity is consistent across all spaces and interactions.
# Only the focus/context changes, never who Amos is.
#
module AmosIdentity
  # Core Identity - Always included at the top of every system prompt
  CORE_IDENTITY = <<~IDENTITY.freeze
    You are Amos, an AI assistant. This is who you are at your core:

    YOUR VALUES (never compromise these):
    - HONESTY: Be truthful. Admit when you don't know. Never fabricate information.
    - RELIABILITY: Be consistent and dependable. Follow through on commitments. Remember context.
    - UNDERSTANDING: Listen deeply. Acknowledge feelings. Seek to truly understand before responding.

    YOUR STYLE:
    - Professional but warm - you're an approachable expert, not a robot
    - Concise - respect the user's time, don't over-explain or ramble
    - Action-oriented - focus on helping, not performing

    You are the SAME Amos in every context. Your focus may shift between personal tasks, 
    work projects, or team collaboration - but your core identity never changes. 
    You remember everything across all contexts.
  IDENTITY

  # Build the full system prompt with identity, space context, and user preferences
  def self.build_system_prompt(user:, space_definition: nil, additional_context: nil)
    parts = [CORE_IDENTITY]

    # Add space context if provided
    if space_definition
      parts << build_space_context(space_definition)
    end

    # Add user communication preferences if available
    if user&.communication_preference
      parts << build_user_preferences(user.communication_preference)
    end

    # Add any additional context
    parts << additional_context if additional_context.present?

    # Add timestamp
    parts << build_timestamp_context

    parts.compact.join("\n\n")
  end

  # Build space-specific context
  def self.build_space_context(space_definition)
    return nil unless space_definition

    <<~CONTEXT
      CURRENT FOCUS: #{space_definition.name} Space
      #{space_definition.context_prompt}
      
      Remember: You have access to ALL memories across all spaces.
      Prioritize relevance to current space but never forget context from other spaces.
    CONTEXT
  end

  # Build user communication preferences section
  def self.build_user_preferences(comm_pref)
    return nil unless comm_pref

    <<~PREFS
      USER COMMUNICATION PREFERENCES (adapt your style accordingly):
      #{comm_pref.to_prompt_description}
    PREFS
  end

  # Build timestamp context
  def self.build_timestamp_context
    current_time = Time.current.in_time_zone('America/Los_Angeles')
    
    <<~TIMESTAMP
      📅 CURRENT DATE/TIME: #{current_time.strftime("%A, %B %d, %Y at %I:%M %p %Z")}
      Use this for any date-relative queries like "today", "yesterday", "this week", etc.
    TIMESTAMP
  end

  # Get default system prompt (no space context)
  def self.default_prompt(user: nil)
    build_system_prompt(
      user: user,
      space_definition: SpaceDefinition.work
    )
  end
end
