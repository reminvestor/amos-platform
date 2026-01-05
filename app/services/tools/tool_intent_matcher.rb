module Tools
  # Intent-based tool matching for agent proposals
  # Instead of hardcoded tool equivalents, this analyzes tool intent and category
  # to determine if an agent can handle a request
  class ToolIntentMatcher
    # Tool intents - what action is being performed
    INTENTS = {
      create: %w[create generate build make add new start design scaffold],
      read: %w[get read fetch retrieve list show view query search find],
      update: %w[update modify edit change configure adjust refine customize extend],
      delete: %w[delete remove destroy cancel],
      execute: %w[execute run invoke test process analyze diagnose repair],
      delegate: %w[delegate propose assign handoff]
    }.freeze

    # Map categories to related categories (for fuzzy matching)
    RELATED_CATEGORIES = {
      'data' => %w[data module_building app_building],
      'integration' => %w[integration integration_repair],
      'landing_page' => %w[landing_page design],
      'module_building' => %w[module_building platform_factory data],
      'agent_management' => %w[agent_management system task_management],
      'planning' => %w[planning task_management workflow]
    }.freeze

    # Keywords in task descriptions that suggest a category
    DOMAIN_KEYWORDS = {
      'landing_page' => %w[landing page website hero sales marketing],
      'integration' => %w[integration api rest webhook connect sync external],
      'module_building' => %w[module schema field model data custom],
      'agent_management' => %w[agent delegate assistant specialist],
      'planning' => %w[plan workflow step sequence multi-step],
      'data' => %w[contact campaign email record object create update],
      'export' => %w[export pdf csv excel download],
      'analytics' => %w[chart graph visualization dashboard metric]
    }.freeze

    def initialize(agent_tools:, task_description: nil)
      @agent_tools = agent_tools
      @task_description = task_description&.downcase || ''
      @tool_metadata_cache = {}
    end

    # Check if the agent can satisfy the requested tools
    # Returns: { satisfied: true/false, mappings: { requested => agent_tool }, missing: [] }
    def can_satisfy?(requested_tools)
      return { satisfied: true, mappings: {}, missing: [] } if requested_tools.blank?

      mappings = {}
      missing = []

      requested_tools.each do |requested_tool|
        if @agent_tools.include?(requested_tool)
          # Direct match
          mappings[requested_tool] = requested_tool
        elsif (matched = find_equivalent_tool(requested_tool))
          # Intent-based match
          mappings[requested_tool] = matched
          Rails.logger.info "[ToolIntentMatcher] Mapped '#{requested_tool}' → '#{matched}'"
        elsif optional_tool?(requested_tool)
          # Optional tool - skip
          Rails.logger.info "[ToolIntentMatcher] Skipping optional tool '#{requested_tool}'"
        else
          # No match found
          missing << requested_tool
        end
      end

      {
        satisfied: missing.empty?,
        mappings: mappings,
        missing: missing
      }
    end

    private

    def find_equivalent_tool(requested_tool)
      requested_intent = extract_intent(requested_tool)
      requested_category = get_tool_category(requested_tool)
      
      # Also infer category from task description
      inferred_categories = infer_categories_from_description
      target_categories = ([requested_category] + inferred_categories + related_categories(requested_category)).compact.uniq

      # Find agent tools with matching intent in target categories
      @agent_tools.each do |agent_tool|
        agent_intent = extract_intent(agent_tool)
        agent_category = get_tool_category(agent_tool)

        # Match if same intent and overlapping categories
        if agent_intent == requested_intent && target_categories.include?(agent_category)
          return agent_tool
        end
      end

      # Fallback: looser matching - same intent, any related category
      @agent_tools.each do |agent_tool|
        agent_intent = extract_intent(agent_tool)
        if agent_intent == requested_intent
          return agent_tool
        end
      end

      nil
    end

    def extract_intent(tool_name)
      name = tool_name.to_s.downcase
      
      INTENTS.each do |intent, keywords|
        if keywords.any? { |kw| name.start_with?(kw) || name.include?("_#{kw}_") || name.include?("_#{kw}") }
          return intent
        end
      end

      :unknown
    end

    def get_tool_category(tool_name)
      return @tool_metadata_cache[tool_name] if @tool_metadata_cache.key?(tool_name)

      begin
        class_name = "Tools::#{tool_name.to_s.camelize}Tool"
        klass = class_name.constantize
        if klass.respond_to?(:metadata)
          category = klass.metadata[:category]&.to_s
          @tool_metadata_cache[tool_name] = category
          return category
        end
      rescue NameError
        # Tool class doesn't exist (might be dynamic)
      end

      @tool_metadata_cache[tool_name] = nil
      nil
    end

    def infer_categories_from_description
      categories = []
      
      DOMAIN_KEYWORDS.each do |category, keywords|
        if keywords.any? { |kw| @task_description.include?(kw) }
          categories << category
        end
      end

      categories
    end

    def related_categories(category)
      RELATED_CATEGORIES[category] || []
    end

    def optional_tool?(tool_name)
      # These tools can be skipped - either generic or have alternative implementations
      optional_tools = %w[
        get_schema get_data list_objects
        propose_module_schema approve_module_design
        start_module_design start_app_design
      ]
      optional_tools.include?(tool_name.to_s)
    end
  end
end

