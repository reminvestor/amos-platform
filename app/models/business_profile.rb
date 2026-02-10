class BusinessProfile < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user, optional: true

  validates :name, presence: true
  validates :industry, presence: true
  validates :description, presence: true

  # Initialize empty knowledge base
  before_validation :initialize_knowledge_base, on: :create

  # When business name changes, sync to Entity so there's one authoritative name
  after_save :sync_entity_name, if: -> { saved_change_to_name? && name.present? }

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

  # Keep Entity.name in sync with the user-editable business name.
  # BusinessProfile.name is the authoritative, user-editable source.
  # Entity.name is set once during onboarding and otherwise not editable.
  def sync_entity_name
    target_entity = entity || user&.entity
    return unless target_entity

    # Also backfill entity_id if missing
    if entity_id.nil? && target_entity.id.present?
      update_column(:entity_id, target_entity.id)
    end

    if target_entity.name != name
      target_entity.update_column(:name, name)
      Rails.logger.info "🔄 Synced Entity##{target_entity.id} name to '#{name}' from BusinessProfile##{id}"
    end
  end
end
