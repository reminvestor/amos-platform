module Factories
  class IntegrationFactory
    attr_reader :user, :entity, :errors, :warnings

    # The Integration Factory validates and creates integrations.
    # 
    # It does NOT prescribe how APIs should work - it validates that:
    # 1. Required fields are present
    # 2. URLs are valid and not internal
    # 3. Auth configuration is complete for the chosen auth_type
    # 4. Operations have valid paths and methods
    #
    # The agent is responsible for researching the API and providing accurate info.
    # The factory ensures the configuration is structurally valid.

    # These come from the Integration model's enum
    VALID_AUTH_TYPES = %w[api_key bearer_token basic_auth oauth2 custom].freeze
    
    # These come from the IntegrationOperation model
    VALID_HTTP_METHODS = %w[GET POST PUT PATCH DELETE HEAD OPTIONS].freeze
    VALID_PAGINATION_STRATEGIES = %w[no_pagination cursor page offset token link_header].freeze
    
    # These come from the Integration model's category validation
    VALID_CATEGORIES = %w[payment ecommerce crm communication productivity marketing analytics custom].freeze

    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @errors = []
      @warnings = []
    end

    # Validate integration configuration
    # Returns detailed feedback on what's missing or wrong
    def validate(params)
      @errors = []
      @warnings = []
      params = params.with_indifferent_access

      # === Required Fields ===
      validate_required!(:name, params[:name], "Integration name")
      validate_required!(:auth_type, params[:auth_type], "Authentication type")
      validate_required!(:base_url, params[:base_url], "API base URL")

      return validation_result if @errors.any?

      # === Field Validations ===
      validate_name!(params[:name])
      validate_slug!(params[:slug]) if params[:slug].present?
      validate_auth_type!(params[:auth_type])
      validate_url!(:base_url, params[:base_url])
      validate_category!(params[:category]) if params[:category].present?

      # === Auth-Specific Validations ===
      validate_auth_config!(params)

      # === Operations Validations ===
      validate_operations!(params[:operations]) if params[:operations].present?

      # === Warnings (non-blocking) ===
      add_warnings!(params)

      validation_result
    end

    # Create integration after validation passes
    def create(params)
      params = params.with_indifferent_access
      
      # Validate first
      validation = validate(params)
      unless validation[:ready_to_create]
        return failure_result
      end

      # Check user limits
      unless @user.admin?
        current_count = custom_integrations_count
        limit = @user.integrations_limit || 5
        
        if current_count >= limit
          @errors << "You have reached your limit of #{limit} custom integrations"
          return failure_result
        end
      end

      begin
        ActiveRecord::Base.transaction do
          integration = create_integration!(params)
          connection = create_connection!(integration, params)
          create_credential!(connection, params)
          create_oauth_config!(integration, params) if params[:auth_type].to_s == 'oauth2'
          operations = create_operations!(integration, params[:operations])

          {
            success: true,
            integration: integration,
            connection: connection,
            operations_created: operations,
            warnings: @warnings,
            next_steps: build_next_steps(integration, params)
          }
        end
      rescue ActiveRecord::RecordInvalid => e
        @errors << "Database validation failed: #{e.message}"
        failure_result
      rescue => e
        Rails.logger.error "IntegrationFactory error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        @errors << "Unexpected error: #{e.message}"
        failure_result
      end
    end

    # Update existing integration
    def update(identifier, params)
      @errors = []
      @warnings = []
      params = params.with_indifferent_access

      integration = find_integration(identifier)
      unless integration
        @errors << "Integration not found: #{identifier}"
        return failure_result
      end

      unless can_edit?(integration)
        @errors << "You don't have permission to edit this integration"
        return failure_result
      end

      # Validate only the fields being updated
      validate_name!(params[:name], exclude_id: integration.id) if params[:name].present?
      validate_url!(:base_url, params[:base_url]) if params[:base_url].present?
      validate_category!(params[:category]) if params[:category].present?
      validate_operations!(params[:operations]) if params[:operations].present?

      return failure_result if @errors.any?

      begin
        ActiveRecord::Base.transaction do
          update_integration!(integration, params)
          operations = create_operations!(integration, params[:operations]) if params[:operations].present?

          {
            success: true,
            integration: integration.reload,
            operations_created: operations || [],
            warnings: @warnings
          }
        end
      rescue => e
        @errors << "Update failed: #{e.message}"
        failure_result
      end
    end

    # Add operation to existing integration
    def add_operation(identifier, operation_params)
      @errors = []
      @warnings = []

      integration = find_integration(identifier)
      unless integration
        @errors << "Integration not found: #{identifier}"
        return failure_result
      end

      unless can_edit?(integration)
        @errors << "You don't have permission to edit this integration"
        return failure_result
      end

      validate_operation!(operation_params.with_indifferent_access)
      return failure_result if @errors.any?

      begin
        operation = create_single_operation!(integration, operation_params)
        {
          success: true,
          operation: operation,
          warnings: @warnings
        }
      rescue => e
        @errors << "Failed to add operation: #{e.message}"
        failure_result
      end
    end

    private

    # ============================================================
    # VALIDATION METHODS - These are the guardrails
    # ============================================================

    def validate_required!(field, value, label)
      @errors << "#{label} is required" if value.blank?
    end

    def validate_name!(name, exclude_id: nil)
      return if name.blank?

      @errors << "Name must be at least 2 characters" if name.length < 2
      @errors << "Name must be less than 100 characters" if name.length > 100

      scope = Integration.where(name: name)
      scope = scope.where.not(id: exclude_id) if exclude_id
      @errors << "An integration named '#{name}' already exists" if scope.exists?
    end

    def validate_slug!(slug)
      return if slug.blank?

      unless slug.match?(/\A[a-z][a-z0-9_]*\z/)
        @errors << "Slug must be lowercase, start with a letter, and contain only letters, numbers, and underscores"
      end

      @errors << "An integration with this slug already exists" if Integration.exists?(slug: slug)
    end

    def validate_auth_type!(auth_type)
      return if auth_type.blank?
      
      unless VALID_AUTH_TYPES.include?(auth_type.to_s)
        @errors << "auth_type must be one of: #{VALID_AUTH_TYPES.join(', ')}"
      end
    end

    def validate_url!(field_name, url)
      return if url.blank?

      begin
        uri = URI.parse(url)
        
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          @errors << "#{field_name} must be a valid HTTP or HTTPS URL"
          return
        end

        # Security: Block internal/private network URLs
        host = uri.host.to_s.downcase
        if internal_host?(host)
          @errors << "#{field_name} cannot point to internal/private networks (security restriction)"
        end

      rescue URI::InvalidURIError
        @errors << "#{field_name} is not a valid URL"
      end
    end

    def validate_category!(category)
      return if category.blank?
      
      unless VALID_CATEGORIES.include?(category.to_s)
        @warnings << "Category '#{category}' is not standard. Valid: #{VALID_CATEGORIES.join(', ')}"
      end
    end

    def validate_auth_config!(params)
      auth_type = params[:auth_type].to_s

      case auth_type
      when 'oauth2'
        # OAuth2 requires authorize_url and token_url
        validate_required!(:authorize_url, params[:authorize_url], "OAuth authorize URL")
        validate_required!(:token_url, params[:token_url], "OAuth token URL")
        validate_url!(:authorize_url, params[:authorize_url]) if params[:authorize_url].present?
        validate_url!(:token_url, params[:token_url]) if params[:token_url].present?
        
        # OAuth URLs should be HTTPS
        [:authorize_url, :token_url].each do |field|
          url = params[field]
          if url.present? && !url.start_with?('https://')
            @warnings << "#{field} should use HTTPS for security"
          end
        end
      end
      
      # Other auth types don't have strict requirements - the system handles defaults
    end

    def validate_operations!(operations)
      return if operations.blank?

      unless operations.is_a?(Array)
        @errors << "operations must be an array"
        return
      end

      operations.each_with_index do |op, idx|
        validate_operation!(op.with_indifferent_access, "operations[#{idx}]")
      end
    end

    def validate_operation!(op, prefix = "operation")
      # Required: name and path
      @errors << "#{prefix}.name is required" if op[:name].blank?
      @errors << "#{prefix}.path is required" if op[:path].blank?

      # HTTP method validation
      method = (op[:method] || op[:http_method] || 'GET').to_s.upcase
      unless VALID_HTTP_METHODS.include?(method)
        @errors << "#{prefix}.method must be one of: #{VALID_HTTP_METHODS.join(', ')}"
      end

      # Path should start with /
      if op[:path].present? && !op[:path].start_with?('/')
        @warnings << "#{prefix}.path should start with '/'"
      end

      # Pagination strategy validation
      if op[:pagination_strategy].present?
        unless VALID_PAGINATION_STRATEGIES.include?(op[:pagination_strategy].to_s)
          @warnings << "#{prefix}.pagination_strategy should be one of: #{VALID_PAGINATION_STRATEGIES.join(', ')}"
        end
      end
    end

    def add_warnings!(params)
      # Suggest test endpoint if not provided
      unless params[:test_endpoint].present? || has_test_operation?(params[:operations])
        @warnings << "Consider adding a test_endpoint to verify credentials work"
      end

      # Suggest documentation URL
      unless params[:documentation_url].present?
        @warnings << "Consider adding documentation_url for future reference"
      end
    end

    def has_test_operation?(operations)
      return false if operations.blank?
      operations.any? { |op| 
        name = (op[:name] || op['name']).to_s.downcase
        name.include?('test') || name.include?('health') || name.include?('ping')
      }
    end

    def internal_host?(host)
      host.match?(/^(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|\[::1\])$/i)
    end

    # ============================================================
    # CREATION METHODS - Build the records
    # ============================================================

    def create_integration!(params)
      slug = params[:slug] || generate_slug(params[:name])
      
      Integration.create!(
        name: params[:name],
        slug: slug,
        description: params[:description] || "Integration with #{params[:name]}",
        category: params[:category] || 'custom',
        auth_type: params[:auth_type],
        api_base_url: normalize_url(params[:base_url]),
        allowed_hosts: extract_hosts(params[:base_url], params[:allowed_hosts]),
        documentation_url: params[:documentation_url],
        is_active: true,
        is_verified: false,
        auth_config: build_auth_config(params),
        metadata: build_metadata(params)
      )
    end

    def create_connection!(integration, params)
      Connection.create!(
        integration: integration,
        entity: @entity,
        name: "#{params[:name]} Connection",
        status: :disconnected,
        metadata: {
          created_by: 'integration_factory',
          setup_required: true
        }
      )
    end

    def create_credential!(connection, params)
      connection.integration_credentials.create!(
        name: "#{connection.name} Credentials",
        credentials: {}.to_json,
        auth_method: auth_method_for(params[:auth_type]),
        status: :expired,
        metadata: {
          pending_setup: true,
          setup_instructions: params[:setup_instructions]
        }.compact
      )
    end

    def create_oauth_config!(integration, params)
      OauthConfiguration.create!(
        integration: integration,
        client_id: params[:client_id] || '',
        client_secret: params[:client_secret] || '',
        redirect_uri: params[:redirect_uri] || default_redirect_uri(integration),
        authorize_url: params[:authorize_url],
        token_url: params[:token_url],
        scopes: Array(params[:scopes]).join(','),
        callback_params: Array(params[:callback_params]),
        test_endpoint: params[:test_endpoint],
        status: :inactive,
        metadata: { pending_setup: true }
      )
    end

    def create_operations!(integration, operations)
      return [] if operations.blank?

      operations.filter_map do |op|
        create_single_operation!(integration, op)
      end
    end

    def create_single_operation!(integration, op)
      op = op.with_indifferent_access
      
      name = op[:name]
      operation_id = "#{integration.slug}.#{op[:operation_id] || name.underscore.gsub(/\s+/, '_')}"
      method = (op[:method] || op[:http_method] || 'GET').to_s.upcase

      # Skip if already exists
      if integration.integration_operations.exists?(operation_id: operation_id)
        @warnings << "Operation '#{name}' already exists, skipping"
        return nil
      end

      integration.integration_operations.create!(
        operation_id: operation_id,
        name: name.titleize,
        description: op[:description] || "#{name.titleize} operation",
        http_method: method,
        path_template: op[:path],
        request_schema: op[:request_schema] || op[:parameters] || {},
        response_schema: op[:response_schema] || {},
        pagination_strategy: op[:pagination_strategy] || 'no_pagination',
        max_limit: op[:max_limit],
        is_idempotent: method == 'GET',
        requires_confirmation: %w[DELETE POST PUT PATCH].include?(method),
        is_enabled: true,
        documentation: op[:documentation],
        examples: op[:examples],
        metadata: { created_by: 'integration_factory', created_at: Time.current }
      )
    end

    def update_integration!(integration, params)
      attrs = {}
      
      attrs[:name] = params[:name] if params[:name].present?
      attrs[:description] = params[:description] if params[:description].present?
      attrs[:api_base_url] = normalize_url(params[:base_url]) if params[:base_url].present?
      attrs[:category] = params[:category] if params[:category].present?
      attrs[:documentation_url] = params[:documentation_url] if params[:documentation_url].present?
      attrs[:is_active] = params[:is_active] if params.key?(:is_active)

      if params[:base_url].present?
        attrs[:allowed_hosts] = extract_hosts(params[:base_url])
      end

      integration.update!(attrs) if attrs.any?
    end

    # ============================================================
    # HELPER METHODS
    # ============================================================

    def build_auth_config(params)
      config = {}
      auth_type = params[:auth_type].to_s

      # Copy relevant auth config fields
      auth_fields = %i[
        auth_method auth_field_name auth_header_prefix auth_header_name
        username_label password_label password_required username_help_text
        authorize_url token_url scopes use_basic_auth
        test_endpoint setup_instructions
      ]

      auth_fields.each do |field|
        config[field] = params[field] if params[field].present?
      end

      # Set sensible defaults based on auth_type
      case auth_type
      when 'api_key'
        config[:auth_method] ||= 'header'
        config[:auth_field_name] ||= params[:auth_header_name] || 'X-API-Key'
      when 'bearer_token'
        config[:auth_method] ||= 'header'
        config[:auth_field_name] ||= 'Authorization'
        config[:auth_header_prefix] ||= 'Bearer'
      when 'basic_auth'
        config[:auth_method] ||= 'basic'
        config[:username_label] ||= 'Username'
        config[:password_required] = true if config[:password_required].nil?
      when 'oauth2'
        # OAuth config is stored in OauthConfiguration model
      end

      config
    end

    def build_metadata(params)
      {
        created_by: 'integration_factory',
        created_at: Time.current,
        owner_entity_id: @entity.id,
        owner_user_id: @user.id,
        custom: true,
        api_version: params[:api_version],
        rate_limits: params[:rate_limits]
      }.compact
    end

    def build_next_steps(integration, params)
      steps = ["Add your credentials via Settings > Integrations > #{integration.name}"]
      
      if integration.auth_type == 'oauth2'
        steps << "Click 'Connect' to authorize with #{integration.name}"
      else
        steps << "Enter your API key/credentials and click 'Test Connection'"
      end
      
      steps << "Once connected, use execute_integration to call API operations"
      steps
    end

    def generate_slug(name)
      return nil if name.blank?
      name.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_|_$/, '')
    end

    def normalize_url(url)
      return url if url.blank?
      url.chomp('/')
    end

    def extract_hosts(base_url, additional_hosts = nil)
      hosts = []
      
      if base_url.present?
        begin
          uri = URI.parse(base_url)
          hosts << uri.host if uri.host
        rescue; end
      end

      hosts.concat(Array(additional_hosts)) if additional_hosts.present?
      hosts.uniq.compact
    end

    def auth_method_for(auth_type)
      case auth_type.to_s
      when 'api_key' then 'header'
      when 'bearer_token' then 'bearer'
      when 'basic_auth' then 'basic'
      when 'oauth2' then 'bearer'
      else 'header'
      end
    end

    def default_redirect_uri(integration)
      base = ENV['APP_URL'] || 'https://app.amoslabs.com'
      "#{base}/integrations/callback/#{integration.slug}"
    end

    def find_integration(identifier)
      return identifier if identifier.is_a?(Integration)
      
      Integration.find_by(id: identifier) ||
        Integration.find_by(slug: identifier) ||
        Integration.find_by(name: identifier)
    end

    def can_edit?(integration)
      return true if @user.admin?
      
      owner_entity_id = integration.metadata&.dig('owner_entity_id')
      owner_entity_id.to_s == @entity.id.to_s
    end

    def custom_integrations_count
      Integration.where("metadata->>'owner_entity_id' = ?", @entity.id.to_s)
                 .where("metadata->>'custom' = 'true'")
                 .count
    end

    def validation_result
      {
        success: @errors.empty?,
        errors: @errors,
        warnings: @warnings,
        ready_to_create: @errors.empty?
      }
    end

    def failure_result
      {
        success: false,
        errors: @errors,
        warnings: @warnings
      }
    end
  end
end
