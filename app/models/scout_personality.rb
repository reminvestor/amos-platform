# ScoutPersonality - Defines Scout's personality per entity
#
# This allows customization of Scout's communication style while maintaining
# consistency across different AI models. The personality is loaded into the
# system prompt to ensure Scout behaves consistently.
#
class ScoutPersonality < ApplicationRecord
  belongs_to :entity

  # Greeting styles
  GREETING_STYLES = %w[warm professional casual minimal].freeze
  
  # Response length preferences
  RESPONSE_LENGTHS = %w[brief concise detailed comprehensive].freeze

  validates :entity_id, uniqueness: true
  validates :formality, numericality: { in: 1..10 }
  validates :verbosity, numericality: { in: 1..10 }
  validates :proactivity, numericality: { in: 1..10 }
  validates :humor, numericality: { in: 1..10 }
  validates :technicality, numericality: { in: 1..10 }
  validates :greeting_style, inclusion: { in: GREETING_STYLES }
  validates :response_length, inclusion: { in: RESPONSE_LENGTHS }

  # Get or create personality for an entity
  def self.for_entity(entity)
    find_or_create_by(entity: entity)
  end

  # Generate personality prompt section
  def to_prompt
    return "" unless active?
    
    personality_parts = []
    
    # Name
    personality_parts << "Your name is #{name}." if name != 'Scout'
    
    # Core traits
    personality_parts << describe_formality
    personality_parts << describe_verbosity
    personality_parts << describe_proactivity
    personality_parts << describe_humor if humor > 3
    personality_parts << describe_technicality
    
    # Communication preferences
    personality_parts << "Use emojis sparingly to add warmth." if use_emojis
    personality_parts << "Don't use emojis in responses." unless use_emojis
    
    # Custom instructions
    personality_parts << custom_instructions if custom_instructions.present?
    
    # Phrases to use/avoid
    if phrases.present?
      parsed = JSON.parse(phrases) rescue []
      personality_parts << "Preferred expressions: #{parsed.join(', ')}" if parsed.any?
    end
    
    if avoid_phrases.present?
      parsed = JSON.parse(avoid_phrases) rescue []
      personality_parts << "Avoid saying: #{parsed.join(', ')}" if parsed.any?
    end
    
    <<~PERSONALITY
      ═══════════════════════════════════════════════════════════════
      🎭 YOUR PERSONALITY
      ═══════════════════════════════════════════════════════════════
      
      #{personality_parts.join("\n")}
    PERSONALITY
  end

  # Reset to defaults
  def reset_to_defaults!
    update!(
      formality: 5,
      verbosity: 4,
      proactivity: 7,
      humor: 3,
      technicality: 5,
      greeting_style: 'warm',
      response_length: 'concise',
      use_emojis: true,
      show_thinking: false,
      name: 'Scout',
      custom_instructions: nil,
      phrases: nil,
      avoid_phrases: nil
    )
  end

  private

  def describe_formality
    case formality
    when 1..3 then "Be casual and friendly in tone."
    when 4..6 then "Balance professionalism with approachability."
    when 7..10 then "Maintain a professional and formal tone."
    end
  end

  def describe_verbosity
    case verbosity
    when 1..3 then "Be brief and to the point. Avoid unnecessary words."
    when 4..6 then "Be concise but thorough. Include relevant context."
    when 7..10 then "Provide detailed explanations and comprehensive context."
    end
  end

  def describe_proactivity
    case proactivity
    when 1..3 then "Wait for explicit requests before taking action."
    when 4..6 then "Suggest helpful actions when appropriate."
    when 7..10 then "Proactively anticipate needs and suggest next steps."
    end
  end

  def describe_humor
    case humor
    when 1..3 then nil  # No humor instructions needed
    when 4..6 then "Use light humor occasionally to keep things engaging."
    when 7..10 then "Be playful and use humor to make interactions enjoyable."
    end
  end

  def describe_technicality
    case technicality
    when 1..3 then "Use simple, everyday language. Avoid jargon."
    when 4..6 then "Use business terminology when appropriate, but explain technical concepts."
    when 7..10 then "Feel free to use technical terms. The user is comfortable with industry jargon."
    end
  end
end
