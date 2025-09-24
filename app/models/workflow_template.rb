class WorkflowTemplate < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :category, presence: true
  validates :template_spec, presence: true
  
  scope :active, -> { where(is_active: true) }
  scope :system, -> { where(is_system: true) }
  scope :by_category, ->(category) { where(category: category) }
  
  # Categories of workflow templates
  CATEGORIES = {
    analytics: 'Data Analytics & Reporting',
    campaign_creation: 'Campaign Creation & Management',
    data_import: 'Data Import & Sync',
    customer_analysis: 'Customer Analysis',
    content_generation: 'Content Generation',
    maintenance: 'System Maintenance'
  }.freeze
  
  # Generate a workflow instance from this template
  def generate_workflow(params = {})
    spec = deep_interpolate_template(template_spec, params)
    
    SimpleWorkflow.new(
      name: interpolate_string(name, params),
      description: interpolate_string(description, params),
      steps: build_steps_from_spec(spec['steps'] || []),
      metadata: spec['metadata'] || {}
    )
  end
  
  private
  
  def deep_interpolate_template(template, params)
    case template
    when Hash
      template.transform_values { |v| deep_interpolate_template(v, params) }
    when Array
      template.map { |v| deep_interpolate_template(v, params) }
    when String
      interpolate_string(template, params)
    else
      template
    end
  end
  
  def interpolate_string(str, params)
    return str unless str.is_a?(String)
    
    str.gsub(/\{\{(\w+)\}\}/) do |match|
      key = $1.to_sym
      params[key] || match
    end
  end
  
  def build_steps_from_spec(steps_spec)
    steps_spec.map.with_index do |step_spec, index|
      Step.new(
        id: step_spec['id'] || "step_#{index + 1}",
        agent_role: step_spec['agent_role'],
        name: step_spec['name'],
        description: step_spec['description'],
        dependencies: step_spec['dependencies'] || [],
        tool_allowlist: step_spec['tool_allowlist'] || [],
        canvas_allowlist: step_spec['canvas_allowlist'] || [],
        data_scopes: step_spec['data_scopes'] || {},
        budgets: step_spec['budgets'] || {},
        confirmations: step_spec['confirmations'] || {},
        prompts: step_spec['prompts'] || {}
      )
    end
  end
end
