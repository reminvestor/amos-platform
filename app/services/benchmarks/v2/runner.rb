# frozen_string_literal: true

module Benchmarks
  module V2
    # Runner - Executes benchmark scenarios through the real V3 agent loop
    #
    # This is the core execution engine. It:
    #   1. Sets up a test environment for the scenario
    #   2. Sends messages through the V3 AgentLoop (the real platform path)
    #   3. Captures the full transcript, tool calls, and created records
    #   4. Runs the Scorer for automated evaluation
    #   5. Stores results in BenchmarkRun / BenchmarkTaskResult
    #
    # Usage:
    #   runner = Benchmarks::V2::Runner.new(entity: entity, user: user)
    #   results = runner.run_suite(:core)
    #   results = runner.run_scenario(:app_build_multi_module)
    #
    class Runner
      attr_reader :entity, :user, :run_type, :git_commit, :model

      def initialize(entity:, user:, run_type: "v2_benchmark", model: nil)
        @entity = entity
        @user = user
        @run_type = run_type
        @model = model
        @git_commit = `git rev-parse --short HEAD 2>/dev/null`.strip.presence
      end

      # Run the core suite (post-deploy quick check)
      def run_suite(suite = :core)
        scenarios = case suite
                    when :core then ScenarioLibrary.core_suite
                    when :full then ScenarioLibrary.all
                    when Symbol then ScenarioLibrary.by_level(suite)
                    else ScenarioLibrary.all
                    end

        run_scenarios(scenarios, suite_name: suite.to_s)
      end

      # Run a single scenario by ID
      def run_scenario(scenario_id)
        scenario = ScenarioLibrary.get(scenario_id)
        raise ArgumentError, "Unknown scenario: #{scenario_id}" unless scenario

        run_scenarios([scenario], suite_name: "single")
      end

      # Run a specific list of scenarios
      def run_scenarios(scenarios, suite_name: "custom")
        benchmark_run = create_benchmark_run(suite_name, scenarios.size)

        results = scenarios.map do |scenario|
          execute_scenario(scenario, benchmark_run)
        end

        complete_benchmark_run!(benchmark_run, results)

        {
          run_id: benchmark_run.run_id,
          git_commit: git_commit,
          suite: suite_name,
          total_scenarios: results.size,
          total_score: results.sum { |r| r[:score][:total_score] },
          max_score: results.sum { |r| r[:score][:max_score] },
          average_score: results.any? ? (results.sum { |r| r[:score][:total_score] }.to_f / results.size).round(1) : 0,
          pass_rate: results.any? ? (results.count { |r| r[:score][:passed] }.to_f / results.size * 100).round(1) : 0,
          duration_ms: results.sum { |r| r[:duration_ms] },
          scenario_results: results.map { |r| r.except(:execution_result) },
          benchmark_run_id: benchmark_run.id
        }
      end

      private

      def execute_scenario(scenario, benchmark_run)
        Rails.logger.info "[BenchmarkV2] Running scenario: #{scenario.id} (#{scenario.level})"
        started_at = Time.current

        execution_result = {
          transcript: [],
          tool_calls: [],
          created_records: {},
          errors: [],
          model_used: nil,
          entity: entity
        }

        begin
          scenario.setup!(entity: entity, user: user)

          before_counts = snapshot_record_counts(entity)
          session_id = SecureRandom.uuid
          conversation_history = []

          scenario.messages.each_with_index do |message, turn|
            Rails.logger.info "[BenchmarkV2] Turn #{turn + 1}/#{scenario.messages.size}: #{message.truncate(80)}"

            turn_result = execute_turn(message, session_id, conversation_history, timeout: scenario.timeout_seconds)

            execution_result[:transcript] << { role: "user", content: message }
            if turn_result[:assistant_text].present?
              execution_result[:transcript] << { role: "assistant", content: turn_result[:assistant_text] }
            end

            execution_result[:tool_calls].concat(turn_result[:tool_calls])
            execution_result[:errors].concat(turn_result[:errors])
            execution_result[:model_used] ||= turn_result[:model_used]

            conversation_history = turn_result[:conversation_history]
          end

          execution_result[:created_records] = detect_created_records(entity, before_counts)

        rescue Timeout::Error
          execution_result[:errors] << "Scenario timed out after #{scenario.timeout_seconds}s"
        rescue => e
          execution_result[:errors] << "Execution error: #{e.message}"
          Rails.logger.error "[BenchmarkV2] Scenario #{scenario.id} failed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
        ensure
          scenario.teardown!(entity: entity, user: user) rescue nil
        end

        duration_ms = ((Time.current - started_at) * 1000).round

        scorer = Scorer.new(scenario: scenario, execution_result: execution_result)
        score = scorer.score!

        task_result = store_task_result!(benchmark_run, scenario, score, execution_result, duration_ms)

        {
          scenario_id: scenario.id,
          scenario_name: scenario.name,
          level: scenario.level,
          category: scenario.category,
          score: score,
          duration_ms: duration_ms,
          task_result_id: task_result.id,
          execution_result: execution_result
        }
      end

      def execute_turn(message, session_id, conversation_history, timeout: 120)
        result = {
          assistant_text: "",
          tool_calls: [],
          errors: [],
          created_records: {},
          model_used: nil,
          conversation_history: conversation_history
        }

        tool_counts = Hash.new(0)

        progress_callback = lambda do |event|
          case event[:type]
          when :content
            result[:assistant_text] += (event[:text] || "").to_s
          when :working
            tool = event[:tool_name]
            next if tool == "processing"
            tool_counts[tool] += 1
          when :canvas_suggestion
            result[:tool_calls] << {
              tool_name: "load_canvas",
              success: true,
              error: nil,
              result_summary: "Canvas: #{event[:canvas]}",
              result_count: nil
            }
          end
        end

        begin
          Timeout.timeout(timeout) do
            agent = V3::AgentLoop.new(user: user, entity: entity, session_id: session_id, model: model)
            loop_result = agent.process_message_streaming(
              message,
              progress_callback,
              conversation_history
            )

            result[:model_used] = agent.model

            if loop_result.is_a?(Hash)
              result[:conversation_history] = loop_result[:conversation_history] if loop_result[:conversation_history]

              if result[:assistant_text].blank?
                result[:assistant_text] = loop_result.dig(:final_response, :message).to_s
              end

              (loop_result[:tools_used] || []).each { |t| tool_counts[t] += 1 if tool_counts[t] == 0 }
            end
          end
        rescue Timeout::Error
          result[:errors] << "Turn execution error: execution expired"
        rescue => e
          result[:errors] << "Turn execution error: #{e.message}"
        ensure
          tool_counts.each do |tool_name, count|
            count.times do
              result[:tool_calls] << {
                tool_name: tool_name,
                success: result[:errors].empty?,
                error: nil,
                result_summary: "",
                result_count: nil
              }
            end
          end
        end

        result
      end

      def snapshot_record_counts(_entity)
        { snapshot_at: Time.current }
      end

      def detect_created_records(entity, before_counts)
        created = {}
        since = before_counts[:snapshot_at]
        %w[Contact ContactGroup LandingPage Campaign AppModule EmailTemplate EmailSequence].each do |model_name|
          klass = model_name.safe_constantize
          next unless klass
          next unless klass.column_names.include?("created_at")

          scope = klass.where(entity_id: entity.id).where("created_at >= ?", since)
          records = scope.select(:id, :created_at).to_a rescue []
          if records.any?
            created[model_name] = records.map { |r| { id: r.id, created_at: r.created_at.iso8601 } }
          end
        end
        created
      end

      def merge_created_records!(target, source)
        source.each do |type, records|
          target[type] ||= []
          target[type].concat(records)
        end
      end

      def create_benchmark_run(suite_name, scenario_count)
        BenchmarkRun.create!(
          entity: entity,
          run_type: run_type,
          benchmark_category: "v2_#{suite_name}",
          agent_slug: "v3_agent_loop",
          model_used: model || V3::AgentLoop::DEFAULT_AUTO_MODEL,
          git_commit: git_commit,
          started_at: Time.current,
          total_tasks: scenario_count,
          metadata: {
            benchmark_version: "v2",
            suite: suite_name,
            scenario_count: scenario_count,
            runner: "Benchmarks::V2::Runner"
          }
        )
      end

      def complete_benchmark_run!(benchmark_run, results)
        scores = results.map { |r| r[:score][:total_score] }
        passed = results.count { |r| r[:score][:passed] }

        benchmark_run.complete!(
          total_tasks: results.size,
          correct_count: passed,
          failed_count: results.size - passed,
          accuracy_percentage: results.any? ? (passed.to_f / results.size * 100).round(1) : 0,
          avg_execution_time_ms: results.any? ? (results.sum { |r| r[:duration_ms] } / results.size).round : 0,
          total_tokens_used: 0,
          total_cost_cents: 0
        )
      end

      def store_task_result!(benchmark_run, scenario, score, execution_result, duration_ms)
        BenchmarkTaskResult.create!(
          benchmark_run: benchmark_run,
          task_id: scenario.id.to_s,
          category: scenario.category.to_s,
          difficulty: scenario.level.to_s,
          question: scenario.messages.first.truncate(500),
          expected_answer: scenario.quality_rubric.truncate(500),
          actual_answer: execution_result[:transcript]
                           .select { |m| m[:role] == "assistant" }
                           .map { |m| m[:content] }
                           .join("\n").truncate(500),
          correct: score[:passed],
          execution_time_ms: duration_ms,
          metadata: {
            total_score: score[:total_score],
            max_score: score[:max_score],
            assertion_score: score[:assertion_score],
            judge_score: score[:judge_score],
            assertion_details: score[:assertion_details],
            judge_reasoning: score[:judge_reasoning],
            judge_breakdown: score[:judge_breakdown],
            tool_calls_count: execution_result[:tool_calls].size,
            errors: execution_result[:errors],
            scenario_level: scenario.level.to_s,
            scenario_category: scenario.category.to_s
          }
        )
      end
    end
  end
end
