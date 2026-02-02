# frozen_string_literal: true

# IntegrationSchemaLearnerService - Self-correcting integration schemas
#
# When an integration call SUCCEEDS, this service learns from it and updates
# the operation's request_schema to prevent future mistakes.
#
# The goal: AMOS should never make the same mistake twice.
#
# How it works:
# 1. After a successful API call, we record the working parameters
# 2. If the schema is missing/incomplete, we add the working params
# 3. If we detect a pattern of failures followed by success, we update the schema
#    to prefer the successful approach
#
# Usage:
#   IntegrationSchemaLearnerService.learn_from_success(
#     operation: operation,
#     params: { limit: 10 },
#     response: { ... }
#   )
#
class IntegrationSchemaLearnerService
  # Minimum number of successful calls before we consider a pattern "learned"
  MIN_SUCCESSES_TO_LEARN = 2
  
  # Track recent failures to detect recovery patterns
  FAILURE_WINDOW = 1.hour
  
  class << self
    # Learn from a successful API call
    # Updates the operation's schema if we discover new valid parameters
    def learn_from_success(operation:, params:, response:, context: {})
      return unless operation.present? && params.present?
      
      Rails.logger.info "[SchemaLearner] Learning from successful call: #{operation.operation_id}"
      
      learner = new(operation)
      learner.record_success(params, response, context)
      learner.update_schema_if_needed(params)
      learner.update_examples_if_helpful(params, response)
    end
    
    # Learn from a failed API call
    # Records the failure pattern so we can correct it later
    def learn_from_failure(operation:, params:, error:, context: {})
      return unless operation.present?
      
      Rails.logger.info "[SchemaLearner] Recording failure: #{operation.operation_id} - #{error.to_s.truncate(100)}"
      
      learner = new(operation)
      learner.record_failure(params, error, context)
    end
    
    # Analyze an integration's operations and suggest schema improvements
    def analyze_integration(integration_slug)
      integration = Integration.find_by(slug: integration_slug)
      return { error: "Integration not found" } unless integration
      
      results = {
        integration: integration_slug,
        operations_analyzed: 0,
        schemas_updated: 0,
        suggestions: []
      }
      
      integration.integration_operations.enabled.find_each do |op|
        results[:operations_analyzed] += 1
        
        learner = new(op)
        suggestion = learner.suggest_improvements
        
        if suggestion[:should_update]
          results[:schemas_updated] += 1
          results[:suggestions] << {
            operation: op.operation_id,
            changes: suggestion[:changes]
          }
        end
      end
      
      results
    end
  end
  
  def initialize(operation)
    @operation = operation
    @integration = operation.integration
  end
  
  # Record a successful parameter combination
  def record_success(params, response, context = {})
    # Store in operation metadata for pattern analysis
    metadata = @operation.metadata || {}
    metadata['successful_calls'] ||= []
    
    # Keep last 10 successful parameter sets
    metadata['successful_calls'] = metadata['successful_calls'].last(9) + [{
      params: sanitize_params(params),
      timestamp: Time.current.iso8601,
      response_size: response.is_a?(Array) ? response.size : 1
    }]
    
    # Clear any recent failures for these params (they're now working)
    metadata['recent_failures'] ||= []
    failed_param_keys = params.keys.map(&:to_s).sort.join(',')
    metadata['recent_failures'].reject! do |f|
      f['param_keys'] == failed_param_keys
    end
    
    @operation.update_column(:metadata, metadata)
  end
  
  # Record a failed parameter combination
  def record_failure(params, error, context = {})
    metadata = @operation.metadata || {}
    metadata['recent_failures'] ||= []
    
    # Keep last 20 failures
    metadata['recent_failures'] = metadata['recent_failures'].last(19) + [{
      params: sanitize_params(params),
      error: error.to_s.truncate(500),
      timestamp: Time.current.iso8601,
      param_keys: params.keys.map(&:to_s).sort.join(',')
    }]
    
    @operation.update_column(:metadata, metadata)
    
    # If we see the same error pattern repeatedly, flag for correction
    detect_repeated_failures(metadata['recent_failures'])
  end
  
  # Update schema if the successful params reveal new valid parameters
  def update_schema_if_needed(successful_params)
    current_schema = @operation.request_schema || {}
    current_props = current_schema['properties'] || {}
    
    new_props = {}
    schema_updated = false
    
    successful_params.each do |key, value|
      key_str = key.to_s
      
      # Skip if already in schema
      next if current_props.key?(key_str)
      
      # Infer type from value
      inferred_type = infer_type(value)
      
      new_props[key_str] = {
        'type' => inferred_type,
        'description' => "Learned from successful API call (auto-discovered)",
        'learned_at' => Time.current.iso8601
      }
      
      schema_updated = true
      Rails.logger.info "[SchemaLearner] Discovered new param: #{key_str} (#{inferred_type}) for #{@operation.operation_id}"
    end
    
    if schema_updated
      updated_schema = current_schema.deep_dup
      updated_schema['properties'] ||= {}
      updated_schema['properties'].merge!(new_props)
      updated_schema['type'] ||= 'object'
      updated_schema['last_learned'] = Time.current.iso8601
      
      @operation.update!(request_schema: updated_schema)
      
      Rails.logger.info "[SchemaLearner] Updated schema for #{@operation.operation_id} with #{new_props.keys.join(', ')}"
    end
  end
  
  # Add helpful examples from successful calls
  def update_examples_if_helpful(params, response)
    return unless response.is_a?(Array) && response.size > 0
    
    current_examples = @operation.examples || {}
    
    # Only update if we don't have good examples yet
    return if current_examples.keys.length >= 3
    
    # Generate a meaningful example name
    example_name = generate_example_name(params)
    return if current_examples.key?(example_name)
    
    # For QuickBooks query operations, extract the query
    if params['query'].present? || params[:query].present?
      query = params['query'] || params[:query]
      current_examples[example_name] = query
    else
      # For other operations, show the param structure
      current_examples[example_name] = params.to_json
    end
    
    @operation.update!(examples: current_examples)
    Rails.logger.info "[SchemaLearner] Added example '#{example_name}' for #{@operation.operation_id}"
  end
  
  # Suggest schema improvements based on historical data
  def suggest_improvements
    metadata = @operation.metadata || {}
    successes = metadata['successful_calls'] || []
    failures = metadata['recent_failures'] || []
    
    suggestions = {
      should_update: false,
      changes: []
    }
    
    # Find parameters that always succeed vs always fail
    if failures.any? && successes.any?
      failure_params = failures.flat_map { |f| f['params']&.keys }.compact.tally
      success_params = successes.flat_map { |s| s['params']&.keys }.compact.tally
      
      # Parameters that appear in failures but not successes = likely invalid
      bad_params = failure_params.keys - success_params.keys
      
      if bad_params.any?
        suggestions[:should_update] = true
        suggestions[:changes] << {
          type: 'mark_invalid',
          params: bad_params,
          reason: 'These parameters appear only in failed calls'
        }
        
        # Actually mark them as deprecated in the schema
        mark_params_deprecated(bad_params)
      end
    end
    
    suggestions
  end
  
  private
  
  def sanitize_params(params)
    # Remove sensitive data, keep structure
    params.transform_values do |v|
      case v
      when String
        v.length > 100 ? "#{v[0..50]}... (truncated)" : v
      when Hash
        sanitize_params(v)
      else
        v
      end
    end
  end
  
  def infer_type(value)
    case value
    when Integer then 'integer'
    when Float then 'number'
    when TrueClass, FalseClass then 'boolean'
    when Array then 'array'
    when Hash then 'object'
    else 'string'
    end
  end
  
  def generate_example_name(params)
    if params['query'].present? || params[:query].present?
      query = params['query'] || params[:query]
      # Extract entity and filter from query
      if query.match?(/WHERE.*Balance\s*>\s*'0'/i)
        'open_items'
      elsif query.match?(/WHERE.*Balance\s*=\s*'0'/i)
        'paid_items'
      elsif query.match?(/WHERE.*Active\s*=\s*true/i)
        'active_items'
      elsif query.match?(/WHERE/i)
        'filtered_query'
      else
        'all_items'
      end
    else
      "example_#{params.keys.first(2).join('_')}"
    end
  end
  
  def detect_repeated_failures(failures)
    return if failures.length < 3
    
    # Check if same error repeated 3+ times
    recent = failures.last(5)
    error_counts = recent.group_by { |f| f['error']&.first(100) }
    
    repeated = error_counts.find { |_err, items| items.length >= 3 }
    
    if repeated
      error_pattern, instances = repeated
      Rails.logger.warn "[SchemaLearner] Repeated failure detected for #{@operation.operation_id}: #{error_pattern}"
      
      # Extract common bad parameters
      bad_params = instances.flat_map { |i| i['params']&.keys }.compact.tally
                           .select { |_k, count| count >= 2 }.keys
      
      if bad_params.any?
        mark_params_deprecated(bad_params)
      end
    end
  end
  
  def mark_params_deprecated(param_names)
    return if param_names.empty?
    
    schema = @operation.request_schema || {}
    schema['deprecated_params'] ||= []
    
    new_deprecated = param_names - schema['deprecated_params']
    return if new_deprecated.empty?
    
    schema['deprecated_params'] += new_deprecated
    schema['deprecated_params'].uniq!
    
    # Also add a note to the description
    if schema['properties']
      new_deprecated.each do |param|
        if schema['properties'][param]
          schema['properties'][param]['deprecated'] = true
          schema['properties'][param]['description'] = 
            "[DEPRECATED - causes failures] " + (schema['properties'][param]['description'] || '')
        end
      end
    end
    
    @operation.update!(request_schema: schema)
    Rails.logger.warn "[SchemaLearner] Marked params as deprecated for #{@operation.operation_id}: #{new_deprecated.join(', ')}"
  end
end
