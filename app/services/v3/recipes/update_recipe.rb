# frozen_string_literal: true

module V3
  module Recipes
    # UpdateRecipe - Generic update for any platform record
    #
    # Handles all update operations including:
    # - Standard record updates
    # - Landing page section editing
    # - Custom field management (add/remove)
    #
    class UpdateRecipe < Base
      UPDATE_PATTERNS = [
        /\bupdate\s+(a\s+|the\s+)?(contact|campaign|email|template|landing|opportunity|activity|automation|ticket)/,
        /\bchange\s+(a\s+|the\s+)?(contact|campaign|email|template|landing|opportunity|automation)/,
        /\bmodify\s+(a\s+|the\s+)?(contact|campaign|email|template|landing|opportunity|automation)/,
        /\bedit\s+(a\s+|the\s+)?(contact|campaign|email|template|opportunity|automation)/,
      ].freeze

      CUSTOM_FIELD_PATTERNS = [
        /\badd\s*(a\s+)?custom\s*field/,
        /\bcreate\s*(a\s+)?custom\s*field/,
        /\bnew\s+custom\s*field/,
        /\bremove\s*(a\s+)?custom\s*field/,
        /\bdelete\s*(a\s+)?custom\s*field/,
        /\badd\s*(a\s+)?field\s+to/,
      ].freeze

      def self.matches?(goal, spec = {})
        UPDATE_PATTERNS.any? { |p| goal.match?(p) } ||
          CUSTOM_FIELD_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        5 # Low priority -- very generic
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if CUSTOM_FIELD_PATTERNS.any? { |p| goal_lower.match?(p) }
          manage_custom_field(spec)
        else
          update_record(spec)
        end
      end

      private

      def update_record(spec)
        type = spec_val(spec, :type)
        id = spec_val(spec, :id)
        data = spec_val(spec, :data, {})

        # If type/id not in spec, try to extract from the goal
        if type.blank?
          type = detect_type(context[:original_goal] || "")
        end

        return error_response("Missing: type (e.g., 'contact', 'campaign')") if type.blank?
        return error_response("Missing: id") if id.blank?

        # If data is empty, treat the entire spec (minus type/id) as the data
        if data.empty?
          data = spec.reject { |k, _| [:type, :id, "type", "id"].include?(k) }
        end

        platform_update(type: type, id: id, data: data)
      end

      def manage_custom_field(spec)
        model_type = spec_val(spec, :model) || spec_val(spec, :type) || "contact"
        goal_lower = (context[:original_goal] || "").downcase

        if goal_lower.match?(/remove|delete/)
          field_name = spec_val(spec, :field_name) || spec_val(spec, :name)
          platform_update(
            type: "schema",
            id: model_type,
            data: { remove_field: field_name }
          )
        else
          field_data = {
            name: spec_val(spec, :field_name) || spec_val(spec, :name),
            field_type: spec_val(spec, :field_type, "string"),
            label: spec_val(spec, :label),
            description: spec_val(spec, :description),
            required: spec_val(spec, :required, false),
            options: spec_val(spec, :options, []),
            default: spec_val(spec, :default)
          }.compact

          platform_update(
            type: "schema",
            id: model_type,
            data: { add_field: field_data }
          )
        end
      end

      def detect_type(goal)
        case goal.downcase
        when /contact/ then "contact"
        when /campaign/ then "campaign"
        when /template/ then "email_template"
        when /landing/ then "landing_page"
        when /opportunity/ then "opportunity"
        when /automation/ then "automation"
        when /ticket/ then "support_ticket"
        when /activity/ then "activity"
        else nil
        end
      end
    end
  end
end
