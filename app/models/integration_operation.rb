class IntegrationOperation < ApplicationRecord
  belongs_to :integration
  
  # Validations
  validates :operation_id, presence: true, uniqueness: { scope: :integration_id }
  validates :name, :http_method, :path_template, presence: true
  validates :http_method, inclusion: { in: %w[GET POST PUT PATCH DELETE HEAD OPTIONS] }
  
  # Enums
  enum :pagination_strategy, {
    no_pagination: 0,
    cursor: 1,
    page: 2,
    offset: 3,
    token: 4,
    link_header: 5
  }, prefix: true
  
  # Scopes
  scope :active, -> { where('deprecated_at IS NULL OR deprecated_at > ?', Time.current) }
  scope :reads, -> { where(http_method: 'GET') }
  scope :writes, -> { where(http_method: %w[POST PUT PATCH DELETE]) }
  scope :confirmable, -> { where(requires_confirmation: true) }
  
  # Default values
  after_initialize :set_defaults, if: :new_record?
  
  def deprecated?
    deprecated_at.present? && deprecated_at <= Time.current
  end
  
  def safe?
    http_method == 'GET' && !requires_confirmation
  end
  
  def write_operation?
    %w[POST PUT PATCH DELETE].include?(http_method)
  end
  
  def build_path(params = {})
    path = path_template.dup
    
    # Replace path parameters
    params.each do |key, value|
      path.gsub!("{#{key}}", value.to_s)
      path.gsub!(":#{key}", value.to_s)
    end
    
    # Ensure no unreplaced parameters remain
    if path.include?('{') || path.include?(':')
      missing = path.scan(/[{:](\w+)[}]?/).flatten
      raise ArgumentError, "Missing required path parameters: #{missing.join(', ')}"
    end
    
    path
  end
  
  def validate_request(params = {}, body = nil)
    errors = []
    
    # Validate request parameters against schema
    if request_schema.present? && request_schema['properties'].present?
      validator = JSONSchemer.schema(request_schema)
      validation_result = validator.validate(params)
      
      validation_result.each do |error|
        errors << format_validation_error(error)
      end
    end
    
    # Check required parameters
    if request_schema.present? && request_schema['required'].present?
      missing = request_schema['required'] - params.keys.map(&:to_s)
      errors << "Missing required parameters: #{missing.join(', ')}" if missing.any?
    end
    
    # Validate max limit
    if max_limit.present? && params['limit'].to_i > max_limit
      errors << "Limit exceeds maximum of #{max_limit}"
    end
    
    errors
  end
  
  def format_example_request
    return {} unless examples.present?
    
    {
      method: http_method,
      path: build_path(examples['path_params'] || {}),
      params: examples['query_params'],
      headers: examples['headers'],
      body: examples['body']
    }
  end
  
  private
  
  def set_defaults
    self.is_idempotent = false if is_idempotent.nil?
    self.requires_confirmation = false if requires_confirmation.nil?
    self.pagination_strategy ||= :no_pagination
    self.request_schema ||= {}
    self.response_schema ||= {}
    self.examples ||= {}
  end
  
  def format_validation_error(error)
    path = error['data_pointer'] || error['schema_pointer']
    "#{path}: #{error['error']}"
  end
end
