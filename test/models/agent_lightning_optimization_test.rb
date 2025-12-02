require "test_helper"

class AgentLightningOptimizationTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @training_job = agent_training_jobs(:one)
  end

  # Validations tests
  test "should require entity_id" do
    optimization = AgentLightningOptimization.new(
      agent_training_job: @training_job,
      status: "pending"
    )
    assert_not optimization.valid?
    assert optimization.errors[:entity_id].any?
  end

  test "should require unique optimization_id" do
    optimization1 = @entity.agent_lightning_optimizations.create!(
      optimization_id: "test-uuid-123",
      status: "pending",
      improvement_percentage: 0
    )

    optimization2 = @entity.agent_lightning_optimizations.build(
      optimization_id: "test-uuid-123",
      status: "pending",
      improvement_percentage: 0
    )

    assert_not optimization2.valid?
    assert optimization2.errors[:optimization_id].any?
  end

  test "should validate status enum" do
    optimization = @entity.agent_lightning_optimizations.build(
      optimization_id: SecureRandom.uuid,
      status: "invalid_status",
      improvement_percentage: 0
    )
    assert_not optimization.valid?
    assert optimization.errors[:status].any?
  end

  test "should validate improvement_percentage range" do
    # Valid: 0
    optimization = @entity.agent_lightning_optimizations.build(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    assert optimization.valid?

    # Valid: 50
    optimization.improvement_percentage = 50
    assert optimization.valid?

    # Valid: -50
    optimization.improvement_percentage = -50
    assert optimization.valid?

    # Invalid: > 100
    optimization.improvement_percentage = 101
    assert_not optimization.valid?

    # Invalid: < -100
    optimization.improvement_percentage = -101
    assert_not optimization.valid?
  end

  # Lifecycle tests
  test "should generate optimization_id on create" do
    optimization = @entity.agent_lightning_optimizations.create!(
      status: "pending",
      improvement_percentage: 0
    )
    assert optimization.optimization_id.present?
    assert_match(/^[a-f0-9\-]{36}$/, optimization.optimization_id) # UUID format
  end

  test "should mark as applied" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 5
    )

    optimization.mark_applied!(3)

    assert_equal "applied", optimization.reload.status
    assert optimization.applied_at.present?
    assert_equal 3, optimization.templates_updated
  end

  test "should mark as rolled back" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 5,
      applied_at: Time.current
    )

    optimization.mark_rolled_back!

    assert_equal "rolled_back", optimization.reload.status
    assert optimization.rolled_back_at.present?
    assert_equal 1, optimization.rollback_count
  end

  test "should increment rollback_count on multiple rollbacks" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 5,
      applied_at: Time.current,
      rollback_count: 1
    )

    optimization.mark_rolled_back!
    assert_equal 2, optimization.reload.rollback_count
  end

  test "should mark as failed with error message" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )

    error_msg = "Failed to apply prompts to templates"
    optimization.mark_failed!(error_msg)

    assert_equal "failed", optimization.reload.status
    assert_equal error_msg, optimization.error_message
  end

  # Scope tests
  test "applied scope returns only applied optimizations" do
    applied = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 5,
      applied_at: Time.current
    )
    pending = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    rolled_back = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "rolled_back",
      improvement_percentage: 5,
      applied_at: Time.current,
      rolled_back_at: Time.current
    )

    applied_optimizations = AgentLightningOptimization.applied

    assert applied_optimizations.include?(applied)
    assert_not applied_optimizations.include?(pending)
    assert_not applied_optimizations.include?(rolled_back)
  end

  test "with_improvement scope returns only positive improvements" do
    improved = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 5.5,
      applied_at: Time.current
    )
    no_improvement = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 0,
      applied_at: Time.current
    )
    regression = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: -2.5,
      applied_at: Time.current
    )

    improved_optimizations = AgentLightningOptimization.with_improvement

    assert improved_optimizations.include?(improved)
    assert_not improved_optimizations.include?(no_improvement)
    assert_not improved_optimizations.include?(regression)
  end

  test "recent scope orders by creation date descending" do
    opt1 = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    travel 1.hour
    opt2 = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )

    recent = AgentLightningOptimization.recent.limit(2)

    assert_equal opt2.id, recent.first.id
    assert_equal opt1.id, recent.last.id
  end

  # Helper method tests
  test "can_rollback? returns true for applied status" do
    applied = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 5,
      applied_at: Time.current
    )
    assert applied.can_rollback?

    pending = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    assert_not pending.can_rollback?
  end

  test "improved? returns true for positive improvement_percentage" do
    improved = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 5.5,
      applied_at: Time.current
    )
    assert improved.improved?

    no_improvement = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: 0,
      applied_at: Time.current
    )
    assert_not no_improvement.improved?

    regression = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "applied",
      improvement_percentage: -2.5,
      applied_at: Time.current
    )
    assert_not regression.improved?
  end

  test "improvement_description returns appropriate message" do
    optimizations = [
      [@entity.agent_lightning_optimizations.create!(
        optimization_id: SecureRandom.uuid,
        status: "applied",
        improvement_percentage: 0,
        applied_at: Time.current
      ), "No change"],
      [@entity.agent_lightning_optimizations.create!(
        optimization_id: SecureRandom.uuid,
        status: "applied",
        improvement_percentage: 3,
        applied_at: Time.current
      ), "Minor improvement"],
      [@entity.agent_lightning_optimizations.create!(
        optimization_id: SecureRandom.uuid,
        status: "applied",
        improvement_percentage: 10,
        applied_at: Time.current
      ), "Moderate improvement"],
      [@entity.agent_lightning_optimizations.create!(
        optimization_id: SecureRandom.uuid,
        status: "applied",
        improvement_percentage: 30,
        applied_at: Time.current
      ), "Significant improvement"],
      [@entity.agent_lightning_optimizations.create!(
        optimization_id: SecureRandom.uuid,
        status: "applied",
        improvement_percentage: 75,
        applied_at: Time.current
      ), "Major improvement"]
    ]

    optimizations.each do |opt, expected_desc|
      assert_equal expected_desc, opt.improvement_description
    end
  end

  test "summary returns complete optimization snapshot" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: "test-uuid-123",
      status: "applied",
      improvement_percentage: 12.5,
      templates_updated: 5,
      prompts_optimized: 15,
      templates_modified: ["template1", "template2"],
      context_types_optimized: ["gather_context", "execute_goal"],
      applied_at: Time.current,
      rollback_count: 0
    )

    summary = optimization.summary

    assert_equal "test-uuid-123", summary[:optimization_id]
    assert_equal "applied", summary[:status]
    assert_equal 12.5, summary[:improvement_percentage]
    assert_equal 5, summary[:templates_updated]
    assert_equal 15, summary[:prompts_optimized]
    assert_equal 2, summary[:templates_modified].length
    assert_equal 2, summary[:context_types].length
    assert summary[:applied_at].present?
  end

  # Association tests
  test "should belong to entity" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    assert_equal @entity, optimization.entity
  end

  test "should belong to agent_training_job" do
    optimization = @entity.agent_lightning_optimizations.create!(
      agent_training_job: @training_job,
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    assert_equal @training_job, optimization.agent_training_job
  end

  test "agent_training_job is optional" do
    optimization = @entity.agent_lightning_optimizations.create!(
      optimization_id: SecureRandom.uuid,
      status: "pending",
      improvement_percentage: 0
    )
    assert_nil optimization.agent_training_job
  end
end
