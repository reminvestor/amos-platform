# frozen_string_literal: true

module Benchmarks
  module V2
    # Scorer - Automated benchmark scoring engine
    #
    # Two components combine into a 0-100 score:
    #   Structural assertions (0-50): Did the right things happen?
    #   Judge LLM quality    (0-50): How well were they done?
    #
    # The structural assertions are deterministic and fast.
    # The judge LLM evaluation is probabilistic but captures quality.
    #
    class Scorer
      ASSERTION_MAX = 35
      JUDGE_MAX = 65
      JUDGE_MODEL = "claude-sonnet-4-6"

      attr_reader :scenario, :execution_result

      # @param scenario [Scenario] The scenario that was executed
      # @param execution_result [Hash] Results from the runner:
      #   - :transcript [Array<Hash>] Full conversation messages
      #   - :tool_calls [Array<Hash>] All tool calls and results
      #   - :created_records [Hash] Records created during execution
      #   - :errors [Array<String>] Any errors encountered
      #   - :entity [Entity] The entity used
      #   - :duration_ms [Integer] Execution time
      def initialize(scenario:, execution_result:)
        @scenario = scenario
        @execution_result = execution_result
      end

      def score!
        assertion_result = run_assertions
        judge_result = run_judge_evaluation

        {
          total_score: assertion_result[:score] + judge_result[:score],
          max_score: ASSERTION_MAX + JUDGE_MAX,
          assertion_score: assertion_result[:score],
          assertion_max: ASSERTION_MAX,
          assertion_details: assertion_result[:details],
          judge_score: judge_result[:score],
          judge_max: JUDGE_MAX,
          judge_reasoning: judge_result[:reasoning],
          judge_breakdown: judge_result[:breakdown],
          passed: (assertion_result[:score] + judge_result[:score]) >= 50,
          scored_at: Time.current.iso8601
        }
      end

      private

      # ═══════════════════════════════════════════════════════════════
      # STRUCTURAL ASSERTIONS (0-50 points)
      # ═══════════════════════════════════════════════════════════════

      def run_assertions
        return { score: 0, details: [] } if scenario.assertions.empty?

        points_per_assertion = (ASSERTION_MAX.to_f / scenario.assertions.size).round(1)
        total = 0
        details = []

        scenario.assertions.each do |assertion|
          result = evaluate_assertion(assertion)
          points = result[:passed] ? points_per_assertion : 0
          total += points

          details << {
            type: assertion[:type],
            passed: result[:passed],
            points: points,
            message: result[:message]
          }
        end

        { score: [total.round, ASSERTION_MAX].min, details: details }
      end

      def evaluate_assertion(assertion)
        case assertion[:type].to_sym
        when :record_exists
          check_record_exists(assertion)
        when :tool_called
          check_tool_called(assertion)
        when :no_errors
          check_no_errors
        when :conversation_completed
          check_conversation_completed
        when :no_hallucinated_urls
          check_no_hallucinated_urls
        when :no_hallucinated_data
          check_no_hallucinated_data
        when :correct_model_used
          check_correct_model(assertion)
        when :response_contains_question
          check_response_contains_question(assertion)
        else
          { passed: false, message: "Unknown assertion type: #{assertion[:type]}" }
        end
      end

      def check_record_exists(assertion)
        model_name = assertion[:model]
        min_count = assertion[:min_count] || 1
        conditions = assertion[:conditions] || {}
        created = execution_result[:created_records]&.dig(model_name) || []

        matching = if conditions.any?
          created.select do |record|
            conditions.all? { |key, value| record[key].to_s == value.to_s }
          end
        else
          created
        end

        condition_label = conditions.any? ? " (#{conditions.map { |k, v| "#{k}=#{v}" }.join(', ')})" : ""
        if matching.size >= min_count
          { passed: true, message: "#{model_name}#{condition_label}: #{matching.size} created (need #{min_count})" }
        else
          { passed: false, message: "#{model_name}#{condition_label}: #{matching.size} created (need #{min_count})" }
        end
      end

      def check_tool_called(assertion)
        tool_name = assertion[:tool_name]
        min_times = assertion[:min_times] || 1
        optional = assertion[:optional] == true
        calls = execution_result[:tool_calls]&.select { |tc| tc[:tool_name] == tool_name } || []

        if calls.size >= min_times
          { passed: true, message: "#{tool_name} called #{calls.size}x (need #{min_times})" }
        elsif optional
          { passed: true, message: "#{tool_name} not called but optional (platform context sufficient)" }
        else
          { passed: false, message: "#{tool_name} called #{calls.size}x (need #{min_times})" }
        end
      end

      def check_no_errors
        errors = execution_result[:errors] || []
        tool_errors = execution_result[:tool_calls]&.select { |tc| tc[:success] == false } || []

        if errors.empty? && tool_errors.empty?
          { passed: true, message: "No errors" }
        else
          all_errors = errors + tool_errors.map { |tc| "#{tc[:tool_name]}: #{tc[:error]}" }
          { passed: false, message: "#{all_errors.size} error(s): #{all_errors.first(3).join('; ')}" }
        end
      end

      def check_conversation_completed
        transcript = execution_result[:transcript] || []
        has_assistant_response = transcript.any? { |m| m[:role] == "assistant" && m[:content].present? }

        if has_assistant_response
          { passed: true, message: "Conversation completed with assistant response" }
        else
          { passed: false, message: "No assistant response in transcript" }
        end
      end

      def check_no_hallucinated_urls
        transcript = execution_result[:transcript] || []
        assistant_text = transcript.select { |m| m[:role] == "assistant" }
                                   .map { |m| m[:content].to_s }
                                   .join(" ")

        fake_domains = assistant_text.scan(/https?:\/\/[^\s]+/)
                                     .select { |url| url.match?(/\.amoslabs\.com|\.example\.com/) }
                                     .reject { |url| url.include?("localhost") || url.include?("/design_preview/") }

        if fake_domains.empty?
          { passed: true, message: "No hallucinated URLs" }
        else
          { passed: false, message: "Hallucinated URLs: #{fake_domains.first(3).join(', ')}" }
        end
      end

      def check_no_hallucinated_data
        transcript = execution_result[:transcript] || []
        tool_calls = execution_result[:tool_calls] || []

        query_calls = tool_calls.select { |tc| tc[:tool_name] == "platform_query" }
        returned_empty = query_calls.any? { |tc| tc[:result_count].to_i == 0 }

        assistant_text = transcript.select { |m| m[:role] == "assistant" }
                                   .map { |m| m[:content].to_s }
                                   .join(" ")

        has_specific_numbers = assistant_text.match?(/\d+%|\d+\.\d+%|open rate|click.?through|conversion/)
        if returned_empty && has_specific_numbers
          { passed: false, message: "Query returned no data but response contains specific metrics" }
        else
          { passed: true, message: "No hallucinated data detected" }
        end
      end

      def check_correct_model(assertion)
        expected = assertion[:model_pattern]
        model_used = execution_result[:model_used]

        if model_used&.match?(expected)
          { passed: true, message: "Used #{model_used} (expected #{expected})" }
        else
          { passed: false, message: "Used #{model_used} (expected #{expected})" }
        end
      end

      def check_response_contains_question(assertion)
        message_index = assertion[:on_message] || 0
        transcript = execution_result[:transcript] || []

        assistant_responses = transcript.select { |m| m[:role] == "assistant" }
        response = assistant_responses[message_index]

        return { passed: false, message: "No assistant response at index #{message_index}" } unless response

        text = response[:content].to_s
        has_question = text.include?("?") || text.match?(/\b(what|how|which|can you|could you|would you|tell me)\b/i)

        if has_question
          { passed: true, message: "Response contains clarifying question" }
        else
          { passed: false, message: "Response should have asked questions but didn't" }
        end
      end

      # ═══════════════════════════════════════════════════════════════
      # JUDGE LLM QUALITY EVALUATION (0-50 points)
      # ═══════════════════════════════════════════════════════════════

      def run_judge_evaluation
        prompt = build_judge_prompt
        response = call_judge_llm(prompt)
        parse_judge_response(response)
      rescue => e
        Rails.logger.error "[BenchmarkScorer] Judge evaluation failed: #{e.message}"
        { score: 0, reasoning: "Judge evaluation failed: #{e.message}", breakdown: {} }
      end

      def build_judge_prompt
        transcript_text = format_transcript
        tool_calls_text = format_tool_calls
        created_records_text = format_created_records

        <<~PROMPT
          You are a benchmark judge evaluating an AI assistant's performance on a specific task.

          ## Scenario
          Name: #{scenario.name}
          Description: #{scenario.description}
          Level: #{scenario.level}

          ## User Messages
          #{scenario.messages.map.with_index { |m, i| "Turn #{i + 1}: #{m}" }.join("\n")}

          ## Conversation Transcript
          #{transcript_text}

          ## Tool Calls Made (with inputs and results)
          #{tool_calls_text.presence || "(no tool calls recorded)"}

          ## Records Created During Execution
          #{created_records_text.presence || "(no records created)"}

          ## Scoring Rubric
          #{scenario.quality_rubric}

          ## Important Context
          The AI receives a real-time Platform Overview in its system prompt with accurate counts
          (e.g., "Contacts: 5 | Campaigns: 0 | Landing Pages: 3"). These counts come from live
          database queries and are trustworthy. If the AI answers a question using this context
          instead of making a tool call (e.g., stating there are 0 campaigns without calling
          platform_query), that is CORRECT and EFFICIENT behavior — not laziness. Tool calls
          should only be required when the user needs details, filtered views, or specific records
          beyond what the summary provides.

          ## Instructions
          Score each criterion in the rubric. The total across all criteria should be 0-65.
          Judge based on the FULL evidence: transcript, tool call results, and records created.
          Tool results show what the platform actually produced — use these to verify task completion.
          Respond in JSON format:

          {
            "total_score": <0-65>,
            "breakdown": {
              "<criterion_name>": { "score": <number>, "max": <number>, "reasoning": "<why>" }
            },
            "overall_reasoning": "<1-2 sentence summary>",
            "strengths": ["<strength 1>", "<strength 2>"],
            "weaknesses": ["<weakness 1>", "<weakness 2>"]
          }
        PROMPT
      end

      def format_transcript
        (execution_result[:transcript] || []).map do |msg|
          role = msg[:role].upcase
          content = msg[:content].to_s.truncate(2000)
          "#{role}: #{content}"
        end.join("\n\n")
      end

      def format_created_records
        created = execution_result[:created_records] || {}
        return "" if created.empty?

        parts = []
        created.each do |model_name, records|
          status_breakdown = records.group_by { |r| r[:status] }.transform_values(&:size)
          status_info = status_breakdown.any? ? " (#{status_breakdown.map { |s, c| "#{c} #{s}" }.join(', ')})" : ""
          parts << "#{model_name}: #{records.size} created#{status_info} (IDs: #{records.map { |r| r[:id] }.join(', ')})"

          records.first(5).each do |record_info|
            detail = fetch_record_detail(model_name, record_info[:id])
            parts << "  - #{detail}" if detail.present?
          end
        end
        parts.join("\n")
      end

      def fetch_record_detail(model_name, id)
        klass = model_name.safe_constantize
        return nil unless klass

        record = klass.find_by(id: id)
        return nil unless record

        case model_name
        when "LandingPage"
          html = record.html_content.to_s
          sections = []
          sections << "hero" if html.match?(/hero|banner/i)
          sections << "features" if html.match?(/features?|benefits?/i)
          sections << "testimonials" if html.match?(/testimonial/i)
          sections << "pricing" if html.match?(/pricing|price|plan/i)
          sections << "form" if html.include?("<form")
          sections << "footer" if html.include?("<footer")
          "#{record.title} (#{html.length} chars HTML, sections: #{sections.join(', ')})"
        when "Contact"
          details = "#{record.first_name} #{record.last_name} <#{record.email}>"
          details += " (#{record.title})" if record.respond_to?(:title) && record.title.present?
          details += " @ #{record.company}" if record.respond_to?(:company) && record.company.present?
          details
        when "ContactGroup"
          member_count = record.contacts.count rescue 0
          members = record.contacts.limit(5).map { |c| c.email }.join(", ") rescue ""
          detail = "#{record.name} (#{member_count} members)"
          detail += ": #{members}" if members.present?
          detail
        when "Campaign"
          detail = "#{record.name} (status: #{record.status})"
          if record.respond_to?(:email_template) && record.email_template
            detail += " | template: #{record.email_template.subject}"
          end
          detail
        when "AppModule"
          field_count = record.module_codes.where(code_type: "model").count rescue 0
          schema_fields = record.metadata&.dig("schema", "fields") || record.metadata&.dig(:schema, :fields) || []
          field_names = schema_fields.map { |f| f["name"] || f[:name] }.compact
          detail = "#{record.name} (slug: #{record.slug}, status: #{record.status}, model_codes: #{field_count}"
          detail += ", fields: [#{field_names.join(', ')}]" if field_names.any?
          detail += ", app_id: #{record.app_id}" if record.app_id.present?
          detail += ")"
          detail
        when "EmailTemplate"
          body_preview = record.body.to_s.gsub(/<[^>]+>/, ' ').squish.truncate(150) rescue ""
          detail = "#{record.name} | subject: '#{record.subject}'"
          detail += " | body preview: #{body_preview}" if body_preview.present?
          detail
        when "EmailSequence"
          step_count = record.sequence_steps.count rescue 0
          steps_detail = begin
            record.sequence_steps.order(:step_number).limit(5).map do |step|
              template = step.email_template
              delay = step.respond_to?(:delay_hours) ? "#{step.delay_hours}h" : "?"
              subject = template&.subject || "no template"
              "Step #{step.step_number} (delay: #{delay}): #{subject}"
            end.join("; ")
          rescue
            ""
          end
          detail = "#{record.name} (#{step_count} steps, status: #{record.status})"
          detail += " | #{steps_detail}" if steps_detail.present?
          detail
        else
          record.respond_to?(:name) ? record.name : "id=#{id}"
        end
      rescue => e
        nil
      end

      def format_tool_calls
        (execution_result[:tool_calls] || []).map do |tc|
          status = tc[:success] ? "SUCCESS" : "ERROR"
          parts = ["- #{tc[:tool_name]} [#{status}]"]
          parts << "  Input: #{tc[:input_summary]}" if tc[:input_summary].present?
          parts << "  Result: #{tc[:result_summary]}" if tc[:result_summary].present?
          parts << "  Error: #{tc[:error]}" if tc[:error].present?
          parts.join("\n")
        end.join("\n\n")
      end

      def call_judge_llm(prompt)
        service = BedrockService.new
        response = service.send_message(
          "You are a strict but fair benchmark judge. Score precisely according to the rubric.",
          [{ role: "user", content: [{ text: prompt }] }],
          model: JUDGE_MODEL,
          max_tokens: 2000,
          temperature: 0.1,
          json_mode: true
        )

        if response.is_a?(String)
          response
        elsif response.is_a?(Hash)
          response.dig(:content) || response.dig("content") || response.to_s
        else
          response.to_s
        end
      end

      def parse_judge_response(response)
        text = response.is_a?(String) ? response : response.to_s

        json_match = text.match(/\{[\s\S]*\}/)
        return { score: 0, reasoning: "Could not parse judge response", breakdown: {} } unless json_match

        parsed = JSON.parse(json_match[0])
        score = [parsed["total_score"].to_i, JUDGE_MAX].min

        {
          score: score,
          reasoning: parsed["overall_reasoning"] || "",
          breakdown: parsed["breakdown"] || {},
          strengths: parsed["strengths"] || [],
          weaknesses: parsed["weaknesses"] || []
        }
      rescue JSON::ParserError => e
        { score: 0, reasoning: "JSON parse error: #{e.message}", breakdown: {} }
      end
    end
  end
end
