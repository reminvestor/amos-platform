# frozen_string_literal: true

# == Schema Information
#
# Table name: app_modules
#
#  id             :bigint           not null, primary key
#  entity_id      :bigint           not null
#  created_by_id  :bigint
#  slug           :string           not null
#  name           :string           not null
#  description    :text
#  version        :string           default("1.0.0")
#  icon           :string
#  status         :string           default("draft"), not null
#  visibility     :string           default("entity_private")
#  author_type    :string           default("amos")
#  components     :jsonb            default({})
#  ui_modes       :jsonb            default({simple: true, advanced: false})
#  dependencies   :jsonb            default([])
#  permissions    :jsonb            default([])
#  show_in_menu   :boolean          default(true)
#  menu_order     :integer          default(100)
#  menu_parent    :string
#  metadata       :jsonb            default({})
#  deployed_at    :datetime
#  last_tested_at :datetime
#  test_results   :jsonb            default({})
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class AppModule < ApplicationRecord
  include WorkflowTriggerable
  
  # Associations
  belongs_to :entity
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :app, optional: true  # Parent app (if part of an app)
  
  has_many :module_canvases, class_name: 'ModuleCanvas', dependent: :destroy
  has_many :module_codes, dependent: :destroy
  has_many :module_webhooks, dependent: :destroy
  has_many :module_actions, dependent: :destroy
  has_many :custom_field_definitions, dependent: :nullify
  has_many :tool_definitions, dependent: :nullify
  has_many :agent_plugins, dependent: :nullify
  has_many :scheduled_agent_tasks, dependent: :nullify
  
  # Convenience method - each module has one primary agent (first created)
  def agent_plugin
    agent_plugins.first
  end
  has_many :module_integrations, dependent: :destroy
  has_many :integrations, through: :module_integrations

  # Status values
  STATUSES = %w[draft designing generating testing deployed active disabled failed].freeze
  VISIBILITIES = %w[user_private entity_private entity_shared public].freeze
  AUTHOR_TYPES = %w[system amos user].freeze

  # Default visibility based on author type
  # AI-created modules default to user_private (only creator sees)
  # System modules default to entity_shared (everyone in entity sees)
  before_validation :set_default_visibility, on: :create

  # Validations
  validates :slug, presence: true, uniqueness: { scope: :entity_id }
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :author_type, inclusion: { in: AUTHOR_TYPES }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :deployed, -> { where(status: %w[deployed active]) }
  scope :draft, -> { where(status: 'draft') }
  scope :by_author, ->(type) { where(author_type: type) }
  scope :in_menu, -> { where(show_in_menu: true).order(:menu_order) }
  scope :ai_created, -> { where(author_type: 'amos') }
  scope :system, -> { where(author_type: 'system') }
  
  # Visibility scopes - CRITICAL: Use this for all user-facing queries
  # user_private: only creator sees it
  # entity_private: everyone in entity sees it (legacy default)
  # entity_shared: everyone in entity sees it (same as entity_private, kept for clarity)
  # public: everyone sees it (future: marketplace)
  scope :visible_to, ->(user) {
    return none unless user
    
    # Query: user's private modules OR entity-level modules OR public modules
    where(
      "(app_modules.visibility = 'user_private' AND app_modules.created_by_id = ?) OR " \
      "(app_modules.visibility IN ('entity_private', 'entity_shared') AND app_modules.entity_id = ?) OR " \
      "app_modules.visibility = 'public'",
      user.id, user.entity_id
    )
  }
  
  # For menu display - only show active modules visible to user
  scope :in_menu_for, ->(user) {
    visible_to(user).active.in_menu
  }

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  # ============================================
  # STATUS HELPERS
  # ============================================

  def draft?
    status == 'draft'
  end

  def active?
    status == 'active'
  end

  def deployed?
    status.in?(%w[deployed active])
  end

  def failed?
    status == 'failed'
  end

  # ============================================
  # VISIBILITY HELPERS
  # ============================================

  def user_private?
    visibility == 'user_private'
  end

  def entity_visible?
    visibility.in?(%w[entity_private entity_shared])
  end

  def public?
    visibility == 'public'
  end

  # Check if a specific user can see this module
  def visible_to?(user)
    return false unless user
    
    case visibility
    when 'user_private'
      created_by_id == user.id
    when 'entity_private', 'entity_shared'
      entity_id == user.entity_id
    when 'public'
      true
    else
      false
    end
  end

  # Check if user can edit this module
  def editable_by?(user)
    return false unless user
    return true if created_by_id == user.id
    return true if user.admin? || user.owner_of_entity?(entity)
    false
  end

  # Share module with team (change from user_private to entity_shared)
  def share_with_team!
    return false unless user_private?
    update!(visibility: 'entity_shared')
  end

  # Make module private again (only works if user is creator)
  def make_private!
    return false unless created_by_id.present?
    update!(visibility: 'user_private')
  end

  # ============================================
  # LIFECYCLE METHODS
  # ============================================

  def start_design!
    update!(status: 'designing')
  end

  def start_generation!
    update!(status: 'generating')
  end

  def start_testing!
    update!(status: 'testing', last_tested_at: Time.current)
  end

  def mark_deployed!
    update!(status: 'deployed', deployed_at: Time.current)
  end

  def activate!
    update!(status: 'active')
  end

  def disable!
    update!(status: 'disabled')
  end

  def mark_failed!(errors)
    update!(
      status: 'failed',
      test_results: test_results.merge(
        last_error: errors,
        failed_at: Time.current.iso8601
      )
    )
  end

  def record_test_results!(results)
    update!(
      test_results: results,
      last_tested_at: Time.current
    )
  end

  # ============================================
  # COMPONENT ACCESSORS
  # ============================================

  def canvases_list
    components['canvases'] || []
  end

  def data_models_list
    components['data_models'] || []
  end

  def tools_list
    components['tools'] || []
  end

  def agents_list
    components['agents'] || []
  end

  def webhooks_list
    components['webhooks'] || []
  end

  def scheduled_tasks_list
    components['scheduled_tasks'] || []
  end

  # ============================================
  # UI MODE HELPERS
  # ============================================

  def supports_simple_mode?
    ui_modes['simple'] == true
  end

  def supports_advanced_mode?
    ui_modes['advanced'] == true
  end

  def default_ui_mode
    ui_modes['simple_default'] ? 'simple' : (supports_simple_mode? ? 'simple' : 'advanced')
  end

  # ============================================
  # DEPENDENCY HELPERS
  # ============================================

  def depends_on?(other_module_slug)
    dependencies.include?(other_module_slug)
  end

  def dependency_modules
    return [] if dependencies.blank?
    AppModule.where(entity: entity, slug: dependencies)
  end

  def dependencies_satisfied?
    return true if dependencies.blank?
    dependency_modules.active.count == dependencies.count
  end

  # ============================================
  # MENU HELPERS
  # ============================================

  def menu_entry
    return nil unless show_in_menu && active?
    
    {
      slug: slug,
      name: name,
      icon: icon || 'box',
      parent: menu_parent,
      order: menu_order,
      canvases: canvases_list
    }
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def to_manifest
    {
      slug: slug,
      name: name,
      description: description,
      version: version,
      author_type: author_type,
      components: components,
      ui_modes: ui_modes,
      dependencies: dependencies,
      permissions: permissions
    }
  end

  # ============================================
  # ENHANCED FIELD CONFIGURATION
  # ============================================

  # Get all fields organized by section
  def fields_by_section
    all_fields = enhanced_fields
    return {} if all_fields.blank?
    
    all_fields.group_by { |f| f['section'] || 'main' }
  end
  
  # Get enhanced field definitions
  def enhanced_fields
    # field_config contains enhanced definitions with sections, visibility, etc.
    return field_config['fields'] if field_config['fields'].present?
    
    # Fall back to schema fields in metadata
    schema_fields = metadata.dig('schema', 'fields') || []
    
    # Enhance schema fields with defaults
    schema_fields.map do |f|
      f.merge(
        'section' => f['section'] || 'main',
        'visibility' => f['visibility'] || 'always',
        'order' => f['order'] || 0
      )
    end
  end
  
  # Get fields for a specific context (create, edit, view)
  def fields_for_context(context = :edit, record = nil)
    enhanced_fields.select do |field|
      visibility = field['visibility'] || 'always'
      
      case visibility
      when 'always'
        true
      when 'create_only'
        context == :create
      when 'edit_only'
        context == :edit
      when 'read_only'
        context == :view
      when 'system', 'never'
        false
      else
        # Check conditional visibility
        if field['show_when'].present? && record.present?
          condition_met?(field['show_when'], record)
        else
          true
        end
      end
    end.sort_by { |f| f['order'] || 0 }
  end
  
  # Get sections configuration
  def sections_config
    field_config['sections'] || default_sections
  end
  
  def default_sections
    [
      { 'name' => 'main', 'label' => 'Details', 'icon' => 'file-text' },
      { 'name' => 'scheduling', 'label' => 'Scheduling', 'icon' => 'calendar' },
      { 'name' => 'workflow', 'label' => 'Workflow', 'icon' => 'git-branch' },
      { 'name' => 'metrics', 'label' => 'Metrics', 'icon' => 'bar-chart' },
      { 'name' => 'advanced', 'label' => 'Advanced', 'icon' => 'settings' }
    ]
  end
  
  # Check if a condition is met for conditional visibility
  def condition_met?(condition, record)
    return true if condition.blank?
    
    field = condition['field']
    return true unless field.present?
    
    value = record.try(field)
    
    if condition['equals'].present?
      value.to_s == condition['equals'].to_s
    elsif condition['not_equals'].present?
      value.to_s != condition['not_equals'].to_s
    elsif condition['in'].present?
      Array(condition['in']).map(&:to_s).include?(value.to_s)
    else
      true
    end
  end

  # ============================================
  # ACTION HELPERS
  # ============================================
  
  # Get actions for a specific location
  def actions_for_location(location, record = nil, user = nil)
    module_actions.active.for_location(location).ordered.select do |action|
      action.visible_for?(record, user)
    end
  end
  
  def toolbar_actions(record = nil, user = nil)
    actions_for_location('toolbar', record, user)
  end
  
  def row_actions(record = nil, user = nil)
    actions_for_location('row', record, user)
  end
  
  def field_actions(field_name)
    module_actions.active.for_fields.where(target_field: field_name)
  end

  # ============================================
  # TOOL GENERATION
  # ============================================
  
  # Auto-generate CRUD tools for this module
  def generate_tools!
    tools = []
    
    # Create tool
    tools << {
      name: "create_#{slug.singularize}",
      description: "Create a new #{name.singularize}",
      parameters: creation_parameters
    }
    
    # Get tool
    tools << {
      name: "get_#{slug}",
      description: "Get #{name} records with optional filters",
      parameters: query_parameters
    }
    
    # Update tool
    tools << {
      name: "update_#{slug.singularize}",
      description: "Update a #{name.singularize} record",
      parameters: update_parameters
    }
    
    # Store in tool_config
    update!(tool_config: tools)
    tools
  end
  
  def creation_parameters
    enhanced_fields.select { |f| f['visibility'] != 'system' && f['visibility'] != 'read_only' }
                   .map do |f|
      {
        name: f['name'],
        type: map_field_type_to_param(f['field_type'] || f['type']),
        required: f['required'] == true,
        description: f['description'] || f['label'] || f['name'].titleize
      }
    end
  end
  
  def query_parameters
    [
      { name: 'filters', type: 'object', required: false, description: 'Filter criteria' },
      { name: 'limit', type: 'integer', required: false, description: 'Max records to return' },
      { name: 'order_by', type: 'string', required: false, description: 'Sort field and direction' }
    ]
  end
  
  def update_parameters
    [{ name: 'id', type: 'integer', required: true, description: 'Record ID' }] +
      creation_parameters.map { |p| p.merge(required: false) }
  end
  
  def map_field_type_to_param(field_type)
    case field_type.to_s
    when 'integer', 'decimal'
      'number'
    when 'boolean'
      'boolean'
    when 'json'
      'object'
    when 'date', 'datetime'
      'string'
    else
      'string'
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # INTEGRATION STATUS
  # ═══════════════════════════════════════════════════════════════════

  # Check if all required integrations are connected
  def integrations_ready?
    module_integrations.required.all?(&:ready?)
  end

  # Check if all critical integrations are connected
  def critical_integrations_ready?
    module_integrations.critical.all?(&:ready?)
  end

  # Get integration status summary
  def integration_status
    total = module_integrations.count
    return { status: 'none', message: 'No integrations needed' } if total.zero?

    connected = module_integrations.connected.count
    required = module_integrations.required.count
    critical = module_integrations.critical.count
    critical_connected = module_integrations.critical.connected.count

    if connected == total
      { status: 'ready', message: "✅ All #{total} integrations connected", connected: connected, total: total }
    elsif critical > 0 && critical_connected < critical
      missing = module_integrations.critical.where.not(status: 'connected').includes(:integration).map { |mi| mi.integration.name }
      { status: 'critical', message: "🚨 Critical integrations missing: #{missing.join(', ')}", connected: connected, total: total, missing: missing }
    elsif connected < required
      missing = module_integrations.required.where.not(status: 'connected').includes(:integration).map { |mi| mi.integration.name }
      { status: 'incomplete', message: "⚠️ #{connected}/#{total} integrations connected", connected: connected, total: total, missing: missing }
    else
      { status: 'partial', message: "ℹ️ #{connected}/#{total} integrations connected (optional missing)", connected: connected, total: total }
    end
  end

  # Sync all integration statuses with actual connections
  def sync_integration_statuses!
    module_integrations.each(&:sync_status!)
    integration_status
  end

  # Add an integration requirement to this module
  def require_integration!(integration_or_slug, purpose:, is_critical: false, description: nil)
    integration = integration_or_slug.is_a?(Integration) ? integration_or_slug : Integration.find_by(slug: integration_or_slug)
    return nil unless integration

    module_integrations.find_or_create_by!(integration: integration) do |mi|
      mi.purpose = purpose
      mi.is_critical = is_critical
      mi.description = description
      mi.status = 'required'
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # WORKFLOW TRIGGERS FOR RECORD EVENTS
  # ═══════════════════════════════════════════════════════════════════

  # Fire workflow triggers for record events (create, update, delete)
  #
  # @param event_type [Symbol] :created, :updated, or :deleted
  # @param record [Hash] The record data
  # @param changes [Hash] The changed attributes (for updates)
  # @param user [User] The user who performed the action
  def fire_record_event(event_type, record:, changes: {}, user: nil)
    trigger_type = "record_#{event_type}"
    
    fire_matching_workflows!(trigger_type, {
      event_type: event_type.to_s,
      record: record,
      changes: changes,
      app_module_id: id,
      app_module_name: name,
      app_module_slug: slug,
      user: user
    })
  end

  # Fire workflow for field change events
  def fire_field_change_event(record:, field:, old_value:, new_value:, user: nil)
    fire_matching_workflows!(:field_changed, {
      event_type: 'field_changed',
      record: record,
      changes: { field => [old_value, new_value] },
      app_module_id: id,
      field: field,
      old_value: old_value,
      new_value: new_value,
      user: user
    })
  end

  # Fire workflow for status change events
  def fire_status_change_event(record:, old_status:, new_status:, user: nil)
    fire_matching_workflows!(:status_changed, {
      event_type: 'status_changed',
      record: record,
      changes: { 'status' => [old_status, new_status] },
      app_module_id: id,
      old_status: old_status,
      new_status: new_status,
      user: user
    })
  end

  private

  def set_default_visibility
    return if visibility.present? && visibility != 'entity_private'
    
    # AI-created and user-created modules default to user_private
    # System modules (templates) default to entity_shared so everyone can see them
    self.visibility = case author_type
    when 'system'
      'entity_shared'
    when 'amos', 'user'
      # Only set to user_private if we have a creator
      created_by_id.present? ? 'user_private' : 'entity_shared'
    else
      'user_private'
    end
  end

  def generate_slug
    base_slug = name.parameterize.underscore
    self.slug = base_slug
    
    counter = 1
    while AppModule.where(entity: entity, slug: slug).exists?
      self.slug = "#{base_slug}_#{counter}"
      counter += 1
    end
  end
end

