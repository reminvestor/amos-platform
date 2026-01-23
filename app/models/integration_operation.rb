class IntegrationOperation < ApplicationRecord
  belongs_to :integration
  has_many :integration_actions, dependent: :nullify

  # Callbacks
  after_create :schedule_action_generation, if: :should_auto_generate_action?

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
  scope :active, -> { where("deprecated_at IS NULL OR deprecated_at > ?", Time.current) }
  scope :enabled, -> { where(is_enabled: true) }
  scope :disabled, -> { where(is_enabled: false) }
  scope :reads, -> { where(http_method: "GET") }
  scope :writes, -> { where(http_method: %w[POST PUT PATCH DELETE]) }
  scope :confirmable, -> { where(requires_confirmation: true) }

  # Vector search configuration
  has_neighbors :embedding

  # Update embedding when relevant fields change
  after_save :update_embedding, if: -> { saved_change_to_name? || saved_change_to_description? || saved_change_to_path_template? }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Class methods for vector search
  def self.search_by_similarity(query, limit: 5)
    query_embedding = AiAgents::VectorStore.instance.generate_embedding(query)
    return none if query_embedding.nil?

    enabled.nearest_neighbors(:embedding, query_embedding, distance: "cosine").first(limit)
  rescue => e
    Rails.logger.error "Operation vector search failed: #{e.message}"
    enabled.limit(limit)
  end

  def deprecated?
    deprecated_at.present? && deprecated_at <= Time.current
  end

  def safe?
    http_method == "GET" && !requires_confirmation
  end

  def write_operation?
    %w[POST PUT PATCH DELETE].include?(http_method)
  end

  def build_path(params = {}, credentials = {})
    path = path_template.dup

    # Combine both credentials and params for substitution
    all_params = credentials.merge(params)
    
    # Find all placeholders in the path
    placeholders = path.scan(/[{:](\w+)[}]?/).flatten.uniq
    
    # Replace each placeholder with smart matching
    placeholders.each do |placeholder|
      value = find_param_value(placeholder, all_params)
      
      if value
        path.gsub!("{#{placeholder}}", value.to_s)
        path.gsub!(":#{placeholder}", value.to_s)
      end
    end

    # Ensure no unreplaced parameters remain
    if path.include?("{") || path.include?(":")
      missing = path.scan(/[{:](\w+)[}]?/).flatten
      raise ArgumentError, "Missing required path parameters: #{missing.join(', ')}"
    end

    path
  end
  
  private
  
  # Smart parameter matching - tries multiple naming conventions
  def find_param_value(placeholder, params)
    # Try exact match first (both string and symbol)
    return params[placeholder] if params.key?(placeholder)
    return params[placeholder.to_sym] if params.key?(placeholder.to_sym)
    
    # Convert placeholder to snake_case and try
    snake_case = placeholder.underscore
    return params[snake_case] if params.key?(snake_case)
    return params[snake_case.to_sym] if params.key?(snake_case.to_sym)
    
    # Convert placeholder to camelCase and try
    camel_case = snake_case.camelize(:lower)
    return params[camel_case] if params.key?(camel_case)
    return params[camel_case.to_sym] if params.key?(camel_case.to_sym)
    
    # Try known aliases
    case placeholder.downcase
    when "companyid", "company_id"
      params[:realmId] || params[:realm_id] || params["realmId"] || params["realm_id"]
    when "realmid", "realm_id"
      params[:companyId] || params[:company_id] || params["companyId"] || params["company_id"]
    else
      nil
    end
  end
  
  public

  def validate_request(params = {}, body = nil)
    errors = []

    # Validate request parameters against schema
    if request_schema.present? && request_schema["properties"].present?
      validator = JSONSchemer.schema(request_schema)
      validation_result = validator.validate(params)

      validation_result.each do |error|
        errors << format_validation_error(error)
      end
    end

    # Check required parameters
    if request_schema.present? && request_schema["required"].present?
      missing = request_schema["required"] - params.keys.map(&:to_s)
      errors << "Missing required parameters: #{missing.join(', ')}" if missing.any?
    end

    # Validate max limit
    if max_limit.present? && params["limit"].to_i > max_limit
      errors << "Limit exceeds maximum of #{max_limit}"
    end

    errors
  end

  def format_example_request
    return {} unless examples.present?

    {
      method: http_method,
      path: build_path(examples["path_params"] || {}),
      params: examples["query_params"],
      headers: examples["headers"],
      body: examples["body"]
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
    path = error["data_pointer"] || error["schema_pointer"]
    "#{path}: #{error['error']}"
  end

  def update_embedding
    embedding_text = <<~TEXT
      Operation: #{name}
      Integration: #{integration&.name}
      Method: #{http_method}
      Path: #{path_template}
      Description: #{description}
    TEXT

    vector = AiAgents::VectorStore.instance.generate_embedding(embedding_text)
    return unless vector

    update_column(:embedding, vector)
  rescue => e
    Rails.logger.error "Failed to update embedding for operation #{id}: #{e.message}"
  end

  # ============================================
  # ACTION AUTO-GENERATION
  # ============================================

  def should_auto_generate_action?
    # Only auto-generate if:
    # 1. Integration has auto_generate_actions enabled
    # 2. Not a test connection operation
    # 3. No action exists yet
    return false unless integration&.metadata&.dig('auto_generate_actions')
    return false if operation_id.include?('test_connection')
    !has_action?
  end

  def has_action?
    integration_actions.exists?
  end

  def schedule_action_generation
    # Run async to not slow down operation creation
    GenerateIntegrationActionJob.perform_later(id)
  rescue => e
    Rails.logger.warn "[IntegrationOperation] Could not schedule action generation: #{e.message}"
  end

  # Generate action synchronously (for manual triggering)
  def generate_action!(options = {})
    Integrations::ActionGeneratorService.generate_for_operation(self, options)
  end
end
