# frozen_string_literal: true

module Benchmarks
  module V2
    # Scenario - A single benchmark test case
    #
    # Each scenario is a self-contained, reproducible test that exercises
    # the platform through the real V3 agent loop. Scenarios define what
    # to test, how to score it, and what "good" looks like.
    #
    # Difficulty levels:
    #   L1 - Single step (too easy, retained for regression only)
    #   L2 - Multi-step workflows (new baseline difficulty)
    #   L3 - Complex orchestration (what real users do)
    #   L4 - Adversarial / edge cases (what breaks in production)
    #   L5 - Full workflow replay (mined from real failures)
    #
    class Scenario
      LEVELS = %i[L1 L2 L3 L4 L5].freeze
      CATEGORIES = %i[
        app_building
        content_creation
        integrations
        file_handling
        data_analysis
        error_recovery
        conversation_quality
      ].freeze
      SOURCES = %i[synthetic mined_failure user_contributed].freeze

      attr_reader :id, :level, :category, :name, :description,
                  :messages, :assertions, :quality_rubric,
                  :source, :tags, :timeout_seconds

      # @param id [Symbol] Unique identifier
      # @param level [Symbol] Difficulty level (L1-L5)
      # @param category [Symbol] Capability being tested
      # @param name [String] Human-readable name
      # @param description [String] What this scenario tests and why it's hard
      # @param messages [Array<String>] User messages (multi-turn conversation)
      # @param assertions [Array<Hash>] Structural checks to run after execution
      # @param quality_rubric [String] Prompt for the judge LLM
      # @param setup [Proc, nil] Lambda to create preconditions
      # @param teardown [Proc, nil] Lambda to clean up after
      # @param source [Symbol] Where this scenario came from
      # @param tags [Array<Symbol>] Optional tags for filtering
      # @param timeout_seconds [Integer] Max execution time
      def initialize(id:, level:, category:, name:, description:, messages:,
                     assertions:, quality_rubric:, setup: nil, teardown: nil,
                     source: :synthetic, tags: [], timeout_seconds: 300)
        @id = id
        @level = level
        @category = category
        @name = name
        @description = description
        @messages = messages
        @assertions = assertions
        @quality_rubric = quality_rubric
        @setup_proc = setup
        @teardown_proc = teardown
        @source = source
        @tags = tags
        @timeout_seconds = timeout_seconds

        validate!
      end

      def setup!(entity:, user:)
        @setup_proc&.call(entity: entity, user: user)
      end

      def teardown!(entity:, user:)
        @teardown_proc&.call(entity: entity, user: user)
      end

      def multi_turn?
        messages.length > 1
      end

      def core?
        tags.include?(:core)
      end

      def to_h
        {
          id: id,
          level: level,
          category: category,
          name: name,
          description: description,
          message_count: messages.length,
          assertion_count: assertions.length,
          source: source,
          tags: tags
        }
      end

      private

      def validate!
        raise ArgumentError, "Invalid level: #{level}" unless LEVELS.include?(level)
        raise ArgumentError, "Invalid category: #{category}" unless CATEGORIES.include?(category)
        raise ArgumentError, "Messages cannot be empty" if messages.empty?
        raise ArgumentError, "Quality rubric is required" if quality_rubric.blank?
      end
    end
  end
end
