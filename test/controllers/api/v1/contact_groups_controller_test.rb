# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ContactGroupsControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test contact group
        @contact_group = ContactGroup.create!(
          name: "Test Group",
          description: "A test contact group",
          entity: @entity,
          user: @user
        )

        # Create test contact
        @contact = Contact.create!(
          email: "group-test@example.com",
          first_name: "Group",
          last_name: "Test",
          status: "active",
          entity: @entity,
          user: @user
        )
      end

      teardown do
        # Clean up join table entries first
        if @contact_group&.id
          ActiveRecord::Base.connection.execute(
            "DELETE FROM contact_groups_contacts WHERE contact_group_id = #{@contact_group.id}"
          )
        end
        Contact.where(email: "group-test@example.com").destroy_all
        Contact.where(email: "new-member@example.com").destroy_all
        ContactGroup.where(name: [ "Test Group", "New Group", "Updated Group", "Delete Me" ]).destroy_all
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

      test "should get contact groups list with valid token" do
        get api_v1_contact_groups_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
      end

      test "contact groups list returns expected fields" do
        get api_v1_contact_groups_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        groups = response_body["data"]

        assert groups.any?

        group = groups.find { |g| g["id"] == @contact_group.id }
        assert group.present?
        assert group.key?("id")
        assert group.key?("name")
        assert group.key?("description")
        assert group.key?("contacts_count")
        assert group.key?("created_at")
      end

      test "contact groups list supports search filter" do
        get api_v1_contact_groups_path, params: { search: "Test Group" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        groups = response_body["data"]

        assert groups.any? { |g| g["name"].include?("Test") }
      end

      test "contact groups list requires authentication" do
        get api_v1_contact_groups_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get contact group details with valid token" do
        get api_v1_contact_group_path(@contact_group), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @contact_group.id, response_body["id"]
        assert_equal @contact_group.name, response_body["name"]
        assert response_body.key?("contacts")
      end

      test "should return 404 for non-existent contact group" do
        get api_v1_contact_group_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "contact group show requires authentication" do
        get api_v1_contact_group_path(@contact_group), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create contact group with valid params" do
        assert_difference "ContactGroup.count", 1 do
          post api_v1_contact_groups_path,
            params: { name: "New Group", description: "A new group" },
            headers: auth_headers,
            as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "New Group", response_body["name"]
        assert_equal "A new group", response_body["description"]
      end

      test "should fail to create contact group without name" do
        post api_v1_contact_groups_path,
          params: { description: "No name group" },
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity
      end

      test "create contact group requires authentication" do
        post api_v1_contact_groups_path,
          params: { name: "New Group" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update contact group with valid params" do
        patch api_v1_contact_group_path(@contact_group),
          params: { name: "Updated Group" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated Group", response_body["name"]
      end

      test "update contact group requires authentication" do
        patch api_v1_contact_group_path(@contact_group),
          params: { name: "Updated" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy contact group" do
        group_to_delete = ContactGroup.create!(
          name: "Delete Me",
          entity: @entity,
          user: @user
        )

        assert_difference "ContactGroup.count", -1 do
          delete api_v1_contact_group_path(group_to_delete), headers: auth_headers, as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]
      end

      test "destroy contact group requires authentication" do
        delete api_v1_contact_group_path(@contact_group), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # ADD CONTACTS Tests
      # ====================================================================

      test "should add contacts to group" do
        new_contact = Contact.create!(
          email: "new-member@example.com",
          first_name: "New",
          last_name: "Member",
          entity: @entity,
          user: @user
        )

        post add_contacts_api_v1_contact_group_path(@contact_group),
          params: { contact_ids: [ @contact.id, new_contact.id ] },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]

        @contact_group.reload
        assert @contact_group.contacts.include?(@contact)
        assert @contact_group.contacts.include?(new_contact)
      end

      test "add contacts requires authentication" do
        post add_contacts_api_v1_contact_group_path(@contact_group),
          params: { contact_ids: [ @contact.id ] },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # REMOVE CONTACTS Tests
      # ====================================================================

      test "should remove contacts from group" do
        # First add contact to group
        @contact_group.contacts << @contact

        post remove_contacts_api_v1_contact_group_path(@contact_group),
          params: { contact_ids: [ @contact.id ] },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]

        @contact_group.reload
        assert_not @contact_group.contacts.include?(@contact)
      end

      test "remove contacts requires authentication" do
        post remove_contacts_api_v1_contact_group_path(@contact_group),
          params: { contact_ids: [ @contact.id ] },
          as: :json

        assert_response :unauthorized
      end
    end
  end
end
