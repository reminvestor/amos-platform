# frozen_string_literal: true

module Amos
  # ConscienceValidator - The "inner voice" that validates Amos's responses
  #
  # Runs in parallel or post-generation to catch:
  # - Claims of actions without actual tool calls
  # - Data hallucinations (response data != tool results)
  # - Inconsistencies with conversation context
  # - Unfulfilled promises
  #
  # Uses a cheap/fast model (Nemotron Nano) for validation
  #
  class ConscienceValidator
    # Patterns that indicate claimed actions
    ACTION_CLAIM_PATTERNS = [
      /I('ve| have) (delegated|handed off|assigned)/i,
      /I('m| am) (delegating|creating|building|sending|saving)/i,
      /I('ve| have) (created|built|sent|saved|imported|exported)/i,
      /One moment.*(delegating|creating|building)/i,
      /Let me (delegate|create|build|send|save)/i,
      /I'll (delegate|create|build|send|save).*right now/i,
    ].freeze

    # Tools that correspond to action claims
    ACTION_TOOL_MAP = {
      'delegated' => %w[delegate_to_agent propose_task_to_agent],
      'handed off' => %w[delegate_to_agent],
      'assigned' => %w[delegate_to_agent],
      'delegating' => %w[delegate_to_agent],
      'creating' => %w[create_object create_freeform_canvas start_module_design],
      'building' => %w[build_app approve_module_design],
      'sent' => %w[send_email execute_integration],
      'saved' => %w[save_visualization update_object create_object],
      'imported' => %w[execute_integration create_object],
      'exported' => %w[delegate_to_agent],
    }.freeze

    attr_reader :entity, :user, :bedrock_service

    def initialize(entity:, user:)
      @entity = entity
      @user = user
      @bedrock_service = BedrockService.new
    end

    # Validate a response before it's sent to the user
    def validate(response:, tool_calls: [], tool_results: [], context: {})
      issues = []
      corrections = []

      # Check 1: Action claims without tool calls
      action_issues = check_action_claims(response, tool_calls)
      issues.concat(action_issues)

      # Check 2: Data accuracy (response vs tool results)
      data_issues = check_data_accuracy(response, tool_results)
      issues.concat(data_issues)

      # Check 3: Consistency with recent context
      consistency_issues = check_consistency(response, context)
      issues.concat(consistency_issues)

      severity = calculate_severity(issues)

      if severity == :critical
        corrections = generate_corrections(issues, tool_calls, context)
      end

      {
        valid: issues.empty?,
        issues: issues,
        corrections: corrections,
        severity: severity,
        should_retry: severity == :critical && corrections.any? { |c| c[:type] == :force_tool_call }
      }
    end

    # Quick pre-flight check during streaming
    def quick_check(partial_response:, tool_calls_so_far: [])
      action_claims = detect_action_claims(partial_response)
      
      if action_claims.any? && tool_calls_so_far.empty?
        return {
          warning: true,
          message: "Response claims action but no tool called yet",
          claims: action_claims
        }
      end

      { warning: false }
    end

    private

    def check_action_claims(response, tool_calls)
      issues = []
      tool_names = tool_calls.map { |t| t[:name] || t['name'] }.compact

      action_claims = detect_action_claims(response)
      
      action_claims.each do |claim|
        expected_tools = ACTION_TOOL_MAP[claim[:action]] || []
        
        unless expected_tools.any? { |t| tool_names.include?(t) }
          issues << {
            type: :unclaimed_action,
            severity: :critical,
            message: "Claimed '#{claim[:action]}' but no matching tool was called",
            claim: claim[:text],
            expected_tools: expected_tools,
            actual_tools: tool_names
          }
        end
      end

      issues
    end

    def detect_action_claims(text)
      claims = []
      
      ACTION_CLAIM_PATTERNS.each do |pattern|
        if text.match?(pattern)
          match = text.match(pattern)
          action = extract_action_word(match.to_s)
          claims << { pattern: pattern, text: match.to_s, action: action }
        end
      end

      claims.uniq { |c| c[:action] }
    end

    def extract_action_word(text)
      ACTION_TOOL_MAP.keys.find { |action| text.downcase.include?(action.downcase) } || 'unknown'
    end

    def check_data_accuracy(response, tool_results)
      issues = []
      
      tool_results.each do |result|
        next unless result.is_a?(Hash) && result[:records].is_a?(Array)
        
        response_emails = response.scan(/[\w.+-]+@[\w.-]+\.\w+/i)
        tool_emails = result[:records].flat_map { |r| r.values.grep(/[\w.+-]+@[\w.-]+\.\w+/i) }
        
        hallucinated = response_emails - tool_emails
        if hallucinated.any? && tool_emails.any?
          issues << {
            type: :data_hallucination,
            severity: :warning,
            message: "Response contains emails not in tool results",
            hallucinated_data: hallucinated.first(3)
          }
        end
      end

      issues
    end

    def check_consistency(response, context)
      issues = []
      
      return issues unless context[:recent_messages].present?
      
      recent_assistant = context[:recent_messages]
        .select { |m| m[:role] == 'assistant' }
        .last(3)
        .map { |m| m[:content].to_s }
        .join(' ')
      
      if recent_assistant.match?(/already (delegated|created|sent)/i) &&
         response.match?(/I('ll| will) (delegate|create|send)/i)
        issues << {
          type: :consistency_warning,
          severity: :warning,
          message: "Offers to do something claimed as already done"
        }
      end

      issues
    end

    def calculate_severity(issues)
      return :none if issues.empty?
      return :critical if issues.any? { |i| i[:severity] == :critical }
      :warning
    end

    def generate_corrections(issues, tool_calls, context)
      corrections = []

      issues.each do |issue|
        case issue[:type]
        when :unclaimed_action
          if issue[:expected_tools].include?('delegate_to_agent')
            corrections << {
              type: :force_tool_call,
              tool: 'delegate_to_agent',
              reason: "Response claimed delegation but tool wasn't called"
            }
          end
        when :data_hallucination
          corrections << {
            type: :flag_response,
            message: "⚠️ Some data may not be accurate"
          }
        end
      end

      corrections
    end
  end
end
