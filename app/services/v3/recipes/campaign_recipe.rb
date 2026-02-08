# frozen_string_literal: true

module V3
  module Recipes
    # CampaignRecipe - Create and send email campaigns
    #
    # Handles:
    # - Campaign creation (with optional template + contact group)
    # - Campaign sending
    # - Sequence enrollment
    #
    class CampaignRecipe < Base
      CREATE_PATTERNS = [
        /\bcreate\s*(a\s+)?campaign/,
        /\bnew\s+campaign/,
        /\bset\s*up\s*(a\s+)?campaign/,
        /\bbuild\s*(a\s+)?campaign/,
        /\blaunch\s*(a\s+)?campaign/,
        /\bcreate\s*(a\s+)?email\s*campaign/,
        /\bset\s*up\s*(a\s+)?drip/,
        /\bdrip\s*campaign/,
      ].freeze

      SEND_PATTERNS = [
        /\bsend\s*(a\s+|the\s+)?campaign/,
        /\bsend\s*out\s*(the\s+)?campaign/,
        /\bblast\s*(a\s+|the\s+)?email/,
      ].freeze

      SEQUENCE_PATTERNS = [
        /\benroll\s*(in\s+)?(a\s+)?sequence/,
        /\badd\s+to\s+sequence/,
        /\bcreate\s*(a\s+)?sequence/,
        /\bemail\s+sequence/,
      ].freeze

      def self.matches?(goal, spec = {})
        CREATE_PATTERNS.any? { |p| goal.match?(p) } ||
          SEND_PATTERNS.any? { |p| goal.match?(p) } ||
          SEQUENCE_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        10
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if SEND_PATTERNS.any? { |p| goal_lower.match?(p) }
          send_campaign(spec)
        elsif SEQUENCE_PATTERNS.any? { |p| goal_lower.match?(p) }
          handle_sequence(spec)
        else
          create_campaign(spec)
        end
      end

      private

      def create_campaign(spec)
        data = {
          name: spec_val(spec, :name) || "Campaign",
          email_template_id: spec_val(spec, :email_template_id) || spec_val(spec, :template_id),
          contact_group_ids: spec_val(spec, :contact_group_ids)
        }.compact

        # Pass through additional data
        data.merge!(spec_val(spec, :data, {}))

        platform_create(type: "campaign", data: data)
      end

      def send_campaign(spec)
        campaign_id = spec_val(spec, :campaign_id) || spec_val(spec, :id)
        return error_response("Missing: campaign_id") if campaign_id.blank?

        platform_execute(action: "send_campaign", campaign_id: campaign_id)
      end

      def handle_sequence(spec)
        sequence_id = spec_val(spec, :sequence_id) || spec_val(spec, :id)
        contact_ids = spec_val(spec, :contact_ids, [])

        if sequence_id && contact_ids.any?
          # Enroll contacts in sequence
          platform_execute(
            action: "enroll_sequence",
            sequence_id: sequence_id,
            contact_ids: contact_ids
          )
        else
          # Create a new sequence (pass through to platform_create)
          data = {
            name: spec_val(spec, :name) || "Email Sequence",
            description: spec_val(spec, :description)
          }.compact
          data.merge!(spec_val(spec, :data, {}))
          platform_create(type: "email_sequence", data: data)
        end
      end
    end
  end
end
