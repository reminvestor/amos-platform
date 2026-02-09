# frozen_string_literal: true

module V3
  module Recipes
    # IntegrationRecipe - Execute integration actions, set up syncs, and connect integrations
    #
    # Handles:
    # - Running integration operations (stripe list_charges, hubspot get_contacts, etc.)
    # - Setting up data syncs between integrations and platform
    # - Connecting / setting up new integrations (routes to Brain for multi-step setup)
    #
    class IntegrationRecipe < Base
      ACTION_PATTERNS = [
        /\brun\s*(an?\s+)?integration/,
        /\bexecute\s*(an?\s+)?integration/,
        /\b(stripe|hubspot|quickbooks|mailgun|coinbase|shopify|trello|slack|mailchimp|sendgrid)\s+\w+/,
        /\blist\s+(stripe|hubspot|shopify)\s+/,
        /\bget\s+(stripe|hubspot|shopify)\s+/,
        /\bpull\s+(stripe|hubspot|shopify)\s+/,
        /\bfetch\s+(stripe|hubspot|shopify)\s+/,
        /\bshow\s+(my\s+)?(stripe|hubspot|shopify)\s+/,
        /\brun\s+integration\s+action/,
        /\bintegration\s+action/,
      ].freeze

      SYNC_PATTERNS = [
        /\bsync\s+(stripe|hubspot|quickbooks|shopify)/,
        /\b(stripe|hubspot|quickbooks|shopify)\s+sync/,
        /\bset\s*up\s*(a\s+)?sync/,
        /\bcreate\s*(a\s+)?sync/,
        /\bsync\s+\w+\s+(customers?|contacts?|invoices?|charges?|orders?)/,
        /\bimport\s+from\s+(stripe|hubspot|quickbooks|shopify)/,
        /\bkeep\s+.*(updated?|synced?)\s+from/,
      ].freeze

      # Setup patterns — these need multi-step reasoning, so route to Brain
      SETUP_PATTERNS = [
        /\bconnect\s+(my\s+)?(stripe|hubspot|quickbooks|shopify|trello|slack|mailchimp|sendgrid|\w+)/,
        /\bset\s*up\s+(my\s+)?(stripe|hubspot|quickbooks|shopify|trello|slack|mailchimp|\w+)\s*(integration)?/,
        /\bintegrate\s+(with\s+)?(stripe|hubspot|quickbooks|shopify|trello|slack|mailchimp|\w+)/,
        /\badd\s+(a\s+)?(new\s+)?integration/,
        /\bcreate\s+(a\s+)?(new\s+)?integration/,
        /\bconnect\s+(a\s+)?(new\s+)?api/,
        /\bconnect\s+to\s+/,
        /\bset\s*up\s+(a\s+)?(new\s+)?integration/,
        /\blink\s+(my\s+)?\w+\s*(account)?/,
      ].freeze

      def self.matches?(goal, spec = {})
        goal_lower = goal.to_s.downcase
        ACTION_PATTERNS.any? { |p| goal_lower.match?(p) } ||
          SYNC_PATTERNS.any? { |p| goal_lower.match?(p) } ||
          SETUP_PATTERNS.any? { |p| goal_lower.match?(p) }
      end

      def self.priority
        12 # Higher than generic to catch integration keywords
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if SETUP_PATTERNS.any? { |p| goal_lower.match?(p) }
          # Setup goals need multi-step reasoning (web_search, create, configure auth, etc.)
          # Route to the Brain which has the tools and intelligence to handle this
          route_to_brain(spec)
        elsif SYNC_PATTERNS.any? { |p| goal_lower.match?(p) }
          create_sync(spec)
        else
          run_integration_action(spec)
        end
      end

      private

      def route_to_brain(spec)
        # Return a signal that tells IntentEngine to route this to PlatformBrain
        # instead of handling it inline in the recipe
        {
          success: true,
          route_to_brain: true,
          goal: context[:original_goal],
          spec: spec,
          reason: "Integration setup requires multi-step reasoning with web research"
        }
      end

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
        when /shopify/ then "shopify"
        when /trello/ then "trello"
        when /slack/ then "slack"
        when /mailchimp/ then "mailchimp"
        when /sendgrid/ then "sendgrid"
        else nil
        end
      end
    end
  end
end
