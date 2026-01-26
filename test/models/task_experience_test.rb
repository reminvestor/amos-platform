# frozen_string_literal: true

require "test_helper"

class TaskExperienceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @experience = task_experiences(:integration_experience)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # VALIDATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  test "valid experience is valid" do
    assert @experience.valid?
  end

  test "requires task_type" do
    @experience.task_type = nil
    assert_not @experience.valid?
    assert @experience.errors[:task_type].present?
  end

  test "requires content" do
    @experience.content = nil
    assert_not @experience.valid?
    assert @experience.errors[:content].present?
  end

  test "content must be at least 20 characters" do
    @experience.content = "Too short"
    assert_not @experience.valid?
    assert @experience.errors[:content].any? { |e| e.include?("too short") }
  end

  test "task_type must be valid" do
    @experience.task_type = "invalid_type"
    assert_not @experience.valid?
    assert @experience.errors[:task_type].present?
  end

  test "utility_score must be between 0 and 1" do
    @experience.utility_score = 1.5
    assert_not @experience.valid?
    
    @experience.utility_score = -0.1
    assert_not @experience.valid?
    
    @experience.utility_score = 0.5
    assert @experience.valid?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SCOPES
  # ═══════════════════════════════════════════════════════════════════════════

  test "for_entity scope filters by entity" do
    experiences = TaskExperience.for_entity(@entity)
    
    assert experiences.any?
    assert experiences.all? { |e| e.entity_id == @entity.id }
  end

  test "for_task_type scope filters by task type" do
    experiences = TaskExperience.for_task_type("integration_setup")
    
    assert experiences.any?
    assert experiences.all? { |e| e.task_type == "integration_setup" }
  end

  test "active scope excludes inactive experiences" do
    active_experiences = TaskExperience.active
    inactive = task_experiences(:inactive_experience)
    
    assert_not active_experiences.include?(inactive)
  end

  test "high_utility scope filters by utility score >= 0.6" do
    high_utility = TaskExperience.high_utility
    
    assert high_utility.all? { |e| e.utility_score >= 0.6 }
  end

  test "platform_wide scope returns experiences with nil entity" do
    platform = TaskExperience.platform_wide
    
    assert platform.any?
    assert platform.all? { |e| e.entity_id.nil? }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # APPLICATION TRACKING
  # ═══════════════════════════════════════════════════════════════════════════

  test "record_application! increments apply_count" do
    initial_count = @experience.apply_count
    
    @experience.record_application!
    
    assert_equal initial_count + 1, @experience.reload.apply_count
    assert_not_nil @experience.last_applied_at
  end

  test "record_outcome! with success increases positive_outcome_count" do
    initial_positive = @experience.positive_outcome_count
    initial_utility = @experience.utility_score
    
    @experience.record_outcome!(success: true)
    
    assert_equal initial_positive + 1, @experience.reload.positive_outcome_count
    assert @experience.utility_score > initial_utility
  end

  test "record_outcome! with failure decreases utility score" do
    initial_utility = @experience.utility_score
    
    @experience.record_outcome!(success: false)
    
    assert @experience.reload.utility_score < initial_utility
  end

  test "success_rate calculates correctly" do
    @experience.apply_count = 10
    @experience.positive_outcome_count = 8
    
    assert_in_delta 0.8, @experience.success_rate, 0.01
  end

  test "success_rate returns 0.5 when no applications" do
    @experience.apply_count = 0
    
    assert_equal 0.5, @experience.success_rate
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # UTILITY MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  test "adjust_utility_score! clamps between 0 and 1" do
    @experience.utility_score = 0.95
    @experience.adjust_utility_score!(0.1)
    assert_equal 1.0, @experience.reload.utility_score
    
    @experience.utility_score = 0.05
    @experience.adjust_utility_score!(-0.1)
    assert_equal 0.0, @experience.reload.utility_score
  end

  test "deactivate! sets active to false" do
    @experience.deactivate!(reason: "test deactivation")
    
    assert_not @experience.reload.active
    assert_equal "test deactivation", @experience.metadata["deactivation_reason"]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  test "for_prompt returns formatted experiences" do
    result = TaskExperience.for_prompt(entity: @entity, task_type: "integration_setup")
    
    assert result.is_a?(String)
    assert result.include?("LEARNED EXPERIENCES")
    assert result.include?("list_integration_actions")
  end

  test "for_prompt includes platform-wide experiences" do
    # Entity with no specific experiences should get platform-wide
    entity_two = entities(:two)
    
    result = TaskExperience.for_prompt(entity: entity_two, task_type: "integration_setup")
    
    assert result.is_a?(String)
    assert result.include?("Platform-wide best practice")
  end

  test "for_prompt returns nil when no experiences" do
    result = TaskExperience.for_prompt(entity: @entity, task_type: "document_analysis")
    
    assert_nil result
  end

  test "learn! creates a new experience" do
    experience = TaskExperience.learn!(
      entity: @entity,
      task_type: "workflow_design",
      content: "When creating workflows, always add error handling for each step to improve reliability",
      applies_when: "When designing automation workflows",
      source_type: "semantic_advantage"
    )
    
    assert experience.persisted?
    assert_equal "workflow_design", experience.task_type
    assert_equal 0.5, experience.utility_score  # Default neutral
  end

  test "current_generation returns max generation for entity" do
    gen = TaskExperience.current_generation(@entity)
    
    assert gen >= 1
  end

  test "prune_low_utility! deactivates low utility experiences" do
    # First, deactivate all existing experiences for clean test
    TaskExperience.for_entity(@entity).update_all(active: false)
    
    # Create many experiences with varying utility
    10.times do |i|
      TaskExperience.create!(
        entity: @entity,
        task_type: "general",
        content: "Test experience number #{i} with enough characters to be valid",
        utility_score: 0.1 + (i * 0.08),  # 0.1, 0.18, 0.26, ..., 0.82
        source_type: "semantic_advantage",
        active: true
      )
    end
    
    initial_count = TaskExperience.for_entity(@entity).active.count
    assert_equal 10, initial_count
    
    # Prune to keep only 5
    TaskExperience.prune_low_utility!(entity: @entity, keep_count: 5)
    
    remaining = TaskExperience.for_entity(@entity).active.count
    # After pruning, we should have at most keep_count active experiences
    assert remaining <= 5, "Should have at most 5 active experiences after pruning, got #{remaining}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TEMPORAL DECAY
  # ═══════════════════════════════════════════════════════════════════════════

  test "apply_temporal_decay! does nothing for experiences with few applications" do
    @experience.apply_count = 3  # Less than 5
    @experience.utility_score = 0.8
    initial_score = @experience.utility_score
    
    @experience.apply_temporal_decay!
    
    assert_equal initial_score, @experience.utility_score
  end

  test "apply_temporal_decay! does nothing for recently successful experiences" do
    @experience.apply_count = 10
    @experience.utility_score = 0.8
    @experience.metadata = { 'last_positive_outcome_at' => 5.days.ago.iso8601 }
    @experience.save!
    
    initial_score = @experience.utility_score
    
    @experience.apply_temporal_decay!
    
    assert_equal initial_score, @experience.reload.utility_score
  end

  test "apply_temporal_decay! reduces utility for stale experiences" do
    @experience.apply_count = 10
    @experience.utility_score = 0.8
    @experience.metadata = { 'last_positive_outcome_at' => 60.days.ago.iso8601 }
    @experience.save!
    
    @experience.apply_temporal_decay!
    
    assert @experience.reload.utility_score < 0.8, "Utility should decay for stale experience"
  end

  test "apply_temporal_decay! does not reduce below 0.5 factor" do
    @experience.apply_count = 10
    @experience.utility_score = 0.8
    @experience.metadata = { 'last_positive_outcome_at' => 365.days.ago.iso8601 }
    @experience.save!
    
    @experience.apply_temporal_decay!
    
    # Should be at least 0.8 * 0.5 = 0.4
    assert @experience.reload.utility_score >= 0.4
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PLATFORM PROMOTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "promotable_to_platform? returns false for platform-wide experiences" do
    platform_exp = task_experiences(:platform_integration_experience)
    
    assert_not platform_exp.promotable_to_platform?
  end

  test "promotable_to_platform? returns false for low utility experiences" do
    @experience.utility_score = 0.5
    @experience.apply_count = 20
    
    assert_not @experience.promotable_to_platform?
  end

  test "promotable_to_platform? returns false for low apply count" do
    @experience.utility_score = 0.9
    @experience.apply_count = 5
    
    assert_not @experience.promotable_to_platform?
  end

  test "promotable_to_platform? returns true for high-performing experience" do
    @experience.utility_score = 0.9
    @experience.apply_count = 20
    @experience.positive_outcome_count = 16  # 80% success rate
    
    assert @experience.promotable_to_platform?
  end

  test "promote_to_platform! creates platform-wide experience" do
    @experience.utility_score = 0.9
    @experience.apply_count = 20
    @experience.positive_outcome_count = 16
    @experience.save!
    
    platform_count_before = TaskExperience.platform_wide.count
    
    promoted = TaskExperience.promote_to_platform!(@experience)
    
    assert promoted.present?
    assert promoted.persisted?
    assert_nil promoted.entity_id
    assert_equal @experience.task_type, promoted.task_type
    assert_equal TaskExperience.platform_wide.count, platform_count_before + 1
  end

  test "similar_content? detects similar content" do
    content1 = "When calling integration APIs, always verify connection first"
    content2 = "Always verify connection first when calling integration APIs"
    
    assert TaskExperience.similar_content?(content1, content2)
  end

  test "similar_content? rejects dissimilar content" do
    content1 = "When calling integration APIs, always verify connection first"
    content2 = "Create landing pages with mobile-first design principles"
    
    assert_not TaskExperience.similar_content?(content1, content2)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONFLICT DETECTION
  # ═══════════════════════════════════════════════════════════════════════════

  test "detect_conflicts returns empty array when no conflicts" do
    conflicts = TaskExperience.detect_conflicts(entity: @entity, task_type: "document_analysis")
    
    assert_empty conflicts
  end

  test "potential_conflict? detects opposing success rates" do
    exp1 = TaskExperience.new(apply_count: 10, positive_outcome_count: 9, content: "Always verify")
    exp2 = TaskExperience.new(apply_count: 10, positive_outcome_count: 2, content: "Skip verify")
    
    assert TaskExperience.potential_conflict?(exp1, exp2)
  end

  test "potential_conflict? detects opposing keywords" do
    exp1 = TaskExperience.new(
      apply_count: 10, 
      positive_outcome_count: 5, 
      content: "Always check the connection before calling"
    )
    exp2 = TaskExperience.new(
      apply_count: 10, 
      positive_outcome_count: 5, 
      content: "Never check the connection before calling"
    )
    
    assert TaskExperience.potential_conflict?(exp1, exp2)
  end

  test "resolve_conflicts! deactivates lower-performing experience" do
    # Create two conflicting experiences
    exp1 = TaskExperience.create!(
      entity: @entity,
      task_type: "crm_operation",
      content: "Always verify contact exists before update to avoid errors",
      utility_score: 0.8,
      apply_count: 20,
      positive_outcome_count: 18,  # 90% success
      source_type: "semantic_advantage"
    )
    
    exp2 = TaskExperience.create!(
      entity: @entity,
      task_type: "crm_operation",
      content: "Never verify contact exists, just update directly for speed",
      utility_score: 0.3,
      apply_count: 15,
      positive_outcome_count: 3,  # 20% success
      source_type: "semantic_advantage"
    )
    
    TaskExperience.resolve_conflicts!(entity: @entity, task_type: "crm_operation")
    
    exp1.reload
    exp2.reload
    
    assert exp1.active, "Higher performing experience should remain active"
    assert_not exp2.active, "Lower performing experience should be deactivated"
  end

  test "determine_conflict_type identifies success_rate_divergence" do
    exp1 = TaskExperience.new(apply_count: 10, positive_outcome_count: 9)
    exp2 = TaskExperience.new(apply_count: 10, positive_outcome_count: 2)
    
    conflict_type = TaskExperience.determine_conflict_type(exp1, exp2)
    
    assert_equal 'success_rate_divergence', conflict_type
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RECORD OUTCOME TRACKING
  # ═══════════════════════════════════════════════════════════════════════════

  test "record_outcome! with success tracks last_positive_outcome_at" do
    @experience.record_outcome!(success: true)
    
    assert @experience.metadata['last_positive_outcome_at'].present?
    last_outcome = Time.parse(@experience.metadata['last_positive_outcome_at'])
    assert_in_delta Time.current, last_outcome, 5.seconds
  end
end
