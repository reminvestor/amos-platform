class Admin::BaseController < ApplicationController
  before_action :authenticate_admin!
  before_action :log_admin_activity

  layout "admin"

  private

  def authenticate_admin!
    if admin_signed_in?
      # Admin is authenticated
    elsif user_signed_in? && current_user.admin?
      # Regular user with admin privileges - create/find admin record
      sign_in_admin_from_user
    else
      redirect_to chat_mode_path, alert: "You must be an admin to access this area."
    end
  end

  def admin_signed_in?
    current_admin.present?
  end

  def current_admin
    @current_admin ||= AdminUser.find_by(id: session[:admin_user_id]) if session[:admin_user_id]
  end
  helper_method :current_admin

  def current_entity
    @current_entity ||= current_user&.entity
  end
  helper_method :current_entity

  def sign_in_admin_from_user
    # Find or create AdminUser record based on user email
    admin = AdminUser.find_by(email: current_user.email)

    if admin.nil?
      # Create admin user record if it doesn't exist
      admin = AdminUser.create!(
        email: current_user.email,
        first_name: current_user.first_name,
        last_name: current_user.last_name,
        password: SecureRandom.hex(32), # Random password, they'll use their user login
        role: "super_admin"
      )
    end

    if admin.locked?
      redirect_to chat_mode_path, alert: "Your admin account is locked."
    else
      session[:admin_user_id] = admin.id
      admin.record_login!
      @current_admin = admin
    end
  end

  def log_admin_activity
    return unless current_admin

    AdminActivity.create!(
      admin_user: current_admin,
      action: "#{controller_name}##{action_name}",
      resource_type: controller_name.classify,
      resource_id: params[:id],
      details: request.filtered_parameters.except("controller", "action").to_json,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  rescue => e
    Rails.logger.error "Failed to log admin activity: #{e.message}"
  end

  def authorize_admin!(required_role = :viewer)
    return if current_admin.super_admin?

    case required_role
    when :editor
      unless current_admin.editor? || current_admin.super_admin?
        redirect_to admin_dashboard_path, alert: "You need editor privileges for this action."
      end
    when :super_admin
      unless current_admin.super_admin?
        redirect_to admin_dashboard_path, alert: "You need super admin privileges for this action."
      end
    end
  end
end
