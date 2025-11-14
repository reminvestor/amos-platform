# Model to store custom agent definitions
class CustomAgentDefinition < ApplicationRecord
  belongs_to :entity
  belongs_to :created_by, class_name: 'User'
  
  # Store the agent configuration
  validates :name, presence: true, uniqueness: { scope: :entity_id }
  validates :definition, presence: true
  validates :agent_type, presence: true
  
  # Status for agent definitions
  enum status: {
    draft: 0,
    active: 1,
    disabled: 2
  }
  
  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :by_type, ->(type) { where(agent_type: type) }
  
  # Agent types
  AGENT_TYPES = [
    'content_generator',
    'data_processor',
    'api_integration',
    'workflow_automation',
    'custom'
  ].freeze
  
  # Get the agent class
  def agent_class
    @agent_class ||= CustomAgentBuilder.new(definition).build
  end
  
  # Execute the agent
  def execute(task, context = {})
    job_id = SecureRandom.uuid
    
    # Build full context
    full_context = {
      entity_id: entity_id,
      user_id: created_by_id,
      custom_agent_id: id,
      **context
    }
    
    # Create job record
    job_record = Amos::JobRecord.create!(
      job_id: job_id,
      agent_type: "custom_#{agent_type}",
      status: 'pending',
      session_id: context[:session_id],
      input_data: {
        task: task,
        context: full_context,
        agent_definition_id: id
      }
    )
    
    # Enqueue the job
    agent_class.perform_later(
      job_id: job_id,
      task: task,
      context: full_context,
      callback_url: Rails.application.routes.url_helpers.amos_callback_url(
        session_id: context[:session_id],
        host: Rails.application.config.action_mailer.default_url_options[:host]
      )
    )
    
    job_record
  end
  
  # Validate the definition structure
  def validate_definition_structure
    required_fields = %w[name description workflow]
    missing = required_fields - definition.keys
    
    if missing.any?
      errors.add(:definition, "Missing required fields: #{missing.join(', ')}")
    end
    
    if definition['workflow'] && !definition['workflow'].is_a?(Hash)
      errors.add(:definition, "Workflow must be a hash")
    end
  end
  
  # Example agent templates
  def self.template_for(type)
    case type
    when 'content_generator'
      {
        name: "Content Generator",
        description: "Generates various types of content",
        capabilities: ["content_generation"],
        required_context: ["topic"],
        use_rag: true,
        interactive: true,
        max_questions: 3,
        fields: [
          {
            name: "content_type",
            question: "What type of content would you like to create?",
            required: true,
            examples: ["blog post", "social media", "email"]
          },
          {
            name: "topic",
            question: "What topic should I write about?",
            required: true
          },
          {
            name: "tone",
            question: "What tone should I use?",
            examples: ["professional", "casual", "humorous"]
          }
        ],
        workflow: {
          type: "llm_generation",
          model: "claude-haiku-4-5-20251001",
          template: "Create {{content_type}} about {{topic}} in a {{tone}} tone.",
          output_format: "text"
        }
      }
    when 'data_processor'
      {
        name: "Data Processor",
        description: "Processes and analyzes data",
        capabilities: ["data_analysis", "reporting"],
        required_context: ["data_source"],
        use_rag: false,
        interactive: true,
        fields: [
          {
            name: "data_source",
            question: "What data would you like to analyze?",
            required: true
          },
          {
            name: "analysis_type",
            question: "What type of analysis do you need?",
            examples: ["summary", "trends", "comparison"]
          }
        ],
        workflow: {
          type: "data_processing",
          data_sources: ["{{data_source}}"],
          transformations: [
            { type: "aggregate", method: "sum", field: "value" }
          ],
          output: {
            format: "report",
            template: "Data Analysis Report"
          }
        }
      }
    else
      {
        name: "Custom Agent",
        description: "A custom agent",
        workflow: {
          type: "llm_generation"
        }
      }
    end
  end
end
