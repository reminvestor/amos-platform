class ToolDefinition < ApplicationRecord
  # Associations
  belongs_to :created_by, class_name: 'User', optional: true

  # Validations
  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
  validates :execution_type, inclusion: { in: %w[ruby_code http_request] }
  validate :validate_parameters_schema
  validate :validate_code_presence

  # Scopes
  scope :admin_only, -> { where(admin_only: true) }
  scope :public_tools, -> { where(admin_only: false) }

  def execute(args, context = {})
    case execution_type
    when 'ruby_code'
      execute_ruby_code(args, context)
    when 'http_request'
      execute_http_request(args)
    else
      raise "Unknown execution type: #{execution_type}"
    end
  end

  def to_bedrock_schema
    {
      name: name,
      description: description,
      parameters: parameters
    }
  end

  private

  def validate_parameters_schema
    return if parameters.blank?
    unless parameters.is_a?(Hash) && parameters.key?('type')
      errors.add(:parameters, "must be a valid JSON schema object")
    end
  end

  def validate_code_presence
    if execution_type == 'ruby_code' && code.blank?
      errors.add(:code, "can't be blank for ruby_code execution type")
    end
    if execution_type == 'http_request' && api_config.blank?
      errors.add(:api_config, "can't be blank for http_request execution type")
    end
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

