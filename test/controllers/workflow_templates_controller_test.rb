require "test_helper"

class WorkflowTemplatesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    # Set host for subdomain constraint matching
    host! "app.example.com"


    # Create entities
    @entity1 = Entity.create!(name: "Test Entity 1", subdomain: "test1-#{SecureRandom.hex(4)}")
    @entity2 = Entity.create!(name: "Test Entity 2", subdomain: "test2-#{SecureRandom.hex(4)}")

    # Create users
    @user1 = User.create!(
      email: "user1-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      entity: @entity1
    )

    @user2 = User.create!(
      email: "user2-#{SecureRandom.hex(4)}@example.com",
      password: "Password123!",
      entity: @entity2
    )

    # Create templates
    @system_template = WorkflowTemplate.create!(
      name: "System Template",
      slug: "system_template_#{SecureRandom.hex(4)}",
      description: "A system-wide template",
      category: "campaign_creation",
      industry: "general",
      tags: ["system", "test"],
      is_system: true,
      is_active: true,
      template_spec: { phases: [] }
    )

    @entity1_template = WorkflowTemplate.create!(
      entity_id: @entity1.id,
      name: "Entity 1 Template",
      slug: "entity1_template_#{SecureRandom.hex(4)}",
      description: "Entity 1 specific template",
      category: "analytics",
      industry: "saas",
      tags: ["custom", "entity1"],
      is_system: false,
      is_active: true,
      template_spec: { phases: [] }
    )

    @entity2_template = WorkflowTemplate.create!(
      entity_id: @entity2.id,
      name: "Entity 2 Template",
      slug: "entity2_template_#{SecureRandom.hex(4)}",
      description: "Entity 2 specific template",
      category: "content_generation",
      industry: "ecommerce",
      tags: ["custom", "entity2"],
      is_system: false,
      is_active: true,
      template_spec: { phases: [] }
    )

    @shared_template = WorkflowTemplate.create!(
      name: "Shared Template",
      slug: "shared_template_#{SecureRandom.hex(4)}",
      description: "A shared template",
      category: "data_import",
      industry: "general",
      tags: ["shared", "public"],
      is_system: false,
      shared: true,
      is_active: true,
      template_spec: { phases: [] }
    )
  end

  # Authentication tests
  test "should require authentication for index" do
    get workflow_templates_path
    assert_redirected_to new_user_session_path
  end

  test "should require authentication for show" do
    get workflow_template_path(@system_template)
    assert_redirected_to new_user_session_path
  end

  test "should require authentication for duplicate" do
    post duplicate_workflow_template_path(@system_template)
    assert_redirected_to new_user_session_path
  end

  test "should require authentication for update" do
    put workflow_template_path(@entity1_template), params: { workflow_template: { name: "Updated" } }
    assert_redirected_to new_user_session_path
  end

  test "should require authentication for destroy" do
    delete workflow_template_path(@entity1_template)
    assert_redirected_to new_user_session_path
  end

  # Index action tests
  test "index should return templates for current entity" do
    sign_in @user1

    get workflow_templates_path
    assert_response :success

    # Should include system, entity-owned, and shared templates
    templates = assigns(:templates)
    assert_includes templates.map(&:id), @system_template.id
    assert_includes templates.map(&:id), @entity1_template.id
    assert_includes templates.map(&:id), @shared_template.id
  end

  test "index should not return other entities' private templates" do
    sign_in @user1

    get workflow_templates_path
    assert_response :success

    templates = assigns(:templates)
    assert_not_includes templates.map(&:id), @entity2_template.id
  end

  test "index should filter by category" do
    sign_in @user1

    get workflow_templates_path, params: { category: "campaign_creation" }
    assert_response :success

    templates = assigns(:templates)
    assert_includes templates.map(&:id), @system_template.id
    assert_not_includes templates.map(&:id), @entity1_template.id
  end

  test "index should filter by industry" do
    sign_in @user1

    get workflow_templates_path, params: { industry: "saas" }
    assert_response :success

    templates = assigns(:templates)
    assert_includes templates.map(&:id), @entity1_template.id
    assert_not_includes templates.map(&:id), @system_template.id
  end

  test "index should filter by tag" do
    sign_in @user1

    get workflow_templates_path, params: { tag: "system" }
    assert_response :success

    templates = assigns(:templates)
    assert_includes templates.map(&:id), @system_template.id
    assert_not_includes templates.map(&:id), @entity1_template.id
  end

  test "index should return JSON" do
    sign_in @user1

    get workflow_templates_path, as: :json
    assert_response :success
    assert_equal "application/json", response.media_type

    json_response = JSON.parse(response.body)
    assert json_response.is_a?(Array)
  end

  # Show action tests
  test "show should return template details" do
    sign_in @user1

    get workflow_template_path(@system_template)
    assert_response :success
  end

  test "show should return 404 for non-existent template" do
    sign_in @user1

    assert_raises(ActiveRecord::RecordNotFound) do
      get workflow_template_path(id: 999999)
    end
  end

  test "show should return JSON" do
    sign_in @user1

    get workflow_template_path(@system_template), as: :json
    assert_response :success

    json_response = JSON.parse(response.body)
    assert_equal @system_template.name, json_response["name"]
  end

  # Duplicate action tests
  test "duplicate should create entity copy of system template" do
    sign_in @user1

    assert_difference("WorkflowTemplate.count", 1) do
      post duplicate_workflow_template_path(@system_template), as: :json
    end

    assert_response :created
    json_response = JSON.parse(response.body)

    new_template = WorkflowTemplate.find(json_response["id"])
    assert_equal @entity1, new_template.entity
    assert_equal false, new_template.is_system
    assert_equal false, new_template.shared
    assert_includes new_template.name, "(Custom)"
  end

  test "duplicate should create entity copy of shared template" do
    sign_in @user1

    assert_difference("WorkflowTemplate.count", 1) do
      post duplicate_workflow_template_path(@shared_template), as: :json
    end

    assert_response :created
  end

  test "duplicate should not allow duplicating entity-specific templates" do
    sign_in @user1

    assert_no_difference("WorkflowTemplate.count") do
      post duplicate_workflow_template_path(@entity1_template), as: :json
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert_includes json_response["error"], "Can only duplicate system or shared templates"
  end

  test "duplicate should return HTML redirect on success" do
    sign_in @user1

    post duplicate_workflow_template_path(@system_template)
    assert_redirected_to workflow_templates_path
    assert_equal "Template duplicated successfully.", flash[:notice]
  end

  test "duplicate should handle errors gracefully" do
    sign_in @user1

    # Mock a save failure
    WorkflowTemplate.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(WorkflowTemplate.new))

    post duplicate_workflow_template_path(@system_template), as: :json
    assert_response :unprocessable_entity
  end

  # Update action tests
  test "update should allow updating entity-owned template" do
    sign_in @user1

    put workflow_template_path(@entity1_template), params: {
      workflow_template: {
        name: "Updated Name",
        description: "Updated description",
        industry: "fintech",
        tags: ["updated", "test"]
      }
    }, as: :json

    assert_response :success

    @entity1_template.reload
    assert_equal "Updated Name", @entity1_template.name
    assert_equal "Updated description", @entity1_template.description
    assert_equal "fintech", @entity1_template.industry
    assert_equal ["updated", "test"], @entity1_template.tags
  end

  test "update should not allow updating system templates" do
    sign_in @user1

    put workflow_template_path(@system_template), params: {
      workflow_template: { name: "Hacked" }
    }, as: :json

    assert_response :forbidden
    json_response = JSON.parse(response.body)
    assert_includes json_response["error"], "Cannot edit system templates"

    @system_template.reload
    assert_equal "System Template", @system_template.name
  end

  test "update should not allow updating other entities' templates" do
    sign_in @user1

    put workflow_template_path(@entity2_template), params: {
      workflow_template: { name: "Hacked" }
    }, as: :json

    assert_response :forbidden

    @entity2_template.reload
    assert_equal "Entity 2 Template", @entity2_template.name
  end

  test "update should only accept permitted parameters" do
    sign_in @user1

    put workflow_template_path(@entity1_template), params: {
      workflow_template: {
        name: "Updated",
        is_system: true,  # Should not be allowed
        is_active: false,  # Should not be allowed
        entity_id: @entity2.id  # Should not be allowed
      }
    }, as: :json

    @entity1_template.reload
    assert_equal "Updated", @entity1_template.name
    assert_equal false, @entity1_template.is_system  # Unchanged
    assert_equal true, @entity1_template.is_active  # Unchanged
    assert_equal @entity1.id, @entity1_template.entity_id  # Unchanged
  end

  test "update should return HTML redirect on success" do
    sign_in @user1

    put workflow_template_path(@entity1_template), params: {
      workflow_template: { name: "Updated" }
    }

    assert_redirected_to workflow_templates_path
    assert_equal "Template updated.", flash[:notice]
  end

  # Destroy action tests
  test "destroy should allow deleting entity-owned template" do
    sign_in @user1

    assert_difference("WorkflowTemplate.count", -1) do
      delete workflow_template_path(@entity1_template), as: :json
    end

    assert_response :no_content
  end

  test "destroy should not allow deleting system templates" do
    sign_in @user1

    assert_no_difference("WorkflowTemplate.count") do
      delete workflow_template_path(@system_template), as: :json
    end

    assert_response :forbidden
    json_response = JSON.parse(response.body)
    assert_includes json_response["error"], "Cannot delete system templates"
  end

  test "destroy should not allow deleting other entities' templates" do
    sign_in @user1

    assert_no_difference("WorkflowTemplate.count") do
      delete workflow_template_path(@entity2_template), as: :json
    end

    assert_response :forbidden
  end

  test "destroy should return HTML redirect on success" do
    sign_in @user1

    delete workflow_template_path(@entity1_template)
    assert_redirected_to workflow_templates_path
    assert_equal "Template deleted.", flash[:notice]
  end

  # Entity scoping security tests
  test "entity scoping should be enforced across all actions" do
    sign_in @user2

    # User2 should not see Entity1's templates in index
    get workflow_templates_path
    templates = assigns(:templates)
    assert_not_includes templates.map(&:id), @entity1_template.id

    # User2 should not be able to update Entity1's template
    put workflow_template_path(@entity1_template), params: {
      workflow_template: { name: "Hacked" }
    }, as: :json
    assert_response :forbidden

    # User2 should not be able to delete Entity1's template
    delete workflow_template_path(@entity1_template), as: :json
    assert_response :forbidden
  end

  # Edge cases
  test "should handle invalid template ID gracefully" do
    sign_in @user1

    assert_raises(ActiveRecord::RecordNotFound) do
      get workflow_template_path(id: "invalid")
    end
  end

  test "should handle missing parameters in update" do
    sign_in @user1

    put workflow_template_path(@entity1_template), params: {}
    # Should not raise an error, just not update anything
    assert_response :unprocessable_entity
  end
end
