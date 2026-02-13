# frozen_string_literal: true

# App - A complete business application built on the platform
#
# Apps are the top-level container for related modules, workflows,
# and AI assistants. They go through a lifecycle:
#
#   designing → planning → building → preview → active → archived
#
# Example: "Social Media Manager" app contains:
#   - Posts module (create/schedule posts)
#   - Media Library module (store assets)
#   - Campaigns module (group posts)
#   - Social Media Strategist agent (helps users)
#   - Auto-publish workflow (schedules posts)
#
class App < ApplicationRecord
  include EntityShareable

  belongs_to :entity
  belongs_to :created_by, class_name: 'User', optional: true
  
  has_many :app_modules, dependent: :destroy
  has_many :module_canvases, through: :app_modules
  has_many :module_actions, through: :app_modules
  has_one :app_assistant, -> { where(role: 'app_assistant') },
          class_name: 'AgentPlugin', dependent: :destroy
  
  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :entity_id }
  validates :status, inclusion: { 
    in: %w[designing planning building preview active archived] 
  }
  
  # Callbacks
  before_validation :generate_slug, on: :create
  
  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :in_development, -> { where(status: %w[designing planning building preview]) }
  scope :published, -> { where.not(published_at: nil) }
  
  # Status helpers
  def designing?
    status == 'designing'
  end
  
  def planning?
    status == 'planning'
  end
  
  def building?
    status == 'building'
  end
  
  def preview?
    status == 'preview'
  end
  
  def active?
    status == 'active'
  end
  
  def archived?
    status == 'archived'
  end
  
  # Lifecycle transitions
  def start_planning!
    return false unless designing?
    update!(status: 'planning')
  end
  
  def approve_blueprint!(blueprint_data = nil)
    return false unless planning?
    update!(
      blueprint: blueprint_data || blueprint,
      blueprint_approved_at: Time.current,
      status: 'building'
    )
  end
  
  def start_build!
    return false unless planning? || building?
    update!(
      status: 'building',
      build_started_at: Time.current
    )
  end
  
  def complete_build!
    return false unless building?
    update!(
      status: 'preview',
      build_completed_at: Time.current
    )
  end
  
  def publish!
    return false unless preview?
    update!(
      status: 'active',
      published_at: Time.current,
      version: version + 1
    )
    log_version_change('Published')
  end
  
  def archive!
    update!(status: 'archived')
  end
  
  def reactivate!
    return false unless archived?
    update!(status: 'active')
  end
  
  # Blueprint helpers
  def modules_blueprint
    blueprint.dig('modules') || []
  end
  
  def workflows_blueprint
    blueprint.dig('workflows') || []
  end
  
  def assistant_blueprint
    blueprint.dig('app_assistant') || {}
  end
  
  def integrations_blueprint
    blueprint.dig('integrations') || []
  end
  
  # Primary module
  def primary_module
    app_modules.find_by(is_primary: true) || app_modules.first
  end
  
  # Get all tools for this app
  def available_tools
    app_modules.flat_map { |m| m.tool_config || [] }
  end
  
  # Intent helpers (from discovery)
  def primary_goal
    intent.dig('primary_goal')
  end
  
  def user_roles
    intent.dig('users') || personas || []
  end
  
  def core_workflows_intent
    intent.dig('core_workflows') || []
  end
  
  private
  
  def generate_slug
    return if slug.present?
    base_slug = name.to_s.parameterize.underscore
    self.slug = base_slug
    
    counter = 1
    while App.where(entity_id: entity_id, slug: slug).where.not(id: id).exists?
      self.slug = "#{base_slug}_#{counter}"
      counter += 1
    end
  end
  
  def log_version_change(action)
    changelog << {
      version: version,
      action: action,
      timestamp: Time.current.iso8601,
      user_id: created_by_id
    }
    save!
  end
end


