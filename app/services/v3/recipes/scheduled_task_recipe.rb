# frozen_string_literal: true

module V3
  module Recipes
    # ScheduledTaskRecipe - Create and manage scheduled tasks
    #
    class ScheduledTaskRecipe < Base
      PATTERNS = [
        /\bcreate\s*(a\s+)?scheduled\s*task/,
        /\bnew\s+scheduled\s*task/,
        /\bschedule\s*(a\s+)?task/,
        /\bset\s*up\s*(a\s+)?recurring/,
        /\bcreate\s*(a\s+)?cron/,
        /\bschedule\s*(a\s+)?(daily|weekly|hourly|monthly)/,
      ].freeze

      def self.matches?(goal, spec = {})
        PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        10
      end

      def execute(spec:)
        data = {
          name: spec_val(spec, :name) || "Scheduled Task",
          prompt: spec_val(spec, :prompt) || spec_val(spec, :description) || "",
          schedule: spec_val(spec, :schedule, "daily"),
          task_type: spec_val(spec, :task_type, "custom"),
          timezone: spec_val(spec, :timezone, "America/Los_Angeles")
        }.compact

        platform_create(type: "scheduled_task", data: data)
      end
    end
  end
end
