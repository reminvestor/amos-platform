# frozen_string_literal: true

module Benchmarks
  module V2
    # ScenarioMiner - Converts failed user conversations into benchmark scenarios
    #
    # The hardest benchmarks come from real failures. This service scans for
    # recent problematic interactions and generates candidate scenarios.
    #
    # Data sources:
    #   1. Negative user feedback (thumbs down)
    #   2. Tool execution errors clustered by session
    #   3. Abandoned sessions (active but no activity for > 1 hour)
    #   4. Sessions with re-ask patterns (user had to repeat themselves)
    #
    # The mining process:
    #   1. Query for recent failures
    #   2. Extract the full conversation
    #   3. Use a judge LLM to classify what went wrong
    #   4. Generate a candidate scenario with assertions
    #   5. Return candidates for review (not auto-added to library)
    #
    # Usage:
    #   miner = Benchmarks::V2::ScenarioMiner.new
    #   candidates = miner.mine(days: 7, limit: 10)
    #
    class ScenarioMiner
      JUDGE_MODEL = "claude-sonnet-4-6"

      def initialize(days: 7, limit: 10)
        @days = days
        @limit = limit
        @since = days.days.ago
      end

      # Mine recent failures and return candidate scenarios
      def mine(days: @days, limit: @limit)
        since = days.days.ago
        candidates = []

        negative_feedback_sessions(since, limit).each do |session_data|
          candidate = analyze_and_generate(session_data)
          candidates << candidate if candidate
        end

        error_cluster_sessions(since, limit).each do |session_data|
          next if candidates.any? { |c| c[:session_id] == session_data[:session_id] }
          candidate = analyze_and_generate(session_data)
          candidates << candidate if candidate
        end

        abandoned_sessions(since, limit).each do |session_data|
          next if candidates.any? { |c| c[:session_id] == session_data[:session_id] }
          candidate = analyze_and_generate(session_data)
          candidates << candidate if candidate
        end

        candidates.first(limit)
      end

      # Generate a single scenario from a specific session
      def mine_session(session_id)
        messages = ScoutMessage
                     .where(session_id: session_id)
                     .oldest_first
                     .pluck(:role, :content)

        return nil if messages.empty?

        session_data = {
          session_id: session_id,
          messages: messages,
          source: :manual_selection,
          failure_type: "manual"
        }

        analyze_and_generate(session_data)
      end

      private

      # ═══════════════════════════════════════════════════════════════
      # FAILURE DETECTION QUERIES
      # ═══════════════════════════════════════════════════════════════

      def negative_feedback_sessions(since, limit)
        feedbacks = UserFeedback
                      .where("created_at > ?", since)
                      .where(rating: -1)
                      .order(created_at: :desc)
                      .limit(limit)

        feedbacks.filter_map do |fb|
          session_id = fb.metadata&.dig("session_id") || fb.feedbackable&.try(:session_id)
          next unless session_id

          messages = ScoutMessage
                       .where(session_id: session_id)
                       .oldest_first
                       .pluck(:role, :content)

          next if messages.empty?

          {
            session_id: session_id,
            messages: messages,
            source: :negative_feedback,
            failure_type: "user_rated_negative",
            feedback_comment: fb.comment
          }
        end
      end

      def error_cluster_sessions(since, limit)
        error_sessions = AgentToolExecution
                           .where("created_at > ?", since)
                           .where(status: "error")
                           .group(:session_id)
                           .having("COUNT(*) >= 2")
                           .order("COUNT(*) DESC")
                           .limit(limit)
                           .pluck(:session_id)

        error_sessions.filter_map do |session_id|
          next unless session_id

          messages = ScoutMessage
                       .where(session_id: session_id)
                       .oldest_first
                       .pluck(:role, :content)

          next if messages.empty?

          error_count = AgentToolExecution
                          .where(session_id: session_id, status: "error")
                          .count

          {
            session_id: session_id,
            messages: messages,
            source: :error_cluster,
            failure_type: "multiple_tool_errors",
            error_count: error_count
          }
        end
      end

      def abandoned_sessions(since, limit)
        recent_sessions = ScoutMessage
                            .where("created_at > ?", since)
                            .select(:session_id)
                            .group(:session_id)
                            .having("MAX(created_at) < ?", 1.hour.ago)
                            .having("COUNT(*) >= 2")
                            .having("COUNT(CASE WHEN role = 'user' THEN 1 END) > COUNT(CASE WHEN role = 'assistant' THEN 1 END)")
                            .order("MAX(created_at) DESC")
                            .limit(limit)
                            .pluck(:session_id)

        recent_sessions.filter_map do |session_id|
          messages = ScoutMessage
                       .where(session_id: session_id)
                       .oldest_first
                       .pluck(:role, :content)

          next if messages.size < 2

          {
            session_id: session_id,
            messages: messages,
            source: :abandoned,
            failure_type: "abandoned_session"
          }
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # SCENARIO GENERATION
      # ═══════════════════════════════════════════════════════════════

      def analyze_and_generate(session_data)
        analysis = analyze_failure(session_data)
        return nil unless analysis

        build_candidate(session_data, analysis)
      rescue => e
        Rails.logger.error "[ScenarioMiner] Failed to generate scenario: #{e.message}"
        nil
      end

      def analyze_failure(session_data)
        conversation = session_data[:messages].map { |role, content|
          "#{role.upcase}: #{content.to_s.truncate(1000)}"
        }.join("\n\n")

        prompt = <<~PROMPT
          Analyze this failed conversation and classify the failure:

          ## Conversation
          #{conversation}

          ## Failure Context
          Failure type: #{session_data[:failure_type]}
          #{session_data[:feedback_comment] ? "User feedback: #{session_data[:feedback_comment]}" : ""}
          #{session_data[:error_count] ? "Tool errors: #{session_data[:error_count]}" : ""}

          Respond in JSON:
          {
            "user_intent": "What was the user trying to accomplish? (1-2 sentences)",
            "what_went_wrong": "What specifically went wrong? (1-2 sentences)",
            "category": "One of: app_building, content_creation, integrations, file_handling, data_analysis, error_recovery, conversation_quality",
            "difficulty_level": "L3 or L4 or L5",
            "key_messages": ["The 1-3 most important user messages to replay"],
            "expected_behavior": "What SHOULD have happened? (2-3 sentences)",
            "assertions": ["List of structural checks that would verify correct behavior"],
            "worth_benchmarking": true/false,
            "reason_if_not_worth": "Optional - why this isn't worth benchmarking"
          }
        PROMPT

        service = BedrockService.new
        response = service.send_message(
          "You are a QA analyst classifying failed AI conversations. Be specific and actionable.",
          [{ role: "user", content: [{ text: prompt }] }],
          model: JUDGE_MODEL,
          max_tokens: 1500,
          temperature: 0.1,
          json_mode: true
        )

        text = response.is_a?(String) ? response : response.dig(:content) || response.to_s
        json_match = text.match(/\{[\s\S]*\}/)
        return nil unless json_match

        parsed = JSON.parse(json_match[0])
        return nil unless parsed["worth_benchmarking"]

        parsed
      rescue JSON::ParserError
        nil
      end

      def build_candidate(session_data, analysis)
        id = "mined_#{session_data[:session_id].to_s.first(8)}"
        messages = analysis["key_messages"] || session_data[:messages].select { |r, _| r == "user" }.map(&:last).first(3)
        category = analysis["category"]&.to_sym || :conversation_quality
        level = analysis["difficulty_level"]&.to_sym || :L4

        assertions = build_assertions(analysis["assertions"] || [])

        rubric = <<~RUBRIC
          This scenario was mined from a real user failure.

          ## What the user was trying to do
          #{analysis["user_intent"]}

          ## What went wrong
          #{analysis["what_went_wrong"]}

          ## Expected behavior
          #{analysis["expected_behavior"]}

          ## Scoring
          1. TASK COMPLETION (0-20): Did the AI accomplish what the user wanted?
          2. ERROR HANDLING (0-15): If something went wrong, was it handled gracefully?
          3. COMMUNICATION (0-15): Was the interaction clear and helpful?
        RUBRIC

        {
          id: id.to_sym,
          session_id: session_data[:session_id],
          source: :mined_failure,
          failure_type: session_data[:failure_type],
          level: level,
          category: category,
          name: "Mined: #{analysis["user_intent"].to_s.truncate(60)}",
          description: analysis["what_went_wrong"],
          messages: messages,
          assertions: assertions,
          quality_rubric: rubric,
          analysis: analysis,
          mined_at: Time.current.iso8601
        }
      end

      def build_assertions(raw_assertions)
        raw_assertions.filter_map do |assertion_text|
          case assertion_text.to_s.downcase
          when /record.*creat|create.*record|module.*active/
            { type: :record_exists, model: "AppModule", conditions: { status: "active" } }
          when /tool.*call|platform_create|platform_query/
            tool = assertion_text.match(/platform_\w+/)&.to_s || "platform_create"
            { type: :tool_called, tool_name: tool, min_times: 1 }
          when /no.*error|error.*free/
            { type: :no_errors }
          when /complet|finish|respond/
            { type: :conversation_completed }
          when /no.*halluc/
            { type: :no_hallucinated_data }
          else
            nil
          end
        end.uniq { |a| a[:type] }
      end
    end
  end
end
