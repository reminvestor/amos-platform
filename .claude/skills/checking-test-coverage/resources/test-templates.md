# Test Templates and Examples

Common test patterns for Rails applications.

## Model Test Template

```ruby
require "test_helper"

class YourModelTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @model = YourModel.new(entity: @entity, attribute: "value")
  end

  # Validation Tests
  test "should be valid with valid attributes" do
    assert @model.valid?
  end

  test "should require required_field" do
    @model.required_field = nil
    assert_not @model.valid?
    assert_includes @model.errors[:required_field], "can't be blank"
  end

  test "should validate uniqueness of unique_field" do
    @model.save!
    duplicate = @model.dup
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:unique_field], "has already been taken"
  end

  test "should validate format of email" do
    @model.email = "invalid"
    assert_not @model.valid?
    assert_includes @model.errors[:email], "is invalid"
  end

  # Association Tests
  test "should belong to entity" do
    assert_respond_to @model, :entity
    assert_instance_of Entity, @model.entity
  end

  test "should have many associated_models" do
    assert_respond_to @model, :associated_models
  end

  # Scope Tests
  test "should return active records with active scope" do
    active = YourModel.create!(entity: @entity, status: "active")
    inactive = YourModel.create!(entity: @entity, status: "inactive")

    results = YourModel.active
    assert_includes results, active
    assert_not_includes results, inactive
  end

  # Instance Method Tests
  test "should calculate total correctly" do
    @model.value = 100
    @model.quantity = 5
    assert_equal 500, @model.calculate_total
  end

  # Class Method Tests
  test "should find by custom criteria" do
    @model.save!
    result = YourModel.find_by_criteria("value")
    assert_equal @model, result
  end

  # Callback Tests
  test "should generate slug before save" do
    @model.name = "Test Name"
    @model.save!
    assert_equal "test-name", @model.slug
  end
end
```

## Controller Test Template

```ruby
require "test_helper"

class YourControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @entity = entities(:one)
    @user = create_valid_user(entity: @entity)
    sign_in @user

    @resource = YourModel.create!(
      entity: @entity,
      name: "Test Resource"
    )
  end

  # Index Action
  test "should get index" do
    get your_resources_path
    assert_response :success
    assert_select "h1", "Your Resources"
  end

  test "should only show current entity resources" do
    other_entity = entities(:two)
    other_resource = YourModel.create!(
      entity: other_entity,
      name: "Other Resource"
    )

    get your_resources_path
    assert_select "td", text: @resource.name
    assert_select "td", text: other_resource.name, count: 0
  end

  # Show Action
  test "should show resource" do
    get your_resource_path(@resource)
    assert_response :success
    assert_select "h1", @resource.name
  end

  test "should not show other entity resource" do
    other_entity = entities(:two)
    other_resource = YourModel.create!(
      entity: other_entity,
      name: "Other Resource"
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      get your_resource_path(other_resource)
    end
  end

  # New Action
  test "should get new" do
    get new_your_resource_path
    assert_response :success
    assert_select "form"
  end

  # Create Action
  test "should create resource" do
    assert_difference("YourModel.count") do
      post your_resources_path, params: {
        your_model: {
          name: "New Resource",
          description: "Test description"
        }
      }
    end

    assert_redirected_to your_resource_path(YourModel.last)
    assert_equal "Resource created successfully", flash[:notice]
  end

  test "should not create resource with invalid params" do
    assert_no_difference("YourModel.count") do
      post your_resources_path, params: {
        your_model: { name: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  # Edit Action
  test "should get edit" do
    get edit_your_resource_path(@resource)
    assert_response :success
    assert_select "form"
  end

  # Update Action
  test "should update resource" do
    patch your_resource_path(@resource), params: {
      your_model: { name: "Updated Name" }
    }

    assert_redirected_to your_resource_path(@resource)
    @resource.reload
    assert_equal "Updated Name", @resource.name
  end

  # Destroy Action
  test "should destroy resource" do
    assert_difference("YourModel.count", -1) do
      delete your_resource_path(@resource)
    end

    assert_redirected_to your_resources_path
  end

  # Authentication Tests
  test "should require authentication" do
    sign_out @user

    get your_resources_path
    assert_redirected_to new_user_session_path
  end

  # JSON Format Tests
  test "should return json" do
    get your_resource_path(@resource), as: :json
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal @resource.name, json["name"]
  end
end
```

## Service Test Template

```ruby
require "test_helper"

class YourServiceTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  test "executes successfully with valid inputs" do
    service = YourService.new(
      entity: @entity,
      user: @user,
      param: "value"
    )

    result = service.execute

    assert result.success?
    assert_equal "expected_value", result.data[:key]
    assert_nil result.error_message
  end

  test "returns error with invalid inputs" do
    service = YourService.new(
      entity: @entity,
      user: @user,
      param: nil
    )

    result = service.execute

    assert_not result.success?
    assert_not_nil result.error_message
    assert_includes result.error_message, "param"
  end

  test "handles edge cases" do
    service = YourService.new(
      entity: @entity,
      user: @user,
      param: ""
    )

    result = service.execute

    assert result.success?
    assert_empty result.data
  end

  test "calls external dependencies correctly" do
    # Mock external dependency
    ExternalService.expects(:call).with("expected_param").returns("result")

    service = YourService.new(entity: @entity, param: "value")
    result = service.execute

    assert result.success?
  end

  test "handles external API failures" do
    # Mock API failure
    ExternalService.expects(:call).raises(StandardError, "API Error")

    service = YourService.new(entity: @entity, param: "value")
    result = service.execute

    assert_not result.success?
    assert_includes result.error_message, "API Error"
  end
end
```

## Job Test Template

```ruby
require "test_helper"

class YourJobTest < ActiveJob::TestCase
  setup do
    @entity = entities(:one)
    @resource = YourModel.create!(entity: @entity, name: "Test")
  end

  test "performs successfully" do
    YourJob.perform_now(@resource.id)

    @resource.reload
    assert_equal "processed", @resource.status
  end

  test "is idempotent" do
    YourJob.perform_now(@resource.id)
    first_result = @resource.reload.updated_at

    YourJob.perform_now(@resource.id)
    second_result = @resource.reload.updated_at

    # Assert running twice doesn't change result
    assert_equal first_result, second_result
  end

  test "handles missing records gracefully" do
    assert_nothing_raised do
      YourJob.perform_now(-1)
    end
  end

  test "retries on failure" do
    # Mock a failure
    YourModel.any_instance.expects(:process!).raises(StandardError).once
    YourModel.any_instance.expects(:process!).returns(true).once

    assert_enqueued_jobs 1 do
      YourJob.perform_later(@resource.id)
    end
  end
end
```

## System/E2E Test Template

```ruby
require "application_system_test_case"

class YourWorkflowTest < ApplicationSystemTestCase
  setup do
    @entity = entities(:one)
    @user = create_valid_user(entity: @entity)
    login_as(@user, scope: :user)
  end

  test "complete workflow from start to finish" do
    # Navigate to starting point
    visit root_path
    click_on "Start Workflow"

    # Step 1: Initial form
    assert_selector "h1", text: "Create Resource"
    fill_in "Name", with: "Test Resource"
    fill_in "Description", with: "Test Description"
    click_on "Next"

    # Step 2: Configuration
    assert_selector "h2", text: "Configure"
    select "Option A", from: "Type"
    check "Enable feature"
    click_on "Next"

    # Step 3: Review and confirm
    assert_selector "h2", text: "Review"
    assert_text "Test Resource"
    assert_text "Option A"
    click_on "Confirm"

    # Step 4: Verify completion
    assert_text "Workflow completed successfully"
    assert_selector ".success-message"

    # Verify database state
    resource = YourModel.last
    assert_equal "Test Resource", resource.name
    assert_equal "Option A", resource.type
    assert resource.feature_enabled
  end

  test "handles validation errors" do
    visit root_path
    click_on "Start Workflow"

    # Submit without required field
    fill_in "Name", with: ""
    click_on "Next"

    # Verify error handling
    assert_selector ".alert-danger"
    assert_text "Name can't be blank"

    # Fix error and continue
    fill_in "Name", with: "Valid Name"
    click_on "Next"

    assert_selector "h2", text: "Configure"
  end

  test "allows navigation back and forth" do
    visit root_path
    click_on "Start Workflow"

    fill_in "Name", with: "Test"
    click_on "Next"

    # Go back
    click_on "Back"
    assert_selector "h1", text: "Create Resource"
    assert_field "Name", with: "Test"

    # Continue forward
    click_on "Next"
    assert_selector "h2", text: "Configure"
  end

  test "handles concurrent users" do
    # Login as second user
    other_user = create_valid_user(
      entity: @entity,
      email: "other@example.com"
    )

    using_session "user_2" do
      login_as(other_user, scope: :user)
      visit root_path

      # Both users should see isolated data
      assert_text @entity.name
    end
  end
end
```

## Integration Test Template

```ruby
require "test_helper"

class YourIntegrationTest < ActionDispatch::IntegrationTest
  test "complete user flow" do
    # Setup
    entity = entities(:one)
    user = create_valid_user(entity: entity)

    # Step 1: Login
    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password123"
      }
    }
    assert_redirected_to root_path
    follow_redirect!

    # Step 2: Create resource
    post your_resources_path, params: {
      your_model: { name: "Test" }
    }
    resource = YourModel.last
    assert_redirected_to your_resource_path(resource)

    # Step 3: Update resource
    patch your_resource_path(resource), params: {
      your_model: { status: "active" }
    }
    resource.reload
    assert_equal "active", resource.status

    # Step 4: Verify final state
    get your_resource_path(resource)
    assert_response :success
  end
end
```

## Common Test Patterns

### Testing Background Jobs

```ruby
test "enqueues background job" do
  assert_enqueued_with(job: YourJob, args: [@resource.id]) do
    @service.execute
  end
end

test "performs job inline in test" do
  perform_enqueued_jobs do
    YourJob.perform_later(@resource.id)
    @resource.reload
    assert_equal "processed", @resource.status
  end
end
```

### Testing Mailers

```ruby
test "sends email" do
  assert_emails 1 do
    YourMailer.notification(@user).deliver_now
  end
end

test "email has correct content" do
  email = YourMailer.notification(@user)
  assert_equal [@user.email], email.to
  assert_equal "Subject", email.subject
  assert_match "Expected content", email.body.to_s
end
```

### Testing File Uploads

```ruby
test "uploads file" do
  file = fixture_file_upload("test.pdf", "application/pdf")

  post upload_path, params: { file: file }

  assert_response :success
  assert ActiveStorage::Attachment.exists?(name: "file")
end
```

### Testing Transactions

```ruby
test "rolls back on error" do
  assert_no_difference "YourModel.count" do
    assert_raises(StandardError) do
      YourModel.transaction do
        YourModel.create!(name: "Test")
        raise StandardError, "Force rollback"
      end
    end
  end
end
```

### Testing Caching

```ruby
test "caches result" do
  Rails.cache.clear

  # First call caches
  result1 = YourService.cached_call
  assert Rails.cache.exist?("cache_key")

  # Second call uses cache
  YourService.expects(:expensive_operation).never
  result2 = YourService.cached_call

  assert_equal result1, result2
end
```
