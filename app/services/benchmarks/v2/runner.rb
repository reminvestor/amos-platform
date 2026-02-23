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

      # Run with real-time progress callback (yields each result as it completes)
      def run_suite_with_progress(suite = :core, scenario_ids: nil, &on_result)
        scenarios = if scenario_ids
                      scenario_ids.map { |id| ScenarioLibrary.get(id.to_sym) }.compact
                    else
                      case suite
                      when :core then ScenarioLibrary.core_suite
                      when :full then ScenarioLibrary.all
                      when :single then ScenarioLibrary.all
                      when Symbol then ScenarioLibrary.by_level(suite)
                      else ScenarioLibrary.all
                      end
                    end

        run_scenarios(scenarios, suite_name: suite.to_s, &on_result)
      end

      # Run a specific list of scenarios
      def run_scenarios(scenarios, suite_name: "custom", &on_result)
        benchmark_run = create_benchmark_run(suite_name, scenarios.size)

        results = scenarios.map do |scenario|
          result = execute_scenario(scenario, benchmark_run)
          on_result&.call(result.except(:execution_result))
          result
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

        seen_canvases = Set.new

        progress_callback = lambda do |event|
          case event[:type]
          when :content
            result[:assistant_text] += (event[:text] || "").to_s
          when :working
            tool = event[:tool_name]
            next if tool == "processing"
            tool_counts[tool] += 1
          when :canvas_suggestion
            canvas_key = event[:canvas].to_s
            unless seen_canvases.include?(canvas_key)
              seen_canvases << canvas_key
              result[:tool_calls] << {
                tool_name: "load_canvas",
                success: true,
                error: nil,
                result_summary: "Canvas: #{canvas_key}",
                result_count: nil
              }
            end
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
          extracted = extract_tool_results_from_history(result[:conversation_history])
          if extracted.any?
            result[:tool_calls].concat(extracted)
          else
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
        end

        result
      end

      def extract_tool_results_from_history(conversation_history)
        return [] unless conversation_history.is_a?(Array)

        tool_calls = []
        tool_inputs = {}

        conversation_history.each do |msg|
          next unless msg[:content].is_a?(Array)

          msg[:content].each do |block|
            if block[:tool_use]
              tool_inputs[block[:tool_use][:id]] = {
                name: block[:tool_use][:name],
                input: block[:tool_use][:input]
              }
            end

            if block[:tool_result]
              tool_id = block[:tool_result][:tool_use_id]
              input_info = tool_inputs[tool_id] || {}
              raw = block[:tool_result][:content].to_s

              parsed = begin
                         JSON.parse(raw)
                       rescue
                         nil
                       end

              is_error = parsed.is_a?(Hash) && (parsed["error"].present? || parsed["success"] == false)
              summary = summarize_tool_result(input_info[:name], input_info[:input], parsed || raw)

              tool_calls << {
                tool_name: input_info[:name] || "unknown",
                success: !is_error,
                error: is_error ? (parsed&.dig("error") || raw.truncate(200)) : nil,
                result_summary: summary,
                input_summary: summarize_tool_input(input_info[:name], input_info[:input])
              }
            end
          end
        end

        tool_calls
      end

      def summarize_tool_result(tool_name, input, result)
        return result.to_s.truncate(500) unless result.is_a?(Hash)

        parts = []
        type = input&.dig('type') || input&.dig(:type)
        parts << "type=#{type}" if input.is_a?(Hash) && type.present?
        parts << result["message"].to_s.truncate(400) if result["message"].present?

        case tool_name
        when "platform_create"
          parts << "id=#{result['id']}" if result["id"]
          parts << "name=#{result['name'] || result['title']}" if result["name"] || result["title"]
          parts << "modules=#{result['modules']&.map { |m| "#{m['name']} (#{m['status']})" }&.join(', ')}" if result["modules"]
          parts << "subject=#{result['subject']}" if result["subject"]
          parts << "status=#{result['status']}" if result["status"]
        when "platform_query"
          parts << "count=#{result['count'] || result['total']}" if result["count"] || result["total"]
          parts << "summary: #{result['summary'].to_s.truncate(300)}" if result["summary"]
          if result["records"].is_a?(Array)
            parts << "returned #{result['records'].size} records"
            result["records"].first(3).each do |rec|
              rec_summary = rec.slice("id", "name", "email", "status", "title", "subject").compact
              parts << "  record: #{rec_summary.map { |k, v| "#{k}=#{v}" }.join(', ')}" if rec_summary.any?
            end
          end
          if result["data"].is_a?(Hash)
            parts << "data: #{result['data'].to_json.truncate(300)}"
          end
        when "platform_update"
          parts << "id=#{result['id']}" if result["id"]
          parts << "updated_fields=#{result['updated_fields']&.join(', ')}" if result["updated_fields"]
        end

        parts.reject(&:blank?).join(" | ").truncate(800)
      end

      def summarize_tool_input(tool_name, input)
        return "" unless input.is_a?(Hash)
        case tool_name
        when "platform_create"
          type = input["type"] || input[:type]
          data = input["data"] || input[:data] || {}
          key_fields = data.slice("name", "email", "title", "subject", "body", "status",
                                  "first_name", "last_name", "company", "description",
                                  :name, :email, :title, :subject, :body, :status,
                                  :first_name, :last_name, :company, :description)
          field_summary = key_fields.map { |k, v| "#{k}=#{v.to_s.truncate(80)}" }.first(6).join(", ")
          "create #{type}: #{field_summary.presence || data.keys.first(5).join(', ')}"
        when "platform_query"
          type = input["type"] || input[:type]
          filters = input["filters"] || input[:filters] || {}
          filter_summary = filters.any? ? " (#{filters.map { |k, v| "#{k}=#{v}" }.first(3).join(', ')})" : ""
          "query #{type}#{filter_summary}"
        when "platform_update"
          type = input["type"] || input[:type]
          data = input["data"] || input[:data] || {}
          "update #{type} id=#{input['id'] || input[:id]}: #{data.keys.first(5).join(', ')}"
        when "platform_execute"
          action = input["action"] || input[:action]
          "execute #{action}"
        else
          tool_name.to_s
        end.truncate(300)
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
          select_cols = [:id, :created_at]
          select_cols << :status if klass.column_names.include?("status")
          records = scope.select(*select_cols).to_a rescue []
          if records.any?
            created[model_name] = records.map do |r|
              entry = { id: r.id, created_at: r.created_at.iso8601 }
              entry[:status] = r.status if r.respond_to?(:status) && r.status.present?
              entry
            end
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
