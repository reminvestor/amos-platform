# frozen_string_literal: true

# ApplicationPlan represents a complete plan for building an application
# within the AMOS ecosystem. It captures the full specification including
# modules, website, agent, tools, integrations, workflows, and scheduled tasks.
#
# The planning flow:
# 1. User describes what they want
# 2. Planner Agent creates plan (status: drafting)
# 3. User reviews plan (status: pending_approval)
# 4. User refines plan (back to drafting, or stays pending_approval)
# 5. User approves (status: approved)
# 6. Build starts (status: building)
# 7. Complete (status: completed) or fail (status: failed)
#
class ApplicationPlan < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :created_by, class_name: 'User'
  
  # Built components (populated after build completes)
  has_many :app_modules, dependent: :nullify
  has_one :website, dependent: :nullify
  has_one :web_app, dependent: :nullify
  has_one :agent_plugin, dependent: :nullify
  
  # Status values
  STATUSES = %w[drafting pending_approval approved building completed failed cancelled].freeze
  ARCHETYPES = %w[knowledge_base crm sales_pipeline inventory project_mgmt social_media custom].freeze
  
  # Validations
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :archetype, inclusion: { in: ARCHETYPES }, allow_nil: true
  validate :plan_spec_structure
  
  # Scopes
  scope :active, -> { where(status: %w[drafting pending_approval approved building]) }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :for_user, ->(user_id) { where(created_by_id: user_id) }
  scope :recent, -> { order(created_at: :desc) }
  
  # ============================================
  # STATUS HELPERS
  # ============================================
  
  def drafting?
    status == 'drafting'
  end
  
  def pending_approval?
    status == 'pending_approval'
  end
  
  def approved?
    status == 'approved'
  end
  
  def building?
    status == 'building'
  end
  
  def completed?
    status == 'completed'
  end
  
  def failed?
    status == 'failed'
  end
  
  def cancelled?
    status == 'cancelled'
  end
  
  def editable?
    drafting? || pending_approval?
  end
  
  # ============================================
  # STATE TRANSITIONS
  # ============================================
  
  def submit_for_approval!
    raise InvalidTransition, "Cannot submit from #{status}" unless drafting?
    update!(status: 'pending_approval')
  end
  
  def request_changes!(feedback)
    raise InvalidTransition, "Cannot request changes from #{status}" unless pending_approval?
    
    self.refinement_history << {
      iteration: refinement_history.length + 1,
      feedback: feedback,
      timestamp: Time.current.iso8601,
      type: 'user_feedback'
    }
    self.status = 'drafting'
    save!
  end
  
  def approve!
    raise InvalidTransition, "Cannot approve from #{status}" unless pending_approval?
    update!(status: 'approved', approved_at: Time.current)
  end
  
  def start_build!
    raise InvalidTransition, "Cannot start build from #{status}" unless approved?
    update!(status: 'building', build_started_at: Time.current)
  end
  
  def complete!(results)
    raise InvalidTransition, "Cannot complete from #{status}" unless building?
    update!(
      status: 'completed',
      build_results: results,
      completed_at: Time.current
    )
  end
  
  def fail!(error_message, log_entry = nil)
    self.error_message = error_message
    self.build_log << log_entry if log_entry
    self.status = 'failed'
    save!
  end
  
  def cancel!
    raise InvalidTransition, "Cannot cancel from #{status}" if completed? || failed?
    update!(status: 'cancelled')
  end
  
  def add_build_log(message, level: :info)
    self.build_log << {
      timestamp: Time.current.iso8601,
      level: level.to_s,
      message: message
    }
    save!
  end
  
  # ============================================
  # PLAN SPEC ACCESSORS
  # ============================================
  
  def modules_spec
    plan_spec['modules'] || []
  end
  
  def website_spec
    plan_spec['website']
  end
  
  def agent_spec
    plan_spec['agent']
  end
  
  def tools_spec
    plan_spec['tools'] || []
  end
  
  def integrations_spec
    plan_spec['integrations'] || []
  end
  
  def workflows_spec
    plan_spec['workflows'] || []
  end
  
  def scheduled_tasks_spec
    plan_spec['scheduled_tasks'] || []
  end
  
  def has_website?
    website_spec.present?
  end
  
  def has_agent?
    agent_spec.present?
  end
  
  # ============================================
  # PLAN SPEC MUTATORS
  # ============================================
  
  def update_plan_spec!(updates)
    raise InvalidTransition, "Cannot update plan in #{status} state" unless editable?
    
    self.plan_spec = plan_spec.deep_merge(updates.deep_stringify_keys)
    save!
  end
  
  def add_module!(module_spec)
    raise InvalidTransition, "Cannot update plan in #{status} state" unless editable?
    
    modules = plan_spec['modules'] || []
    modules << module_spec.deep_stringify_keys
    update!(plan_spec: plan_spec.merge('modules' => modules))
  end
  
  def add_integration!(integration_spec)
    raise InvalidTransition, "Cannot update plan in #{status} state" unless editable?
    
    integrations = plan_spec['integrations'] || []
    integrations << integration_spec.deep_stringify_keys
    update!(plan_spec: plan_spec.merge('integrations' => integrations))
  end
  
  def add_workflow!(workflow_spec)
    raise InvalidTransition, "Cannot update plan in #{status} state" unless editable?
    
    workflows = plan_spec['workflows'] || []
    workflows << workflow_spec.deep_stringify_keys
    update!(plan_spec: plan_spec.merge('workflows' => workflows))
  end
  
  def add_scheduled_task!(task_spec)
    raise InvalidTransition, "Cannot update plan in #{status} state" unless editable?
    
    tasks = plan_spec['scheduled_tasks'] || []
    tasks << task_spec.deep_stringify_keys
    update!(plan_spec: plan_spec.merge('scheduled_tasks' => tasks))
  end
  
  # ============================================
  # SUMMARY & DISPLAY
  # ============================================
  
  def component_summary
    {
      modules: modules_spec.count,
      website_pages: website_spec&.dig('pages')&.count || 0,
      has_agent: has_agent?,
      tools: tools_spec.count,
      integrations: integrations_spec.count,
      workflows: workflows_spec.count,
      scheduled_tasks: scheduled_tasks_spec.count
    }
  end
  
  def estimated_build_time
    # Rough estimate based on components
    base = 30 # seconds
    base += modules_spec.count * 10
    base += (website_spec&.dig('pages')&.count || 0) * 5
    base += 15 if has_agent?
    base += tools_spec.count * 2
    base += integrations_spec.count * 3
    base += workflows_spec.count * 3
    base += scheduled_tasks_spec.count * 2
    
    if base < 60
      "#{base} seconds"
    else
      "#{(base / 60.0).ceil} minutes"
    end
  end
  
  def to_preview
    {
      id: id,
      name: name,
      description: description,
      archetype: archetype,
      status: status,
      summary: component_summary,
      estimated_time: estimated_build_time,
      plan_spec: plan_spec,
      created_at: created_at&.iso8601,
      approved_at: approved_at&.iso8601,
      completed_at: completed_at&.iso8601
    }
  end
  
  # ============================================
  # EXCEPTIONS
  # ============================================
  
  class InvalidTransition < StandardError; end
  
  private
  
  def plan_spec_structure
    return if plan_spec.blank?
    
    # Validate modules have required fields
    if plan_spec['modules'].is_a?(Array)
      plan_spec['modules'].each_with_index do |mod, i|
        unless mod['name'].present?
          errors.add(:plan_spec, "modules[#{i}] must have a name")
        end
      end
    end
    
    # Validate website has pages if present
    if plan_spec['website'].present? && plan_spec['website']['pages'].blank?
      errors.add(:plan_spec, "website must have pages defined")
    end
    
    # Validate agent has name if present
    if plan_spec['agent'].present? && plan_spec['agent']['name'].blank?
      errors.add(:plan_spec, "agent must have a name")
    end
  end
end

