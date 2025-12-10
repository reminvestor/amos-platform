# frozen_string_literal: true

class TeamInvitesController < ApplicationController
  before_action :set_invite, only: [:show, :accept, :decline]
  skip_before_action :check_token_balance, only: [:show, :accept, :decline]

  # Show invite details (for logged in users)
  def show
    if @invite.nil?
      redirect_to root_path, alert: "Invalid or expired invitation"
      return
    end

    if @invite.expired?
      redirect_to root_path, alert: "This invitation has expired"
      return
    end

    if @invite.status != 'pending'
      redirect_to root_path, notice: "This invitation has already been #{@invite.status}"
      return
    end

    # If user is logged in, show accept page
    if user_signed_in?
      # Check if user is already a member
      if @invite.entity.users.include?(current_user)
        redirect_to root_path, notice: "You're already a member of #{@invite.entity.name}"
        return
      end
      
      render :show
    else
      # Store invite token and redirect to registration
      session[:team_invite_token] = params[:token]
      redirect_to new_user_registration_path, notice: "Please create an account or sign in to accept the invitation"
    end
  end

  # Accept the invitation
  def accept
    unless user_signed_in?
      session[:team_invite_token] = params[:token]
      redirect_to new_user_session_path, notice: "Please sign in to accept the invitation"
      return
    end

    if @invite.nil? || @invite.expired? || @invite.status != 'pending'
      redirect_to root_path, alert: "This invitation is no longer valid"
      return
    end

    if @invite.accept!(current_user)
      session.delete(:team_invite_token)
      redirect_to root_path, notice: "Welcome to #{@invite.entity.name}! You're now part of the team."
    else
      redirect_to root_path, alert: "Failed to accept invitation: #{@invite.errors.full_messages.join(', ')}"
    end
  end

  # Decline the invitation
  def decline
    if @invite&.pending?
      @invite.decline!
      redirect_to root_path, notice: "Invitation declined"
    else
      redirect_to root_path, alert: "This invitation is no longer valid"
    end
  end

  private

  def set_invite
    @invite = TeamInvite.find_by(token: params[:token])
  end
end
