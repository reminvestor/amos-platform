# frozen_string_literal: true

module V3
  module Recipes
    # IntegrationRecipe - Execute integration actions and set up syncs
    #
    # Handles:
    # - Running integration operations (stripe list_charges, hubspot get_contacts, etc.)
    # - Setting up data syncs between integrations and platform
    #
    class IntegrationRecipe < Base
      ACTION_PATTERNS = [
        /\brun\s*(an?\s+)?integration/,
        /\bexecute\s*(an?\s+)?integration/,
        /\b(stripe|hubspot|quickbooks|mailgun|coinbase)\s+\w+/,
        /\blist\s+(stripe|hubspot)\s+/,
        /\bget\s+(stripe|hubspot)\s+/,
        /\bpull\s+(stripe|hubspot)\s+/,
        /\bfetch\s+(stripe|hubspot)\s+/,
        /\brun\s+integration\s+action/,
        /\bintegration\s+action/,
      ].freeze

      SYNC_PATTERNS = [
        /\bsync\s+(stripe|hubspot|quickbooks)/,
        /\b(stripe|hubspot|quickbooks)\s+sync/,
        /\bset\s*up\s*(a\s+)?sync/,
        /\bcreate\s*(a\s+)?sync/,
        /\bsync\s+\w+\s+(customers?|contacts?|invoices?|charges?)/,
        /\bimport\s+from\s+(stripe|hubspot|quickbooks)/,
      ].freeze

      def self.matches?(goal, spec = {})
        ACTION_PATTERNS.any? { |p| goal.match?(p) } ||
          SYNC_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        12 # Higher than generic to catch integration keywords
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if SYNC_PATTERNS.any? { |p| goal_lower.match?(p) }
          create_sync(spec)
        else
          run_integration_action(spec)
        end
      end

      private

      def run_integration_action(spec)
        integration = spec_val(spec, :integration) || detect_integration(context[:original_goal] || "")
        operation = spec_val(spec, :operation) || spec_val(spec, :action)
        inputs = spec_val(spec, :inputs, {})

        return error_response("Missing: integration (e.g., 'stripe', 'hubspot')") if integration.blank?
        return error_response("Missing: operation (e.g., 'list_charges', 'get_contacts')") if operation.blank?

        platform_execute(
          action: "integration",
          integration: integration,
          operation: operation,
          inputs: inputs
        )
      end

      def create_sync(spec)
        platform_create(
          type: "sync",
          data: {
            integration: spec_val(spec, :integration) || detect_integration(context[:original_goal] || ""),
            source: spec_val(spec, :source) || spec_val(spec, :resource_type),
            target: spec_val(spec, :target) || "Contact",
            field_mappings: spec_val(spec, :field_mappings, {}),
            schedule: spec_val(spec, :schedule, "manual"),
            direction: spec_val(spec, :direction, "inbound"),
            run_now: spec_val(spec, :run_now, false)
          }.compact
        )
      end

      def detect_integration(goal)
        case goal.downcase
        when /stripe/ then "stripe"
        when /hubspot/ then "hubspot"
        when /quickbooks/ then "quickbooks"
        when /mailgun/ then "mailgun"
        when /coinbase/ then "coinbase"
        else nil
        end
      end
    end
  end
end
