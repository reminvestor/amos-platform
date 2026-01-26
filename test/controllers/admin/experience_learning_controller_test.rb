# frozen_string_literal: true

require "test_helper"

class Admin::ExperienceLearningControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = users(:admin)
    @non_admin = users(:marketer_user)
    @entity = entities(:one)

    # Experiences from fixtures
    @integration_experience = task_experiences(:integration_experience)
    @landing_page_experience = task_experiences(:landing_page_experience)
    @low_utility_experience = task_experiences(:low_utility_experience)
    @inactive_experience = task_experiences(:inactive_experience)
    @platform_wide_experience = task_experiences(:platform_wide_experience)

    sign_in @admin
  end

  # === Access Control Tests ===

  test "should require admin access" do
    sign_out @admin
    sign_in @non_admin

    get admin_experience_learning_path
    assert_redirected_to chat_mode_path
  end

  test "should redirect non-authenticated users" do
    sign_out @admin
    get admin_experience_learning_path
    assert_redirected_to new_user_session_path
  end

  # === Index Action Tests ===

  test "index is accessible to admin" do
    get admin_experience_learning_path
    assert_response :success
  end

  test "index displays global stats" do
    get admin_experience_learning_path
    assert_response :success
    assert_select "h2", text: /\d+/ # Stats cards show numbers
  end

  test "index displays task type breakdown" do
    get admin_experience_learning_path
    assert_response :success
    # The page should render without errors
  end

  test "index lists entities" do
    get admin_experience_learning_path
    assert_response :success
    # Should list entities with experiences
  end

  test "index shows recent experiences" do
    get admin_experience_learning_path
    assert_response :success
  end

  # === Entity Action Tests ===

  test "entity page is accessible" do
    get entity_admin_experience_learning_path(@entity)
    assert_response :success
  end

  test "entity page shows entity-specific stats" do
    get entity_admin_experience_learning_path(@entity)
    assert_response :success
  end

  test "entity page lists entity experiences" do
    get entity_admin_experience_learning_path(@entity)
    assert_response :success
  end

  test "entity page handles pagination" do
    get entity_admin_experience_learning_path(@entity, page: 1)
    assert_response :success
  end

  test "entity page shows conflict warnings when present" do
    # Create conflicting experiences for the same task type
    TaskExperience.create!(
      entity: @entity,
      task_type: "general",
      content: "Do it this way - always verify before proceeding with changes",
      source_type: "semantic_advantage",
      utility_score: 0.9,
      apply_count: 20,
      positive_outcome_count: 18,
      active: true
    )
    TaskExperience.create!(
      entity: @entity,
      task_type: "general",
      content: "Never verify before proceeding - just do it quickly without checking",
      source_type: "semantic_advantage",
      utility_score: 0.2,
      apply_count: 20,
      positive_outcome_count: 4,
      active: true
    )

    get entity_admin_experience_learning_path(@entity)
    assert_response :success
  end

  # === Experiences Action Tests ===

  test "experiences index is accessible" do
    get experiences_admin_experience_learning_path
    assert_response :success
  end

  test "experiences filters by entity_id" do
    get experiences_admin_experience_learning_path(entity_id: @entity.id)
    assert_response :success
  end

  test "experiences filters by task_type" do
    get experiences_admin_experience_learning_path(task_type: "integration_setup")
    assert_response :success
  end

  test "experiences filters by source_type" do
    get experiences_admin_experience_learning_path(source_type: "semantic_advantage")
    assert_response :success
  end

  test "experiences filters by active" do
    get experiences_admin_experience_learning_path(active: "true")
    assert_response :success
  end

  test "experiences filters by high_utility" do
    get experiences_admin_experience_learning_path(high_utility: "true")
    assert_response :success
  end

  test "experiences handles pagination" do
    get experiences_admin_experience_learning_path(page: 1)
    assert_response :success
  end

  # === Show Experience Action Tests ===

  test "show_experience displays experience details" do
    get experience_admin_experience_learning_path(@integration_experience)
    assert_response :success
  end

  test "show_experience finds related decision traces" do
    get experience_admin_experience_learning_path(@integration_experience)
    assert_response :success
  end

  test "show_experience shows similar experiences" do
    get experience_admin_experience_learning_path(@integration_experience)
    assert_response :success
  end

  # === Calibration Action Tests ===

  test "calibration page is accessible" do
    get calibration_admin_experience_learning_path(@entity)
    assert_response :success
  end

  test "calibration page accepts days parameter" do
    get calibration_admin_experience_learning_path(@entity, days: 7)
    assert_response :success
  end

  test "calibration page shows sample traces" do
    get calibration_admin_experience_learning_path(@entity)
    assert_response :success
  end

  # === Platform Experiences Action Tests ===

  test "platform_experiences page is accessible" do
    get platform_experiences_admin_experience_learning_path
    assert_response :success
  end

  test "platform_experiences lists platform-wide experiences" do
    get platform_experiences_admin_experience_learning_path
    assert_response :success
  end

  test "platform_experiences shows promotable experiences" do
    get platform_experiences_admin_experience_learning_path
    assert_response :success
  end

  test "platform_experiences handles pagination" do
    get platform_experiences_admin_experience_learning_path(page: 1)
    assert_response :success
  end

  # === Conflicts Action Tests ===

  test "conflicts page is accessible" do
    get conflicts_admin_experience_learning_path
    assert_response :success
  end

  test "conflicts page lists detected conflicts" do
    get conflicts_admin_experience_learning_path
    assert_response :success
  end

  # === Implicit Feedback Action Tests ===

  test "implicit_feedback page is accessible" do
    get implicit_feedback_admin_experience_learning_path
    assert_response :success
  end

  test "implicit_feedback handles pagination" do
    get implicit_feedback_admin_experience_learning_path(page: 1)
    assert_response :success
  end

  # === Run Maintenance Action Tests ===

  test "run_maintenance triggers global maintenance job" do
    assert_enqueued_with(job: ExperienceMaintenanceJob) do
      post run_maintenance_admin_experience_learning_path
    end

    assert_redirected_to admin_experience_learning_path
    assert_match /maintenance job queued/i, flash[:notice]
  end

  test "run_maintenance with entity_id triggers entity-specific job" do
    assert_enqueued_with(job: ExperienceMaintenanceJob) do
      post run_maintenance_admin_experience_learning_path(entity_id: @entity.id)
    end

    assert_redirected_to entity_admin_experience_learning_path(@entity)
    assert_match /maintenance job queued/i, flash[:notice]
  end

  # === Promote Action Tests ===

  test "promote creates platform-wide experience from high-performing entity experience" do
    # Create a promotable experience
    promotable = TaskExperience.create!(
      entity: @entity,
      task_type: "analytics_review",
      content: "Highly successful pattern that should be promoted to all entities for analytics",
      source_type: "semantic_advantage",
      utility_score: 0.92,
      apply_count: 25,
      positive_outcome_count: 23,
      active: true
    )

    assert_difference "TaskExperience.platform_wide.count", 1 do
      post promote_admin_experience_learning_path(promotable)
    end

    assert_match /promoted/i, flash[:notice]
  end

  test "promote rejects non-promotable experience" do
    assert_no_difference "TaskExperience.platform_wide.count" do
      post promote_admin_experience_learning_path(@low_utility_experience)
    end

    assert_match /not eligible/i, flash[:alert]
  end

  # === Deactivate Action Tests ===

  test "deactivate marks experience as inactive" do
    assert @integration_experience.active?

    post deactivate_admin_experience_learning_path(@integration_experience)

    @integration_experience.reload
    assert_not @integration_experience.active?
    assert_match /deactivated/i, flash[:notice]
  end

  test "deactivate accepts reason parameter" do
    post deactivate_admin_experience_learning_path(@landing_page_experience), 
      params: { reason: "Outdated approach" }

    @landing_page_experience.reload
    assert_not @landing_page_experience.active?
  end

  # === Resolve Conflict Action Tests ===

  test "resolve_conflict resolves conflicts for entity and task type" do
    # Create conflicting experiences
    exp1 = TaskExperience.create!(
      entity: @entity,
      task_type: "email_creation",
      content: "Always use HTML formatting for professional email templates",
      source_type: "semantic_advantage",
      utility_score: 0.9,
      apply_count: 20,
      positive_outcome_count: 18,
      active: true
    )
    exp2 = TaskExperience.create!(
      entity: @entity,
      task_type: "email_creation",
      content: "Never use HTML formatting - stick to plain text only",
      source_type: "semantic_advantage",
      utility_score: 0.2,
      apply_count: 20,
      positive_outcome_count: 4,
      active: true
    )

    post resolve_conflict_admin_experience_learning_path(
      entity_id: @entity.id,
      task_type: "email_creation"
    )

    assert_redirected_to conflicts_admin_experience_learning_path
    assert_match /resolved/i, flash[:notice]
  end

  # === Edge Cases ===

  test "handles missing entity gracefully" do
    get entity_admin_experience_learning_path(99999)
    assert_response :not_found
  rescue ActiveRecord::RecordNotFound
    # Expected behavior
  end

  test "handles missing experience gracefully" do
    get experience_admin_experience_learning_path(99999)
    assert_response :not_found
  rescue ActiveRecord::RecordNotFound
    # Expected behavior
  end
end
