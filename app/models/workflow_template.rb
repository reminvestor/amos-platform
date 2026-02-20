class WorkflowTemplate < ApplicationRecord
  belongs_to :entity, optional: true

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :category, presence: true
  validates :template_spec, presence: true

  scope :active, -> { where(is_active: true) }
  scope :system, -> { where(is_system: true) }
  scope :by_category, ->(category) { where(category: category) }

  # Entity scoping: returns system templates (nil entity), entity-owned templates, and shared templates
  scope :for_entity, ->(entity_id) {
    where(entity_id: [nil, entity_id])
      .or(where(shared: true, is_system: true))
  }
  scope :custom, -> { where(is_system: false) }
  scope :shared_templates, -> { where(shared: true, is_system: false) }
  scope :by_industry, ->(industry) { where(industry: industry) }
  scope :tagged_with, ->(tag) { where("tags @> ?", [tag].to_json) }

  # Duplicate a system or shared template for a specific entity
  def duplicate_for_entity(entity)
    dup.tap do |copy|
      copy.entity = entity
      copy.is_system = false
      copy.shared = false
      copy.name = "#{name} (Custom)"
      copy.slug = "#{slug}-#{entity.id}-#{SecureRandom.hex(4)}"
      copy.save!
    end
  end

  # Class method to get all templates (DB + file-based)
  def self.all_templates
    # Get templates from database
    db_templates = all.to_a

    # Get templates from files
    file_templates = WorkflowTemplateLoader.load_all.map do |template_data|
      # Create in-memory WorkflowTemplate objects
      new(template_data)
    end

    # Combine and return
    db_templates + file_templates
  end

  # Override active scope to include file templates
  def self.active_with_files
    db_templates = active.to_a

    # Load V2 templates from files
    file_templates = WorkflowTemplateLoader.load_all_v2.map do |template_data|
      new(template_data) if template_data[:is_active] != false
    end.compact

    db_templates + file_templates
  end

  # Categories of workflow templates
  CATEGORIES = {
    analytics: "Data Analytics & Reporting",
    campaign_creation: "Campaign Creation & Management",
    data_import: "Data Import & Sync",
    customer_analysis: "Customer Analysis",
    content_generation: "Content Generation",
    maintenance: "System Maintenance"
  }.freeze

  # Generate a workflow instance from this template
  def generate_workflow(params = {})
    spec = deep_interpolate_template(template_spec, params)

    SimpleWorkflow.new(
      name: interpolate_string(name, params),
      description: interpolate_string(description, params),
      steps: build_steps_from_spec(spec["steps"] || []),
      metadata: spec["metadata"] || {}
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
        id: step_spec["id"] || "step_#{index + 1}",
        agent_role: step_spec["agent_role"],
        name: step_spec["name"],
        description: step_spec["description"],
        dependencies: step_spec["dependencies"] || [],
        tool_allowlist: step_spec["tool_allowlist"] || [],
        canvas_allowlist: step_spec["canvas_allowlist"] || [],
        data_scopes: step_spec["data_scopes"] || {},
        budgets: step_spec["budgets"] || {},
        confirmations: step_spec["confirmations"] || {},
        prompts: step_spec["prompts"] || {}
      )
    end
  end
end
