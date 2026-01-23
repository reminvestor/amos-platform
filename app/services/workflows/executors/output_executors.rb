# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # OUTPUT EXECUTORS
    # These handle workflow completion
    # ═══════════════════════════════════════════════════════════════

    # SuccessOutputExecutor - Marks workflow as successfully completed
    class SuccessOutputExecutor < BaseExecutor
      def execute
        log_info "Workflow completing successfully"

        message = interpolate(config[:message] || 'Workflow completed successfully')
        notify_user = config[:notify_user]

        # Collect final output from all inputs
        final_output = inputs.to_h

        # Notify user if configured
        if notify_user && user.present?
          send_completion_notification(message, final_output)
        end

        success(
          message: message,
          completed_at: Time.current.iso8601,
          data: final_output
        )
      end

      private

      def send_completion_notification(message, output)
        # Create a Hub notification or work item
        if defined?(AgentWorkItem)
          AgentWorkItem.create!(
            entity: entity,
            user: user,
            agent_name: 'Workflow',
            work_type: 'notification',
            status: 'completed',
            summary: message,
            content: output.to_json,
            metadata: {
              workflow_id: execution.automation_code_id,
              workflow_name: execution.automation_code.name,
              execution_id: execution.id
            }
          )
        end
      rescue => e
        log_warn "Failed to send completion notification: #{e.message}"
      end
    end

    # ErrorOutputExecutor - Marks workflow as failed
    class ErrorOutputExecutor < BaseExecutor
      def execute
        log_info "Workflow completing with error"

        error_message = interpolate(config[:error_message] || inputs[:error] || 'Workflow failed')
        notify_user = config[:notify_user] != false  # Default to true for errors
        retry_allowed = config[:retry_allowed] != false  # Default to true

        # Notify user if configured
        if notify_user && user.present?
          send_error_notification(error_message)
        end

        # Note: This returns success:true because the executor itself succeeded
        # The workflow will be marked as failed based on the node type
        success(
          error: error_message,
          failed_at: Time.current.iso8601,
          retry_allowed: retry_allowed
        )
      end

      private

      def send_error_notification(error_message)
        if defined?(AgentWorkItem)
          AgentWorkItem.create!(
            entity: entity,
            user: user,
            agent_name: 'Workflow',
            work_type: 'error',
            status: 'error',
            summary: "Workflow failed: #{execution.automation_code.name}",
            content: error_message,
            metadata: {
              workflow_id: execution.automation_code_id,
              workflow_name: execution.automation_code.name,
              execution_id: execution.id,
              error: error_message
            }
          )
        end
      rescue => e
        log_warn "Failed to send error notification: #{e.message}"
      end
    end

    # IntegrationCallExecutor - Calls integration actions
    class IntegrationCallExecutor < BaseExecutor
      def execute
        log_info "Calling integration action"

        integration_id = config[:integration_id]
        action = config[:action]

        return failure("Integration ID is required") if integration_id.blank?
        return failure("Action is required") if action.blank?

        integration = Integration.find_by(id: integration_id)
        return failure("Integration not found") unless integration

        # Check if integration is connected for this entity
        connection = EntityIntegration.find_by(entity: entity, integration: integration)
        return failure("Integration not connected") unless connection&.connected?

        # Build parameters from mapping
        params = build_params

        begin
          # Execute the integration action
          result = execute_integration_action(integration, action, params, connection)

          if result[:success]
            success(
              result: result[:data],
              integration: integration.name,
              action: action
            )
          else
            failure(result[:error])
          end
        rescue => e
          log_error "Integration call failed: #{e.message}"
          failure("Integration call failed: #{e.message}")
        end
      end

      private

      def build_params
        params = {}

        if config[:param_mapping].present?
          config[:param_mapping].each do |param_name, source_path|
            params[param_name] = resolve_path(source_path) || interpolate(source_path)
          end
        end

        params.merge(inputs[:params] || {})
      end

      def execute_integration_action(integration, action, params, connection)
        # Use the integration service
        service_class = "Integrations::#{integration.slug.camelize}Service".constantize
        service = service_class.new(entity: entity, connection: connection)
        service.execute_action(action, params)
      rescue NameError
        # Fallback to generic integration execution
        IntegrationActionService.new(integration, connection).execute(action, params)
      end
    end
  end
end
