# frozen_string_literal: true

module Api
  module V1
    class TeamController < BaseController
      before_action :require_entity_admin, only: [:invite, :update_member, :remove_member]

      # GET /api/v1/team/members
      def members
        team_members = current_entity.entity_users.includes(:user).order(:role, :created_at)

        render json: {
          members: team_members.map { |eu| member_json(eu) },
          pending_invites: pending_invites_json
        }
      end

      # POST /api/v1/team/invite
      def invite
        @invite = TeamInvite.new(invite_params.merge(
          entity: current_entity,
          invited_by: current_user,
          token: SecureRandom.urlsafe_base64(32),
          expires_at: 7.days.from_now
        ))

        if @invite.save
          TeamMailer.invite_email(@invite).deliver_later
          render json: {
            success: true,
            message: "Invitation sent to #{@invite.email}",
            invite: {
              id: @invite.id,
              email: @invite.email,
              role: @invite.role,
              expires_at: @invite.expires_at
            }
          }
        else
          render json: {
            success: false,
            errors: @invite.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/team/invite/:id
      def cancel_invite
        invite = TeamInvite.find_by(id: params[:id], entity: current_entity)

        if invite.nil?
          render json: { error: "Invitation not found" }, status: :not_found
          return
        end

        invite.destroy
        render json: { success: true, message: "Invitation cancelled" }
      end

      # POST /api/v1/team/invite/:id/resend
      def resend_invite
        invite = TeamInvite.find_by(id: params[:id], entity: current_entity)

        if invite.nil?
          render json: { error: "Invitation not found" }, status: :not_found
          return
        end

        invite.update!(expires_at: 7.days.from_now)
        TeamMailer.invite_email(invite).deliver_later
        render json: { success: true, message: "Invitation resent to #{invite.email}" }
      end

      # PATCH /api/v1/team/members/:id
      def update_member
        entity_user = current_entity.entity_users.find_by(id: params[:id])

        if entity_user.nil?
          render json: { error: "Team member not found" }, status: :not_found
          return
        end

        if entity_user.update(member_params)
          render json: {
            success: true,
            message: "#{entity_user.user.full_name}'s role updated",
            member: member_json(entity_user)
          }
        else
          render json: {
            success: false,
            errors: entity_user.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/team/members/:id
      def remove_member
        entity_user = current_entity.entity_users.find_by(id: params[:id])

        if entity_user.nil?
          render json: { error: "Team member not found" }, status: :not_found
          return
        end

        if entity_user.user == current_user
          render json: { error: "You cannot remove yourself from the team" }, status: :unprocessable_entity
          return
        end

        user_name = entity_user.user.full_name
        if entity_user.destroy
          render json: { success: true, message: "#{user_name} has been removed from the team" }
        else
          render json: {
            success: false,
            errors: entity_user.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def require_entity_admin
        unless current_user.entity_admin?
          render json: { error: "Admin access required" }, status: :forbidden
        end
      end

      def invite_params
        params.require(:team_invite).permit(:email, :role)
      end

      def member_params
        params.require(:entity_user).permit(:role)
      end

      def member_json(entity_user)
        user = entity_user.user
        {
          id: entity_user.id,
          user_id: user.id,
          email: user.email,
          name: user.full_name,
          first_name: user.first_name,
          last_name: user.last_name,
          role: entity_user.role,
          avatar_url: user.respond_to?(:avatar_url) ? user.avatar_url : nil,
          created_at: entity_user.created_at
        }
      end

      def pending_invites_json
        TeamInvite.pending.where(entity: current_entity).map do |invite|
          {
            id: invite.id,
            email: invite.email,
            role: invite.role,
            expires_at: invite.expires_at,
            invited_by: invite.invited_by&.full_name
          }
        end
      end
    end
  end
end
