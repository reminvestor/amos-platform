# frozen_string_literal: true

module V3
  module Recipes
    # AppBuildRecipe - Build apps, modules, and data-driven applications
    #
    # Delegates to the existing ApplicationPlannerService + ApplicationBuildService
    # through PlatformCreateTool.
    #
    class AppBuildRecipe < Base
      PATTERNS = [
        /\bbuild\s*(a\s+|an\s+)?app/,
        /\bcreate\s*(a\s+|an\s+)?app/,
        /\bnew\s+app/,
        /\bbuild\s*(a\s+|an\s+)?module/,
        /\bcreate\s*(a\s+|an\s+)?module/,
        /\bnew\s+module/,
        /\bbuild\s*(a\s+|me\s+)?(a\s+)?crm/,
        /\bcreate\s*(a\s+|me\s+)?(a\s+)?crm/,
        /\bbuild\s*(a\s+)?(database|data\s*model|schema)/,
      ].freeze

      def self.matches?(goal, spec = {})
        PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        8 # Lower priority -- broader patterns
      end

      def execute(spec:)
        data = {
          name: spec_val(spec, :name) || "App",
          description: spec_val(spec, :description) || ""
        }

        # Pass through all other spec fields as requirements
        extra = spec.reject { |k, _| [:name, :description, "name", "description"].include?(k) }
        data.merge!(extra) if extra.any?

        platform_create(type: "app", data: data)
      end
    end
  end
end
