# frozen_string_literal: true

# Authorizable concern provides role-based authorization for controller actions
#
# Usage in controllers:
#   include Authorizable
#   before_action :authorize_destroy!, only: [:destroy]
#
# Or with custom permission level:
#   before_action -> { authorize_action!(:admin) }, only: [:destroy, :update]
#
# Permission levels (from EntityUser roles):
#   :member  - Basic access (can view, limited modifications)
#   :admin   - Full access to entity resources
#   :owner   - Complete control including entity settings
#
module Authorizable
  extend ActiveSupport::Concern

  included do
    helper_method :can_destroy?, :can_modify? if respond_to?(:helper_method)
  end

  protected

  # Authorize destroy action - requires admin or owner role
  def authorize_destroy!
    authorize_action!(:admin)
  end

  # Authorize any action with specified minimum role
  # @param required_role [Symbol] :member, :admin, or :owner
  def authorize_action!(required_role = :member)
    unless authorized_for_role?(required_role)
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path, alert: "You don't have permission to perform this action.") }
        format.json { render json: { error: "Unauthorized" }, status: :forbidden }
        format.turbo_stream { head :forbidden }
      end
    end
  end

  # Check if current user has sufficient role for the action
  # @param required_role [Symbol] :member, :admin, or :owner
  # @return [Boolean]
  def authorized_for_role?(required_role)
    return false unless current_user && current_entity

    entity_user = current_user.entity_users.find_by(entity: current_entity)
    return false unless entity_user

    case required_role
    when :owner
      entity_user.owner?
    when :admin
      entity_user.admin? || entity_user.owner?
    when :member
      true # All roles can perform member-level actions
    else
      false
    end
  end

  # Helper: Can the current user destroy records?
  def can_destroy?
    authorized_for_role?(:admin)
  end

  # Helper: Can the current user modify records?
  def can_modify?
    authorized_for_role?(:member)
  end

  # Authorize based on record ownership (user created the record)
  # Use when you want creators to be able to delete their own records
  def authorize_owner_or_admin!(record)
    return if authorized_for_role?(:admin)
    return if record.respond_to?(:user_id) && record.user_id == current_user.id
    return if record.respond_to?(:created_by_id) && record.created_by_id == current_user.id

    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path, alert: "You can only modify your own records.") }
      format.json { render json: { error: "Unauthorized" }, status: :forbidden }
      format.turbo_stream { head :forbidden }
    end
  end
end
