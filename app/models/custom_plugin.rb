class CustomPlugin < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  
  # Plugin types
  PLUGIN_TYPES = %w[agent tool model workflow].freeze
  
  # Status
  enum :status, {
    pending: 'pending',
    active: 'active',
    suspended: 'suspended',
    deleted: 'deleted'
  }, prefix: true
  
  # Validations
  validates :plugin_type, inclusion: { in: PLUGIN_TYPES }
  validates :plugin_id, presence: true, uniqueness: { scope: [:entity_id, :plugin_type] }
  validates :spec, presence: true
  validates :code, presence: true, if: -> { %w[agent tool].include?(plugin_type) }
  
  # Scopes
  scope :agents, -> { where(plugin_type: 'agent') }
  scope :tools, -> { where(plugin_type: 'tool') }
  scope :models, -> { where(plugin_type: 'model') }
  scope :workflows, -> { where(plugin_type: 'workflow') }
  
  # Callbacks
  before_validation :set_plugin_id, on: :create
  after_create :register_with_platform
  after_update :update_platform_registration
  before_destroy :unregister_from_platform
  
  # Convert to plugin info for API responses
  def to_plugin_info
    {
      id: plugin_id,
      type: plugin_type,
      name: spec['name'] || plugin_id,
      description: spec['description'],
      version: spec['version'] || '1.0.0',
      capabilities: spec['capabilities'] || [],
      created_by: user.name,
      entity: entity.name,
      created_at: created_at,
      status: status
    }
  end
  
  # Check if plugin is shared
  def shared?
    spec['sharing'] && spec['sharing']['enabled']
  end
  
  # Get sharing scope
  def sharing_scope
    return nil unless shared?
    spec['sharing']['scope'] || 'entity'
  end
  
  # Check if user can access this plugin
  def accessible_by?(check_user, check_entity = nil)
    # Owner always has access
    return true if user_id == check_user.id
    
    # Entity members have access to entity plugins
    if check_entity && entity_id == check_entity.id
      return true if sharing_scope == 'entity'
    end
    
    # Public plugins are accessible to all
    return true if sharing_scope == 'public'
    
    # Check explicit permissions
    PluginPermission.exists?(
      custom_plugin: self,
      user: check_user,
      permission_type: 'use'
    )
  end
  
  # Execute plugin (for agents and tools)
  def execute(method, args, context)
    raise "Cannot execute #{plugin_type} plugin" unless %w[agent tool].include?(plugin_type)
    raise "Plugin not active" unless status_active?
    
    Agents::Platform::PluginManager.instance.execute_plugin(
      plugin_id,
      method,
      args,
      context.merge(plugin: self)
    )
  end
  
  # Get usage statistics
  def usage_stats(period = 30.days)
    PluginUsage.where(
      plugin_id: plugin_id,
      created_at: period.ago..Time.current
    ).group_by_day(:created_at).sum(:execution_count)
  end
  
  # Get resource usage
  def resource_usage(period = 30.days)
    usages = PluginUsage.where(
      plugin_id: plugin_id,
      created_at: period.ago..Time.current
    )
    
    {
      total_executions: usages.sum(:execution_count),
      total_memory_mb: usages.sum(:memory_mb),
      total_cpu_seconds: usages.sum(:cpu_seconds),
      total_api_calls: usages.sum(:api_calls),
      average_duration: usages.average(:duration_ms),
      total_cost: calculate_usage_cost(usages)
    }
  end
  
  private
  
  def set_plugin_id
    self.plugin_id ||= "#{plugin_type}-#{entity_id}-#{SecureRandom.hex(8)}"
  end
  
  def register_with_platform
    case plugin_type
    when 'agent'
      Agents::Platform::PluginManager.instance.load_custom_agent(
        code,
        user: user,
        entity: entity
      )
    when 'tool'
      Agents::Platform::PluginManager.instance.load_custom_tool(
        code,
        user: user,
        entity: entity
      )
    when 'model'
      Agents::Platform::ModelRegistry.instance.register_custom_model(
        user: user,
        entity: entity,
        model_config: spec
      )
    when 'workflow'
      # Workflow templates are loaded differently
      WorkflowTemplateLoader.register_custom_template(self)
    end
  rescue => e
    Rails.logger.error "Failed to register plugin: #{e.message}"
    update_column(:status, 'suspended')
    raise
  end
  
  def update_platform_registration
    if saved_change_to_status?
      if status_active?
        register_with_platform
      else
        unregister_from_platform
      end
    elsif saved_change_to_code? || saved_change_to_spec?
      # Re-register with updated code/spec
      unregister_from_platform
      register_with_platform if status_active?
    end
  end
  
  def unregister_from_platform
    case plugin_type
    when 'agent'
      Agents::Communication::AgentRegistry.unregister(plugin_id)
    when 'tool'
      # Tools don't have unregister yet
    when 'model'
      # Models are tracked differently
    end
  rescue => e
    Rails.logger.error "Failed to unregister plugin: #{e.message}"
  end
  
  def calculate_usage_cost(usages)
    # Simple cost calculation - can be enhanced
    cpu_cost = usages.sum(:cpu_seconds) * 0.0001 # $0.0001 per CPU second
    memory_cost = usages.sum(:memory_mb) * 0.00001 # $0.00001 per MB
    api_cost = usages.sum(:api_calls) * 0.001 # $0.001 per API call
    
    cpu_cost + memory_cost + api_cost
  end
end
