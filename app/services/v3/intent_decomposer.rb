# frozen_string_literal: true

module V3
  # IntentDecomposer - LLM fallback for goals that don't match any recipe
  #
  # When no pre-built recipe matches a goal, this service makes a single,
  # cheap LLM call to decompose the goal into a sequence of platform steps.
  #
  # This is fundamentally different from the user-facing Amos call:
  # - Small, focused system prompt (no identity, no history, no tools)
  # - Asks for structured JSON output
  # - Runs server-side with no streaming overhead
  # - Uses the cheapest available model
  #
  # The decomposer produces a step plan like:
  #   [
  #     { "action": "create", "type": "email_template", "data": { "name": "...", "subject": "..." } },
  #     { "action": "create", "type": "automation", "data": { "trigger": "...", "action": "..." } }
  #   ]
  #
  # The IntentEngine then executes each step using existing tool classes.
  #
  class IntentDecomposer
    DECOMPOSER_MODEL = "qwen3-next-80b"

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a platform task decomposer. Given a goal and spec, produce a JSON array of steps to accomplish it.

      Each step is a JSON object with:
      - "action": One of "create", "update", "delete", "execute"
      - "type": The object type (contact, contact_group, email_template, campaign, automation, landing_page, app, sync, scheduled_task, support_ticket, opportunity, activity)
      - "data": Object with the fields/parameters needed

      For "execute" actions, also include:
      - "execute_action": The specific action (integration, send_campaign, publish_landing_page, generate_file, generate_image, send_email, delete, enroll_sequence)
      - Plus any action-specific fields (integration, operation, inputs, campaign_id, etc.)

      Available automation triggers: contact_created, form_submit, record_updated, status_changed, field_changed, schedule, webhook
      Available automation actions: send_email, add_to_campaign, update_field, create_activity, call_webhook, notify_user

      IMPORTANT:
      - Return ONLY a valid JSON array. No markdown, no explanation, just the JSON.
      - Keep steps minimal -- only what's needed to accomplish the goal.
      - Reference IDs from earlier steps using "$step_N_id" (e.g., "$step_0_id" for the ID of the first step's result).
    PROMPT

    def initialize(user:, entity:)
      @user = user
      @entity = entity
      @bedrock = BedrockService.new(user: user, entity: entity)
    end

    # Decompose a goal into executable steps
    # @param goal [String] What to accomplish
    # @param spec [Hash] Parameters and details
    # @return [Array<Hash>] Steps to execute
    def decompose(goal:, spec:)
      user_prompt = "Goal: #{goal}\nSpec: #{spec.to_json}"

      Rails.logger.info "[V3::IntentDecomposer] Decomposing: #{goal}"

      messages = [{ role: "user", content: [{ text: user_prompt }] }]

      response = @bedrock.send_message(
        SYSTEM_PROMPT,
        messages,
        model: DECOMPOSER_MODEL,
        max_tokens: 2000,
        temperature: 0.3, # Low temperature for structured output
        json_mode: true
      )

      # Extract the text response
      text = extract_text(response)
      return [] if text.blank?

      # Parse JSON
      steps = parse_steps(text)

      Rails.logger.info "[V3::IntentDecomposer] Decomposed into #{steps.length} steps"
      steps
    rescue => e
      Rails.logger.error "[V3::IntentDecomposer] Failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      []
    end

    private

    def extract_text(response)
      return response if response.is_a?(String)

      if response.is_a?(Hash)
        return response[:text] || response["text"] || response[:content] || response["content"]
      end

      # Bedrock converse response format
      if response.respond_to?(:output) && response.output.respond_to?(:message)
        content = response.output.message.content
        return content.first.text if content&.first&.respond_to?(:text)
      end

      response.to_s
    end

    def parse_steps(text)
      # Try to extract JSON array from the response
      # Handle cases where the model wraps it in markdown code blocks
      json_text = text.strip
      json_text = json_text.gsub(/\A```json?\s*\n?/, "").gsub(/\n?```\s*\z/, "")

      # Try to find a JSON array in the text
      if json_text.include?("[")
        start_idx = json_text.index("[")
        end_idx = json_text.rindex("]")
        json_text = json_text[start_idx..end_idx] if start_idx && end_idx
      end

      parsed = JSON.parse(json_text)

      # Ensure it's an array
      parsed = [parsed] if parsed.is_a?(Hash)

      # Validate each step has required fields
      parsed.select { |step|
        step.is_a?(Hash) && step["action"].present? && (step["type"].present? || step["execute_action"].present?)
      }
    rescue JSON::ParserError => e
      Rails.logger.warn "[V3::IntentDecomposer] JSON parse failed: #{e.message}. Raw: #{text.truncate(500)}"
      []
    end
  end
end
