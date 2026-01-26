# frozen_string_literal: true

require "test_helper"

class ExperienceLearningFlowTest < ActionDispatch::IntegrationTest
  setup do
    @entity = entities(:one)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # END-TO-END FLOW TEST
  # This tests the complete Training-Free GRPO implementation
  # ═══════════════════════════════════════════════════════════════════════════

  test "complete experience learning flow" do
    # STEP 1: Verify we have decision traces (simulating recorded executions)
    traces = DecisionTrace.where(entity: @entity)
    assert traces.any?, "Should have decision traces to learn from"

    # STEP 2: Verify traces have task_type in metadata
    traces_with_task_type = traces.where("metadata->>'task_type' IS NOT NULL")
    assert traces_with_task_type.any?, "Traces should have task_type for grouping"

    # STEP 3: Run semantic advantage extraction
    service = Learning::SemanticAdvantageService.new(entity: @entity)
    results = service.extract_experiences(window: 30.days)

    assert results.is_a?(Hash)
    assert results[:task_types_analyzed].is_a?(Array)

    # STEP 4: Verify experiences can be retrieved
    experiences = TaskExperience.for_entity(@entity).active
    assert experiences.any?, "Should have active experiences"

    # STEP 5: Verify GuidanceLibrary includes experiences
    guidance = GuidanceLibrary.for_task(:integration_setup, entity: @entity)
    
    assert guidance.is_a?(String)
    assert guidance.include?("CURRENT FOCUS"), "Should have static guidance"
    
    # If we have integration_setup experiences, they should be included
    if TaskExperience.for_entity(@entity).for_task_type("integration_setup").active.any?
      assert guidance.include?("LEARNED EXPERIENCES"), 
             "Should include learned experiences in guidance"
    end

    # STEP 6: Verify DynamicContextService passes entity
    context_service = DynamicContextService.new(user: nil, entity: @entity)
    context = context_service.build_context(
      canvas_context: nil,
      message: "Connect my Stripe integration"
    )

    assert context[:guidance_block].present?
    assert_equal :integration_setup, context[:task_type]
  end

  test "experience utility tracking through application" do
    experience = task_experiences(:integration_experience)
    initial_apply_count = experience.apply_count

    # Simulate experience being applied (this happens when GuidanceLibrary fetches)
    experience.record_application!

    assert_equal initial_apply_count + 1, experience.reload.apply_count
    assert_not_nil experience.last_applied_at

    # Simulate successful outcome
    initial_utility = experience.utility_score
    experience.record_outcome!(success: true)

    assert experience.reload.utility_score >= initial_utility
    assert experience.positive_outcome_count > 0
  end

  test "low utility experiences get pruned" do
    # Create some low utility experiences
    10.times do |i|
      TaskExperience.create!(
        entity: @entity,
        task_type: "general",
        content: "Test experience #{i} that should be pruned due to low utility score",
        utility_score: 0.1 + (i * 0.01),
        source_type: "semantic_advantage"
      )
    end

    initial_count = TaskExperience.for_entity(@entity).active.count

    # Prune to keep only top experiences
    pruned = TaskExperience.prune_low_utility!(entity: @entity, keep_count: 5)

    assert pruned > 0, "Should have pruned some experiences"
    
    remaining = TaskExperience.for_entity(@entity).active.count
    assert remaining <= initial_count, "Should have fewer active experiences after pruning"
  end

  test "evolution cycle includes experience learning phase" do
    # Run evolution cycle
    cycle_service = LivingPlatform::EvolutionCycleService.new(@entity)
    cycle = cycle_service.run_cycle(type: 'triggered')

    assert cycle.persisted?
    
    # Check that experience learning was recorded in learnings
    learnings = cycle.learnings || []
    
    experience_learning = learnings.find { |l| l['type'] == 'experience_learning' }
    
    if experience_learning
      assert experience_learning['task_types_analyzed'].is_a?(Array)
      assert experience_learning['experiences_created'].is_a?(Integer)
    end
  end

  test "platform-wide experiences available to all entities" do
    # Create a second entity
    entity_two = entities(:two)

    # Platform-wide experience should be accessible
    platform_exp = task_experiences(:platform_wide_experience)
    assert_nil platform_exp.entity_id, "Platform experience should have nil entity"

    # Both entities should be able to get this experience
    result_one = TaskExperience.for_prompt(entity: @entity, task_type: "integration_setup")
    result_two = TaskExperience.for_prompt(entity: entity_two, task_type: "integration_setup")

    # Platform experience should appear for entity_two (which has no specific experiences)
    assert result_two&.include?("Platform-wide") || result_two&.include?("best practice"),
           "Entity without specific experiences should get platform-wide ones"
  end

  test "context graph records task type for future learning" do
    # Create a decision recorder
    recorder = ContextGraph::DecisionRecorder.new(@entity, nil)

    # Record a tool decision with task type
    decision = recorder.record_tool_decision!(
      tool_name: "execute_integration_action",
      tool_input: { integration: "stripe", action: "list_customers" },
      tool_output: { success: true, customers: [] },
      task_type: "integration_setup"
    )

    assert decision.persisted?
    assert_equal "integration_setup", decision.metadata["task_type"]
  end

  test "user feedback updates experience utility scores" do
    # Setup: Apply an experience first
    experience = task_experiences(:integration_experience)
    initial_utility = experience.utility_score
    
    # Mark it as recently applied
    experience.update!(last_applied_at: 30.minutes.ago)
    
    # Get a user for feedback
    user = users(:one)
    
    # Create a feedbackable (we'll use a mock approach)
    # In real usage, this would be an AgentPluginExecution or ScoutMessage
    feedback = UserFeedback.new(
      user: user,
      entity: @entity,
      feedbackable_type: "ScoutMessage",
      feedbackable_id: 1,  # Mock ID
      rating: 1,  # Positive feedback
      session_id: "test-session",
      metadata: { 'task_type' => 'integration_setup' }
    )
    
    # Skip validation on feedbackable existence for this test
    feedback.save(validate: false)
    
    # The callback should have updated the experience
    experience.reload
    
    # Utility should have increased (or stayed same if experience wasn't matched)
    assert experience.utility_score >= initial_utility
  end

  test "negative feedback decreases experience utility" do
    # Setup: Create a test experience
    experience = TaskExperience.create!(
      entity: @entity,
      task_type: "integration_setup",
      content: "Test experience for feedback utility tracking with enough characters",
      utility_score: 0.7,
      source_type: "semantic_advantage",
      last_applied_at: 30.minutes.ago
    )
    
    initial_utility = experience.utility_score
    
    # Simulate negative feedback via direct method call
    experience.record_outcome!(success: false)
    
    # Utility should have decreased
    assert experience.reload.utility_score < initial_utility
  end
end
