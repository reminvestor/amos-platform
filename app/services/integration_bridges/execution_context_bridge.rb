# frozen_string_literal: true

module IntegrationBridges
  # ExecutionContextBridge - Connects agent executions to the Context Graph
  #
  # This bridge ensures that every significant agent decision is recorded
  # in the Context Graph for future precedent search and learning.
  #
  # Triggered after agent execution completes.
  #
  class ExecutionContextBridge
    attr_reader :execution

    def initialize(execution)
      @execution = execution
    end

    # Record the execution as a decision in the Context Graph
    def bridge!
      return unless should_record?

      DecisionTrace.record_decision!(
        entity: execution.agent_plugin.entity,
        agent_plugin: execution.agent_plugin,
        decision_type: determine_decision_type,
        decision_summary: build_summary,
        reasoning: extract_reasoning,
        context_gathered: extract_context,
        inputs_used: extract_inputs,
        policies_evaluated: extract_policies,
        outcome: determine_outcome,
        confidence_score: extract_confidence,
        is_exception: was_exception?,
        exception_justification: exception_justification,
        requires_approval: requires_approval?,
        metadata: {
          agent_plugin_execution_id: execution.id,
          outcome_quality_score: calculate_quality_score,
          model_used: extract_model_used,
          task_type: extract_task_type
        }.compact
      )

      Rails.logger.info "[ExecutionContextBridge] Recorded decision for execution #{execution.id}"
    rescue => e
      Rails.logger.warn "[ExecutionContextBridge] Failed to record: #{e.message}"
    end

    private

    def should_record?
      # Record completed executions that made meaningful decisions
      return false unless execution.status.in?(%w[completed failed])
      return false unless execution.agent_plugin.present?
      
      # Skip very fast executions (likely just lookups)
      return false if execution.duration_ms.to_i < 500
      
      # Skip if output is empty
      return false if execution.output_result.blank?
      
      true
    end

    def determine_decision_type
      output = execution.output_result || {}
      
      if output['error'].present? || execution.status == 'failed'
        'failure_handling'
      elsif output['delegated_to'].present?
        'delegation'
      elsif output['action_taken'].present?
        'action'
      elsif was_exception?
        'exception'
      else
        'action'
      end
    end

    def build_summary
      output = execution.output_result || {}
      input = execution.input_context || {}
      
      if output['summary'].present?
        output['summary']
      elsif input['task_description'].present?
        "Executed: #{input['task_description'].truncate(100)}"
      else
        "Agent #{execution.agent_plugin.name} execution"
      end
    end

    def extract_reasoning
      output = execution.output_result || {}
      
      parts = []
      parts << output['reasoning'] if output['reasoning'].present?
      parts << output['thought_process'] if output['thought_process'].present?
      parts << output['explanation'] if output['explanation'].present?
      
      parts.join("\n\n").presence || "Automated execution based on task requirements."
    end

    def extract_context
      input = execution.input_context || {}
      
      {
        task_type: input['task_type'],
        tools_used: extract_tools_used,
        agent_role: execution.agent_plugin.role,
        execution_duration_ms: execution.duration_ms,
        tokens_used: execution.tokens_used
      }.compact
    end

    def extract_inputs
      input = execution.input_context || {}
      input.keys.select { |k| input[k].present? }
    end

    def extract_policies
      # Extract any policies that were checked during execution
      output = execution.output_result || {}
      output['policies_checked'] || []
    end

    def extract_tools_used
      # Get tools from AgentToolExecution records if available
      if execution.respond_to?(:agent_tool_executions)
        execution.agent_tool_executions.pluck(:tool_name)
      else
        []
      end
    end

    def determine_outcome
      case execution.status
      when 'completed'
        output = execution.output_result || {}
        output['success'] == false ? 'failed' : 'success'
      when 'failed'
        'failed'
      else
        'unknown'
      end
    end

    def calculate_quality_score
      output = execution.output_result || {}
      
      # Use explicit quality if provided
      return output['quality_score'].to_f if output['quality_score'].present?
      
      # Calculate based on available signals
      score = 0.5
      score += 0.2 if execution.status == 'completed'
      score += 0.1 if execution.duration_ms.to_i < 5000  # Fast execution bonus
      score += 0.1 if output['error'].blank?
      score += 0.1 if output['user_satisfied'].present? && output['user_satisfied']
      
      [score, 1.0].min
    end

    def extract_confidence
      output = execution.output_result || {}
      output['confidence']&.to_f || 0.7
    end

    def was_exception?
      output = execution.output_result || {}
      output['is_exception'] == true || output['exception_made'] == true
    end

    def exception_justification
      output = execution.output_result || {}
      output['exception_reason'] || output['exception_justification']
    end

    def requires_approval?
      output = execution.output_result || {}
      output['requires_approval'] == true || output['needs_human_review'] == true
    end

    def extract_model_used
      output = execution.output_result || {}
      output['model_used'] || execution.try(:model_id)
    end

    def extract_task_type
      input = execution.input_context || {}
      input['task_type'] || input[:task_type]
    end
  end
end


