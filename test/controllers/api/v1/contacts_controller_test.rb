# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ContactsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))
      end

      teardown do
        # Clean up created contacts and groups
        Contact.where(user: @user, email: [
          "batch1@example.com", "batch2@example.com", "batch3@example.com",
          "single@example.com", "new@example.com", "updated@example.com"
        ]).destroy_all
        ContactGroup.where(user: @user).where("name LIKE ?", "%API Import%").destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # CREATE Tests - Batch Contact Creation
      # ====================================================================

      test "should create batch contacts with valid params" do
        assert_difference("Contact.count", 2) do
          post api_v1_contacts_path, params: {
            contacts: [
              {
                email: "batch1@example.com",
                first_name: "Batch",
                last_name: "One",
                status: "active"
              },
              {
                email: "batch2@example.com",
                first_name: "Batch",
                last_name: "Two",
                status: "active"
              }
            ]
          }, headers: auth_headers, as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal 2, response_body["created"]
        assert_equal 0, response_body["updated"]
        assert response_body.key?("group")
        assert response_body.key?("contacts")
      end

      test "batch create creates new group when no group_id specified" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "single@example.com",
              first_name: "Single",
              last_name: "Contact"
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["group"]["name"].include?("API Import")
      end

      test "batch create uses existing group when group_id specified" do
        group = ContactGroup.create!(
          user: @user,
          entity: @entity,
          name: "Existing Group"
        )

        post api_v1_contacts_path, params: {
          contact_group_id: group.id,
          contacts: [
            {
              email: "new@example.com",
              first_name: "New",
              last_name: "Contact"
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal group.id, response_body["group"]["id"]
        assert_equal "Existing Group", response_body["group"]["name"]

        group.destroy
      end

      test "batch create updates existing contacts" do
        existing_contact = Contact.create!(
          user: @user,
          entity: @entity,
          email: "updated@example.com",
          first_name: "Original",
          last_name: "Name",
          status: "active"
        )

        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "updated@example.com",
              first_name: "Updated",
              last_name: "Contact"
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert_equal 0, response_body["created"]
        assert_equal 1, response_body["updated"]

        existing_contact.reload
        assert_equal "Updated", existing_contact.first_name
        assert_equal "Contact", existing_contact.last_name

        existing_contact.destroy
      end

      test "batch create returns errors for invalid contacts" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "valid@example.com",
              first_name: "Valid",
              last_name: "Contact"
            },
            {
              email: "invalid@example.com"
              # Missing first_name and last_name
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal true, response_body["success"]
        assert response_body["errors"].any?
      end

      test "batch create returns error for missing email" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              first_name: "No",
              last_name: "Email"
              # Missing email
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["errors"].any?
      end

      test "create requires contacts parameter" do
        post api_v1_contacts_path, params: {}, headers: auth_headers, as: :json

        assert_response :bad_request

        response_body = JSON.parse(response.body)
        assert_equal false, response_body["success"]
      end

      test "create requires authentication" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "test@example.com",
              first_name: "Test",
              last_name: "User"
            }
          ]
        }, as: :json

        assert_response :unauthorized
      end

      test "create rejects invalid token" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "test@example.com",
              first_name: "Test",
              last_name: "User"
            }
          ]
        }, headers: { "Authorization" => "Bearer invalid_token" }, as: :json

        assert_response :unauthorized
      end

      test "batch create returns 404 for non-existent group" do
        post api_v1_contacts_path, params: {
          contact_group_id: 999999,
          contacts: [
            {
              email: "test@example.com",
              first_name: "Test",
              last_name: "User"
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "batch create includes processing time" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "batch3@example.com",
              first_name: "Time",
              last_name: "Test"
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("processing_time_seconds")
      end

      test "batch create returns contact details in response" do
        post api_v1_contacts_path, params: {
          contacts: [
            {
              email: "batch1@example.com",
              first_name: "Detail",
              last_name: "Test",
              corporation_id: "corp123",
              corporation_name: "Test Corp"
            }
          ]
        }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        contacts = response_body["contacts"]

        assert contacts.any?
        contact = contacts.first
        assert_equal "batch1@example.com", contact["email"]
        assert_equal "Detail", contact["first_name"]
        assert_equal "Test", contact["last_name"]
        assert_equal "corp123", contact["corporation_id"]
        assert contact.key?("contact_groups")
      end
    end
  end
end
