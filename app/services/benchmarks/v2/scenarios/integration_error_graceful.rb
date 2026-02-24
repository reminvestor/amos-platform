# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class IntegrationErrorGraceful
        INTEGRATION_SLUG = "bench-mailservice"
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
          integration.integration_actions.delete_all
          IntegrationLog.where(integration_operation_id: integration.integration_operations.select(:id)).delete_all
          integration.integration_operations.delete_all
          integration.connections.each { |c| c.integration_credentials.delete_all; c.integration_logs.delete_all; c.destroy }

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
