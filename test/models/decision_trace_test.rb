# frozen_string_literal: true

require "test_helper"

class DecisionTraceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
  end

  test "creates decision trace with required fields" do
    decision = DecisionTrace.create!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Executed send_email tool',
      trace_id: "dt_#{SecureRandom.uuid}"
    )
    
    assert decision.persisted?
    assert_equal 'action', decision.decision_type
  end

  test "validates decision type" do
    decision = DecisionTrace.new(
      entity: @entity,
      decision_type: 'invalid_type',
      decision_summary: 'Test'
    )
    
    assert_not decision.valid?
    assert decision.errors[:decision_type].any?
  end

  test "record_decision! creates with full context" do
    decision = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'exception',
      decision_summary: 'Granted 20% discount',
      reasoning: 'Customer had service disruption',
      context_gathered: { customer_tier: 'enterprise', incidents: 3 },
      inputs_used: ['customer_data', 'incident_history'],
      policies_evaluated: [{ policy: 'discount_cap', result: 'override' }],
      is_exception: true,
      exception_justification: 'Service impact policy allows exceptions',
      confidence_score: 0.85
    )
    
    assert decision.persisted?
    assert decision.is_exception?
    assert_equal 'exception', decision.decision_type
    assert_equal 0.85, decision.confidence_score.to_f
    assert_equal 3, decision.context_gathered['incidents']
  end

  test "exception tracking works" do
    decision = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Test action',
      reasoning: 'Normal operation'
    )
    
    decision.mark_as_exception!(
      justification: 'Special case for VIP customer',
      policy_overridden: 'standard_pricing'
    )
    
    assert decision.is_exception?
    assert_equal 'Special case for VIP customer', decision.exception_justification
  end

  test "approval workflow works" do
    decision = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'exception',
      decision_summary: 'Needs approval',
      reasoning: 'Test',
      requires_approval: true
    )
    
    assert decision.pending_approval?
    assert_equal 'pending', decision.approval_status
    
    decision.approve!(approved_by: 'admin@test.com', notes: 'Approved')
    
    assert_not decision.pending_approval?
    assert_equal 'approved', decision.approval_status
    assert_equal 'admin@test.com', decision.approved_by
  end

  test "rejection workflow works" do
    decision = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'exception',
      decision_summary: 'Needs approval',
      reasoning: 'Test',
      requires_approval: true
    )
    
    decision.reject!(rejected_by: 'admin@test.com', notes: 'Not justified')
    
    assert_equal 'rejected', decision.approval_status
  end

  test "outcome tracking works" do
    decision = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Test action',
      reasoning: 'Test'
    )
    
    decision.record_outcome!(
      outcome: 'success',
      outcome_details: { result: 'completed' },
      quality_score: 0.95
    )
    
    assert decision.was_successful?
    assert_equal 0.95, decision.outcome_quality_score.to_f
  end

  test "scope exceptions works" do
    DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Normal action',
      reasoning: 'Test'
    )
    
    DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'exception',
      decision_summary: 'Exception action',
      reasoning: 'Test',
      is_exception: true
    )
    
    exceptions = DecisionTrace.where(entity: @entity).exceptions
    assert_equal 1, exceptions.count
  end

  test "decision chain works" do
    parent = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Parent decision',
      reasoning: 'Test'
    )
    
    child = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Child decision',
      reasoning: 'Test'
    )
    child.update!(parent_decision: parent)
    
    chain = child.decision_chain
    assert_equal 2, chain.length
    assert_equal parent, chain.first
    assert_equal child, chain.last
  end

  test "to_graph_node returns expected structure" do
    decision = DecisionTrace.record_decision!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Test action',
      reasoning: 'Test',
      confidence_score: 0.8
    )
    
    node = decision.to_graph_node
    
    assert node[:id].present?
    assert node[:trace_id].present?
    assert_equal 'action', node[:type]
    assert_equal 'Test action', node[:summary]
    assert_equal 0.8, node[:confidence].to_f
  end
end


