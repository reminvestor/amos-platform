# frozen_string_literal: true

module PlatformEvolution
  # DebugAgentService - AI-powered debugging for support tickets
  #
  # This service:
  # 1. Analyzes the error and gathers context
  # 2. Reviews relevant code files
  # 3. Searches for similar past issues
  # 4. Proposes fixes with confidence scores
  # 5. Can interact with users for more information
  #
  class DebugAgentService


    attr_reader :ticket, :session, :entity

    SYSTEM_PROMPT = <<~PROMPT
      You are a senior software engineer debugging a Rails application issue.

      Your job is to:
      1. Analyze the error message and stack trace
      2. Identify the root cause
      3. Propose a fix with high confidence

      When analyzing:
      - Look at the stack trace to find the originating file and line
      - Consider what might have changed recently
      - Think about edge cases and null checks
      - Consider database/model issues
      - Look for typos, missing methods, or incorrect arguments

      When proposing fixes:
      - Be specific about which file and line to change
      - Provide the exact code change needed
      - Explain why this fix will work
      - Rate your confidence (0.0 to 1.0)

      Always format your response as JSON:
      {
        "root_cause": "Clear explanation of what's causing the error",
        "confidence": 0.85,
        "proposed_fix": {
          "file": "app/services/example.rb",
          "line": 42,
          "original": "the original code",
          "replacement": "the fixed code",
          "explanation": "why this fixes the issue"
        },
        "additional_investigation_needed": false,
        "questions_for_user": []
      }
    PROMPT

    def initialize(ticket)
      @ticket = ticket
      @entity = ticket.entity
      @session = nil
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN DEBUGGING FLOW
    # ═══════════════════════════════════════════════════════════════════════════

    def start_debugging!
      @session = ticket.create_debug_session!
      @session.start_analysis!

      Rails.logger.info "[DebugAgent] Starting debug session #{@session.session_id} for #{ticket.ticket_number}"

      begin
        # Step 1: Gather context
        context = gather_context
        Rails.logger.info "[DebugAgent] Context gathered: error_class=#{context.dig(:error, :class)}, has_source=#{context[:source_code].present?}"

        # Step 2: Analyze with AI
        analysis = analyze_with_ai(context)

        if analysis.nil?
          # AI call failed - mark session as needing manual review
          @session.add_system_message("AI analysis failed. Manual investigation required.")
          @session.update!(status: 'gathering_info')
          Rails.logger.warn "[DebugAgent] AI analysis returned nil for #{ticket.ticket_number}"
        else
          # Step 3: Process results
          process_analysis(analysis)
        end
      rescue => e
        Rails.logger.error "[DebugAgent] Error during debugging: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        @session.add_system_message("Error during analysis: #{e.message}")
        @session.update!(status: 'gathering_info')
      end

      @session
    end

    def continue_debugging!(user_input)
      raise "No active session" unless @session

      @session.add_user_message(user_input)

      # Re-analyze with new information
      context = gather_context
      context[:user_input] = user_input
      context[:previous_analysis] = @session.root_cause_analysis

      analysis = analyze_with_ai(context)
      process_analysis(analysis)

      @session
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT GATHERING
    # ═══════════════════════════════════════════════════════════════════════════

    def gather_context
      context = {
        ticket: ticket.to_context,
        error: {
          class: ticket.error_class,
          message: ticket.error_message,
          stack_trace: ticket.stack_trace
        }
      }

      # Add source code if we can identify the file
      if ticket.error_file.present?
        context[:source_code] = read_source_file(ticket.error_file, ticket.error_line)
      elsif ticket.stack_trace.present?
        context[:source_code] = extract_source_from_stack_trace(ticket.stack_trace)
      end

      # Add recent similar errors
      context[:similar_errors] = find_similar_errors

      # Add recent code changes if available
      context[:recent_changes] = get_recent_git_changes

      # Add conversation history if continuing
      if @session.conversation_history.any?
        context[:conversation] = @session.messages_for_context
      end

      context
    end

    def read_source_file(file_path, line_number, context_lines: 15)
      full_path = Rails.root.join(file_path)
      return nil unless File.exist?(full_path)

      lines = File.readlines(full_path)
      start_line = [line_number - context_lines, 0].max
      end_line = [line_number + context_lines, lines.length].min

      {
        file: file_path,
        content: lines[start_line..end_line].join,
        start_line: start_line + 1,
        target_line: line_number
      }
    rescue => e
      Rails.logger.warn "[DebugAgent] Could not read file #{file_path}: #{e.message}"
      nil
    end

    def extract_source_from_stack_trace(stack_trace)
      return nil if stack_trace.blank?

      sources = []
      stack_trace.lines.first(5).each do |line|
        next unless line.include?('app/') || line.include?('lib/')

        match = line.match(/([^:]+):(\d+)/)
        next unless match

        file_path = match[1].gsub(Rails.root.to_s + '/', '')
        line_number = match[2].to_i

        source = read_source_file(file_path, line_number, context_lines: 10)
        sources << source if source
      end

      sources.first(3)
    end

    def find_similar_errors
      SupportTicket.where(entity: entity)
        .where.not(id: ticket.id)
        .where(error_class: ticket.error_class)
        .where(status: 'resolved')
        .order(resolved_at: :desc)
        .limit(3)
        .map do |t|
          {
            ticket_number: t.ticket_number,
            error_message: t.error_message,
            resolution: t.resolution_notes
          }
        end
    end

    def get_recent_git_changes
      # Get recent commits that might have caused the issue
      begin
        output = `cd #{Rails.root} && git log --oneline -10 2>/dev/null`
        output.split("\n").map do |line|
          sha, message = line.split(' ', 2)
          { sha: sha, message: message }
        end
      rescue
        []
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AI ANALYSIS
    # ═══════════════════════════════════════════════════════════════════════════

    def analyze_with_ai(context)
      prompt = build_analysis_prompt(context)

      response = call_ai(
        system_prompt: SYSTEM_PROMPT,
        user_prompt: prompt,
        model: 'qwen3-next-80b'  # Cost-efficient with strong code understanding
      )

      parse_ai_response(response)
    end

    def build_analysis_prompt(context)
      <<~PROMPT
        ## Error to Debug

        **Ticket:** #{context[:ticket][:ticket_number]}
        **Error Class:** #{context[:error][:class]}
        **Error Message:** #{context[:error][:message]}

        ### Stack Trace
        ```
        #{context[:error][:stack_trace]}
        ```

        #{format_source_code(context[:source_code])}

        #{format_similar_errors(context[:similar_errors])}

        #{format_conversation(context[:conversation])}

        #{context[:user_input] ? "**New information from user:** #{context[:user_input]}" : ""}

        Please analyze this error and propose a fix.
      PROMPT
    end

    def format_source_code(source_code)
      return "" unless source_code

      sources = source_code.is_a?(Array) ? source_code : [source_code]
      
      sources.map do |source|
        <<~CODE
          ### Source Code: #{source[:file]} (line #{source[:target_line]})
          ```ruby
          #{source[:content]}
          ```
        CODE
      end.join("\n")
    end

    def format_similar_errors(similar)
      return "" if similar.blank?

      text = "### Similar Past Issues\n"
      similar.each do |s|
        text += "- **#{s[:ticket_number]}**: #{s[:error_message]} → #{s[:resolution]}\n"
      end
      text
    end

    def format_conversation(conversation)
      return "" if conversation.blank?

      text = "### Previous Debug Conversation\n"
      conversation.each do |msg|
        text += "**#{msg[:role]}**: #{msg[:content]}\n\n"
      end
      text
    end

    def call_ai(system_prompt:, user_prompt:, model:)
      service = BedrockLlmService.new(model: model)
      
      response = service.chat(
        messages: [{ role: 'user', content: user_prompt }],
        system_prompt: system_prompt,
        max_tokens: 2000
      )

      # Track usage
      if @session
        @session.update!(
          ai_model_used: model,
          total_tokens_used: (@session.total_tokens_used || 0) + (response[:usage]&.dig(:total_tokens) || 0)
        )
      end

      response[:content]
    rescue => e
      Rails.logger.error "[DebugAgent] AI call failed: #{e.message}"
      nil
    end

    def parse_ai_response(response)
      return nil if response.blank?

      # Try to extract JSON from the response
      json_match = response.match(/\{[\s\S]*\}/)
      return nil unless json_match

      JSON.parse(json_match[0]).with_indifferent_access
    rescue JSON::ParserError => e
      Rails.logger.warn "[DebugAgent] Could not parse AI response as JSON: #{e.message}"
      { raw_response: response }
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # RESULT PROCESSING
    # ═══════════════════════════════════════════════════════════════════════════

    def process_analysis(analysis)
      return if analysis.blank?

      # Store the root cause
      if analysis[:root_cause]
        @session.set_root_cause!(
          analysis: analysis[:root_cause],
          confidence: analysis[:confidence] || 0.5
        )
        @session.add_agent_message("**Root Cause Identified:** #{analysis[:root_cause]}")
      end

      # Add proposed fix
      if analysis[:proposed_fix]
        fix = analysis[:proposed_fix]
        @session.add_proposed_fix(
          description: fix[:explanation],
          files: [fix[:file]],
          risk_level: determine_risk_level(fix),
          estimated_impact: 'Fixes the reported error'
        )
        @session.add_agent_message("**Proposed Fix:** #{fix[:explanation]}\n\nFile: `#{fix[:file]}`")
      end

      # Check if we need more information
      if analysis[:additional_investigation_needed] && analysis[:questions_for_user].present?
        questions = analysis[:questions_for_user].join("\n- ")
        @session.add_agent_message("I need more information:\n- #{questions}")
      elsif analysis[:proposed_fix] && (analysis[:confidence] || 0) >= 0.7
        # High confidence - proceed to fix proposal
        @session.select_fix!(index: 0, rationale: analysis[:root_cause])
      end
    end

    def determine_risk_level(fix)
      file = fix[:file].to_s

      return 'low' if file.include?('_test.rb') || file.include?('/spec/')
      return 'low' if file.include?('.md') || file.include?('.txt')
      return 'high' if file.include?('/models/') || file.include?('migration')
      return 'high' if file.include?('/services/') && file.include?('billing')
      
      'medium'
    end
  end
end

