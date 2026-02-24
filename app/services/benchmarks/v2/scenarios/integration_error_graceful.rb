# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class IntegrationErrorGraceful
        INTEGRATION_SLUG = "bench-mailservice"
        ALL_BENCHMARK_SLUGS = %w[bench-crm-api bench-mailservice].freeze

        def self.cleanup!(entity)
          integration_ids = Integration.where(entity: entity, slug: ALL_BENCHMARK_SLUGS).pluck(:id)
          return if integration_ids.empty?

          op_ids = IntegrationOperation.where(integration_id: integration_ids).pluck(:id)
          conn_ids = Connection.where(integration_id: integration_ids).pluck(:id)

          IntegrationAction.where(integration_id: integration_ids).delete_all
          IntegrationLog.where(integration_operation_id: op_ids).delete_all if op_ids.any?
          IntegrationLog.where(connection_id: conn_ids).delete_all if conn_ids.any?
          IntegrationOperation.where(id: op_ids).delete_all if op_ids.any?
          IntegrationCredential.where(connection_id: conn_ids).delete_all if conn_ids.any?
          Connection.where(id: conn_ids).delete_all if conn_ids.any?
          Integration.where(id: integration_ids).delete_all
        rescue => e
          Rails.logger.warn "[BenchmarkCleanup] integration_error cleanup failed: #{e.message}"
        end

        def self.setup_disconnected_integration!(entity, user)
          integration = Integration.where(entity: entity, slug: INTEGRATION_SLUG).first_or_create!(
            entity: entity,
            created_by: user,
            name: "BenchMail Service",
            slug: INTEGRATION_SLUG,
            description: "Email delivery service for transactional and marketing emails",
            category: "communication",
            auth_type: :api_key,
            api_base_url: "https://api.benchmail.example.com/v1",
            is_active: true,
            is_verified: false
          )
          op_ids = integration.integration_operations.pluck(:id)
          conn_ids = integration.connections.pluck(:id)
          integration.integration_actions.delete_all
          IntegrationLog.where(integration_operation_id: op_ids).delete_all if op_ids.any?
          IntegrationLog.where(connection_id: conn_ids).delete_all if conn_ids.any?
          integration.integration_operations.delete_all
          IntegrationCredential.where(connection_id: conn_ids).delete_all if conn_ids.any?
          Connection.where(id: conn_ids).delete_all if conn_ids.any?

          integration.integration_operations.create!(
            operation_id: "send_email",
            name: "Send Email",
            description: "Send a transactional email",
            http_method: "POST",
            path_template: "/messages",
            is_enabled: true
          )

          Connection.create!(
            entity: entity,
            user: user,
            integration: integration,
            name: "BenchMail Connection",
            status: :disconnected
          )

          integration
        end

        def self.build
          Scenario.new(
            id: :integration_error_graceful,
            level: :L4,
            category: :error_recovery,
            name: "Handle disconnected integration gracefully",
            description: "Modeled on real production failures: users ask the AI to use an " \
                         "integration that exists but has no active credentials (disconnected). " \
                         "Based on patterns from users who created Google Contacts integrations " \
                         "with 4 disconnected connections and zero successful API calls. " \
                         "The AI should detect the problem and guide the user to fix it " \
                         "rather than failing silently or hallucinating success.",
            tags: [],
            setup: ->(entity:, user:) {
              IntegrationErrorGraceful.cleanup!(entity)
              IntegrationErrorGraceful.setup_disconnected_integration!(entity, user)
            },
            teardown: ->(entity:, user:) {
              IntegrationErrorGraceful.cleanup!(entity)
            },
            messages: [
              "Send a test email through my BenchMail Service integration to test@example.com " \
              "with the subject 'Hello from AMOS' and body 'This is a test email.'",
            ],
            assertions: [
              { type: :no_hallucinated_data },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate how the AI handles a disconnected integration:
              1. ERROR DETECTION (0-25): Did the AI identify the real problem?
                 - Attempted to use the integration (via platform_execute or platform_query)
                 - Discovered the connection is disconnected or has no credentials
                 - Did NOT hallucinate that the email was sent successfully
                 - Did NOT say 'I don't have access to integrations' without checking
              2. USER GUIDANCE (0-20): Did the AI help the user fix the issue?
                 - Clearly explained WHY it failed (disconnected / no credentials)
                 - Directed user to the Integrations panel or settings to enter credentials
                 - Offered to help configure the integration
                 - Didn't just say 'error' without actionable next steps
              3. ALTERNATIVES (0-10): Did the AI suggest workarounds?
                 - Offered to send the email through the platform's built-in email (if available)
                 - Suggested checking if credentials are entered correctly
                 - Didn't leave the user stuck with no path forward
              4. TONE (0-10): Was the response helpful, not frustrating?
                 - Empathetic (the user has been trying to get this working)
                 - Clear and specific (not vague 'something went wrong')
                 - Professional and encouraging about resolving it
            RUBRIC
            timeout_seconds: 120
          )
        end
      end
    end
  end
end
