# frozen_string_literal: true

module Tools
  # GenerateAutomationCodeTool - AI generates deterministic Ruby code
  #
  # This is the key tool for creating automations. The AI writes Ruby code
  # that will run WITHOUT AI afterwards - fast, cheap, and predictable.
  #
  class GenerateAutomationCodeTool < BaseTool
    def self.metadata
      {
        name: "generate_automation_code",
        description: "Generate deterministic Ruby automation code. AI writes the code ONCE during setup, " \
                     "then it runs WITHOUT AI - fast (~50ms), cheap (no LLM cost), and predictable. " \
                     "Use this for: record events (create/update), status changes, scheduled tasks, webhooks, form submissions.",
        category: "automation",
        input_schema: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Name for this automation (e.g., 'Notify on Publish', 'Weekly Report')"
            },
            description: {
              type: "string",
              description: "Brief description of what this automation does"
            },
            trigger_type: {
              type: "string",
              enum: AutomationCode::TRIGGER_TYPES,
              description: "What triggers this automation"
            },
            trigger_config: {
              type: "object",
              description: "Trigger-specific config. For status_changed: { from: 'draft', to: 'published' }. " \
                           "For field_changed: { field: 'priority' }. For schedule: { schedule: 'daily', time: '09:00' }."
            },
            action_description: {
              type: "string",
              description: "Natural language description of what should happen when triggered"
            },
            app_module_id: {
              type: "integer",
              description: "Optional: AppModule this automation is for (for record triggers)"
            },
            web_app_id: {
              type: "integer",
              description: "Optional: WebApp this automation is for"
            }
          },
          required: %w[name trigger_type action_description]
        }
      }
    end

    def execute(args)
      log_execution(args)

      name = get_arg(args, :name)
      description = get_arg(args, :description, '')
      trigger_type = get_arg(args, :trigger_type)
      trigger_config = get_arg(args, :trigger_config, {})
      action_description = get_arg(args, :action_description)
      app_module_id = get_arg(args, :app_module_id)
      web_app_id = get_arg(args, :web_app_id)

      # Validate trigger type
      unless AutomationCode::TRIGGER_TYPES.include?(trigger_type)
        return error_response("Invalid trigger type: #{trigger_type}")
      end

      # Generate the Ruby code using AI
      code_result = generate_code(trigger_type, trigger_config, action_description)
      return error_response(code_result[:error]) unless code_result[:success]

      # Create the automation record
      automation = AutomationCode.new(
        entity: entity,
        created_by: user,
        web_app_id: web_app_id,
        app_module_id: app_module_id,
        name: name,
        description: description,
        trigger_type: trigger_type,
        trigger_config: trigger_config,
        code: code_result[:code],
        code_generated_at: Time.current,
        code_generated_by: 'claude-sonnet-4-20250514',
        status: 'testing'
      )

      unless automation.save
        return error_response("Failed to save automation: #{automation.errors.full_messages.join(', ')}")
      end

      # Test the generated code
      test_result = automation.test!

      if test_result[:success]
        success_response(
          automation_id: automation.id,
          name: automation.name,
          trigger_description: automation.trigger_description,
          status: 'testing',
          is_tested: true,
          message: "✅ Automation '#{name}' created and tested successfully!",
          code_preview: code_result[:code].lines.first(15).join,
          test_output: test_result[:data],
          test_duration_ms: test_result[:duration_ms],
          next_steps: [
            "Review the automation code",
            "Activate it when ready: 'activate the #{name} automation'",
            "It will run WITHOUT AI - fast and predictable!"
          ]
        )
      else
        automation.update!(status: 'draft')
        error_response(
          "Code generated but test failed: #{test_result[:error]}. " \
          "The automation was saved as draft. Please refine the action description and try again."
        )
      end
    rescue => e
      Rails.logger.error "[GenerateAutomationCodeTool] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      error_response("Failed to generate automation: #{e.message}")
    end

    private

    def generate_code(trigger_type, trigger_config, action_description)
      prompt = build_generation_prompt(trigger_type, trigger_config, action_description)

      response = BedrockService.new.chat(
        messages: [{ role: 'user', content: prompt }],
        system: system_prompt,
        model: 'claude-sonnet-4-20250514',
        temperature: 0.2  # Low temperature for consistent code
      )

      code = extract_code(response[:content])

      if code.present?
        { success: true, code: code }
      else
        { success: false, error: "AI failed to generate valid Ruby code" }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def system_prompt
      <<~PROMPT
        You are a Ruby code generator for automation scripts. Generate ONLY the execute method.

        CRITICAL RULES:
        1. Define an `execute(trigger_data)` method
        2. `trigger_data` is a Hash with: { record: {...}, changes: {...}, user_id: ..., timestamp: ... }
        3. Return a Hash: { success: true/false, message: "..." }
        4. Use ONLY the safe helpers listed below - no other methods!
        5. Do NOT use: require, load, eval, send, system, exec, File, IO, Net::HTTP
        6. Handle nil values gracefully with `default()` or `&.` operator
        7. Keep code simple, readable, and well-commented
        8. Log important actions with `log()`

        AVAILABLE HELPERS:

        ## Data Access
        - record                           → The record that triggered this (Hash)
        - changes                          → Field changes { field: [old, new] }
        - find_record(id)                  → Find record by ID
        - query_records(conditions, limit:, order:) → Query records
        - count_records(conditions)        → Count matching records
        - create_record(attributes)        → Create a new record
        - update_record(id, attributes)    → Update a record

        ## Notifications (max 10 per execution)
        - send_email(to:, subject:, body:) → Send email
        - send_slack_message(channel:, message:) → Post to Slack
        - notify_user(user_id:, message:, type:) → Hub notification
        - notify_role(role:, message:, type:) → Notify all users with role

        ## HTTP (allowlisted domains only, max 5 per execution)
        - http_get(url, headers:)          → GET request
        - http_post(url, body:, headers:)  → POST request

        ## Date/Time
        - now, today, days_from_now(n), days_ago(n)
        - beginning_of_day(date), end_of_day(date)
        - parse_date(str), parse_datetime(str)
        - format_date(date, format), format_time(time, format)

        ## String/Number
        - titleize, downcase, upcase, strip, truncate, slugify
        - format_currency(cents), to_cents(dollars), to_dollars(cents)
        - format_number(num), format_percentage(num)

        ## Helpers
        - present?(val), blank?(val), default(val, fallback)
        - get(hash, 'nested.path'), merge(hash1, hash2)
        - join(array, sep), split(str, sep), first(arr), last(arr)
        - lookup_user_by_email(email), get_user(user_id)
        - log(message), debug(message)

        OUTPUT FORMAT:
        Return ONLY Ruby code wrapped in ```ruby ... ``` blocks.
        No explanations before or after the code.
      PROMPT
    end

    def build_generation_prompt(trigger_type, trigger_config, action_description)
      <<~PROMPT
        Generate a Ruby `execute(trigger_data)` method for this automation:

        TRIGGER: #{trigger_type}
        #{trigger_config.present? ? "TRIGGER CONFIG: #{trigger_config.to_json}" : ''}

        ACTION REQUIRED:
        #{action_description}

        Remember:
        - Access the triggering record with `record` (e.g., `record[:title]`, `record[:status]`)
        - Access field changes with `changes` (e.g., `changes[:status]` returns `[old_value, new_value]`)
        - Return `{ success: true, message: "..." }` or `{ success: false, error: "..." }`
        - Use `log()` to record important actions
        - Handle edge cases gracefully

        Generate the execute method:
      PROMPT
    end

    def extract_code(response)
      # Try to extract from markdown code blocks
      match = response.match(/```ruby\s*(.*?)\s*```/m)
      return match[1].strip if match

      # Try without language specifier
      match = response.match(/```\s*(def execute.*?^end)/m)
      return match[1].strip if match

      # Look for def execute directly
      match = response.match(/(def execute\(trigger_data\).*?^end)/m)
      match ? match[1].strip : nil
    end
  end
end

