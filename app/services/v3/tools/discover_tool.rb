# frozen_string_literal: true

module V3
  module Tools
    # DiscoverTool - Search platform capabilities, skills, and integrations
    #
    # This is the V3 replacement for discover_tools. Instead of discovering
    # individual tools, it discovers:
    # - Platform skills (markdown knowledge)
    # - Available integrations and their capabilities  
    # - Platform features and how to use them
    # - User's custom skills
    #
    # The model uses this when it needs to learn HOW to do something.
    #
    class DiscoverTool < ::Tools::BaseTool
      def self.read_only?
        true
      end

      def self.metadata
        {
          name: "discover",
          description: <<~DESC.strip,
            Search platform capabilities, skills, and knowledge.
            
            Categories: "skills", "integrations", "features", "recipes"
            
            Examples:
            - query: "how to set up a Stripe integration"
            - query: "lead capture workflow", category: "recipes"
            - query: "email sequence best practices", category: "skills"
            - query: "what integrations are available"
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "What you want to learn about or find"
              },
              category: {
                type: "string",
                description: "Optional: narrow search to specific category",
                enum: %w[skills integrations features recipes all]
              }
            },
            required: ["query"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        query = get_arg(args, :query)
        category = get_arg(args, :category, "all")

        return error_response("Missing: query") if query.blank?

        results = []

        # Search skills
        if %w[all skills recipes].include?(category)
          skill_results = search_skills(query)
          results.concat(skill_results)
        end

        # Search integrations
        if %w[all integrations].include?(category)
          integration_results = search_integrations(query)
          results.concat(integration_results)
        end

        # Search features/capabilities
        if %w[all features].include?(category)
          feature_results = search_features(query)
          results.concat(feature_results)
        end

        if results.empty?
          success_response(
            query: query,
            results: [],
            count: 0,
            message: "No results found. Try a different search query or broader category."
          )
        else
          success_response(
            query: query,
            category: category,
            results: results.first(10),
            count: results.length,
            message: "Found #{results.length} result(s). Use the information above to proceed."
          )
        end
      rescue => e
        Rails.logger.error "[V3::Discover] Error: #{e.message}"
        error_response("Discovery failed: #{e.message}")
      end

      private

      def search_skills(query)
        results = []

        # 1. Search SkillLibraryService for built-in and custom skills
        skill_result = SkillLibraryService.discover_skills(
          message: query,
          entity: entity,
          integrations: detect_integrations(query),
          limit: 5
        )

        if skill_result
          results << {
            type: "skill",
            name: "Platform Skills",
            content: skill_result[:skill_block],
            sources: skill_result[:skill_names],
            relevance: "high"
          }
        end

        # 2. Search user's custom skills (UserSkill model)
        if entity.present?
          custom_skills = UserSkill.where(entity: entity)
                                   .where("name ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")
                                   .limit(3)

          custom_skills.each do |skill|
            results << {
              type: "custom_skill",
              name: skill.name,
              content: skill.content&.truncate(500),
              source: "user_uploaded",
              relevance: "medium"
            }
          end
        end

        results
      rescue => e
        Rails.logger.warn "[V3::Discover] Skills search error: #{e.message}"
        []
      end

      def search_integrations(query)
        results = []
        query_lower = query.downcase

        # Search available integrations
        integrations = Integration.all rescue []
        
        integrations.each do |integration|
          name_match = integration.name.downcase.include?(query_lower)
          slug_match = integration.slug.downcase.include?(query_lower)
          category_match = integration.category&.downcase&.include?(query_lower) rescue false

          next unless name_match || slug_match || category_match

          # Check if entity has this connected
          connection = entity.connections.find_by(integration: integration) rescue nil

          # Get available actions
          actions = IntegrationAction.where(integration: integration).limit(10).map do |a|
            { name: a.action_name, description: a.description }
          end rescue []

          results << {
            type: "integration",
            name: integration.name,
            slug: integration.slug,
            category: integration.category,
            connected: connection.present?,
            connection_status: connection&.status,
            available_actions: actions,
            relevance: name_match ? "high" : "medium"
          }
        end

        results
      rescue => e
        Rails.logger.warn "[V3::Discover] Integration search error: #{e.message}"
        []
      end

      def search_features(query)
        results = []
        query_lower = query.downcase

        # Static feature catalog — these describe platform capabilities
        features = [
          { name: "Landing Pages & Websites", keywords: %w[landing page website build design], description: "Create landing pages and websites. Use the platform_create tool with type='landing_page' for a single page, or type='website' for multi-page sites. Edit with the load_canvas tool using canvas_name='landing_page_editor'." },
          { name: "Workflows & Automations", keywords: %w[workflow automation trigger action automate flow], description: "Create automations that trigger actions. Use the platform_create tool with type='workflow'. View in the automation_dashboard canvas." },
          { name: "Applications / Web Apps", keywords: %w[app application webapp custom build software module], description: "Build custom applications with data models and interfaces. Use the platform_create tool with type='app'. A web app is just a website with workflows attached to forms." },
          { name: "Email Campaigns", keywords: %w[email campaign send blast newsletter], description: "Create email templates, build campaigns, and send to contact groups." },
          { name: "Email Sequences", keywords: %w[sequence drip follow-up nurture], description: "Automated email sequences with delays and triggers. Use the load_canvas tool with canvas_name='sequence_manager'." },
          { name: "CRM / Contacts", keywords: %w[contact crm lead customer pipeline opportunity], description: "Manage contacts, opportunities, activities, and sales pipeline." },
          { name: "Integrations", keywords: %w[integrate connect api stripe hubspot], description: "Connect external services. Use the load_canvas tool with canvas_name='integrations_manager'." },
          { name: "Bounty System", keywords: %w[bounty reward token contributor community], description: "Create bounties, track contributions, and award tokens." },
          { name: "Support Tickets", keywords: %w[ticket support help issue bug], description: "Track and resolve support issues." },
          { name: "Custom Modules", keywords: %w[module data model database schema], description: "Build custom data models and extend platform capabilities." },
          { name: "Scheduled Tasks", keywords: %w[schedule cron timer recurring], description: "Schedule automated tasks to run on a recurring basis." },
          { name: "Documents", keywords: %w[document upload file pdf knowledge], description: "Upload and query documents for knowledge base." },
          { name: "Analytics", keywords: %w[analytics report metrics dashboard chart], description: "View platform analytics and create visualizations." },
          { name: "Web Search", keywords: %w[search web internet research], description: "Search the web for real-time information." }
        ]

        features.each do |feature|
          if feature[:keywords].any? { |k| query_lower.include?(k) } ||
             feature[:name].downcase.include?(query_lower)
            results << {
              type: "feature",
              name: feature[:name],
              description: feature[:description],
              relevance: "high"
            }
          end
        end

        results
      end

      def detect_integrations(query)
        query_lower = query.downcase
        known = %w[stripe hubspot salesforce mailgun twilio quickbooks coinbase shopify slack]
        known.select { |name| query_lower.include?(name) }
      end
    end
  end
end
