# frozen_string_literal: true

# == Schema Information
#
# Table name: module_webhooks
#
#  id                    :bigint           not null, primary key
#  app_module_id         :bigint           not null
#  entity_id             :bigint           not null
#  event_name            :string           not null
#  slug                  :string           not null
#  description           :text
#  auth_type             :string           default("token")
#  auth_token            :string
#  signing_secret        :string
#  ip_allowlist          :jsonb            default([])
#  payload_schema        :jsonb            default({})
#  field_mappings        :jsonb            default({})
#  target_type           :string           not null
#  target_id             :bigint
#  target_tool           :string
#  context_template      :jsonb            default({})
#  rate_limit_per_minute :integer          default(60)
#  rate_limit_per_hour   :integer          default(1000)
#  status                :string           default("active")
#  call_count            :integer          default(0)
#  last_called_at        :datetime
#  last_success_at       :datetime
#  last_failure_at       :datetime
#  last_failure_reason   :text
#  metadata              :jsonb            default({})
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
class ModuleWebhook < ApplicationRecord
  # Associations
  belongs_to :app_module
  belongs_to :entity

  # Auth types
  AUTH_TYPES = %w[token signature ip_allowlist none].freeze
  TARGET_TYPES = %w[agent tool workflow].freeze
  STATUSES = %w[active paused disabled].freeze

  # Validations
  validates :event_name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :entity_id }
  validates :auth_type, inclusion: { in: AUTH_TYPES }
  validates :target_type, presence: true, inclusion: { in: TARGET_TYPES }
  validates :target_id, presence: true, if: -> { target_type.in?(%w[agent workflow]) }
  validates :target_tool, presence: true, if: -> { target_type == 'tool' }
  validates :status, inclusion: { in: STATUSES }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :paused, -> { where(status: 'paused') }
  scope :by_event, ->(event) { where(event_name: event) }
  scope :for_module, ->(app_module) { where(app_module: app_module) }

  # Callbacks
  before_validation :generate_slug, if: -> { slug.blank? && event_name.present? }
  before_create :generate_auth_credentials

  # ============================================
  # STATUS HELPERS
  # ============================================

  def active?
    status == 'active'
  end

  def paused?
    status == 'paused'
  end

  def disabled?
    status == 'disabled'
  end

  def pause!
    update!(status: 'paused')
  end

  def activate!
    update!(status: 'active')
  end

  def disable!
    update!(status: 'disabled')
  end

  # ============================================
  # URL GENERATION
  # ============================================

  def webhook_url
    "/api/webhooks/modules/#{slug}"
  end

  def full_webhook_url(host = nil)
    host ||= Rails.application.routes.default_url_options[:host] || 'localhost:3000'
    "https://#{host}#{webhook_url}"
  end

  # ============================================
  # AUTHENTICATION
  # ============================================

  def verify_request(request)
    return true if auth_type == 'none'
    
    case auth_type
    when 'token'
      verify_token(request)
    when 'signature'
      verify_signature(request)
    when 'ip_allowlist'
      verify_ip(request)
    else
      false
    end
  end

  def verify_token(request)
    provided_token = request.headers['Authorization']&.sub(/^Bearer\s+/, '')
    return false if provided_token.blank? || auth_token.blank?
    
    ActiveSupport::SecurityUtils.secure_compare(provided_token, auth_token)
  end

  def verify_signature(request)
    return false if signing_secret.blank?
    
    provided_signature = request.headers['X-Webhook-Signature']
    return false if provided_signature.blank?
    
    payload = request.raw_post
    expected_signature = generate_signature(payload)
    
    ActiveSupport::SecurityUtils.secure_compare(provided_signature, expected_signature)
  end

  def verify_ip(request)
    return true if ip_allowlist.blank?
    
    client_ip = request.remote_ip
    ip_allowlist.any? { |allowed| IPAddr.new(allowed).include?(client_ip) }
  rescue IPAddr::InvalidAddressError
    false
  end

  def generate_signature(payload)
    "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, payload)}"
  end

  # ============================================
  # PAYLOAD PROCESSING
  # ============================================

  def process_payload(payload)
    # Apply field mappings
    mapped_data = {}
    
    field_mappings.each do |source_path, target_path|
      value = dig_path(payload, source_path)
      set_path(mapped_data, target_path, value) if value.present?
    end
    
    # Merge with context template
    context_template.merge(mapped_data)
  end

  def validate_payload(payload)
    return { valid: true } if payload_schema.blank?
    
    # Basic schema validation
    errors = []
    
    if payload_schema['required'].is_a?(Array)
      payload_schema['required'].each do |field|
        errors << "Missing required field: #{field}" unless dig_path(payload, field).present?
      end
    end
    
    { valid: errors.empty?, errors: errors }
  end

  # ============================================
  # EXECUTION
  # ============================================

  def trigger!(payload, request = nil)
    return { success: false, error: 'Webhook is not active' } unless active?
    
    # Verify authentication
    if request && !verify_request(request)
      record_failure!('Authentication failed')
      return { success: false, error: 'Authentication failed' }
    end
    
    # Validate payload
    validation = validate_payload(payload)
    unless validation[:valid]
      record_failure!(validation[:errors].join(', '))
      return { success: false, errors: validation[:errors] }
    end
    
    # Process payload
    processed = process_payload(payload)
    
    # Execute target
    result = execute_target(processed)
    
    if result[:success]
      record_success!
    else
      record_failure!(result[:error])
    end
    
    result
  end

  def execute_target(data)
    case target_type
    when 'agent'
      execute_agent_target(data)
    when 'tool'
      execute_tool_target(data)
    when 'workflow'
      execute_workflow_target(data)
    else
      { success: false, error: 'Unknown target type' }
    end
  end

  def execute_agent_target(data)
    agent = AgentPlugin.find_by(id: target_id)
    return { success: false, error: 'Agent not found' } unless agent
    
    # Queue agent execution
    execution = AgentPluginExecution.create!(
      agent_plugin: agent,
      user: entity.owner,
      status: 'pending',
      input_context: data.merge(
        triggered_by: 'webhook',
        webhook_slug: slug,
        webhook_event: event_name
      )
    )
    
    AgentPluginExecutionJob.perform_later(
      execution.id,
      "Webhook triggered: #{event_name}",
      { entity_id: entity.id, webhook_data: data }
    )
    
    { success: true, execution_id: execution.id }
  end

  def execute_tool_target(data)
    catalog = Tools::ToolCatalog.instance
    tool_def = catalog.get_tool(target_tool)
    
    return { success: false, error: 'Tool not found' } unless tool_def
    
    # Execute tool
    tool_class = tool_def[:class]
    tool = tool_class.new(
      user: entity.owner,
      entity: entity,
      context: { webhook_triggered: true, webhook_slug: slug }
    )
    
    result = tool.execute(data)
    { success: result[:success] != false, result: result }
  end

  def execute_workflow_target(data)
    # TODO: Implement workflow execution
    { success: false, error: 'Workflow execution not yet implemented' }
  end

  # ============================================
  # METRICS
  # ============================================

  def record_success!
    update!(
      call_count: call_count + 1,
      last_called_at: Time.current,
      last_success_at: Time.current,
      last_failure_reason: nil
    )
  end

  def record_failure!(reason)
    update!(
      call_count: call_count + 1,
      last_called_at: Time.current,
      last_failure_at: Time.current,
      last_failure_reason: reason
    )
  end

  def success_rate
    return 0.0 if call_count.zero?
    return 100.0 if last_failure_at.nil?
    
    # Approximate based on recent history
    if last_success_at && last_failure_at
      last_success_at > last_failure_at ? 90.0 : 50.0
    else
      50.0
    end
  end

  private

  def generate_slug
    base = event_name.parameterize.underscore
    self.slug = "#{app_module.slug}_#{base}"
    
    counter = 1
    while ModuleWebhook.where(entity: entity, slug: slug).exists?
      self.slug = "#{app_module.slug}_#{base}_#{counter}"
      counter += 1
    end
  end

  def generate_auth_credentials
    self.auth_token ||= SecureRandom.hex(32) if auth_type == 'token'
    self.signing_secret ||= SecureRandom.hex(32) if auth_type == 'signature'
  end

  def dig_path(hash, path)
    path.split('.').reduce(hash) { |obj, key| obj.is_a?(Hash) ? obj[key] : nil }
  end

  def set_path(hash, path, value)
    keys = path.split('.')
    last_key = keys.pop
    
    target = keys.reduce(hash) do |obj, key|
      obj[key] ||= {}
      obj[key]
    end
    
    target[last_key] = value
  end
end





