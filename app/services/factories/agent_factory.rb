module Factories
  class AgentFactory
    class ValidationError < StandardError; end
    class SchemaError < StandardError; end
    class TestError < StandardError; end
    class SecurityError < StandardError; end

    # Valid roles for agents
    VALID_ROLES = %w[executor planner analyst verifier fixer architect engineer custom].freeze

    # Valid execution strategies
    VALID_STRATEGIES = %w[standard workflow remote_http].freeze

    # Required sections in a system prompt
    REQUIRED_PROMPT_SECTIONS = %w[role objective constraints].freeze

    attr_reader :user, :entity, :errors, :warnings

    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @errors = []
      @warnings = []
    end

    # Main factory method to create an agent
    # Options:
    #   skip_test: Skip basic validation test
    #   run_acceptance_tests: Run full test-driven creation with AI-generated tests (3 attempts)
    #   max_test_attempts: Override default 3 attempts
    def create(params)
      @errors = []
      @warnings = []

      # Step 1: Validate the schema/structure
      validate_schema!(params)

      # Step 2: Validate the system prompt
      validate_system_prompt!(params[:system_prompt])

      # Step 3: Validate capabilities
      validate_capabilities!(params[:capabilities]) if params[:capabilities].present?

      # Step 4: Validate tools exist
      validate_tools!(params[:tools]) if params[:tools].present?

      # Raise if we have errors
      raise ValidationError, @errors.join("; ") if @errors.any?

      # Step 5: Create the agent
      agent = build_agent(params)

      # Step 6: Run basic test execution (optional, can be skipped)
      if params[:skip_test] != true && params[:run_acceptance_tests] != true
        test_result = test_agent(agent, params[:test_prompt])
        unless test_result[:success]
          agent.destroy if agent.persisted?
          raise TestError, "Agent test failed: #{test_result[:error]}"
        end
      end

      # Step 7: Run full acceptance tests if requested (test-driven creation)
      if params[:run_acceptance_tests] == true
        acceptance_result = run_acceptance_tests(agent, max_attempts: params[:max_test_attempts] || 3)
        
        return {
          success: acceptance_result[:success],
          agent: agent.reload,
          warnings: @warnings,
          test_session: acceptance_result[:session],
          test_report: acceptance_result[:report],
          test_analysis: acceptance_result[:analysis]
        }
      end

      {
        success: true,
        agent: agent,
        warnings: @warnings
      }
    rescue ValidationError, SchemaError, TestError => e
      { success: false, error: e.message, errors: @errors, warnings: @warnings }
    rescue => e
      Rails.logger.error "AgentFactory error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { success: false, error: "Unexpected error: #{e.message}", errors: @errors }
    end

    # Run full acceptance test suite with AI-generated tests
    # Returns after 3 attempts (or success), with full test report and AI analysis
    def run_acceptance_tests(agent, max_attempts: 3)
      Rails.logger.info "🧪 Running acceptance tests for agent: #{agent.name}"
      
      # Step 1: Generate test criteria using AI
      criteria = generate_test_criteria(agent)
      
      if criteria.empty?
        Rails.logger.warn "⚠️ No test criteria generated for agent #{agent.id}"
        return { success: true, message: "No tests generated", session: nil, report: nil, analysis: nil }
      end

      # Step 2: Run tests with retry logic
      runner = FactoryTestRunner.new(user: @user, entity: @entity)
      result = runner.run_all_tests(agent, max_attempts: max_attempts)

      Rails.logger.info "🧪 Acceptance tests completed: #{result[:success] ? 'PASSED' : 'DELIVERED WITH ISSUES'}"
      
      result
    end

    # Generate AI-powered test criteria for an agent
    def generate_test_criteria(agent)
      generator = TestCriteriaGenerator.new(user: @user, entity: @entity)
      generator.generate_tests_for(agent)
    rescue => e
      Rails.logger.error "Failed to generate test criteria: #{e.message}"
      []
    end

    # Update an existing agent with validation
    def update(agent, params)
      @errors = []
      @warnings = []

      # Verify ownership
      unless can_edit?(agent)
        return { success: false, error: "You don't have permission to edit this agent" }
      end

      # Validate updates
      validate_schema!(params, update: true) if params[:name] || params[:slug] || params[:role]
      validate_system_prompt!(params[:system_prompt]) if params[:system_prompt].present?
      validate_capabilities!(params[:capabilities]) if params[:capabilities].present?
      validate_tools!(params[:tools]) if params[:tools].present?

      raise ValidationError, @errors.join("; ") if @errors.any?

      # Apply updates
      ActiveRecord::Base.transaction do
        update_agent_attributes(agent, params)
        update_capabilities(agent, params[:capabilities]) if params[:capabilities].present?
        update_tools(agent, params[:tools]) if params[:tools].present?
        agent.save!
      end

      # Re-test if system prompt changed
      if params[:system_prompt].present? && params[:skip_test] != true
        test_result = test_agent(agent, params[:test_prompt])
        unless test_result[:success]
          @warnings << "Agent updated but test execution had issues: #{test_result[:error]}"
        end
      end

      {
        success: true,
        agent: agent.reload,
        warnings: @warnings
      }
    rescue ValidationError => e
      { success: false, error: e.message, errors: @errors, warnings: @warnings }
    rescue => e
      Rails.logger.error "AgentFactory update error: #{e.message}"
      { success: false, error: "Update failed: #{e.message}" }
    end

    # Get available tools that can be assigned to agents
    def available_tools
      catalog = Tools::ToolCatalog.instance
      
      # Get all registered tools with their metadata
      catalog.all_tools.map do |name, info|
        {
          name: name,
          description: info[:metadata][:description],
          category: info[:metadata][:category],
          read_only: info[:read_only]
        }
      end
    end

    # Get available integrations for the entity
    def available_integrations
      return [] unless @entity

      @entity.connections.active.includes(:integration).map do |conn|
        {
          name: conn.integration.name,
          slug: conn.integration.slug,
          category: conn.integration.category,
          operations: conn.integration.integration_operations.pluck(:name, :slug)
        }
      end
    rescue => e
      Rails.logger.warn "Could not load integrations: #{e.message}"
      []
    end

    # Validate agent schema without creating
    def validate_only(params)
      @errors = []
      @warnings = []

      validate_schema!(params)
      validate_system_prompt!(params[:system_prompt]) if params[:system_prompt].present?
      validate_capabilities!(params[:capabilities]) if params[:capabilities].present?
      validate_tools!(params[:tools]) if params[:tools].present?

      {
        valid: @errors.empty?,
        errors: @errors,
        warnings: @warnings
      }
    end

    # ============================================
    # SECURITY & PUBLICATION
    # ============================================

    # Run security audit on an agent
    def run_security_audit(agent)
      service = AgentSecurityCheckService.new
      result = service.evaluate(agent)

      agent.update!(
        security_rating: result['rating'],
        security_reason: result['reason']
      )

      {
        rating: result['rating'],
        reason: result['reason'],
        concerns: result['concerns'] || [],
        recommendations: result['recommendations'] || [],
        passed: result['rating'] == 'pass'
      }
    rescue => e
      Rails.logger.error "Security audit failed for agent #{agent.id}: #{e.message}"
      {
        rating: 'review',
        reason: "Security audit failed: #{e.message}",
        concerns: ['Audit system error'],
        recommendations: ['Manual review required'],
        passed: false
      }
    end

    # Request publication of an agent to the public marketplace
    def request_publication(agent)
      @errors = []
      @warnings = []

      # Verify ownership
      unless can_edit?(agent)
        return { success: false, error: "You don't have permission to publish this agent" }
      end

      # Can't republish rejected agents without updates
      if agent.publish_status == 'rejected'
        return { 
          success: false, 
          error: "This agent was previously rejected. Please update it based on the review notes before resubmitting.",
          review_notes: agent.review_notes
        }
      end

      # Already public?
      if agent.is_public && agent.publish_status == 'approved'
        return { success: false, error: "This agent is already published" }
      end

      # Run security audit
      audit_result = run_security_audit(agent)

      case audit_result[:rating]
      when 'fail'
        # Auto-reject with security concerns
        rejection_reason = "Automatically rejected due to security concerns:\n#{audit_result[:reason]}\n\nConcerns: #{audit_result[:concerns].join(', ')}"
        
        agent.update!(
          is_public: false,
          publish_status: 'rejected',
          review_notes: rejection_reason
        )

        # Notify agent owner of rejection
        MarketplaceNotificationService.notify_agent_rejected(agent, reason: rejection_reason)

        return {
          success: false,
          error: "Agent failed security review",
          security_rating: 'fail',
          concerns: audit_result[:concerns],
          recommendations: audit_result[:recommendations]
        }

      when 'pass'
        # Auto-approve agents that pass security
        agent.update!(
          is_public: true,
          publish_status: 'approved',
          published_at: Time.current
        )

        Rails.logger.info "✅ Agent #{agent.name} (#{agent.id}) auto-approved for publication"

        # Notify agent owner of approval
        MarketplaceNotificationService.notify_agent_approved(agent)

        return {
          success: true,
          message: "Agent approved and published!",
          security_rating: 'pass',
          agent: agent.reload
        }

      when 'review'
        # Needs manual review
        agent.update!(
          is_public: true,
          publish_status: 'pending_review'
        )

        Rails.logger.info "⏳ Agent #{agent.name} (#{agent.id}) submitted for manual review"

        # Notify user that agent is pending
        MarketplaceNotificationService.notify_agent_pending_review(agent)
        
        # Notify admins of pending review
        MarketplaceNotificationService.notify_admins_agent_pending(agent)

        return {
          success: true,
          message: "Agent submitted for review. An admin will review it shortly.",
          security_rating: 'review',
          concerns: audit_result[:concerns],
          agent: agent.reload
        }
      end
    rescue => e
      Rails.logger.error "Publication request failed for agent #{agent.id}: #{e.message}"
      { success: false, error: "Publication failed: #{e.message}" }
    end

    # Unpublish an agent (make it private again)
    def unpublish(agent)
      unless can_edit?(agent)
        return { success: false, error: "You don't have permission to unpublish this agent" }
      end

      agent.update!(
        is_public: false,
        publish_status: 'private',
        published_at: nil
      )

      {
        success: true,
        message: "Agent unpublished successfully",
        agent: agent.reload
      }
    rescue => e
      { success: false, error: "Unpublish failed: #{e.message}" }
    end

    # Admin approval of a pending agent
    def approve_publication(agent, reviewer:, notes: nil)
      unless reviewer.admin?
        return { success: false, error: "Only admins can approve agents" }
      end

      agent.update!(
        publish_status: 'approved',
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        review_notes: notes,
        published_at: Time.current
      )

      Rails.logger.info "✅ Agent #{agent.name} approved by admin #{reviewer.email}"

      # Notify the agent owner
      MarketplaceNotificationService.notify_agent_approved(agent)

      {
        success: true,
        message: "Agent approved and published",
        agent: agent.reload
      }
    rescue => e
      { success: false, error: "Approval failed: #{e.message}" }
    end

    # Admin rejection of a pending agent
    def reject_publication(agent, reviewer:, reason:)
      unless reviewer.admin?
        return { success: false, error: "Only admins can reject agents" }
      end

      agent.update!(
        is_public: false,
        publish_status: 'rejected',
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        review_notes: reason
      )

      Rails.logger.info "❌ Agent #{agent.name} rejected by admin #{reviewer.email}: #{reason}"

      # Notify agent owner of rejection
      MarketplaceNotificationService.notify_agent_rejected(agent, reason: reason)

      {
        success: true,
        message: "Agent rejected",
        agent: agent.reload
      }
    rescue => e
      { success: false, error: "Rejection failed: #{e.message}" }
    end

    private

    def validate_schema!(params, update: false)
      # Required fields for creation
      unless update
        @errors << "name is required" if params[:name].blank?
        @errors << "role is required" if params[:role].blank?
        @errors << "system_prompt is required" if params[:system_prompt].blank?
      end

      # Name validation
      if params[:name].present?
        if params[:name].length < 3
          @errors << "name must be at least 3 characters"
        elsif params[:name].length > 100
          @errors << "name must be less than 100 characters"
        end
      end

      # Slug validation
      if params[:slug].present?
        unless params[:slug].match?(/\A[a-z0-9_]+\z/)
          @errors << "slug must only contain lowercase letters, numbers, and underscores"
        end

        # Check uniqueness
        existing = AgentPlugin.find_by(slug: params[:slug])
        if existing && (!update || existing.id != params[:id])
          @errors << "slug '#{params[:slug]}' is already taken"
        end
      end

      # Role validation
      if params[:role].present? && !VALID_ROLES.include?(params[:role])
        @errors << "role must be one of: #{VALID_ROLES.join(', ')}"
      end

      # Execution strategy validation
      if params[:execution_strategy].present? && !VALID_STRATEGIES.include?(params[:execution_strategy])
        @errors << "execution_strategy must be one of: #{VALID_STRATEGIES.join(', ')}"
      end
    end

    def validate_system_prompt!(prompt)
      return if prompt.blank?

      prompt_text = prompt.is_a?(Hash) ? prompt['prompt'] || prompt[:prompt] : prompt.to_s

      if prompt_text.blank?
        @errors << "system_prompt cannot be empty"
        return
      end

      if prompt_text.length < 50
        @warnings << "system_prompt is very short (#{prompt_text.length} chars). Consider adding more detail."
      end

      if prompt_text.length > 50000
        @errors << "system_prompt is too long (max 50000 characters)"
      end

      # Check for recommended sections
      prompt_lower = prompt_text.downcase
      
      unless prompt_lower.include?('role') || prompt_lower.include?('you are')
        @warnings << "system_prompt should define the agent's role (e.g., 'You are a...')"
      end

      unless prompt_lower.include?('objective') || prompt_lower.include?('goal') || prompt_lower.include?('task')
        @warnings << "system_prompt should define the agent's objective or goals"
      end

      # Check for common issues
      if prompt_lower.include?('todo') || prompt_lower.include?('fixme')
        @warnings << "system_prompt contains TODO/FIXME markers - ensure it's complete"
      end

      # Check for user interaction guidance
      # Agents that need user input should use ask_user tool, not just respond with questions
      unless prompt_lower.include?('ask_user') || prompt_lower.include?('ask user')
        @warnings << "system_prompt doesn't mention 'ask_user' tool. If your agent needs user input (location, preferences, etc.), instruct it to use the ask_user tool instead of asking questions in text responses. Text responses complete the task - ask_user pauses and waits for a reply."
      end
    end

    def validate_capabilities!(capabilities)
      return if capabilities.blank?

      capabilities.each_with_index do |cap, idx|
        cap_name = cap['name'] || cap['capability_name'] || cap[:name] || cap[:capability_name]
        
        if cap_name.blank?
          @errors << "capability at index #{idx} is missing a name"
          next
        end

        # Validate capability schema if provided
        schema = cap['input_schema'] || cap['contract_schema'] || cap['schema'] || 
                 cap[:input_schema] || cap[:contract_schema] || cap[:schema]
        
        if schema.present?
          validate_json_schema!(schema, "capability '#{cap_name}'")
        end
      end
    end

    def validate_tools!(tools)
      return if tools.blank?

      catalog = Tools::ToolCatalog.instance
      
      tools.each do |tool_name|
        unless catalog.tool_exists?(tool_name)
          @errors << "tool '#{tool_name}' does not exist in the catalog"
        end
      end
    end

    def validate_json_schema!(schema, context)
      unless schema.is_a?(Hash)
        @errors << "#{context} schema must be an object"
        return
      end

      # Basic JSON Schema validation
      if schema['inputs'].present?
        unless schema['inputs'].is_a?(Array)
          @errors << "#{context} inputs must be an array"
        end
      end

      if schema['outputs'].present?
        unless schema['outputs'].is_a?(Array)
          @errors << "#{context} outputs must be an array"
        end
      end
    end

    def build_agent(params)
      ActiveRecord::Base.transaction do
        # Generate slug if not provided
        slug = params[:slug] || params[:name].parameterize.underscore

        # Build configuration with sensible defaults
        config = params[:configuration] || {}
        
        # Set default canvas_on_completion if not specified
        # This ensures agents always have a way to display their output
        unless config['canvas_on_completion'] || config[:canvas_on_completion]
          config['canvas_on_completion'] = default_canvas_for_role(params[:role])
        end

        agent = AgentPlugin.create!(
          name: params[:name],
          slug: slug,
          role: params[:role] || 'executor',
          description: params[:description] || "Custom agent created by #{@user.name}",
          version: params[:version] || "1.0.0",
          status: params[:status] || "draft",
          priority: params[:priority] || 50,
          system_prompt: normalize_system_prompt(params[:system_prompt]),
          configuration: config,
          ai_model: params[:ai_model] || "qwen3-next-80b",
          execution_strategy: params[:execution_strategy] || "standard",
          entity_id: @entity&.id,
          user_id: @user.id
        )

        # Add capabilities
        (params[:capabilities] || []).each do |cap|
          agent.agent_capabilities.create!(
            capability_name: cap['name'] || cap['capability_name'] || cap[:name] || cap[:capability_name],
            contract_schema: cap['input_schema'] || cap['contract_schema'] || cap['schema'] || 
                           cap[:input_schema] || cap[:contract_schema] || cap[:schema] || {}
          )
        end

        # Add tools - always include essential tools
        tools = (params[:tools] || []).dup
        tools << "ask_user" unless tools.include?("ask_user")
        tools << "get_data" unless tools.include?("get_data")

        tools.uniq.each do |tool_name|
          if Tools::ToolCatalog.instance.tool_exists?(tool_name)
            agent.agent_tools.create!(tool_name: tool_name)
          end
        end

        agent
      end
    end

    def update_agent_attributes(agent, params)
      updateable = %i[name slug role description version status priority 
                      system_prompt configuration ai_model execution_strategy]
      
      updateable.each do |attr|
        if params[attr].present?
          value = attr == :system_prompt ? normalize_system_prompt(params[attr]) : params[attr]
          agent.send("#{attr}=", value)
        end
      end
    end

    def update_capabilities(agent, capabilities)
      # Remove existing and recreate
      agent.agent_capabilities.destroy_all
      
      capabilities.each do |cap|
        agent.agent_capabilities.create!(
          capability_name: cap['name'] || cap['capability_name'] || cap[:name] || cap[:capability_name],
          contract_schema: cap['input_schema'] || cap['contract_schema'] || cap['schema'] || 
                         cap[:input_schema] || cap[:contract_schema] || cap[:schema] || {}
        )
      end
    end

    def update_tools(agent, tools)
      # Remove existing and recreate
      agent.agent_tools.destroy_all
      
      # Always include essential tools
      tools << "ask_user" unless tools.include?("ask_user")
      tools << "get_data" unless tools.include?("get_data")

      tools.uniq.each do |tool_name|
        if Tools::ToolCatalog.instance.tool_exists?(tool_name)
          agent.agent_tools.create!(tool_name: tool_name)
        end
      end
    end

    def normalize_system_prompt(prompt)
      if prompt.is_a?(String)
        { 'prompt' => prompt }
      elsif prompt.is_a?(Hash)
        prompt.stringify_keys
      else
        { 'prompt' => prompt.to_s }
      end
    end

    def can_edit?(agent)
      return true if @user.admin?
      return false if agent.user_id.nil? # System agents can't be edited by non-admins
      agent.user_id == @user.id
    end

    def default_canvas_for_role(role)
      case role
      when 'analyst'
        'dynamic_canvas'  # Analysts typically produce reports/visualizations
      when 'executor'
        'dynamic_canvas'  # Executors often produce detailed output
      when 'verifier'
        'dynamic_canvas'  # Verifiers produce validation reports
      when 'architect', 'engineer'
        'dynamic_canvas'  # Technical roles produce documentation
      else
        'dynamic_canvas'  # Default to dynamic_canvas for all agents
      end
    end

    def test_agent(agent, test_prompt = nil)
      # Use a simple test prompt if none provided
      test_prompt ||= "Respond with a brief confirmation that you understand your role as #{agent.name}."

      begin
        # Create a test execution context
        executor = agent.instantiate(
          entity: @entity,
          user: @user,
          test_mode: true
        )

        # Run a simple test (just validate the agent can be instantiated and respond)
        # In test mode, we don't actually call the LLM - just verify the setup
        
        # Verify the agent has required tools
        if agent.agent_tools.empty?
          return { success: false, error: "Agent has no tools configured" }
        end

        # Verify system prompt is valid
        if agent.system_prompt.blank? || (agent.system_prompt.is_a?(Hash) && agent.system_prompt['prompt'].blank?)
          return { success: false, error: "Agent has no system prompt configured" }
        end

        { success: true, message: "Agent passed validation tests" }
      rescue => e
        { success: false, error: e.message }
      end
    end
  end
end

