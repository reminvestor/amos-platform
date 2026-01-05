# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class TeamControllerTest < ActionDispatch::IntegrationTest
      setup do
        @owner = users(:one)
        @entity = entities(:one)
        @owner.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create entity_user record for owner
        @owner_entity_user = EntityUser.find_or_create_by!(
          entity: @entity,
          user: @owner
        ) do |eu|
          eu.role = 'owner'
        end
        @owner_entity_user.update!(role: 'owner')

        # Create a regular member
        @member = users(:two)
        @member.update!(entity: @entity, api_key: SecureRandom.hex(32))
        @member_entity_user = EntityUser.find_or_create_by!(
          entity: @entity,
          user: @member
        ) do |eu|
          eu.role = 'member'
        end
        @member_entity_user.update!(role: 'member')

        # Create a pending invite
        @pending_invite = TeamInvite.create!(
          entity: @entity,
          invited_by: @owner,
          email: "pending@example.com",
          role: "member",
          token: SecureRandom.urlsafe_base64(32),
          expires_at: 7.days.from_now,
          status: 'pending'
        )
      end

      teardown do
        TeamInvite.where(entity: @entity).destroy_all
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers(user = @owner)
        { "Authorization" => "Bearer #{user.api_key}" }
      end

      # ====================================================================
      # MEMBERS (GET /api/v1/team) Tests
      # ====================================================================

      test "should get team members list with valid token" do
        get api_v1_team_members_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("members")
        assert response_body.key?("pending_invites")
      end

      test "members list returns expected fields" do
        get api_v1_team_members_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        members = response_body["members"]

        assert members.any?

        member = members.first
        assert member.key?("id")
        assert member.key?("user_id")
        assert member.key?("email")
        assert member.key?("name")
        assert member.key?("role")
        assert member.key?("created_at")
      end

      test "members list includes pending invites" do
        get api_v1_team_members_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        invites = response_body["pending_invites"]

        assert invites.any?
        invite = invites.find { |i| i["email"] == "pending@example.com" }
        assert_not_nil invite
        assert_equal "member", invite["role"]
      end

      test "members list requires authentication" do
        get api_v1_team_members_path, as: :json

        assert_response :unauthorized
      end

      test "members list accessible by non-admin" do
        # Viewing team members is allowed for all entity users
        # Only modifying (invite, update, remove) requires admin
        get api_v1_team_members_path, headers: auth_headers(@member), as: :json

        assert_response :success
      end

      # ====================================================================
      # INVITE (POST /api/v1/team/invite) Tests
      # ====================================================================

      test "should create invite with valid data" do
        assert_difference("TeamInvite.count", 1) do
          post api_v1_team_invite_path,
            params: { team_invite: { email: "newuser@example.com", role: "member" } },
            headers: auth_headers,
            as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]
        assert_equal "newuser@example.com", response_body["invite"]["email"]
        assert_equal "member", response_body["invite"]["role"]
      end

      test "should create admin invite" do
        post api_v1_team_invite_path,
          params: { team_invite: { email: "admin@example.com", role: "admin" } },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal "admin", response_body["invite"]["role"]
      end

      test "invite fails with invalid email" do
        assert_no_difference("TeamInvite.count") do
          post api_v1_team_invite_path,
            params: { team_invite: { email: "invalid-email", role: "member" } },
            headers: auth_headers,
            as: :json
        end

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert_not response_body["success"]
        assert response_body["errors"].any?
      end

      test "invite fails for existing member email" do
        assert_no_difference("TeamInvite.count") do
          post api_v1_team_invite_path,
            params: { team_invite: { email: @member.email, role: "member" } },
            headers: auth_headers,
            as: :json
        end

        assert_response :unprocessable_entity
      end

      test "invite requires authentication" do
        post api_v1_team_invite_path,
          params: { team_invite: { email: "test@example.com", role: "member" } },
          as: :json

        assert_response :unauthorized
      end

      test "invite requires admin role" do
        post api_v1_team_invite_path,
          params: { team_invite: { email: "test@example.com", role: "member" } },
          headers: auth_headers(@member),
          as: :json

        assert_response :forbidden
      end

      # ====================================================================
      # CANCEL INVITE (DELETE /api/v1/team/invite/:id) Tests
      # ====================================================================

      test "should cancel pending invite" do
        assert_difference("TeamInvite.count", -1) do
          delete api_v1_team_cancel_invite_path(@pending_invite.id),
            headers: auth_headers,
            as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]
      end

      test "cancel invite returns 404 for non-existent invite" do
        delete api_v1_team_cancel_invite_path(999999),
          headers: auth_headers,
          as: :json

        assert_response :not_found
      end

      test "cancel invite requires authentication" do
        delete api_v1_team_cancel_invite_path(@pending_invite.id), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # RESEND INVITE (POST /api/v1/team/invite/:id/resend) Tests
      # ====================================================================

      test "should resend pending invite" do
        original_expires_at = @pending_invite.expires_at

        post api_v1_team_resend_invite_path(@pending_invite.id),
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]

        @pending_invite.reload
        assert @pending_invite.expires_at > original_expires_at
      end

      test "resend invite returns 404 for non-existent invite" do
        post api_v1_team_resend_invite_path(999999),
          headers: auth_headers,
          as: :json

        assert_response :not_found
      end

      # ====================================================================
      # UPDATE MEMBER (PATCH /api/v1/team/members/:id) Tests
      # ====================================================================

      test "should update member role" do
        patch api_v1_team_update_member_path(@member_entity_user.id),
          params: { entity_user: { role: "admin" } },
          headers: auth_headers,
          as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]
        assert_equal "admin", response_body["member"]["role"]

        @member_entity_user.reload
        assert_equal "admin", @member_entity_user.role
      end

      test "update member returns 404 for non-existent member" do
        patch api_v1_team_update_member_path(999999),
          params: { entity_user: { role: "admin" } },
          headers: auth_headers,
          as: :json

        assert_response :not_found
      end

      test "update member requires admin role" do
        patch api_v1_team_update_member_path(@member_entity_user.id),
          params: { entity_user: { role: "admin" } },
          headers: auth_headers(@member),
          as: :json

        assert_response :forbidden
      end

      # ====================================================================
      # REMOVE MEMBER (DELETE /api/v1/team/members/:id) Tests
      # ====================================================================

      test "should remove team member" do
        assert_difference("EntityUser.count", -1) do
          delete api_v1_team_remove_member_path(@member_entity_user.id),
            headers: auth_headers,
            as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]
      end

      test "cannot remove self from team" do
        assert_no_difference("EntityUser.count") do
          delete api_v1_team_remove_member_path(@owner_entity_user.id),
            headers: auth_headers,
            as: :json
        end

        assert_response :unprocessable_entity
      end

      test "remove member returns 404 for non-existent member" do
        delete api_v1_team_remove_member_path(999999),
          headers: auth_headers,
          as: :json

        assert_response :not_found
      end

      test "remove member requires admin role" do
        delete api_v1_team_remove_member_path(@member_entity_user.id),
          headers: auth_headers(@member),
          as: :json

        assert_response :forbidden
      end
    end
  end
end
