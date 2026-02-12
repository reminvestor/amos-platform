# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class EmailTemplatesControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test email template
        @email_template = EmailTemplate.create!(
          name: "Test Template",
          subject: "Welcome {{first_name}}!",
          body: "Hello {{first_name}},\n\nWelcome to our platform!\n\nBest,\n{{company_name}}",
          entity: @entity,
          user: @user
        )
      end

      teardown do
        EmailTemplate.where(name: [ "Test Template", "New Template", "Updated Template" ]).destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # INDEX Tests
      # ====================================================================

      test "should get email templates list with valid token" do
        get api_v1_email_templates_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
      end

      test "email templates list returns expected fields" do
        get api_v1_email_templates_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        templates = response_body["data"]

        assert templates.any?

        template = templates.find { |t| t["id"] == @email_template.id }
        assert template.present?
        assert template.key?("id")
        assert template.key?("name")
        assert template.key?("subject")
        assert template.key?("created_at")
        assert template.key?("updated_at")
      end

      test "email templates list requires authentication" do
        get api_v1_email_templates_path, as: :json

        assert_response :unauthorized
      end

      test "email templates list returns pagination info" do
        get api_v1_email_templates_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        pagination = response_body["pagination"]

        assert pagination.key?("current_page")
        assert pagination.key?("total_pages")
        assert pagination.key?("total_count")
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get email template details with valid token" do
        get api_v1_email_template_path(@email_template), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @email_template.id, response_body["id"]
        assert_equal @email_template.name, response_body["name"]
        assert_equal @email_template.subject, response_body["subject"]
        assert response_body.key?("body")
        assert response_body.key?("campaigns_count")
      end

      test "should return 404 for non-existent email template" do
        get api_v1_email_template_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "email template show requires authentication" do
        get api_v1_email_template_path(@email_template), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create email template with valid params" do
        assert_difference "EmailTemplate.count", 1 do
          post api_v1_email_templates_path,
            params: {
              name: "New Template",
              subject: "Hello {{first_name}}",
              body: "Welcome to our service!"
            },
            headers: auth_headers,
            as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "New Template", response_body["name"]
        assert_equal "Hello {{first_name}}", response_body["subject"]
      end

      test "should fail to create email template without name" do
        post api_v1_email_templates_path,
          params: { subject: "Test", body: "Test body" },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert response_body["errors"].present?
      end

      test "create email template requires authentication" do
        post api_v1_email_templates_path,
          params: { name: "New Template" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update email template with valid params" do
        patch api_v1_email_template_path(@email_template),
          params: { name: "Updated Template" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated Template", response_body["name"]
      end

      test "should update email template subject" do
        patch api_v1_email_template_path(@email_template),
          params: { subject: "New Subject Line" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "New Subject Line", response_body["subject"]
      end

      test "should update email template body" do
        patch api_v1_email_template_path(@email_template),
          params: { body: "Updated body content" },
          headers: auth_headers,
          as: :json

        assert_response :success

        @email_template.reload
        assert_equal "Updated body content", @email_template.body
      end

      test "update email template requires authentication" do
        patch api_v1_email_template_path(@email_template),
          params: { name: "Updated" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy email template" do
        template_to_delete = EmailTemplate.create!(
          name: "Delete Me",
          subject: "Test",
          body: "Test body",
          entity: @entity,
          user: @user
        )

        assert_difference "EmailTemplate.count", -1 do
          delete api_v1_email_template_path(template_to_delete), headers: auth_headers, as: :json
        end

        assert_response :no_content
      end

      test "destroy email template requires authentication" do
        delete api_v1_email_template_path(@email_template), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # Entity Scoping Tests
      # ====================================================================

      test "should not access email template from different entity" do
        # Create another entity and template
        other_entity = Entity.create!(name: "Other Entity", subdomain: "other-template-#{SecureRandom.hex(4)}")
        other_user = User.create!(
          email: "other-#{SecureRandom.hex(4)}@example.com",
          password: "Password123!",
          entity: other_entity
        )
        other_template = EmailTemplate.create!(
          name: "Other Template",
          subject: "Test",
          body: "Test",
          entity: other_entity,
          user: other_user
        )

        # Try to access template from different entity
        get api_v1_email_template_path(other_template), headers: auth_headers, as: :json

        assert_response :not_found

        # Cleanup
        other_template.destroy
        other_user.destroy
        other_entity.destroy
      end
    end
  end
end
