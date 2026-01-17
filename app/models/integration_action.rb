# frozen_string_literal: true

# IntegrationAction - Pre-defined, tested API operation templates
#
# This provides a normalized interface for Amos to call API operations.
# Instead of guessing at API-specific parameters, Amos uses a standard
# input schema, and AI-generated mapping_code converts to API format.
#
# Similar to how IntegrationSyncConfig + TransformCodeExecutor work for ETL,
# IntegrationAction + ActionCodeExecutor work for ad-hoc API calls.
#
# Example:
#   action = IntegrationAction.find_by(slug: "coinbase.place_limit_order")
#   
#   # Amos provides normalized inputs:
#   inputs = { symbol: "BTC/USD", side: "buy", quantity: 0.001, price: 50000 }
#   
#   # mapping_code converts to API-specific params:
#   # => { product_id: "BTC-USD", side: "BUY", size: "0.001", price: "50000", type: "limit" }
#
class IntegrationAction < ApplicationRecord
  belongs_to :integration
  belongs_to :integration_operation
  belongs_to :entity, optional: true  # nil = global template
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :executions, class_name: 'IntegrationActionExecution', dependent: :destroy

  # Status enum
  enum :status, {
    draft: 0,
    testing: 1,
    active: 2,
    deprecated: 3
  }

  # Validations
  validates :action_name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :action_name, uniqueness: { scope: :integration_id }
  validates :input_schema, presence: true

  # Callbacks
  before_validation :generate_slug, on: :create

  # Scopes
  scope :for_entity, ->(entity) { where(entity_id: [nil, entity.id]) }
  scope :global, -> { where(entity_id: nil) }
  scope :usable, -> { where(status: [:testing, :active]) }
  
  # ============================================
  # EXECUTION
  # ============================================

  # Execute this action with provided inputs
  def execute!(inputs:, connection:, user:, entity:)
    execution = executions.create!(
      connection: connection,
      user: user,
      entity: entity,
      inputs: inputs,
      status: :pending,
      started_at: Time.current
    )

    begin
      # Validate inputs against schema
      validation = validate_inputs(inputs)
      unless validation[:valid]
        execution.fail!(validation[:errors].join(', '))
        return execution
      end

      # Map inputs to API params using AI-generated code
      mapped = map_inputs(inputs)
      unless mapped[:success]
        execution.fail!(mapped[:error])
        return execution
      end
      execution.update!(mapped_params: mapped[:params])

      # Execute the underlying operation
      result = UniversalIntegrationExecutor.execute(
        integration: integration,
        operation: integration_operation.operation_id,
        params: mapped[:params],
        user: user,
        entity: entity,
        connection_id: connection.id
      )

      execution.update!(
        raw_response: result[:data] || result[:error_details],
        http_status_code: result[:status_code]
      )

      if result[:success]
        # Normalize response if mapping exists
        normalized = response_mapping_code.present? ? 
          normalize_response(result[:data]) : 
          { success: true, data: result[:data] }
        
        execution.update!(normalized_response: normalized[:data] || normalized)
        execution.complete!
        
        # Update usage metrics
        increment!(:usage_count)
        increment!(:success_count)
        update!(last_used_at: Time.current)
      else
        execution.fail!(result[:error])
        increment!(:usage_count)
        increment!(:error_count)
      end

      execution
    rescue => e
      Rails.logger.error "[IntegrationAction] Execution failed: #{e.message}"
      execution.fail!(e.message)
      increment!(:error_count)
      execution
    end
  end

  # ============================================
  # INPUT VALIDATION
  # ============================================

  def validate_inputs(inputs)
    errors = []
    inputs = inputs.with_indifferent_access

    input_schema.each do |field_def|
      field = field_def.with_indifferent_access
      name = field[:name]
      value = inputs[name]

      # Check required
      if field[:required] && value.nil?
        errors << "#{name} is required"
        next
      end

      next if value.nil?

      # Type validation
      case field[:type]
      when 'string'
        errors << "#{name} must be a string" unless value.is_a?(String)
      when 'number', 'integer', 'float'
        errors << "#{name} must be a number" unless value.is_a?(Numeric)
      when 'boolean'
        errors << "#{name} must be true or false" unless [true, false].include?(value)
      when 'enum'
        unless field[:values]&.include?(value.to_s)
          errors << "#{name} must be one of: #{field[:values].join(', ')}"
        end
      when 'array'
        errors << "#{name} must be an array" unless value.is_a?(Array)
      when 'object'
        errors << "#{name} must be an object" unless value.is_a?(Hash)
      end

      # Min/max validation for numbers
      if value.is_a?(Numeric)
        errors << "#{name} must be >= #{field[:min]}" if field[:min] && value < field[:min]
        errors << "#{name} must be <= #{field[:max]}" if field[:max] && value > field[:max]
      end

      # Pattern validation for strings
      if value.is_a?(String) && field[:pattern]
        unless value.match?(Regexp.new(field[:pattern]))
          errors << "#{name} format is invalid"
        end
      end
    end

    { valid: errors.empty?, errors: errors }
  end

  # ============================================
  # CODE EXECUTION
  # ============================================

  def map_inputs(inputs)
    return fallback_mapping(inputs) if mapping_code.blank?

    executor = Integrations::ActionCodeExecutor.new(self)
    executor.map_inputs(inputs)
  end

  def normalize_response(response)
    return { success: true, data: response } if response_mapping_code.blank?

    executor = Integrations::ActionCodeExecutor.new(self)
    executor.normalize_response(response)
  end

  # Simple fallback if no mapping code (direct pass-through)
  def fallback_mapping(inputs)
    { success: true, params: inputs.to_h }
  end

  # ============================================
  # TESTING
  # ============================================

  def test_mapping(test_inputs = nil)
    inputs = test_inputs || sample_input
    return { success: false, error: 'No test inputs provided' } if inputs.blank?

    validation = validate_inputs(inputs)
    return { success: false, errors: validation[:errors] } unless validation[:valid]

    mapped = map_inputs(inputs)
    {
      success: mapped[:success],
      inputs: inputs,
      mapped_params: mapped[:params],
      error: mapped[:error]
    }
  end

  # ============================================
  # HELPERS
  # ============================================

  def success_rate
    return 100.0 if usage_count.zero?
    (success_count.to_f / usage_count * 100).round(1)
  end

  def input_field_names
    input_schema.map { |f| f['name'] || f[:name] }
  end

  def required_fields
    input_schema.select { |f| f['required'] || f[:required] }.map { |f| f['name'] || f[:name] }
  end

  private

  def generate_slug
    self.slug ||= "#{integration.slug}.#{action_name.underscore}"
  end
end

