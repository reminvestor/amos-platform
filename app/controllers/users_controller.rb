class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, only: [ :show, :edit, :update ]
  layout 'customer_admin'

  def show
    # Just display the user's profile
  end

  def edit
    # Show form to edit user details
  end

  def update
    respond_to do |format|
      if @user.update(user_params)
        format.html { redirect_to @user, notice: "Your profile was successfully updated." }
        format.json { render json: { success: true, message: "Profile updated successfully" }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @user.errors }, status: :unprocessable_entity }
      end
    end
  end

  def deactivate
    unless current_user.valid_password?(params[:password])
      redirect_to user_path(current_user), alert: "Incorrect password."
      return
    end

    now = Time.current

    current_user.entity_users.where(role: "owner").each do |entity_user|
      entity = entity_user.entity
      next unless entity
      if entity.entity_users.where(role: "owner").count == 1
        entity.update!(deleted_at: now)
      end
    end

    current_user.update!(deleted_at: now, api_key: SecureRandom.hex(32))
    Rails.logger.info "🗑️ User #{current_user.id} (#{current_user.email}) deactivated their account via web"
    sign_out(current_user)
    redirect_to new_user_session_path, notice: "Your account has been deactivated. Contact support to reactivate."
  end

  def destroy_account
    unless current_user.valid_password?(params[:password])
      redirect_to user_path(current_user), alert: "Incorrect password."
      return
    end

    user_id = current_user.id
    user_email = current_user.email

    current_user.entity_users.where(role: "owner").each do |entity_user|
      entity = entity_user.entity
      next unless entity
      if entity.entity_users.where(role: "owner").count == 1
        entity.destroy!
      end
    end

    current_user.reload
    sign_out(current_user)

    user = User.find(user_id)
    if user.destroy
      Rails.logger.info "🗑️ User #{user_id} (#{user_email}) permanently deleted their account via web"
      redirect_to new_user_session_path, notice: "Your account has been permanently deleted."
    else
      redirect_to new_user_session_path, alert: "Failed to delete account. Please contact support."
    end
  rescue ActiveRecord::InvalidForeignKey
    redirect_to new_user_session_path, alert: "Cannot delete account due to existing records. Please contact support."
  end

  private

  def set_user
    @user = current_user
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :phone, :timezone, :bio, :full_name, :business_name)
  end
end
