# frozen_string_literal: true

require 'test_helper'

class Learning::ImmediateExperienceServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    
    # Create a decision trace with failure outcome
    @failed_trace = DecisionTrace.create!(
      entity: @entity,
      user: @user,
      decision_type: 'action',
      decision_summary: 'Attempted to call integration API without verifying connection',
      reasoning: 'User asked to get Stripe customers, called API directly',
      outcome: 'failure',
      outcome_details: { error: 'Connection not found' },
      metadata: { task_type: 'integration_setup' },
      context_gathered: { tool_name: 'execute_integration_action' }
    )
    
    @successful_trace = DecisionTrace.create!(
      entity: @entity,
      user: @user,
      decision_type: 'action',
      decision_summary: 'Successfully verified connection before API call',
      reasoning: 'Checked list_connections first, then called API',
      outcome: 'success',
      metadata: { task_type: 'integration_setup' },
      context_gathered: { tool_name: 'list_connections' }
    )
  end

  test "initializes with decision trace" do
    service = Learning::ImmediateExperienceService.new(@failed_trace)
    assert_equal @failed_trace, service.decision_trace
  end

  test "should_learn returns false for traces without entity" do
    trace = DecisionTrace.new(decision_type: 'action', decision_summary: 'Test')
    service = Learning::ImmediateExperienceService.new(trace)
    
    # Service checks for entity presence
    assert_not service.send(:should_learn?)
  end

  test "infers task type from context when not in metadata" do
    trace = DecisionTrace.create!(
      entity: @entity,
      decision_type: 'action',
      decision_summary: 'Created a landing page for the client',
      reasoning: 'Used plan_design tool',
      outcome: 'failure',
      metadata: {},  # No task_type
      context_gathered: { landing_page_id: 123 }
    )
    
    service = Learning::ImmediateExperienceService.new(trace)
    task_type = service.send(:task_type)
    
    assert_equal 'landing_page_edit', task_type
  end

  test "extracts failure context correctly" do
    service = Learning::ImmediateExperienceService.new(@failed_trace)
    context = service.send(:extract_failure_context)
    
    assert_equal @failed_trace.decision_summary, context[:summary]
    assert_equal @failed_trace.reasoning, context[:reasoning]
    assert_equal 'Connection not found', context[:error_message]
    assert_includes context[:tools_used], 'execute_integration_action'
  end

  test "finds success patterns from similar decisions" do
    # Generate embeddings for both traces (mock this in real test)
    service = Learning::ImmediateExperienceService.new(@failed_trace)
    
    # The service should try to find similar successful decisions
    patterns = service.send(:find_success_patterns)
    
    # Patterns should be an array (may be empty if no embeddings)
    assert_kind_of Array, patterns
  end

  test "marks trace as learned from after creating experience" do
    service = Learning::ImmediateExperienceService.new(@failed_trace)
    
    # Create a mock experience
    experience_data = {
      'content' => 'When calling integration APIs, always verify the connection exists first.',
      'applies_when' => 'Before executing integration actions',
      'confidence' => 0.8
    }
    
    # Ensure metadata is a hash
    @failed_trace.update!(metadata: @failed_trace.metadata || {})
    
    # Create experience
    experience = service.send(:create_experience!, experience_data)
    
    assert experience.present?
    assert experience.persisted?
    assert_equal 'integration_setup', experience.task_type
    assert_includes experience.content, 'integration APIs'
    
    # Trace should be marked as learned from
    @failed_trace.reload
    assert @failed_trace.metadata['experience_created']
    assert_equal experience.id, @failed_trace.metadata['experience_id']
  end
end
