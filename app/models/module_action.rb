# frozen_string_literal: true

# ModuleAction - Custom buttons and operations for modules
#
# Actions define what happens when users click buttons in the UI.
# They can update records, show modals, call tools, invoke agents, etc.
#
# Example actions for a Posts module:
#   - "Submit for Review" (updates status, notifies approvers)
#   - "Approve" (updates status, requires approver role)
#   - "AI Write" (invokes app assistant to help write content)
#   - "Schedule" (shows modal with date picker, updates record)
#
class ModuleAction < ApplicationRecord
  belongs_to :app_module
  belongs_to :entity
  
  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :app_module_id }
  validates :behavior_type, presence: true, inclusion: {
    in: %w[
      update
      update_and_notify
      modal_form
      navigate
      call_tool
      agent_assist
      run_workflow
      confirm
      custom
      load_canvas
    ]
  }
  validates :style, inclusion: {
    in: %w[primary secondary success danger warning outline link]
  }
  validates :location, inclusion: {
    in: %w[toolbar row field form_footer header]
  }
  
  # Callbacks
  before_validation :generate_slug, on: :create
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_location, ->(loc) { where(location: loc) }
  scope :for_toolbar, -> { where(location: 'toolbar') }
  scope :for_rows, -> { where(location: 'row') }
  scope :for_fields, -> { where(location: 'field') }
  scope :ordered, -> { order(position: :asc) }
  
  # Check if action should be shown given current record state
  def visible_for?(record, user = nil)
    return true if show_when.blank?
    
    conditions_met?(record, show_when) && role_allowed?(user)
  end
  
  # Check if user has required role/permission
  def role_allowed?(user)
    return true if requires_role.blank? || user.nil?
    
    role = requires_role['role']
    permission = requires_role['permission']
    
    if role.present?
      # Check if user has this role in the entity
      user.has_role?(role) || user.admin?
    elsif permission.present?
      user.can?(permission)
    else
      true
    end
  end
  
  # Execute the action
  def execute!(record, user, params = {})
    case behavior_type
    when 'update'
      execute_update(record, params)
    when 'update_and_notify'
      execute_update_and_notify(record, user, params)
    when 'modal_form'
      # Returns modal config - actual execution happens after form submit
      { type: 'modal', config: behavior_config }
    when 'navigate'
      { type: 'navigate', url: interpolate_url(behavior_config['url'], record) }
    when 'call_tool'
      execute_tool(record, user, params)
    when 'agent_assist'
      execute_agent_assist(record, user, params)
    when 'run_workflow'
      execute_workflow(record, user, params)
    when 'confirm'
      { type: 'confirm', config: behavior_config }
    when 'load_canvas'
      { type: 'load_canvas', canvas: behavior_config['canvas'], data: build_canvas_data(record) }
    else
      { type: 'error', message: "Unknown behavior type: #{behavior_type}" }
    end
  end
  
  # Convert to JSON for frontend
  def to_frontend_json(record = nil)
    {
      id: id,
      name: name,
      slug: slug,
      icon: icon,
      style: style,
      location: location,
      target_field: target_field,
      visible: record ? visible_for?(record) : true,
      behavior_type: behavior_type,
      requires_confirmation: behavior_type == 'confirm' || behavior_config['confirm'].present?
    }
  end
  
  private
  
  def generate_slug
    return if slug.present?
    self.slug = name.to_s.parameterize.underscore
  end
  
  def conditions_met?(record, conditions)
    field = conditions['field']
    return true unless field.present?
    
    value = record.try(field)
    
    if conditions['equals'].present?
      value.to_s == conditions['equals'].to_s
    elsif conditions['not_equals'].present?
      value.to_s != conditions['not_equals'].to_s
    elsif conditions['in'].present?
      Array(conditions['in']).map(&:to_s).include?(value.to_s)
    elsif conditions['not_in'].present?
      !Array(conditions['not_in']).map(&:to_s).include?(value.to_s)
    elsif conditions['present'].present?
      value.present?
    elsif conditions['blank'].present?
      value.blank?
    else
      true
    end
  end
  
  def execute_update(record, params)
    updates = behavior_config['updates'] || {}
    updates = updates.merge(params['updates'] || {})
    
    record.update!(updates)
    { type: 'success', message: "#{app_module.name} updated", record: record.reload }
  end
  
  def execute_update_and_notify(record, user, params)
    result = execute_update(record, params)
    
    # Send notifications
    notify_config = behavior_config['notify']
    if notify_config.present?
      send_notification(record, user, notify_config)
    end
    
    result
  end
  
  def execute_tool(record, user, params)
    tool_name = behavior_config['tool']
    tool_params = interpolate_params(behavior_config['params'] || {}, record, params)
    
    # Execute via ToolCatalog
    catalog = Tools::ToolCatalog.new
    result = catalog.execute_tool(tool_name, tool_params, user: user, entity: entity)
    
    { type: 'tool_result', result: result }
  end
  
  def execute_agent_assist(record, user, params)
    agent = behavior_config['agent'] || 'app_assistant'
    prompt = behavior_config['prompt'] || "Help with this task"
    
    # Find the agent
    app = app_module.app
    agent_plugin = if agent == 'app_assistant' && app&.app_assistant
                     app.app_assistant
                   else
                     AgentPlugin.find_by(slug: agent, entity_id: entity_id)
                   end
    
    return { type: 'error', message: "Agent not found: #{agent}" } unless agent_plugin
    
    # Return agent invocation config
    {
      type: 'agent_assist',
      agent_id: agent_plugin.id,
      agent_name: agent_plugin.name,
      prompt: interpolate_prompt(prompt, record, params),
      context: {
        module: app_module.slug,
        record_id: record.id,
        field: target_field
      }
    }
  end
  
  def execute_workflow(record, user, params)
    workflow = behavior_config['workflow']
    
    # Queue the workflow
    # Implementation depends on your workflow system
    { type: 'workflow_started', workflow: workflow }
  end
  
  def interpolate_url(url, record)
    url.to_s
       .gsub('$record.id', record.id.to_s)
       .gsub(/\$record\.(\w+)/) { record.try($1).to_s }
  end
  
  def interpolate_params(params, record, user_params)
    params.transform_values do |value|
      if value.is_a?(String) && value.start_with?('$record.')
        field = value.sub('$record.', '')
        record.try(field)
      elsif value.is_a?(String) && value.start_with?('$params.')
        key = value.sub('$params.', '')
        user_params[key]
      else
        value
      end
    end
  end
  
  def interpolate_prompt(prompt, record, params)
    result = prompt.to_s
    
    # Replace record placeholders
    result = result.gsub(/\{(\w+)\}/) do
      field = $1
      if field.start_with?('record.')
        record.try(field.sub('record.', ''))
      elsif params[field].present?
        params[field]
      else
        "{#{field}}"
      end
    end
    
    result
  end
  
  def build_canvas_data(record)
    data = behavior_config['canvas_data'] || {}
    data['id'] = record.id if record
    data
  end
  
  def send_notification(record, actor, config)
    # Implementation depends on your notification system
    # This would typically queue a notification job
    Rails.logger.info "[ModuleAction] Would notify #{config['role']} about #{app_module.name} action"
  end
end





