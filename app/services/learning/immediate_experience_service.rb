# frozen_string_literal: true

module Learning
  # ImmediateExperienceService - Real-time learning from failures
  #
  # Unlike SemanticAdvantageService which runs in batch during evolution cycles,
  # this service triggers immediately when a failure is detected.
  #
  # Philosophy:
  # - Don't wait for daily/weekly cycles to learn from obvious failures
  # - Create actionable experiences instantly so the same mistake isn't repeated
  # - Use the failure context + any available success patterns to generate advice
  #
  # Integration:
  # - Triggered by DecisionTrace after_update callback when outcome='failure'
  # - Creates TaskExperience entries immediately
  # - Works alongside batch SemanticAdvantageService for deeper analysis
  #
  class ImmediateExperienceService
    attr_reader :decision_trace

    # Minimum confidence to create an experience (avoid noise)
    MIN_CONFIDENCE_FOR_EXPERIENCE = 0.6

    def initialize(decision_trace)
      @decision_trace = decision_trace
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN ENTRY POINT
    # ═══════════════════════════════════════════════════════════════════════════

    def learn_from_failure!
      return unless should_learn?

      Rails.logger.info "[ImmediateLearning] Analyzing failure for trace #{decision_trace.id}"

      # Get context about what went wrong
      failure_context = extract_failure_context

      # Find similar successful decisions for contrast
      success_patterns = find_success_patterns

      # Generate experience using LLM
      experience = generate_experience(failure_context, success_patterns)

      return unless experience.present?

      # Create the experience
      create_experience!(experience)
    end

    # Learn from success (reinforcement)
    def learn_from_success!
      return unless should_learn?

      Rails.logger.info "[ImmediateLearning] Reinforcing success for trace #{decision_trace.id}"

      # Check if we have existing experiences that might have helped
      reinforce_applied_experiences!
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # VALIDATION
    # ═══════════════════════════════════════════════════════════════════════════

    def should_learn?
      return false unless decision_trace.entity.present?
      return false unless task_type.present?
      return false if already_learned_from?

      true
    end

    def already_learned_from?
      # Check if we've already created an experience from this trace
      decision_trace.metadata&.dig('experience_created').present?
    end

    def task_type
      @task_type ||= decision_trace.metadata&.dig('task_type') ||
                     infer_task_type_from_context
    end

    def infer_task_type_from_context
      context = decision_trace.context_gathered || {}
      summary = decision_trace.decision_summary&.downcase || ''

      # Infer from context clues
      return 'landing_page_edit' if summary.include?('landing page') || context['landing_page_id']
      return 'workflow_design' if summary.include?('workflow') || context['workflow_id']
      return 'integration_setup' if summary.include?('integration') || context['integration']
      return 'crm_operation' if summary.include?('contact') || summary.include?('crm')
      return 'email_creation' if summary.include?('email')

      'general'
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT EXTRACTION
    # ═══════════════════════════════════════════════════════════════════════════

    def extract_failure_context
      {
        summary: decision_trace.decision_summary,
        reasoning: decision_trace.reasoning,
        decision_type: decision_trace.decision_type,
        context: decision_trace.context_gathered,
        outcome_details: decision_trace.outcome_details,
        tools_used: extract_tools_used,
        error_message: extract_error_message,
        confidence: decision_trace.confidence_score
      }
    end

    def extract_tools_used
      tools = []

      if decision_trace.context_gathered.is_a?(Hash)
        tools << decision_trace.context_gathered['tool_name'] if decision_trace.context_gathered['tool_name']
      end

      decision_trace.child_decisions.where(decision_type: 'action').each do |child|
        tools << child.metadata['tool_name'] if child.metadata&.dig('tool_name')
      end

      tools.uniq
    end

    def extract_error_message
      details = decision_trace.outcome_details || {}
      
      details['error'] ||
        details['error_message'] ||
        details['failure_reason'] ||
        details.dig('response', 'error')
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SUCCESS PATTERN FINDING
    # ═══════════════════════════════════════════════════════════════════════════

    def find_success_patterns
      # Find similar decisions that succeeded
      similar = decision_trace.find_similar_decisions(limit: 5, min_similarity: 0.6)

      successful = similar.select { |s| s[:was_successful] }

      successful.map do |match|
        {
          summary: match[:decision].decision_summary,
          reasoning: match[:decision].reasoning,
          similarity: match[:similarity],
          tools_used: extract_tools_from_decision(match[:decision])
        }
      end
    end

    def extract_tools_from_decision(decision)
      tools = []
      
      if decision.context_gathered.is_a?(Hash)
        tools << decision.context_gathered['tool_name'] if decision.context_gathered['tool_name']
      end

      tools
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EXPERIENCE GENERATION
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_experience(failure_context, success_patterns)
      prompt = build_experience_prompt(failure_context, success_patterns)

      begin
        response = bedrock_service.quick_completion(prompt)
        parse_experience_response(response)
      rescue => e
        Rails.logger.error "[ImmediateLearning] Failed to generate experience: #{e.message}"
        nil
      end
    end

    def build_experience_prompt(failure_context, success_patterns)
      <<~PROMPT
        You are analyzing an AI agent failure to extract a learning that will prevent similar failures.

        ## Failed Task
        - Summary: #{failure_context[:summary]}
        - Reasoning: #{failure_context[:reasoning]}
        - Error: #{failure_context[:error_message] || 'No specific error'}
        - Tools Used: #{failure_context[:tools_used].join(', ').presence || 'None'}

        ## Similar Successful Tasks (for contrast)
        #{format_success_patterns(success_patterns)}

        ## Your Task

        Generate ONE concise, actionable experience that would prevent this failure.

        Requirements:
        1. Start with context: "When [situation]..."
        2. Include the action: "...always/never [do this]..."
        3. Include the reason: "...because [why]"
        4. Be specific enough to be useful, general enough to apply broadly
        5. Max 150 words

        ## Response Format (JSON)

        ```json
        {
          "content": "When [situation], always [action] because [reason]",
          "applies_when": "Brief trigger condition (e.g., 'Before calling integration APIs')",
          "confidence": 0.7
        }
        ```

        ONLY return the JSON object, no other text.
      PROMPT
    end

    def format_success_patterns(patterns)
      return "(No similar successful tasks found)" if patterns.empty?

      patterns.map.with_index do |p, i|
        <<~PATTERN
          ### Success #{i + 1} (#{(p[:similarity] * 100).round}% similar)
          - Summary: #{p[:summary]}
          - Reasoning: #{p[:reasoning].to_s.truncate(150)}
          - Tools: #{p[:tools_used].join(', ').presence || 'None'}
        PATTERN
      end.join("\n")
    end

    def parse_experience_response(response)
      # Extract JSON from response
      json_match = response.match(/\{[\s\S]*\}/)
      return nil unless json_match

      parsed = JSON.parse(json_match[0])
      
      return nil unless parsed['content'].present?
      return nil if parsed['confidence'].to_f < MIN_CONFIDENCE_FOR_EXPERIENCE

      parsed
    rescue JSON::ParserError => e
      Rails.logger.warn "[ImmediateLearning] Failed to parse response: #{e.message}"
      nil
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EXPERIENCE CREATION
    # ═══════════════════════════════════════════════════════════════════════════

    def create_experience!(experience_data)
      experience = TaskExperience.learn!(
        entity: decision_trace.entity,
        task_type: task_type,
        content: experience_data['content'],
        applies_when: experience_data['applies_when'],
        source_type: 'immediate_failure',
        source_context: {
          decision_trace_id: decision_trace.id,
          extracted_at: Time.current.iso8601,
          confidence: experience_data['confidence']
        }
      )

      # Mark the trace as learned from
      decision_trace.update!(
        metadata: (decision_trace.metadata || {}).merge(
          'experience_created' => true,
          'experience_id' => experience.id
        )
      )

      Rails.logger.info "[ImmediateLearning] Created experience #{experience.id}: #{experience.content.truncate(60)}"

      experience
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[ImmediateLearning] Failed to create experience: #{e.message}"
      nil
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SUCCESS REINFORCEMENT
    # ═══════════════════════════════════════════════════════════════════════════

    def reinforce_applied_experiences!
      # Find experiences that were recently applied for this task type
      applied_experiences = TaskExperience.where(entity: decision_trace.entity, task_type: task_type)
                                          .active
                                          .where('last_applied_at > ?', 1.hour.ago)

      applied_experiences.each do |experience|
        experience.record_outcome!(success: true)
        Rails.logger.info "[ImmediateLearning] Reinforced experience #{experience.id} from success"
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def bedrock_service
      @bedrock_service ||= BedrockService.new(entity: decision_trace.entity)
    end
  end
end
