# frozen_string_literal: true

module Workflows
  module Executors
    # ═══════════════════════════════════════════════════════════════
    # TRIGGER EXECUTORS
    # These handle the entry points of workflows
    # ═══════════════════════════════════════════════════════════════
    module TriggerExecutors
      # Module wrapper for Zeitwerk compatibility
    end

    # FormTriggerExecutor - Handles form submission triggers
    class FormTriggerExecutor < BaseExecutor
      def execute
        log_info "Processing form submission trigger"

        # Form data comes from the trigger context
        submission = context[:submission] || context[:form_data] || {}
        submitter = context[:submitter] || context[:user] || {}

        # Validate required fields if configured
        if config[:required_fields].present?
          missing = config[:required_fields].select { |f| submission[f].blank? }
          return failure("Missing required fields: #{missing.join(', ')}") if missing.any?
        end

        success(
          submission: submission,
          submitter: submitter,
          submitted_at: Time.current.iso8601,
          source: {
            landing_page_id: context[:landing_page_id],
            website_page_id: context[:website_page_id],
            form_id: context[:form_id]
          }
        )
      end
    end

    # WebhookTriggerExecutor - Handles webhook triggers
    class WebhookTriggerExecutor < BaseExecutor
      def execute
        log_info "Processing webhook trigger"

        payload = context[:payload] || context[:body] || {}
        headers = context[:headers] || {}

        # Parse JSON payload if string
        if payload.is_a?(String)
          begin
            payload = JSON.parse(payload)
          rescue JSON::ParserError
            # Keep as string if not valid JSON
          end
        end

        success(
          payload: payload,
          headers: headers.to_h.transform_keys(&:to_s),
          received_at: Time.current.iso8601,
          webhook_path: context[:webhook_path]
        )
      end
    end

    # ScheduleTriggerExecutor - Handles scheduled triggers
    class ScheduleTriggerExecutor < BaseExecutor
      def execute
        log_info "Processing scheduled trigger"

        success(
          trigger_time: Time.current.iso8601,
          run_count: context[:run_count] || 1,
          scheduled_time: context[:scheduled_time],
          schedule: {
            cron: config[:cron_expression],
            timezone: config[:timezone] || 'UTC'
          }
        )
      end
    end

    # RecordTriggerExecutor - Handles record create/update/delete events
    class RecordTriggerExecutor < BaseExecutor
      def execute
        log_info "Processing record event trigger"

        record = context[:record] || {}
        changes = context[:changes] || {}
        event_type = context[:event_type] || 'updated'

        success(
          record: record,
          changes: changes,
          event_type: event_type,
          module_id: context[:app_module_id],
          module_name: context[:app_module_name],
          triggered_at: Time.current.iso8601
        )
      end
    end

    # ManualTriggerExecutor - Handles manual/API triggers
    class ManualTriggerExecutor < BaseExecutor
      def execute
        log_info "Processing manual trigger"

        # Validate input against expected schema if configured
        if config[:input_schema].present?
          validation = validate_input_schema(context, config[:input_schema])
          return failure(validation[:error]) unless validation[:valid]
        end

        success(
          context: context.to_h,
          triggered_by: {
            user_id: user&.id,
            user_email: user&.email
          },
          triggered_at: Time.current.iso8601
        )
      end

      private

      def validate_input_schema(input, schema)
        # Simple schema validation
        required = schema['required'] || []
        
        missing = required.select { |field| input[field].blank? }
        
        if missing.any?
          { valid: false, error: "Missing required inputs: #{missing.join(', ')}" }
        else
          { valid: true }
        end
      end
    end
  end
end
