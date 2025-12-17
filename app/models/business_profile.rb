class BusinessProfile < ApplicationRecord
  belongs_to :entity
  belongs_to :user, optional: true

  validates :name, presence: true
  validates :industry, presence: true
  validates :description, presence: true

  # Initialize empty knowledge base
  before_validation :initialize_knowledge_base, on: :create

  # Serialized jsonb field
  def knowledge_base_data
    self.knowledge_base || {}
  end

  # Add a new section to the knowledge base
  def add_knowledge_section(section_name, content)
    self.knowledge_base = knowledge_base_data.merge({
      section_name => content
    })
    save
  end

  # Get formatted context for LLM
  def llm_context
    context = {
      business: {
        name: name,
        industry: industry,
        description: description,
        founded_year: founded_year,
        website: website,
        values: values,
        target_audience: target_audience,
        tone_of_voice: tone_of_voice
      },
      knowledge_base: knowledge_base_data
    }

    context.to_json
  end

  private

  def initialize_knowledge_base
    self.knowledge_base ||= {}
  end
end
