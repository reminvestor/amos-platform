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
          er = result[:execution_result] || {}
          callback_result = result.except(:execution_result)
          callback_result[:routing] = {
            model_used: er[:model_used],
            pre_routed: er[:pre_routed],
            escalated: er[:escalated]
          }
          on_result&.call(callback_result)
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
            execution_result[:pre_routed] ||= turn_result[:pre_routed]
            execution_result[:escalated] ||= turn_result[:escalated]

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

        agent = nil
        begin
          Timeout.timeout(timeout) do
            agent = V3::AgentLoop.new(user: user, entity: entity, session_id: session_id, model: model)
            loop_result = agent.process_message_streaming(
              message,
              progress_callback,
              conversation_history
            )

            result[:model_used] = agent.model
            result[:pre_routed] = loop_result[:pre_routed] if loop_result.is_a?(Hash)
            result[:escalated] = loop_result[:escalated] if loop_result.is_a?(Hash)

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
          # On timeout, grab whatever conversation history the agent built
          result[:conversation_history] = agent&.conversation_messages if agent&.conversation_messages.present?
        rescue => e
          result[:errors] << "Turn execution error: #{e.message}"
        ensure
          extracted = extract_tool_results_from_history(result[:conversation_history])
          if extracted.any?
            result[:tool_calls].concat(extracted)
          else
            # Fallback: use progress callback counts. Tool calls that were
            # tracked succeeded individually even if the turn later timed out.
            tool_counts.each do |tool_name, count|
              count.times do
                result[:tool_calls] << {
                  tool_name: tool_name,
                  success: true,
                  error: nil,
                  result_summary: "(from progress tracking)",
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
              tu = block[:tool_use]
              use_id = tu[:tool_use_id] || tu[:id]
              tool_inputs[use_id] = {
                name: tu[:name],
                input: tu[:input]
              }
            end

            if block[:tool_result]
              tool_id = block[:tool_result][:tool_use_id] || block[:tool_result][:id]
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
          parts << "slug=#{result['slug']}" if result["slug"]
          parts << "contact_group_id=#{result['contact_group_id']}" if result["contact_group_id"]
          parts << "enrolled_count=#{result['enrolled_count']}" if result["enrolled_count"]
          parts << "steps_created=#{result['steps_created']}" if result["steps_created"]
          if result["steps"].is_a?(Array)
            result["steps"].each do |step|
              step = step.stringify_keys if step.respond_to?(:stringify_keys)
              parts << "  step#{step['step']}: subject='#{step['subject']}' delay=#{step['delay_hours']}h template_id=#{step['template_id']}"
            end
          end
          if type == "landing_page" && result["id"]
            lp = LandingPage.find_by(id: result["id"])
            if lp&.html_content.present?
              html = lp.html_content
              parts << "html_size=#{html.length} chars"
              sects = []
              sects << "hero" if html.match?(/hero|banner/i)
              sects << "features" if html.match?(/features?|benefits?/i)
              sects << "testimonials" if html.match?(/testimonial/i)
              sects << "pricing" if html.match?(/pricing|price|plan/i)
              sects << "form" if html.include?("<form")
              parts << "sections=#{sects.join(', ')}"
            end
          end
          if type.to_s.in?(%w[app module]) && result["modules"].is_a?(Array)
            result["modules"].each do |mod|
              mod_record = AppModule.find_by(id: mod["id"] || mod[:id])
              next unless mod_record
              schema = mod_record.metadata&.dig("schema", "fields") || mod_record.metadata&.dig(:schema, :fields) || []
              field_names = schema.map { |f| f["name"] || f[:name] }.compact
              parts << "  #{mod_record.name}: fields=[#{field_names.join(', ')}]" if field_names.any?
            end
          end
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

        parts.reject(&:blank?).join(" | ").truncate(1200)
      end

      def summarize_tool_input(tool_name, input)
        return "" unless input.is_a?(Hash)
        case tool_name
        when "platform_create"
          type = input["type"] || input[:type]
          data = input["data"] || input[:data] || {}
          parts = ["create #{type}"]

          key_fields = data.slice("name", "email", "title", "subject", "body", "status",
                                  "first_name", "last_name", "company", "description",
                                  "contact_group_id", "goal", "activate",
                                  :name, :email, :title, :subject, :body, :status,
                                  :first_name, :last_name, :company, :description,
                                  :contact_group_id, :goal, :activate)
          field_summary = key_fields.map { |k, v| "#{k}=#{v.to_s.truncate(80)}" }.first(8).join(", ")
          parts << field_summary if field_summary.present?

          emails = data["emails"] || data[:emails] || data["steps"] || data[:steps]
          if emails.is_a?(Array) && emails.any?
            parts << "emails=[#{emails.length} steps]"
            emails.each_with_index do |e, i|
              e = e.stringify_keys if e.respond_to?(:stringify_keys)
              subj = e["subject"] || e[:subject] || "(no subject)"
              delay = e["delay_hours"] || e[:delay_hours] || (e["delay_days"] || e[:delay_days] || 0).to_i * 24
              has_body = (e["body"] || e[:body]).present?
              has_personalization = (e["body"] || e[:body]).to_s.include?("{{")
              parts << "  step#{i + 1}: subject='#{subj.to_s.truncate(50)}' delay=#{delay}h body=#{has_body ? 'yes' : 'no'} personalized=#{has_personalization ? 'yes' : 'no'}"
            end
          end

          parts.join(", ").presence || "create #{type}: #{data.keys.first(5).join(', ')}"
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
          extra = []
          extra << "sequence_id=#{input['sequence_id'] || input[:sequence_id]}" if input['sequence_id'] || input[:sequence_id]
          extra << "group_id=#{input['group_id'] || input[:group_id]}" if input['group_id'] || input[:group_id]
          "execute #{action}#{extra.any? ? " (#{extra.join(', ')})" : ""}"
        else
          tool_name.to_s
        end.truncate(600)
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
