require "test_helper"

module Api
  module V1
    class ContactsListControllerTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create test contacts for the entity
        @contact = Contact.create!(
          email: "test@example.com",
          first_name: "Test",
          last_name: "User",
          status: "active",
          entity: @entity,
          user: @user
        )
      end

      teardown do
        Contact.where(email: "test@example.com").destroy_all
        Contact.where(email: "new@example.com").destroy_all
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

      test "should get contacts list with valid token" do
        get api_v1_contacts_list_index_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("pagination")
      end

      test "contacts list returns expected fields" do
        get api_v1_contacts_list_index_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        contacts = response_body["data"]

        assert contacts.any?

        contact = contacts.first
        assert contact.key?("id")
        assert contact.key?("email")
        assert contact.key?("name")
        assert contact.key?("status")
        assert contact.key?("groups")
        assert contact.key?("created_at")
        assert contact.key?("updated_at")
      end

      test "contacts list supports search filter" do
        get api_v1_contacts_list_index_path, params: { search: "test@example" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        contacts = response_body["data"]

        assert contacts.any? { |c| c["email"].include?("test@example") }
      end

      test "contacts list requires authentication" do
        get api_v1_contacts_list_index_path, as: :json

        assert_response :unauthorized
      end

      test "contacts list returns pagination info" do
        get api_v1_contacts_list_index_path, headers: auth_headers, as: :json

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

      test "should get contact details with valid token" do
        get api_v1_contacts_list_path(@contact), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @contact.id, response_body["id"]
        assert_equal @contact.email, response_body["email"]
      end

      test "should return 404 for non-existent contact" do
        get api_v1_contacts_list_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "contact show requires authentication" do
        get api_v1_contacts_list_path(@contact), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests
      # ====================================================================

      test "should create contact with valid params" do
        assert_difference "Contact.count", 1 do
          post api_v1_contacts_list_index_path,
            params: { email: "new@example.com", first_name: "New", last_name: "Contact", status: "active" },
            headers: auth_headers,
            as: :json
        end

        assert_response :created

        response_body = JSON.parse(response.body)
        assert_equal "new@example.com", response_body["email"]
        assert_equal "New", response_body["first_name"]
        assert_equal "Contact", response_body["last_name"]
      end

      test "create contact requires authentication" do
        post api_v1_contacts_list_index_path,
          params: { email: "new@example.com" },
          as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # UPDATE Tests
      # ====================================================================

      test "should update contact with valid params" do
        patch api_v1_contacts_list_path(@contact),
          params: { first_name: "Updated" },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "Updated", response_body["first_name"]
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy contact" do
        assert_difference "Contact.count", -1 do
          delete api_v1_contacts_list_path(@contact), headers: auth_headers, as: :json
        end

        assert_response :no_content
      end
    end
  end
end
