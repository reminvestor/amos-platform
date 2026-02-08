# frozen_string_literal: true

module V3
  module Recipes
    # LandingPageRecipe - Build, edit, and publish landing pages and websites
    #
    # Handles:
    # - Creating new landing pages (delegates to existing GenerateLandingPageTool)
    # - Editing landing page sections
    # - Publishing landing pages
    # - Building multi-page websites
    #
    class LandingPageRecipe < Base
      BUILD_PATTERNS = [
        /\bbuild\s*(a\s+)?landing\s*page/,
        /\bcreate\s*(a\s+)?landing\s*page/,
        /\bgenerate\s*(a\s+)?landing\s*page/,
        /\bnew\s+landing\s*page/,
        /\bmake\s*(a\s+)?landing\s*page/,
        /\bbuild\s*(a\s+)?website/,
        /\bcreate\s*(a\s+)?website/,
        /\bnew\s+website/,
      ].freeze

      EDIT_PATTERNS = [
        /\bedit\s*(a\s+)?landing\s*page/,
        /\bedit\s*(the\s+)?.*section/,
        /\bchange\s*(the\s+)?.*section/,
        /\bupdate\s*(the\s+)?.*section/,
        /\bmodify\s*(the\s+)?(hero|header|footer|cta|pricing|features?|testimonial|faq|about)/,
      ].freeze

      PUBLISH_PATTERNS = [
        /\bpublish\s*(a\s+|the\s+)?landing\s*page/,
        /\bpublish\s+page/,
        /\bgo\s+live/,
      ].freeze

      def self.matches?(goal, spec = {})
        BUILD_PATTERNS.any? { |p| goal.match?(p) } ||
          EDIT_PATTERNS.any? { |p| goal.match?(p) } ||
          PUBLISH_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        10
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if PUBLISH_PATTERNS.any? { |p| goal_lower.match?(p) }
          publish_landing_page(spec)
        elsif EDIT_PATTERNS.any? { |p| goal_lower.match?(p) }
          edit_landing_page(spec)
        elsif goal_lower.match?(/website/)
          build_website(spec)
        else
          build_landing_page(spec)
        end
      end

      private

      def build_landing_page(spec)
        platform_create(type: "landing_page", data: spec_to_data(spec))
      end

      def build_website(spec)
        platform_create(type: "website", data: spec_to_data(spec))
      end

      def edit_landing_page(spec)
        landing_page_id = spec_val(spec, :landing_page_id) || spec_val(spec, :id)
        section = spec_val(spec, :section)
        instruction = spec_val(spec, :instruction)

        return error_response("Missing: landing_page_id") if landing_page_id.blank?

        platform_update(
          type: "landing_page",
          id: landing_page_id,
          data: { section: section, instruction: instruction }.compact
        )
      end

      def publish_landing_page(spec)
        landing_page_id = spec_val(spec, :landing_page_id) || spec_val(spec, :id)
        return error_response("Missing: landing_page_id") if landing_page_id.blank?

        platform_execute(action: "publish_landing_page", landing_page_id: landing_page_id)
      end

      def spec_to_data(spec)
        # Pass through spec as data, normalizing common field names
        data = spec.dup
        data["title"] ||= data.delete("name") if data["name"] && !data["title"]
        data
      end
    end
  end
end
