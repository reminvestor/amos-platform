# frozen_string_literal: true

require "test_helper"

class ContextGraph::DecisionRecorderTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @recorder = ContextGraph::DecisionRecorder.new(@entity, @user)
  end

  test "record_decision! creates decision trace" do
    decision = @recorder.record_decision!(
      decision_type: 'action',
      summary: 'Executed tool',
      reasoning: 'Tool was needed for the task',
      context: { task: 'send email' },
      inputs: ['email_content'],
      confidence: 0.9
    )
    
    assert decision.persisted?
    assert_equal @entity.id, decision.entity_id
    assert_equal @user.id, decision.user_id
    assert_equal 'action', decision.decision_type
    assert_equal 0.9, decision.confidence_score.to_f
  end

  test "record_tool_decision! creates action decision" do
    decision = @recorder.record_tool_decision!(
      tool_name: 'send_email',
      tool_input: { to: 'test@example.com', subject: 'Hello' },
      tool_output: { success: true },
      reasoning: 'User requested to send an email'
    )
    
    assert decision.persisted?
    assert_equal 'action', decision.decision_type
    assert decision.decision_summary.include?('send_email')
  end

  test "record_escalation! creates escalation decision" do
    decision = @recorder.record_escalation!(
      reason: 'Need human approval for large discount',
      context: { discount_amount: '30%' },
      escalated_to: 'sales_manager'
    )
    
    assert decision.persisted?
    assert_equal 'escalation', decision.decision_type
    assert decision.requires_approval?
  end

  test "record_exception! creates exception decision" do
    decision = @recorder.record_exception!(
      policy: 'discount_cap_10_percent',
      action_taken: 'Granted 20% discount',
      justification: 'Customer had significant service disruption',
      context: { customer_tier: 'enterprise' }
    )
    
    assert decision.persisted?
    assert_equal 'exception', decision.decision_type
    assert decision.is_exception?
    assert_equal 'Customer had significant service disruption', decision.exception_justification
  end

  test "record_delegation! creates delegation decision" do
    agent = agent_plugins(:one)
    
    decision = @recorder.record_delegation!(
      target_agent: agent,
      task: 'Analyze customer data',
      reasoning: 'Specialist agent needed for analysis',
      context: { complexity: 'high' }
    )
    
    assert decision.persisted?
    assert_equal 'delegation', decision.decision_type
    assert decision.decision_summary.include?(agent.name)
  end

  test "record_outcome! updates decision" do
    decision = @recorder.record_decision!(
      decision_type: 'action',
      summary: 'Test action',
      reasoning: 'Test'
    )
    
    @recorder.record_outcome!(decision, outcome: 'success', details: { result: 'completed' }, quality: 0.95)
    decision.reload
    
    assert_equal 'success', decision.outcome
    assert_equal 0.95, decision.outcome_quality_score.to_f
  end

  test "approve_decision! updates approval status" do
    decision = @recorder.record_decision!(
      decision_type: 'exception',
      summary: 'Needs approval',
      reasoning: 'Test',
      requires_approval: true
    )
    
    @recorder.approve_decision!(decision, approved_by: 'admin@test.com', notes: 'Approved')
    decision.reload
    
    assert_equal 'approved', decision.approval_status
    assert_equal 'admin@test.com', decision.approved_by
  end

  test "reject_decision! updates approval status" do
    decision = @recorder.record_decision!(
      decision_type: 'exception',
      summary: 'Needs approval',
      reasoning: 'Test',
      requires_approval: true
    )
    
    @recorder.reject_decision!(decision, rejected_by: 'admin@test.com', notes: 'Not justified')
    decision.reload
    
    assert_equal 'rejected', decision.approval_status
  end

  test "pending_approvals returns pending decisions" do
    @recorder.record_decision!(
      decision_type: 'exception',
      summary: 'Pending 1',
      reasoning: 'Test',
      requires_approval: true
    )
    
    @recorder.record_decision!(
      decision_type: 'exception',
      summary: 'Pending 2',
      reasoning: 'Test',
      requires_approval: true
    )
    
    pending = @recorder.pending_approvals
    assert pending.count >= 2
  end

  test "stats returns expected structure" do
    # Create some decisions
    3.times do |i|
      @recorder.record_decision!(
        decision_type: 'action',
        summary: "Action #{i}",
        reasoning: 'Test'
      )
    end
    
    @recorder.record_exception!(
      policy: 'test_policy',
      action_taken: 'Test exception',
      justification: 'Test'
    )
    
    stats = @recorder.stats(period: 1.day)
    
    assert stats[:total_decisions] >= 4
    assert stats[:exceptions] >= 1
    assert stats[:decision_type_breakdown].is_a?(Hash)
  end
end


