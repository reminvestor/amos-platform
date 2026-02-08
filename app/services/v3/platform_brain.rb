# frozen_string_literal: true

module V3
  # PlatformBrain - The intelligent backend executor
  #
  # Architecture:
  #   Amos (Qwen, cheap) = user-facing translator, understands WHAT
  #   PlatformBrain (Claude, powerful) = backend executor, figures out HOW and does it
  #
  # The Platform Brain:
  # - Receives a goal + spec from Amos via the IntentEngine
  # - Has NO personality, NO conversation history, NO streaming
  # - Has a focused system prompt about platform capabilities
  # - Has direct access to platform_create, platform_update, platform_execute, platform_query
  # - Runs its OWN agent loop to accomplish goals (not shared with Amos's loop)
  # - Can make multiple tool calls, inspect results, adapt, and retry
  # - Returns structured results back to Amos
  #
  # This is fundamentally different from the user-facing Amos:
  # - No identity/personality overhead
  # - No conversation history (just the goal)
  # - Uses Claude (reliable tool use) not Qwen
  # - Focused system prompt (~500 tokens vs ~5000)
  # - Non-streaming (runs server-side, returns when done)
  # - Executes V3 tools directly (not through ToolCatalog)
  #
  class PlatformBrain
    # Use Claude Sonnet for reliable tool execution
    BRAIN_MODEL = "claude-sonnet-4-5"
    BRAIN_MODEL_ID = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    MAX_TOOL_TURNS = 15

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the Platform Execution Brain. Your job is to accomplish a goal on the platform using the tools available to you.

      You receive a goal and optional spec. Figure out the steps needed and execute them using your tools.

      RULES:
      - Execute the goal completely. Don't ask questions -- just do it.
      - If you need information (e.g., an ID, a list of contacts), query first using platform_query.
      - If something fails, try to recover or adapt. Report what succeeded and what failed.
      - Be efficient: minimize tool calls. Combine when possible.
      - When done, respond with a brief summary of what you accomplished.

      PLATFORM CAPABILITIES:
      - platform_create: Create contacts, email_templates, campaigns, automations, landing_pages, apps, websites, syncs, scheduled_tasks, contact_groups, support_tickets
      - platform_update: Update any record by type + ID. Also: edit landing page sections (section + instruction), manage custom fields (add_field/remove_field on schema)
      - platform_execute: Run integration actions, send campaigns, publish landing pages, generate files (CSV/Excel/PDF), generate images, delete records, send emails, enroll in sequences
      - platform_query: Query any data (contacts, campaigns, stats, schema, integrations, documents)

      AUTOMATION DETAILS:
      - Triggers: contact_created, form_submit, record_updated, status_changed, field_changed, schedule, webhook
      - Actions: send_email, add_to_campaign, update_field, create_activity, call_webhook, notify_user
      - Landing pages auto-create contacts when forms are submitted (built-in, no setup needed)
      - A "welcome email flow" = create email_template + create automation with trigger="contact_created" action="send_email"

      IMPORTANT:
      - Always use the tools. Never claim you did something without a tool call.
      - If creating multiple related objects, do them in order (template first, then automation referencing the template ID).
    PROMPT

    def initialize(user:, entity:, context: {}, progress_callback: nil)
      @user = user
      @entity = entity
      @context = context
      @progress_callback = progress_callback
      @tools_called = []
    end

    # Execute a goal using the Platform Brain's agent loop
    # @param goal [String] What to accomplish
    # @param spec [Hash] Parameters and details
    # @return [Hash] Result with { success: true/false, message: "...", ... }
    def execute(goal:, spec: {})
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Rails.logger.info "[V3::PlatformBrain] Executing goal: #{goal}"

      # Build the initial conversation
      user_message = build_user_message(goal, spec)
      messages = [{ role: "user", content: [{ text: user_message }] }]

      # Build tool definitions
      tools = build_brain_tools

      # Run the agent loop
      final_text = run_agent_loop(messages, tools)

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      latency_ms = ((end_time - start_time) * 1000).round

      Rails.logger.info "[V3::PlatformBrain] Completed in #{latency_ms}ms, #{@tools_called.length} tool calls"

      {
        success: true,
        message: final_text,
        tools_used: @tools_called,
        _engine: {
          path: "platform_brain",
          model: BRAIN_MODEL,
          tool_calls: @tools_called.length,
          latency_ms: latency_ms
        }
      }
    rescue => e
      Rails.logger.error "[V3::PlatformBrain] Failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      {
        success: false,
        error: "Platform Brain execution failed: #{e.message}",
        _engine: { path: "platform_brain", error: e.message }
      }
    end

    private

    # ═══════════════════════════════════════════════════════════════
    # AGENT LOOP - The Brain's own tool-use loop
    # ═══════════════════════════════════════════════════════════════

    def run_agent_loop(messages, tools)
      client = bedrock_client
      turn_count = 0
      accumulated_text = ""

      loop do
        turn_count += 1
        if turn_count > MAX_TOOL_TURNS
          Rails.logger.warn "[V3::PlatformBrain] Exceeded max turns (#{MAX_TOOL_TURNS})"
          break
        end

        # Call Claude
        payload = {
          model_id: BRAIN_MODEL_ID,
          messages: messages,
          inference_config: { max_tokens: 4096, temperature: 0.3 },
          system: [{ text: SYSTEM_PROMPT }],
          tool_config: {
            tools: format_tools(tools),
            tool_choice: { auto: {} }
          }
        }

        response = client.converse(payload)
        content_blocks = response.output.message.content

        # Extract text and tool use blocks
        text_blocks = content_blocks.select { |b| b.respond_to?(:text) && b.text }
        tool_use_blocks = content_blocks.select { |b| b.respond_to?(:tool_use) && b.tool_use }

        # Accumulate any text
        text_blocks.each { |b| accumulated_text = b.text }

        # If no tool calls, we're done
        if tool_use_blocks.empty?
          Rails.logger.info "[V3::PlatformBrain] Turn #{turn_count}: Done (text response)"
          break
        end

        Rails.logger.info "[V3::PlatformBrain] Turn #{turn_count}: #{tool_use_blocks.length} tool call(s)"

        # Add assistant's response to conversation
        assistant_content = content_blocks.map do |block|
          if block.respond_to?(:tool_use) && block.tool_use
            { tool_use: { tool_use_id: block.tool_use.tool_use_id, name: block.tool_use.name, input: block.tool_use.input } }
          elsif block.respond_to?(:text) && block.text
            { text: block.text }
          end
        end.compact

        messages << { role: "assistant", content: assistant_content }

        # Execute tools and build results
        tool_results = tool_use_blocks.map do |block|
          tool_use = block.tool_use
          tool_name = tool_use.name
          tool_input = tool_use.input.to_h

          @tools_called << tool_name

          Rails.logger.info "[V3::PlatformBrain] Executing: #{tool_name}"

          result = execute_brain_tool(tool_name, tool_input)

          Rails.logger.info "[V3::PlatformBrain] Result: #{result.is_a?(Hash) && result[:success] != false ? '✅' : '❌'}"

          {
            tool_result: {
              tool_use_id: tool_use.tool_use_id,
              content: [{ text: result.to_json }]
            }
          }
        end

        # Add tool results to conversation
        messages << { role: "user", content: tool_results }

        # Check stop reason
        stop_reason = response.stop_reason rescue nil
        break if stop_reason == "end_turn"
      end

      accumulated_text.presence || "Goal executed with #{@tools_called.length} tool calls."
    end

    # ═══════════════════════════════════════════════════════════════
    # TOOL EXECUTION - Uses V3 tools directly
    # ═══════════════════════════════════════════════════════════════

    def execute_brain_tool(name, args)
      # Execute through V3::ToolRegistry which has all internal tools
      V3::ToolRegistry.execute(
        name,
        args,
        user: @user,
        entity: @entity,
        context: @context,
        progress_callback: @progress_callback
      )
    rescue => e
      Rails.logger.error "[V3::PlatformBrain] Tool #{name} error: #{e.message}"
      { success: false, error: e.message }
    end

    # ═══════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════

    def build_user_message(goal, spec)
      parts = ["Goal: #{goal}"]
      if spec.present? && spec.any?
        parts << "Spec: #{spec.to_json}"
      end

      # Add brief platform context
      entity_context = build_entity_context
      parts << entity_context if entity_context.present?

      parts.join("\n\n")
    end

    def build_entity_context
      begin
        counts = {
          contacts: @entity.contacts.count,
          campaigns: @entity.campaigns.count,
          email_templates: @entity.email_templates.count,
          landing_pages: @entity.landing_pages.count,
          automations: (AutomationCode.where(entity: @entity).count rescue 0)
        }.select { |_, v| v > 0 }

        if counts.any?
          "Current platform state: #{counts.map { |k, v| "#{v} #{k}" }.join(", ")}"
        end
      rescue => e
        Rails.logger.debug "[V3::PlatformBrain] Context build failed: #{e.message}"
        nil
      end
    end

    def build_brain_tools
      [
        V3::Tools::PlatformCreateTool,
        V3::Tools::PlatformUpdateTool,
        V3::Tools::PlatformExecuteTool,
        V3::Tools::PlatformQueryTool,
      ].map do |tool_class|
        metadata = tool_class.metadata
        {
          name: metadata[:name],
          description: metadata[:description],
          input_schema: metadata[:input_schema] || metadata[:parameters]
        }
      end
    end

    def format_tools(tools)
      tools.map do |tool|
        {
          tool_spec: {
            name: tool[:name],
            description: tool[:description],
            input_schema: { json: tool[:input_schema] }
          }
        }
      end
    end

    def bedrock_client
      # Use the same credential chain as BedrockService:
      # env vars → ECS/EC2 instance profile → ~/.aws/credentials
      # Do NOT hardcode credentials -- let the AWS SDK find them.
      @bedrock_client ||= Aws::BedrockRuntime::Client.new(
        region: ENV["AWS_REGION"] || "us-east-1",
        http_read_timeout: 300,
        http_open_timeout: 30
      )
    end
  end
end
