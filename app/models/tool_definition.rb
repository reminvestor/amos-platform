class ToolDefinition < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :entity, optional: true  # nil = available to all entities
  belongs_to :app_module, optional: true  # If part of an extensible module

  # Validations
  # Scope uniqueness to entity_id - allows same tool name in different tenants
  # For global tools (entity_id: nil), name must be globally unique among global tools
  validates :name, presence: true, uniqueness: { scope: :entity_id }, format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
  validates :execution_type, inclusion: { in: %w[ruby_code http_request] }
  validate :validate_parameters_schema
  validate :validate_code_presence
  validate :run_security_audit, if: :security_check_needed?

  # Callbacks
  before_save :normalize_parameters_schema

  # Scopes
  scope :admin_only, -> { where(admin_only: true) }
  scope :public_tools, -> { where(admin_only: false) }
  scope :for_entity, ->(entity) { where(entity: entity).or(where(entity: nil)) }
  scope :created_by, ->(user) { where(created_by: user) }
  scope :editable_by, ->(user) { user.admin? ? all : where(created_by: user) }
  scope :scout_accessible, -> { where(scout_accessible: true) }

  # Instance methods for ownership
  def editable_by?(user)
    return true if user.admin?
    return false if created_by_id.nil? # System tools can't be edited by non-admins
    created_by_id == user.id
  end

  def owned_by?(user)
    created_by_id == user.id
  end

  def execute(args, context = {})
    # Only block tools that explicitly failed security check
    # "review" and "pass" rated tools are allowed to execute
    if security_rating == 'fail'
       return { error: "Tool execution blocked due to security concerns: #{security_reason}", success: false }
    end
    
    # Log a warning for "review" rated tools but allow execution
    if security_rating == 'review'
      Rails.logger.warn "⚠️ Executing tool '#{name}' with security_rating=review: #{security_reason}"
    end

    case execution_type
    when 'ruby_code'
      execute_ruby_code(args, context)
    when 'http_request'
      execute_http_request(args)
    else
      raise "Unknown execution type: #{execution_type}"
    end
  end

  def run_security_audit
    service = SecurityCheckService.new
    result = service.evaluate_tool(self)
    
    self.security_rating = result["rating"]
    self.security_reason = result["reason"]
    
    if self.security_rating == 'fail'
      errors.add(:base, "Security Audit Failed: #{self.security_reason}")
    end
  rescue => e
    Rails.logger.error "Security check failed: #{e.message}"
    errors.add(:base, "Security check system unavailable. Please try again later.")
  end

  def security_check_needed?
    (code_changed? || api_config_changed? || new_record?)
  end


  def to_bedrock_schema
    {
      name: name,
      description: description,
      parameters: parameters
    }
  end

  # Vector search configuration
  has_neighbors :embedding

  # Update embedding when relevant fields change
  after_save :update_embedding, if: -> { saved_change_to_name? || saved_change_to_description? || saved_change_to_parameters? || (saved_change_to_is_public? && is_public) }

  # Class methods
  def self.search_by_similarity(query, limit: 5)
    # Generate embedding for the query
    query_embedding = AiAgents::VectorStore.instance.generate_embedding(query)
    
    # Use pgvector nearest_neighbors search
    # We assume RAG should return public tools or tools created by the user (handled by controller/service layer usually, but for pure semantic search we can filter after)
    # Here we return all matches, caller must filter by permission
    nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(limit)
  rescue => e
    Rails.logger.error "Vector search failed: #{e.message}"
    # Fallback to keyword search if vector search fails
    where("description ILIKE ? OR name ILIKE ?", "%#{query}%", "%#{query}%").limit(limit)
  end

  private

  def update_embedding
    # Construct a rich text representation of the tool
    embedding_text = <<~TEXT
      Tool: #{name}
      Description: #{description}
      Parameters: #{parameters.to_json}
      Type: #{execution_type}
    TEXT
    
    # Generate embedding using VectorStore service
    vector = AiAgents::VectorStore.instance.generate_embedding(embedding_text)
    
    # Update the column directly to avoid triggering callbacks again
    update_column(:embedding, vector)
  rescue => e
    Rails.logger.error "Failed to update embedding for tool #{id}: #{e.message}"
  end

  def validate_parameters_schema
    return if parameters.blank?
    unless parameters.is_a?(Hash) && parameters.key?('type')
      errors.add(:parameters, "must be a valid JSON schema object")
      return
    end
    
    # Validate properties structure for JSON Schema 2020-12 compliance
    if parameters['properties'].is_a?(Hash)
      parameters['properties'].each do |prop_name, prop_def|
        next unless prop_def.is_a?(Hash)
        
        # Check for empty enum arrays (invalid in JSON Schema 2020-12)
        if prop_def.key?('enum') && (!prop_def['enum'].is_a?(Array) || prop_def['enum'].empty?)
          errors.add(:parameters, "property '#{prop_name}' has invalid enum (must be non-empty array)")
        end
        
        # Check for missing type in properties
        unless prop_def.key?('type') || prop_def.key?('$ref') || prop_def.key?('anyOf') || prop_def.key?('oneOf') || prop_def.key?('allOf') || prop_def.key?('enum')
          errors.add(:parameters, "property '#{prop_name}' is missing 'type' field")
        end
      end
    end
  end
  
  # Sanitize schema to fix common JSON Schema 2020-12 issues
  def self.sanitize_schema(schema)
    return schema unless schema.is_a?(Hash)
    
    sanitized = schema.deep_dup
    
    if sanitized['properties'].is_a?(Hash)
      sanitized['properties'].each do |prop_name, prop_def|
        next unless prop_def.is_a?(Hash)
        
        # Remove empty enum arrays
        if prop_def.key?('enum') && (!prop_def['enum'].is_a?(Array) || prop_def['enum'].empty?)
          prop_def.delete('enum')
          Rails.logger.warn "[ToolDefinition] Removed invalid empty enum from property '#{prop_name}'"
        end
        
        # Add default type if missing
        unless prop_def.key?('type') || prop_def.key?('$ref') || prop_def.key?('anyOf') || prop_def.key?('oneOf') || prop_def.key?('allOf') || prop_def.key?('enum')
          prop_def['type'] = 'string'
          Rails.logger.warn "[ToolDefinition] Added default type 'string' to property '#{prop_name}'"
        end
      end
    end
    
    sanitized
  end

  def validate_code_presence
    if execution_type == 'ruby_code' && code.blank?
      errors.add(:code, "can't be blank for ruby_code execution type")
    end
    if execution_type == 'http_request' && api_config.blank?
      errors.add(:api_config, "can't be blank for http_request execution type")
    end
  end

  # Fix the nested schema bug where AI agents accidentally wrap schemas inside properties
  # This detects and unwraps incorrectly nested schemas before saving
  def normalize_parameters_schema
    return unless parameters.is_a?(Hash)

    params = parameters.with_indifferent_access

    # Check for the nested schema bug: properties contains type/required/properties keys
    if params[:properties].is_a?(Hash)
      nested_keys = params[:properties].keys.map(&:to_s) & %w[type required properties]
      
      if nested_keys.include?('properties') && nested_keys.include?('type')
        Rails.logger.warn "[ToolDefinition] Fixing incorrectly nested schema for tool '#{name}'"
        
        # Extract the real schema from the nested structure
        nested_schema = params[:properties].with_indifferent_access
        real_properties = nested_schema[:properties]
        real_required = nested_schema[:required]
        
        if real_properties.is_a?(Hash)
          # Remove schema keys that were incorrectly placed in properties
          clean_properties = real_properties.reject { |k, _| %w[type required properties].include?(k.to_s) }
          
          self.parameters = {
            'type' => 'object',
            'properties' => clean_properties.deep_stringify_keys,
            'required' => real_required.is_a?(Array) ? real_required : []
          }
          
          Rails.logger.info "[ToolDefinition] ✅ Fixed nested schema for tool '#{name}'"
        end
      end
    end
    
    # Ensure basic structure
    self.parameters['type'] ||= 'object' if parameters.is_a?(Hash)
    self.parameters['properties'] ||= {} if parameters.is_a?(Hash)
    self.parameters['required'] ||= [] if parameters.is_a?(Hash)
  end

  def execute_ruby_code(args, context)
    # SECURITY: This is a simplified implementation. 
    # In production, this must run in a secure sandbox (e.g., separate container/process).
    # For now, we only allow admins to create these tools.
    
    # We wrap the code in a Proc
    # The code should return the result
    
    # Make args available as a local variable
    _args = args
    _context = context
    
    begin
      # Bindings for the eval
      eval(code)
    rescue => e
      Rails.logger.error "Tool Execution Error (#{name}): #{e.message}"
      { error: e.message, backtrace: e.backtrace.first(5) }
    end
  end

  def execute_http_request(args)
    require 'net/http'
    require 'uri'
    
    url_template = api_config['url']
    method = api_config['method'] || 'GET'
    headers = api_config['headers'] || {}
    
    # Interpolate args into URL if needed (e.g., https://api.com/users/{{user_id}})
    url = url_template.gsub(/\{\{(\w+)\}\}/) { args[$1] }
    
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    
    request = case method.upcase
              when 'GET' then Net::HTTP::Get.new(uri)
              when 'POST' then Net::HTTP::Post.new(uri)
              when 'PUT' then Net::HTTP::Put.new(uri)
              when 'DELETE' then Net::HTTP::Delete.new(uri)
              else raise "Unsupported method: #{method}"
              end
              
    headers.each { |k, v| request[k] = v }
    
    # If POST/PUT, send args as body
    if %w[POST PUT].include?(method.upcase)
      request.body = args.to_json
      request['Content-Type'] = 'application/json'
    end
    
    response = http.request(request)
    
    begin
      JSON.parse(response.body)
    rescue
      response.body
    end
  end
end

