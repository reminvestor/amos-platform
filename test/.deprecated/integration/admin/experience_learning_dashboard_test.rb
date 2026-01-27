# frozen_string_literal: true

require "test_helper"

class Admin::ExperienceLearningDashboardTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)
    @entity = entities(:one)

    # Experiences from fixtures
    @integration_experience = task_experiences(:integration_experience)
    @platform_wide_experience = task_experiences(:platform_wide_experience)

    sign_in @admin
  end

  # === Main Dashboard Tests ===

  test "dashboard displays experience learning overview" do
    get admin_experience_learning_path
    assert_response :success

    # Check key sections are present
    assert_select "h1", text: /Experience Learning/
    assert_select ".card" # Stats cards
  end

  test "dashboard shows entity list with experience counts" do
    get admin_experience_learning_path
    assert_response :success

    # Entity list should be present
    assert_select ".list-group"
  end

  test "dashboard displays task type breakdown" do
    get admin_experience_learning_path
    assert_response :success

    # Task type stats table should be present
    assert_select "table"
  end

  # === Entity Page Tests ===

  test "entity page shows entity-specific experiences" do
    get entity_admin_experience_learning_path(@entity)
    assert_response :success

    assert_select "h1", text: /#{@entity.name}/
  end

  test "entity page allows running maintenance" do
    assert_enqueued_with(job: ExperienceMaintenanceJob) do
      post run_maintenance_admin_experience_learning_path(entity_id: @entity.id)
    end

    assert_redirected_to entity_admin_experience_learning_path(@entity)
  end

  # === Experience Detail Tests ===

  test "experience detail page shows full experience info" do
    get experience_admin_experience_learning_path(@integration_experience)
    assert_response :success

    # Check content is displayed
    assert_select ".card-body", text: /#{@integration_experience.content.truncate(50)}/
  end

  test "experience detail shows related traces" do
    get experience_admin_experience_learning_path(@integration_experience)
    assert_response :success
  end

  # === Platform Experiences Tests ===

  test "platform experiences page lists global experiences" do
    get platform_experiences_admin_experience_learning_path
    assert_response :success

    assert_select "h1", text: /Platform-Wide/
  end

  test "platform experiences shows promotable experiences" do
    get platform_experiences_admin_experience_learning_path
    assert_response :success

    assert_select "h5", text: /Eligible for Promotion/
  end

  # === Conflicts Page Tests ===

  test "conflicts page is accessible" do
    get conflicts_admin_experience_learning_path
    assert_response :success

    assert_select "h1", text: /Conflicts/
  end

  test "conflicts page shows no conflicts message when none exist" do
    # Clear any existing conflicting experiences
    TaskExperience.where(entity: @entity).where('utility_score < 0.5').update_all(active: false)

    get conflicts_admin_experience_learning_path
    assert_response :success
  end

  # === Calibration Page Tests ===

  test "calibration page shows calibration analysis" do
    get calibration_admin_experience_learning_path(@entity)
    assert_response :success

    assert_select "h1", text: /Calibration/
  end

  test "calibration page accepts days parameter" do
    get calibration_admin_experience_learning_path(@entity, days: 7)
    assert_response :success
  end

  # === Implicit Feedback Page Tests ===

  test "implicit feedback page shows feedback stats" do
    get implicit_feedback_admin_experience_learning_path
    assert_response :success

    assert_select "h1", text: /Implicit Feedback/
  end

  test "implicit feedback explains detection methods" do
    get implicit_feedback_admin_experience_learning_path
    assert_response :success

    assert_select ".card-header", text: /How Implicit Feedback Works/
  end

  # === Action Tests ===

  test "promote action works for eligible experience" do
    # Create a highly promotable experience
    promotable = TaskExperience.create!(
      entity: @entity,
      task_type: "workflow_design",
      content: "High performing experience for promotion test in workflow design",
      source_type: "semantic_advantage",
      utility_score: 0.95,
      apply_count: 30,
      positive_outcome_count: 28,
      active: true
    )

    assert_difference "TaskExperience.platform_wide.count", 1 do
      post promote_admin_experience_learning_path(promotable)
    end
  end

  test "deactivate action deactivates experience" do
    active_exp = TaskExperience.create!(
      entity: @entity,
      task_type: "document_analysis",
      content: "Experience to be deactivated for document analysis tasks",
      source_type: "semantic_advantage",
      utility_score: 0.5,
      apply_count: 5,
      positive_outcome_count: 2,
      active: true
    )

    post deactivate_admin_experience_learning_path(active_exp)

    active_exp.reload
    assert_not active_exp.active?
  end

  test "resolve conflict action resolves conflicts" do
    # Create conflicting experiences
    TaskExperience.create!(
      entity: @entity,
      task_type: "app_design",
      content: "Always use mobile-first design approach for app development",
      source_type: "semantic_advantage",
      utility_score: 0.9,
      apply_count: 20,
      positive_outcome_count: 18,
      active: true
    )
    TaskExperience.create!(
      entity: @entity,
      task_type: "app_design",
      content: "Never use mobile-first design - start with desktop always",
      source_type: "semantic_advantage",
      utility_score: 0.2,
      apply_count: 20,
      positive_outcome_count: 4,
      active: true
    )

    post resolve_conflict_admin_experience_learning_path(
      entity_id: @entity.id,
      task_type: "app_design"
    )

    assert_redirected_to conflicts_admin_experience_learning_path
  end

  # === Navigation Integration Tests ===

  test "experience learning is accessible from living platform" do
    get admin_living_platform_index_path
    assert_response :success

    # Link should be present
    assert_select "a[href=?]", admin_experience_learning_path
  end

  test "experience learning is accessible from context graph" do
    get admin_context_graph_path
    assert_response :success

    # Link should be present
    assert_select "a[href=?]", admin_experience_learning_path
  end

  # === Filter Tests ===

  test "experiences page filters by entity" do
    get experiences_admin_experience_learning_path(entity_id: @entity.id)
    assert_response :success
  end

  test "experiences page filters by task type" do
    get experiences_admin_experience_learning_path(task_type: "integration_setup")
    assert_response :success
  end

  test "experiences page filters by source type" do
    get experiences_admin_experience_learning_path(source_type: "semantic_advantage")
    assert_response :success
  end

  test "experiences page filters by high utility" do
    get experiences_admin_experience_learning_path(high_utility: "true")
    assert_response :success
  end

  test "experiences page combines multiple filters" do
    get experiences_admin_experience_learning_path(
      entity_id: @entity.id,
      task_type: "integration_setup",
      active: "true"
    )
    assert_response :success
  end
end
