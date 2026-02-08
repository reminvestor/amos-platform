# frozen_string_literal: true

module V3
  module Recipes
    # FileGenerationRecipe - Generate files (CSV, Excel, PDF) and images
    #
    class FileGenerationRecipe < Base
      FILE_PATTERNS = [
        /\bgenerate\s*(a\s+)?(csv|excel|xlsx|pdf|file|report|export)/,
        /\bcreate\s*(a\s+)?(csv|excel|xlsx|pdf|export)/,
        /\bexport\s+(to\s+)?(csv|excel|xlsx|pdf)/,
        /\bdownload\s*(a\s+)?(csv|excel|xlsx|pdf)/,
      ].freeze

      IMAGE_PATTERNS = [
        /\bgenerate\s*(a\s+|an\s+)?image/,
        /\bcreate\s*(a\s+|an\s+)?image/,
        /\bgenerate\s*(a\s+)?banner/,
        /\bcreate\s*(a\s+)?banner/,
        /\bgenerate\s*(a\s+)?logo/,
      ].freeze

      EMAIL_PATTERNS = [
        /\bsend\s*(a\s+|an\s+)?email\s+to/,
        /\bsend\s+email/,
        /\bemail\s+(to\s+)?[\w@]/,
      ].freeze

      def self.matches?(goal, spec = {})
        FILE_PATTERNS.any? { |p| goal.match?(p) } ||
          IMAGE_PATTERNS.any? { |p| goal.match?(p) } ||
          EMAIL_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        10
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if IMAGE_PATTERNS.any? { |p| goal_lower.match?(p) }
          generate_image(spec)
        elsif EMAIL_PATTERNS.any? { |p| goal_lower.match?(p) }
          send_email(spec)
        else
          generate_file(spec)
        end
      end

      private

      def generate_file(spec)
        platform_execute(
          action: "generate_file",
          inputs: {
            format: spec_val(spec, :format, "csv"),
            title: spec_val(spec, :title, "Data Export"),
            headers: spec_val(spec, :headers, []),
            rows: spec_val(spec, :rows, []),
            data: spec_val(spec, :data)
          }.compact
        )
      end

      def generate_image(spec)
        platform_execute(
          action: "generate_image",
          inputs: {
            prompt: spec_val(spec, :prompt) || spec_val(spec, :description),
            style: spec_val(spec, :style, "professional photography"),
            size: spec_val(spec, :size, "1024x1024"),
            title: spec_val(spec, :title)
          }.compact
        )
      end

      def send_email(spec)
        platform_execute(
          action: "send_email",
          inputs: {
            to: spec_val(spec, :to),
            subject: spec_val(spec, :subject),
            body: spec_val(spec, :body)
          }.compact
        )
      end
    end
  end
end
