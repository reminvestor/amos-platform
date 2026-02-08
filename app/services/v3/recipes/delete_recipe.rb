# frozen_string_literal: true

module V3
  module Recipes
    # DeleteRecipe - Delete any platform record
    #
    class DeleteRecipe < Base
      PATTERNS = [
        /\bdelete\s+(a\s+|the\s+)?(contact|campaign|email|template|landing|opportunity|activity|automation|ticket|group|sequence)/,
        /\bremove\s+(a\s+|the\s+)?(contact|campaign|email|template|landing|opportunity|activity|automation|ticket|group|sequence)/,
        /\bdestroy\s+(a\s+|the\s+)?(contact|campaign|email|template|landing|opportunity|activity|automation|ticket)/,
      ].freeze

      def self.matches?(goal, spec = {})
        PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        8
      end

      def execute(spec:)
        type = spec_val(spec, :type) || detect_type(context[:original_goal] || "")
        id = spec_val(spec, :id)

        return error_response("Missing: type") if type.blank?
        return error_response("Missing: id") if id.blank?

        platform_execute(action: "delete", type: type, id: id)
      end

      private

      def detect_type(goal)
        case goal.downcase
        when /contact\s*group|group/ then "contact_group"
        when /contact/ then "contact"
        when /campaign/ then "campaign"
        when /template/ then "email_template"
        when /sequence/ then "email_sequence"
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
