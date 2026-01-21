# frozen_string_literal: true

# Tracks interactive module design conversations between users and the Platform Factory
# Enables iterative refinement of module schemas before building
class ModuleDesignSession < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :app_module, optional: true
  
  # Validations
  validates :status, presence: true, inclusion: { 
    in: %w[gathering_requirements proposing_schema awaiting_feedback refining building completed cancelled] 
  }
  validates :module_name, presence: true, on: :update
  
  # Scopes
  scope :active, -> { where(status: %w[gathering_requirements proposing_schema awaiting_feedback refining]) }
  scope :completed, -> { where(status: 'completed') }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  
  # State machine methods
  def gathering_requirements?
    status == 'gathering_requirements'
  end
  
  def proposing_schema?
    status == 'proposing_schema'
  end
  
  def awaiting_feedback?
    status == 'awaiting_feedback'
  end
  
  def refining?
    status == 'refining'
  end
  
  def building?
    status == 'building'
  end
  
  def completed?
    status == 'completed'
  end
  
  def cancelled?
    status == 'cancelled'
  end
  
  # Transition methods
  def propose_schema!(schema)
    self.proposed_schema = schema
    self.status = 'awaiting_feedback'
    self.iteration_count += 1
    save!
  end
  
  def receive_feedback!(feedback)
    self.user_feedback << {
      iteration: iteration_count,
      feedback: feedback,
      timestamp: Time.current.iso8601
    }
    self.status = 'refining'
    save!
  end
  
  def approve_schema!
    self.final_schema = proposed_schema
    self.status = 'building'
    save!
  end
  
  def complete!(app_module)
    self.app_module = app_module
    self.status = 'completed'
    self.completed_at = Time.current
    save!
  end
  
  def cancel!
    self.status = 'cancelled'
    save!
  end
  
  # Schema helpers
  def has_proposed_schema?
    proposed_schema.present? && proposed_schema['fields'].present?
  end
  
  def field_count
    proposed_schema.dig('fields')&.count || 0
  end
  
  def add_field_to_proposal(field)
    self.proposed_schema['fields'] ||= []
    self.proposed_schema['fields'] << field
    save!
  end
  
  def remove_field_from_proposal(field_name)
    return unless proposed_schema['fields']
    self.proposed_schema['fields'].reject! { |f| f['name'] == field_name }
    save!
  end
  
  def modify_field_in_proposal(field_name, updates)
    return unless proposed_schema['fields']
    field = proposed_schema['fields'].find { |f| f['name'] == field_name }
    field&.merge!(updates)
    save!
  end
  
  # Context for AI conversations
  def conversation_summary
    {
      session_id: id,
      module_name: module_name,
      status: status,
      user_description: user_description,
      iteration_count: iteration_count,
      proposed_schema: proposed_schema,
      feedback_history: user_feedback,
      field_count: field_count
    }
  end
  
  # Generate clarifying questions based on description
  def suggested_questions
    questions = []
    
    # Basic questions if we're just starting
    if gathering_requirements?
      questions << "What are the main entities or things you want to track?"
      questions << "What information do you need to store for each item?"
      questions << "Do you need to connect this to existing data like Contacts or Campaigns?"
      questions << "What actions would you like to perform on this data?"
    end
    
    # Refinement questions after initial proposal
    if awaiting_feedback? || refining?
      questions << "Are there any fields missing that you need?"
      questions << "Should any fields be required vs optional?"
      questions << "Do you need any calculated fields or formulas?"
      questions << "What views or reports would be most useful?"
    end
    
    questions
  end
end





