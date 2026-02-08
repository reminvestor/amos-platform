# frozen_string_literal: true

module V3
  module Recipes
    # Base class for all recipes
    #
    # A recipe is a pre-defined handler that knows how to accomplish a specific
    # type of goal. Recipes execute entirely in Ruby (no LLM calls) making them
    # fast, reliable, and deterministic.
    #
    # Each recipe:
    #   1. Defines a matches? method that checks if a goal matches this recipe
    #   2. Implements execute() to accomplish the goal using existing service objects
    #   3. Returns a structured result hash
    #
    # Recipes can internally use the existing V3 tool classes (PlatformCreateTool,
    # PlatformUpdateTool, PlatformExecuteTool) as service objects, preserving all
    # existing functionality.
    #
    # Usage:
    #   recipe = V3::Recipes::Registry.find("welcome email automation", { trigger: "new_lead" })
    #   result = recipe.execute(spec: spec, user: user, entity: entity)
    #
    class Base
      attr_reader :user, :entity, :context, :progress_callback

      def initialize(user:, entity:, context: {}, progress_callback: nil)
        @user = user
        @entity = entity
        @context = context
        @progress_callback = progress_callback
      end

      # Override in subclasses: does this recipe handle the given goal?
      # @param goal [String] The goal description (lowercased)
      # @param spec [Hash] The spec data
      # @return [Boolean]
      def self.matches?(goal, spec = {})
        raise NotImplementedError, "Recipe must define self.matches?"
      end

      # Override in subclasses: execute the recipe
      # @param spec [Hash] The spec data from the LLM
      # @return [Hash] Result with { success: true/false, ... }
      def execute(spec:)
        raise NotImplementedError, "Recipe must implement execute"
      end

      # Optional: priority for recipe matching (higher = checked first)
      # Useful when multiple recipes could match the same goal
      def self.priority
        0
      end

      # Optional: human-readable name for logging/analytics
      def self.recipe_name
        name.demodulize.underscore.gsub("_recipe", "")
      end

      protected

      # ═══════════════════════════════════════════════════════════════
      # HELPERS: Delegate to existing V3 tools as service objects
      # ═══════════════════════════════════════════════════════════════

      # Create a platform object using the existing PlatformCreateTool
      def platform_create(type:, data:)
        tool = V3::Tools::PlatformCreateTool.new(
          user: user, entity: entity, context: context, progress_callback: progress_callback
        )
        tool.execute({ "type" => type, "data" => data.stringify_keys })
      end

      # Update a platform object using the existing PlatformUpdateTool
      def platform_update(type:, id:, data:)
        tool = V3::Tools::PlatformUpdateTool.new(
          user: user, entity: entity, context: context, progress_callback: progress_callback
        )
        tool.execute({ "type" => type, "id" => id, "data" => data.stringify_keys })
      end

      # Execute a platform action using the existing PlatformExecuteTool
      def platform_execute(args)
        tool = V3::Tools::PlatformExecuteTool.new(
          user: user, entity: entity, context: context, progress_callback: progress_callback
        )
        tool.execute(args.stringify_keys)
      end

      # Query platform data using the existing PlatformQueryTool
      def platform_query(args)
        tool = V3::Tools::PlatformQueryTool.new(
          user: user, entity: entity, context: context
        )
        tool.execute(args.stringify_keys)
      end

      # Helper: build a success response
      def success_response(data = {})
        { success: true }.merge(data)
      end

      # Helper: build an error response
      def error_response(message, details = {})
        { success: false, error: message }.merge(details)
      end

      # Helper: stream progress to the user
      def stream_progress(message, percentage: nil)
        return unless progress_callback

        progress_callback.call({
          type: "progress",
          tool: "platform_do",
          recipe: self.class.recipe_name,
          message: message,
          percentage: percentage,
          timestamp: Time.current.iso8601
        })
      end

      # Helper: extract value from spec with string/symbol flexibility
      def spec_val(spec, key, default = nil)
        spec[key] || spec[key.to_s] || default
      end
    end
  end
end
