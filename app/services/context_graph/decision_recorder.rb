# frozen_string_literal: true

module ContextGraph
  # DecisionRecorder - Records agent decisions into the context graph
  #
  # This service sits in the execution path (as the article emphasizes)
  # and captures the full decision context at commit time.
  #
  # Usage:
  #   recorder = ContextGraph::DecisionRecorder.new(entity, user)
  #   
  #   # Before making a decision, check for precedents
  #   precedents = recorder.find_precedents("Customer wants 20% discount on renewal")
  #   
  #   # Record the decision
  #   decision = recorder.record_decision!(
  #     decision_type: 'exception',
  #     summary: "Granted 20% discount due to service issues",
  #     reasoning: "Customer had 3 SEV-1 incidents in the past quarter",
  #     context: { customer_tier: 'enterprise', incidents: 3, churn_risk: 'high' },
  #     is_exception: true,
  #     exception_justification: "Policy allows up to 20% for service-impacted customers"
  #   )
  #   
  #   # Later, record the outcome
  #   recorder.record_outcome!(decision, outcome: 'success', quality: 0.9)
  #
  class DecisionRecorder
    attr_reader :entity, :user, :agent_plugin

    def initialize(entity, user = nil, agent_plugin: nil, lightning_trace: nil)
      @entity = entity
      @user = user
      @agent_plugin = agent_plugin
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PRECEDENT SEARCH (Before making decisions)
    # ═══════════════════════════════════════════════════════════════════════════

    # Find relevant precedents for a given context
    def find_precedents(context_description, decision_type: nil, limit: 5)
      DecisionTrace.find_precedents_for(
        entity: entity,
        context_description: context_description,
        decision_type: decision_type,
        limit: limit
      )
    end

    # Find exception precedents specifically
    def find_exception_precedents(context_description, limit: 5)
      DecisionTrace.find_exception_precedents(
        entity: entity,
        context_description: context_description,
        limit: limit
      )
    end

    # Get precedent summary for including in agent prompts
    def precedent_summary_for_prompt(context_description, limit: 3)
      precedents = find_precedents(context_description, limit: limit)
      return nil if precedents.empty?

      summary = "## Relevant Precedents\n\n"
      summary += "The following similar decisions were made previously:\n\n"

      precedents.each_with_index do |p, i|
        summary += "### Precedent #{i + 1} (#{(p[:similarity] * 100).round}% similar)\n"
        summary += "- **Decision**: #{p[:summary]}\n"
        summary += "- **Reasoning**: #{p[:reasoning]}\n"
        summary += "- **Outcome**: #{p[:outcome]}\n"
        summary += "- **Was Exception**: #{p[:was_exception] ? 'Yes' : 'No'}\n\n"
      end

      summary
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # DECISION RECORDING (At decision time)
    # ═══════════════════════════════════════════════════════════════════════════

    # Record a decision with full context
    def record_decision!(
      decision_type:,
      summary:,
      reasoning:,
      context: {},
      inputs: [],
      policies: [],
      is_exception: false,
      exception_justification: nil,
      requires_approval: false,
      approved_by: nil,
      confidence: nil,
      parent_decision: nil,
      metadata: {}
    )
      DecisionTrace.record_decision!(
        entity: entity,
        user: user,
        agent_plugin: agent_plugin,
        decision_type: decision_type,
        decision_summary: summary,
        reasoning: reasoning,
        context_gathered: context,
        inputs_used: inputs,
        policies_evaluated: policies,
        is_exception: is_exception,
        exception_justification: exception_justification,
        requires_approval: requires_approval,
        approved_by: approved_by,
        confidence_score: confidence,
        metadata: metadata.merge(
          recorded_by: 'context_graph',
          agent_slug: agent_plugin&.slug,
          user_email: user&.email
        )
      )
    end

    # Record a tool execution as a decision
    # Record a tool execution as a decision
    # task_type is used for Training-Free GRPO grouping
    def record_tool_decision!(
      tool_name:,
      tool_input:,
      tool_output:,
      reasoning: nil,
      parent_decision: nil,
      task_type: nil
    )
      record_decision!(
        decision_type: 'action',
        summary: "Executed tool: #{tool_name}",
        reasoning: reasoning || "Tool was selected to accomplish the task",
        context: {
          tool_name: tool_name,
          tool_input: tool_input,
          tool_output: tool_output.to_s.truncate(1000)
        },
        inputs: [tool_input],
        parent_decision: parent_decision,
        metadata: { 
          tool_name: tool_name,
          task_type: task_type 
        }.compact
      )
    end

    # Record an escalation to human
    def record_escalation!(
      reason:,
      context: {},
      escalated_to: nil
    )
      record_decision!(
        decision_type: 'escalation',
        summary: "Escalated to human: #{reason.truncate(100)}",
        reasoning: reason,
        context: context,
        requires_approval: true,
        metadata: { escalated_to: escalated_to }
      )
    end

    # Record a delegation to another agent
    def record_delegation!(
      target_agent:,
      task:,
      reasoning:,
      context: {}
    )
      record_decision!(
        decision_type: 'delegation',
        summary: "Delegated to #{target_agent.name}: #{task.truncate(80)}",
        reasoning: reasoning,
        context: context.merge(
          target_agent_slug: target_agent.slug,
          target_agent_name: target_agent.name,
          delegated_task: task
        ),
        metadata: { target_agent_id: target_agent.id }
      )
    end

    # Record an exception to normal policy
    def record_exception!(
      policy:,
      action_taken:,
      justification:,
      context: {},
      precedent_ids: []
    )
      decision = record_decision!(
        decision_type: 'exception',
        summary: "Exception to #{policy}: #{action_taken.truncate(80)}",
        reasoning: justification,
        context: context,
        policies: [{ policy: policy, action: 'overridden', justification: justification }],
        is_exception: true,
        exception_justification: justification,
        metadata: { 
          policy_overridden: policy,
          precedent_ids: precedent_ids 
        }
      )

      # Link to cited precedents
      precedent_ids.each do |precedent_id|
        precedent = DecisionTrace.find_by(id: precedent_id)
        next unless precedent

        DecisionPrecedent.create!(
          decision_trace: decision,
          precedent_decision: precedent,
          similarity_score: 1.0,  # Explicitly cited
          influence_type: 'exception_precedent'
        )
      end

      decision
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # OUTCOME RECORDING (After execution)
    # ═══════════════════════════════════════════════════════════════════════════

    def record_outcome!(decision, outcome:, details: {}, quality: nil)
      decision.record_outcome!(
        outcome: outcome,
        outcome_details: details,
        quality_score: quality
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # APPROVAL HANDLING
    # ═══════════════════════════════════════════════════════════════════════════

    def approve_decision!(decision, approved_by:, notes: nil)
      decision.approve!(approved_by: approved_by, notes: notes)
    end

    def reject_decision!(decision, rejected_by:, notes: nil)
      decision.reject!(rejected_by: rejected_by, notes: notes)
    end

    # Get pending approvals
    def pending_approvals
      DecisionTrace.where(entity: entity, approval_status: 'pending')
        .order(created_at: :desc)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT GRAPH QUERIES
    # ═══════════════════════════════════════════════════════════════════════════

    # Get decision statistics
    def stats(period: 30.days)
      decisions = DecisionTrace.where(entity: entity)
        .where('decision_traces.created_at > ?', period.ago)

      {
        total_decisions: decisions.count,
        decisions_with_precedents: decisions.with_precedents.count,
        exceptions: decisions.exceptions.count,
        exception_success_rate: calculate_exception_success_rate(decisions),
        decision_type_breakdown: decisions.group(:decision_type).count,
        avg_confidence: decisions.where.not(confidence_score: nil).average(:confidence_score)&.round(3),
        precedent_usage_rate: calculate_precedent_usage_rate(decisions),
        top_precedents: top_precedents(decisions, limit: 5)
      }
    end

    private

    def calculate_exception_success_rate(decisions)
      exceptions = decisions.exceptions.where.not(outcome: nil)
      return 0 if exceptions.count.zero?

      successful = exceptions.where(outcome: 'success').count
      (successful.to_f / exceptions.count * 100).round(1)
    end

    def calculate_precedent_usage_rate(decisions)
      return 0 if decisions.count.zero?

      with_precedents = decisions.with_precedents.count
      (with_precedents.to_f / decisions.count * 100).round(1)
    end

    def top_precedents(decisions, limit:)
      decision_ids = decisions.pluck(:id)
      
      DecisionPrecedent.where(decision_trace_id: decision_ids)
        .group(:precedent_decision_id)
        .count
        .sort_by { |_, count| -count }
        .first(limit)
        .map do |precedent_id, count|
          precedent = DecisionTrace.find_by(id: precedent_id)
          {
            id: precedent_id,
            summary: precedent&.decision_summary,
            times_used: count
          }
        end
    end
  end
end

