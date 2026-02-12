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
    VALID_AUTH_TYPES = %w[api_key bearer_token basic_auth oauth2 no_auth custom].freeze
    
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
    # Options:
    #   run_acceptance_tests: Run full test-driven creation with AI-generated tests (3 attempts)
    #   max_test_attempts: Override default 3 attempts
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
        limit = @user.integrations_limit || 1000
        
        if current_count >= limit
          @errors << "You have reached your limit of #{limit} custom integrations"
          return failure_result
        end
      end

      begin
        integration = nil
        connection = nil
        operations = nil
        
        ActiveRecord::Base.transaction do
          integration = create_integration!(params)
          connection = create_connection!(integration, params)
          create_credential!(connection, params)
          
          # Create OauthConfiguration for all integrations (needed for AuthConfigs)
          # For OAuth2, this stores OAuth URLs; for others, it just holds AuthConfigs
          create_oauth_config!(integration, params)
          
          operations = create_operations!(integration, params[:operations])
        end

        # Run acceptance tests if requested (outside transaction so we can see partial results)
        if params[:run_acceptance_tests] == true
          acceptance_result = run_acceptance_tests(integration, max_attempts: params[:max_test_attempts] || 3)
          
          return {
            success: acceptance_result[:success],
            integration: integration.reload,
            connection: connection,
            operations_created: operations,
            warnings: @warnings,
            next_steps: build_next_steps(integration, params),
            test_session: acceptance_result[:session],
            test_report: acceptance_result[:report],
            test_analysis: acceptance_result[:analysis]
          }
        end

        {
          success: true,
          integration: integration,
          connection: connection,
          operations_created: operations,
          warnings: @warnings,
          next_steps: build_next_steps(integration, params)
        }
      rescue ActiveRecord::RecordInvalid => e
        @errors << "Database validation failed: #{e.message}"
        failure_result
      rescue => e
        Rails.logger.error "IntegrationFactory error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        @errors << "Unexpected error: #{e.message}"
        failure_result
      end
    end

    # Run full acceptance test suite with AI-generated tests
    def run_acceptance_tests(integration, max_attempts: 3)
      Rails.logger.info "🧪 Running acceptance tests for integration: #{integration.name}"
      
      # Generate test criteria using AI
      criteria = generate_test_criteria(integration)
      
      if criteria.empty?
        Rails.logger.warn "⚠️ No test criteria generated for integration #{integration.id}"
        return { success: true, message: "No tests generated", session: nil, report: nil, analysis: nil }
      end

      # Run tests with retry logic
      runner = FactoryTestRunner.new(user: @user, entity: @entity)
      result = runner.run_all_tests(integration, max_attempts: max_attempts)

      Rails.logger.info "🧪 Integration acceptance tests completed: #{result[:success] ? 'PASSED' : 'DELIVERED WITH ISSUES'}"
      
      result
    end

    # Generate AI-powered test criteria for an integration
    def generate_test_criteria(integration)
      generator = TestCriteriaGenerator.new(user: @user, entity: @entity)
      generator.generate_tests_for(integration)
    rescue => e
      Rails.logger.error "Failed to generate test criteria: #{e.message}"
      []
    end

    # ============================================================
    # STAGED CREATION METHODS
    # These allow creating integrations in phases for better accuracy
    # ============================================================

    # STAGE 1: Create foundation (name, base_url, docs)
    def create_foundation(name:, base_url:, documentation_url:, description: nil, category: nil, api_version: nil)
      @errors = []
      @warnings = []

      # Validate required fields
      validate_required!(:name, name, "Integration name")
      validate_required!(:base_url, base_url, "API base URL")
      validate_required!(:documentation_url, documentation_url, "Documentation URL")
      
      return failure_result if @errors.any?

      # Validate fields
      validate_name!(name)
      validate_url!(:base_url, base_url)
      validate_url!(:documentation_url, documentation_url)
      validate_category!(category) if category.present?

      return failure_result if @errors.any?

      # Check user limits
      unless @user.admin?
        current_count = custom_integrations_count
        limit = @user.integrations_limit || 1000
        
        if current_count >= limit
          @errors << "You have reached your limit of #{limit} custom integrations"
          return failure_result
        end
      end

      begin
        ActiveRecord::Base.transaction do
          slug = generate_slug(name)
          
          integration = Integration.create!(
            name: name,
            slug: slug,
            entity: @entity,
            created_by: @user,
            description: description || "Integration with #{name}",
            category: category || 'custom',
            auth_type: :api_key, # Placeholder - will be set in Stage 2
            api_base_url: normalize_url(base_url),
            allowed_hosts: extract_hosts(base_url),
            documentation_url: documentation_url,
            is_active: false, # Not active until auth is configured
            is_verified: false,
            auth_config: {},
            metadata: build_metadata({ name: name, api_version: api_version })
          )

          # Create connection in disconnected state
          Connection.create!(
            integration: integration,
            entity: @entity,
            name: "#{name} Connection",
            status: :disconnected,
            metadata: {
              created_by: 'integration_factory',
              stage: 'foundation',
              setup_required: true
            }
          )

          {
            success: true,
            integration: integration,
            warnings: @warnings
          }
        end
      rescue ActiveRecord::RecordInvalid => e
        @errors << "Database validation failed: #{e.message}"
        failure_result
      rescue => e
        Rails.logger.error "IntegrationFactory.create_foundation error: #{e.message}"
        @errors << "Unexpected error: #{e.message}"
        failure_result
      end
    end

    # STAGE 2: Configure authentication
    def configure_auth(integration_id:, auth_type:, auth_placement: nil, test_endpoint: nil, 
                       auth_configs: nil, auth_header_name: nil, username_label: nil, 
                       password_required: nil, authorize_url: nil, token_url: nil, 
                       scopes: nil, callback_params: nil)
      @errors = []
      @warnings = []

      integration = Integration.find_by(id: integration_id)
      unless integration
        @errors << "Integration not found: #{integration_id}"
        return failure_result
      end

      unless can_edit?(integration)
        @errors << "You don't have permission to edit this integration"
        return failure_result
      end

      # Validate auth type
      validate_auth_type!(auth_type)
      return failure_result if @errors.any?

      # For no_auth, set sensible defaults
      if auth_type == 'no_auth'
        auth_placement ||= 'none'
        test_endpoint ||= '/' # Default to root for testing
      end

      # Validate OAuth2 requirements
      if auth_type == 'oauth2'
        validate_required!(:authorize_url, authorize_url, "OAuth authorize URL")
        validate_required!(:token_url, token_url, "OAuth token URL")
        validate_url!(:authorize_url, authorize_url) if authorize_url.present?
        validate_url!(:token_url, token_url) if token_url.present?
        return failure_result if @errors.any?
      end

      begin
        ActiveRecord::Base.transaction do
          # Update integration auth type
          integration.update!(
            auth_type: auth_type,
            is_active: true,
            auth_config: build_auth_config({
              auth_type: auth_type,
              auth_header_name: auth_header_name,
              username_label: username_label,
              password_required: password_required,
              test_endpoint: test_endpoint
            })
          )

          # Create or update OauthConfiguration
          oauth_config = OauthConfiguration.find_or_initialize_by(integration: integration)
          oauth_config.update!(
            client_id: '',
            client_secret: '',
            redirect_uri: default_redirect_uri(integration),
            authorize_url: authorize_url,
            token_url: token_url,
            scopes: Array(scopes).join(','),
            callback_params: Array(callback_params),
            test_endpoint: test_endpoint,
            status: :inactive,
            metadata: { pending_setup: true, auth_placement: auth_placement }
          )

          # Delete existing auth configs and create new ones
          oauth_config.auth_configs.destroy_all
          
          auth_configs_created = []
          
          if auth_configs.present?
            # Use provided auth_configs
            auth_configs.each_with_index do |config, idx|
              config = config.with_indifferent_access
              ac = oauth_config.auth_configs.create!(
                auth_key: config[:key],
                auth_value: config[:value],
                auth_placement: config[:placement] || auth_placement,
                position: idx
              )
              auth_configs_created << { key: ac.auth_key, placement: ac.auth_placement }
            end
          else
            # Generate default auth configs based on auth_type and placement
            default_configs = generate_default_auth_configs(auth_type, auth_placement, auth_header_name)
            default_configs.each_with_index do |config, idx|
              ac = oauth_config.auth_configs.create!(
                auth_key: config[:key],
                auth_value: config[:value],
                auth_placement: config[:placement],
                position: idx
              )
              auth_configs_created << { key: ac.auth_key, placement: ac.auth_placement }
            end
          end

          # Update connection metadata and status
          connection = integration.connections.find_by(entity: @entity)
          if connection
            connection_updates = { metadata: connection.metadata.merge('stage' => 'auth_configured') }
            
            # For no_auth integrations, automatically mark the connection as connected
            if auth_type == 'no_auth'
              connection_updates[:status] = :connected
              connection_updates[:last_health_check] = Time.current
              # Also mark the integration as verified since no auth is needed
              integration.update!(is_verified: true) unless integration.is_verified?
            end
            
            connection.update!(connection_updates)
          end

          {
            success: true,
            integration: integration,
            auth_configs_created: auth_configs_created,
            warnings: @warnings
          }
        end
      rescue ActiveRecord::RecordInvalid => e
        @errors << "Database validation failed: #{e.message}"
        failure_result
      rescue => e
        Rails.logger.error "IntegrationFactory.configure_auth error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        @errors << "Unexpected error: #{e.message}"
        failure_result
      end
    end

    # STAGE 3: Test authentication using stored credentials
    # Credentials should be entered via the Integrations UI, NOT passed in chat
    def test_auth(integration_id:, credentials: nil)
      @errors = []
      @warnings = []

      integration = Integration.find_by(id: integration_id)
      unless integration
        @errors << "Integration not found: #{integration_id}"
        return failure_result
      end

      connection = integration.connections.find_by(entity: @entity)
      unless connection
        @errors << "No connection found for this integration"
        return failure_result
      end

      oauth_config = integration.oauth_configurations.first
      unless oauth_config&.test_endpoint.present?
        @errors << "No test endpoint configured. Call configure_integration_auth first."
        return failure_result
      end

      begin
        # Get existing credential (should have been entered via UI)
        credential = connection.integration_credentials.first
        
        unless credential
          @errors << "No credentials found. User must enter credentials at Settings → Integrations → #{integration.name}"
          return failure_result.merge(
            needs_credentials: true,
            user_action: "Go to Settings → Integrations → #{integration.name} and enter your credentials"
          )
        end
        
        # Check if credentials are actually set (not just empty placeholder)
        stored_creds = credential.credentials.is_a?(String) ? JSON.parse(credential.credentials) : credential.credentials
        if stored_creds.blank? || stored_creds.values.all?(&:blank?)
          @errors << "Credentials are empty. User must enter credentials at Settings → Integrations → #{integration.name}"
          return failure_result.merge(
            needs_credentials: true,
            user_action: "Go to Settings → Integrations → #{integration.name} and enter your credentials"
          )
        end

        # Test the connection using stored credentials
        api_service = IntegrationApiService.new(connection)
        result = api_service.test_connection

        if result[:success]
          # Mark connection as connected
          connection.update!(status: :connected, last_health_check: Time.current)
          connection.update!(metadata: connection.metadata.merge('stage' => 'authenticated'))
          credential.update!(status: :active)
          
          Rails.logger.info "✅ Integration #{integration.name} auth test passed"
          
          # CREATE AN INTEGRATION EXPERT AGENT
          # This agent becomes the API specialist for this integration
          integration_agent = nil
          begin
            agent_result = Integrations::IntegrationAgentGenerator.new(
              integration: integration,
              user: @user,
              entity: @entity
            ).generate!
            
            if agent_result[:success]
              integration_agent = agent_result[:agent]
              Rails.logger.info "✅ Created integration agent: #{integration_agent.name}"
            end
          rescue => e
            Rails.logger.warn "Integration agent creation failed (non-fatal): #{e.message}"
          end

          {
            success: true,
            integration: integration,
            integration_agent: integration_agent ? {
              id: integration_agent.id,
              name: integration_agent.name,
              slug: integration_agent.slug
            } : nil,
            test_response: result[:data],
            warnings: @warnings
          }
        else
          # Mark connection as failing but keep credentials (user may want to fix)
          connection.update!(status: :failing)
          
          Rails.logger.warn "❌ Integration #{integration.name} auth test failed: #{result[:error]}"

          {
            success: false,
            error: result[:error],
            api_response: result[:raw_response] || result[:data],
            status_code: result[:status_code],
            suggestion: suggest_auth_fix(integration.auth_type, result[:status_code], result[:error]),
            debug_info: {
              test_endpoint: oauth_config.test_endpoint,
              auth_type: integration.auth_type,
              auth_placement: oauth_config.metadata&.dig('auth_placement')
            },
            user_action: "Review the error above, then update credentials at Settings → Integrations → #{integration.name}"
          }
        end
      rescue JSON::ParserError => e
        Rails.logger.error "IntegrationFactory.test_auth JSON error: #{e.message}"
        @errors << "Invalid credential format. User should re-enter credentials at Settings → Integrations"
        failure_result.merge(needs_credentials: true)
      rescue => e
        Rails.logger.error "IntegrationFactory.test_auth error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        @errors << "Test failed: #{e.message}"
        failure_result
      end
    end

    # STAGE 4: Add operations
    def add_operations(integration_id:, operations:)
      @errors = []
      @warnings = []

      integration = Integration.find_by(id: integration_id)
      unless integration
        @errors << "Integration not found: #{integration_id}"
        return failure_result
      end

      unless can_edit?(integration)
        @errors << "You don't have permission to edit this integration"
        return failure_result
      end

      connection = integration.connections.find_by(entity: @entity)
      unless connection&.connected?
        @warnings << "Integration is not connected. Operations will be created but may not work until auth is configured."
      end

      validate_operations!(operations)
      return failure_result if @errors.any?

      begin
        created_operations = create_operations!(integration, operations)
        
        # Update connection metadata
        connection&.update!(
          metadata: connection.metadata.merge('stage' => 'complete')
        )

        {
          success: true,
          integration: integration,
          operations_created: created_operations,
          warnings: @warnings
        }
      rescue => e
        Rails.logger.error "IntegrationFactory.add_operations error: #{e.message}"
        @errors << "Failed to add operations: #{e.message}"
        failure_result
      end
    end

    # ============================================================
    # END STAGED CREATION METHODS
    # ============================================================

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

      # Scope uniqueness check to entity (multi-tenancy)
      scope = Integration.where(name: name, entity: @entity)
      scope = scope.where.not(id: exclude_id) if exclude_id
      @errors << "An integration named '#{name}' already exists for this entity" if scope.exists?
    end

    def validate_slug!(slug)
      return if slug.blank?

      unless slug.match?(/\A[a-z][a-z0-9_]*\z/)
        @errors << "Slug must be lowercase, start with a letter, and contain only letters, numbers, and underscores"
      end

      # Scope uniqueness check to entity (multi-tenancy)
      @errors << "An integration with this slug already exists for this entity" if Integration.where(slug: slug, entity: @entity).exists?
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
        entity: @entity,
        created_by: @user,
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
      # If credentials are provided and validated, mark as connected
      # Otherwise, mark as disconnected (pending setup)
      initial_status = params[:credentials_validated] ? :connected : :disconnected
      
      Connection.create!(
        integration: integration,
        entity: @entity,
        name: "#{params[:name]} Connection",
        status: initial_status,
        metadata: {
          created_by: 'integration_factory',
          setup_required: !params[:credentials_validated]
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
      oauth_config = OauthConfiguration.create!(
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

      # Create auth_configs for flexible auth patterns
      create_auth_configs!(oauth_config, params)
      
      oauth_config
    end

    # Create AuthConfig records for flexible key-value auth patterns
    # This allows any auth pattern: headers, query params, URL params
    def create_auth_configs!(oauth_config, params)
      auth_configs = params[:auth_configs] || []
      
      # If no explicit auth_configs, generate defaults based on auth_type
      if auth_configs.empty?
        auth_configs = default_auth_configs_for(params[:auth_type], params)
      end

      auth_configs.each_with_index do |config, idx|
        config = config.with_indifferent_access
        oauth_config.auth_configs.create!(
          auth_key: config[:key] || config[:auth_key],
          auth_value: config[:value] || config[:auth_value],
          auth_placement: config[:placement] || config[:auth_placement] || 'header',
          position: config[:position] || idx
        )
      end
    end

    # Generate default auth configs based on auth_type
    def default_auth_configs_for(auth_type, params)
      case auth_type.to_s
      when 'api_key'
        header_name = params[:auth_header_name] || 'X-API-Key'
        [{ key: header_name, value: '{api_key}', placement: 'header' }]
      when 'bearer_token'
        [{ key: 'Authorization', value: 'Bearer {token}', placement: 'header' }]
      when 'basic_auth'
        # Two fields: username + password — the credential model handles Base64 encoding
        username_lbl = params[:username_label] || 'username'
        [
          { key: username_lbl, value: "{username}", placement: 'header' },
          { key: 'password', value: '{password}', placement: 'header' }
        ]
      when 'oauth2'
        [{ key: 'Authorization', value: 'Bearer {access_token}', placement: 'header' }]
      when 'no_auth'
        # No authentication needed - return empty config
        []
      else
        []
      end
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

      # Schema columns for integration_operations:
      # operation_id, name, description, http_method, path_template,
      # request_schema (jsonb), response_schema (jsonb), pagination_strategy (integer enum),
      # is_idempotent (boolean), requires_confirmation (boolean), max_limit (integer),
      # documentation (text), examples (jsonb), version (string), deprecated_at (datetime),
      # is_enabled (boolean, default: true)
      integration.integration_operations.create!(
        operation_id: operation_id,
        name: name.titleize,
        description: op[:description] || "#{name.titleize} operation",
        http_method: method,
        path_template: op[:path],
        request_schema: build_request_schema(op[:request_schema] || op[:parameters]),
        response_schema: op[:response_schema] || {},
        pagination_strategy: normalize_pagination_strategy(op[:pagination_strategy]),
        max_limit: op[:max_limit],
        is_idempotent: method == 'GET',
        requires_confirmation: %w[DELETE POST PUT PATCH].include?(method),
        documentation: op[:documentation],
        examples: op[:examples],
        version: op[:version],
        is_enabled: true
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

    # Generate default auth configs based on auth type and placement
    def generate_default_auth_configs(auth_type, auth_placement, auth_header_name = nil)
      configs = []
      
      case auth_type.to_s
      when 'api_key'
        if auth_placement == 'query'
          # Query param auth (like Trello)
          configs << { key: 'key', value: '{api_key}', placement: 'query' }
        else
          # Header auth (most common)
          header_name = auth_header_name || 'X-API-Key'
          configs << { key: header_name, value: '{api_key}', placement: 'header' }
        end
      when 'bearer_token'
        configs << { key: 'Authorization', value: 'Bearer {token}', placement: 'header' }
      when 'basic_auth'
        # Two fields: username + password — the credential model handles Base64 encoding
        configs << { key: 'username', value: '{username}', placement: 'header' }
        configs << { key: 'password', value: '{password}', placement: 'header' }
      when 'oauth2'
        configs << { key: 'Authorization', value: 'Bearer {access_token}', placement: 'header' }
      when 'no_auth'
        # No authentication needed - no configs required
        # Leave configs empty
      end
      
      configs
    end

    # Suggest fixes for auth failures
    def suggest_auth_fix(auth_type, status_code, error_message)
      case status_code
      when 401, 403
        case auth_type.to_s
        when 'api_key'
          "Authentication failed. Check:\n" \
          "1. Is the API key correct?\n" \
          "2. Is auth_placement correct? (header vs query)\n" \
          "3. Are the parameter names correct? (e.g., 'key' vs 'api_key')\n" \
          "4. Does the API require multiple auth params? (e.g., Trello needs 'key' AND 'token')"
        when 'bearer_token'
          "Authentication failed. Check:\n" \
          "1. Is the token correct and not expired?\n" \
          "2. Does the token have required scopes?"
        when 'basic_auth'
          "Authentication failed. Check:\n" \
          "1. Is the username/API key correct?\n" \
          "2. Is the password correct (or empty if using API key as username)?"
        else
          "Authentication failed. Verify your credentials."
        end
      when 404
        "Endpoint not found. Check:\n" \
        "1. Is the test_endpoint path correct?\n" \
        "2. Does the path need a version prefix (e.g., /v1/, /1/)?"
      when 429
        "Rate limited. Wait and try again."
      else
        "Request failed with status #{status_code}. Check the API documentation."
      end
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
      when 'no_auth' then 'none'
      else 'header'
      end
    end

    def build_request_schema(schema_or_params)
      return {} if schema_or_params.blank?
      
      # If it's already a proper JSON Schema, return it
      if schema_or_params.is_a?(Hash) && schema_or_params['type'].present?
        return schema_or_params.deep_stringify_keys
      end

      # Convert simple param hash to JSON Schema
      if schema_or_params.is_a?(Hash)
        {
          'type' => 'object',
          'properties' => schema_or_params.transform_values { |type|
            { 'type' => normalize_json_schema_type(type) }
          }.deep_stringify_keys
        }
      else
        {}
      end
    end

    def normalize_json_schema_type(type)
      case type.to_s.downcase
      when 'string', 'text' then 'string'
      when 'integer', 'int', 'number' then 'integer'
      when 'float', 'decimal' then 'number'
      when 'boolean', 'bool' then 'boolean'
      when 'array', 'list' then 'array'
      when 'object', 'hash' then 'object'
      else 'string'
      end
    end

    def normalize_pagination_strategy(strategy)
      return 'no_pagination' if strategy.blank?
      
      strategy_str = strategy.to_s.downcase
      VALID_PAGINATION_STRATEGIES.include?(strategy_str) ? strategy_str : 'no_pagination'
    end

    def default_redirect_uri(integration)
      base = ENV['APP_URL'] || 'https://app.amoslabs.com'
      "#{base}/integrations/callback/#{integration.slug}"
    end

    def find_integration(identifier)
      return identifier if identifier.is_a?(Integration)
      
      # Use find_for_use which PREFERS entity-owned integrations over globals
      # This ensures we edit the entity's version, not a global template
      Integration.find_for_use(identifier, @entity)
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
