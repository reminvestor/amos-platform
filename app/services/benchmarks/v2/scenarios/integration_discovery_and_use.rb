# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class IntegrationDiscoveryAndUse
        INTEGRATION_SLUG = "bench-crm-api"
        ALL_BENCHMARK_SLUGS = %w[bench-crm-api bench-mailservice].freeze

        def self.cleanup!(entity)
          Integration.where(entity: entity, slug: ALL_BENCHMARK_SLUGS).find_each do |i|
            i.integration_actions.delete_all
            IntegrationLog.where(integration_operation_id: i.integration_operations.select(:id)).delete_all
            i.integration_operations.delete_all
            i.connections.each do |c|
              c.integration_credentials.delete_all
              c.integration_logs.delete_all
              c.destroy
            end
            i.destroy
          rescue => e
            Rails.logger.debug "[BenchmarkCleanup] Integration #{i.id}: #{e.message}"
          end
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] integration_discovery cleanup failed: #{e.message}"
        end

        def self.setup_integration!(entity, user)
          integration = Integration.where(entity: entity, slug: INTEGRATION_SLUG).first_or_create!(
            entity: entity,
            created_by: user,
            name: "BenchCRM",
            slug: INTEGRATION_SLUG,
            description: "A CRM platform for managing customer relationships",
            category: "crm",
            auth_type: :api_key,
            api_base_url: "https://api.benchcrm.example.com/v1",
            is_active: true,
            is_verified: false
          )
          integration.integration_actions.delete_all
          IntegrationLog.where(integration_operation_id: integration.integration_operations.select(:id)).delete_all
          integration.integration_operations.delete_all
          integration.connections.each { |c| c.integration_credentials.delete_all; c.integration_logs.delete_all; c.destroy }

          [
            { operation_id: "list_contacts", name: "List Contacts", description: "Retrieve all contacts", http_method: "GET", path_template: "/contacts" },
            { operation_id: "get_contact", name: "Get Contact", description: "Get a single contact by ID", http_method: "GET", path_template: "/contacts/{id}" },
            { operation_id: "create_contact", name: "Create Contact", description: "Create a new contact", http_method: "POST", path_template: "/contacts" },
            { operation_id: "list_deals", name: "List Deals", description: "List all deals in the pipeline", http_method: "GET", path_template: "/deals" },
            { operation_id: "create_deal", name: "Create Deal", description: "Create a new deal", http_method: "POST", path_template: "/deals" },
          ].each do |op_attrs|
            integration.integration_operations.create!(**op_attrs, is_enabled: true)
          end

          conn = Connection.create!(
            entity: entity,
            user: user,
            integration: integration,
            name: "BenchCRM Connection",
            status: :connected
          )

          conn.integration_credentials.create!(
            name: "BenchCRM API Key",
            auth_method: "header",
            credentials: { api_key: "bench_test_key_123" },
            status: :active
          )

          integration
        end

        def self.build
          Scenario.new(
            id: :integration_discovery_and_use,
            level: :L3,
            category: :integrations,
            name: "Discover integrations and explain capabilities",
            description: "Tests the AI's ability to navigate the integration system: " \
                         "discover what's connected, list available operations, and " \
                         "explain what can be done. Based on real user patterns where " \
                         "users ask 'what integrations do I have?' before trying to use them. " \
                         "A test CRM integration with 5 operations is seeded.",
            tags: [:core],
            setup: ->(entity:, user:) {
              IntegrationDiscoveryAndUse.cleanup!(entity)
              IntegrationDiscoveryAndUse.setup_integration!(entity, user)
            },
            teardown: ->(entity:, user:) {
              IntegrationDiscoveryAndUse.cleanup!(entity)
            },
            messages: [
              "What integrations do I have set up? Show me what's connected.",
              "What can I do with the BenchCRM integration? List the available operations.",
            ],
            assertions: [
              { type: :tool_called, tool_name: "platform_query", min_times: 1 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate integration discovery and explanation:
              1. DISCOVERY (0-20): Did the AI correctly identify what's connected?
                 - Used platform_query with type='integrations' to find connections
                 - Reported BenchCRM as a connected integration
                 - Showed connection status accurately
                 - Didn't hallucinate integrations that don't exist
              2. OPERATIONS (0-20): Did the AI correctly list available operations?
                 - Used platform_query with type='integration_operations' to list ops
                 - Listed the 5 operations (list_contacts, get_contact, create_contact, list_deals, create_deal)
                 - Described what each operation does
                 - Indicated which are read (GET) vs write (POST) operations
              3. COMMUNICATION (0-15): Was the information presented clearly?
                 - Well-organized (table or structured list)
                 - Explained capabilities in user-friendly terms (not raw API jargon)
                 - Offered to help the user take action (e.g., 'Want me to pull your contacts?')
              4. ACCURACY (0-10): No hallucinated capabilities or operations
                 - Only described operations that actually exist
                 - Didn't invent features the integration doesn't have
                 - Connection status reported correctly
            RUBRIC
            timeout_seconds: 180
          )
        end
      end
    end
  end
end
