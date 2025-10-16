class Admin::SessionsController < ApplicationController
  layout "admin"

  def new
    redirect_to admin_dashboard_path if admin_signed_in?
  end

  def create
    admin = AdminUser.find_by(email: params[:email]&.downcase)

    if admin&.authenticate(params[:password])
      if admin.locked?
        flash.now[:alert] = "Your account has been locked due to multiple failed login attempts."
        render :new, status: :unprocessable_entity
      else
        admin.record_login!
        session[:admin_user_id] = admin.id
        redirect_to admin_dashboard_path, notice: "Welcome back, #{admin.full_name}!"
      end
    else
      admin&.record_failed_login!
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.delete(:admin_user_id)
    redirect_to new_admin_session_path, notice: "You have been logged out."
  end

  private

  def admin_signed_in?
    session[:admin_user_id].present? && AdminUser.active.exists?(id: session[:admin_user_id])
  end
end
