class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :make_admin, :reset_password ]
  before_action -> { authorize_admin!(:editor) }, only: [ :edit, :update, :destroy, :make_admin, :reset_password ]

  def index
    @users = User.includes(:entity).order(created_at: :desc).page(params[:page])

    @stats = {
      total_users: User.count,
      onboarded: User.where(onboarded: true).count,
      admins: User.where(role: "admin").count,
      active_today: User.where("current_sign_in_at > ?", 24.hours.ago).count
    }
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User updated successfully."
    else
      render :edit
    end
  end

  def destroy
    # Get user info before deletion for logging
    user_email = @user.email
    user_id = @user.id
    
    if @user.destroy
      Rails.logger.info "🗑️ Admin deleted user #{user_id} (#{user_email})"
      redirect_to admin_users_path, notice: "User #{user_email} deleted successfully."
    else
      Rails.logger.error "❌ Failed to delete user #{user_id}: #{@user.errors.full_messages.join(', ')}"
      redirect_to admin_user_path(@user), alert: "Failed to delete user: #{@user.errors.full_messages.join(', ')}"
    end
  rescue ActiveRecord::InvalidForeignKey => e
    Rails.logger.error "❌ Foreign key constraint prevented deletion of user #{user_id}: #{e.message}"
    redirect_to admin_user_path(@user), alert: "Cannot delete user - they have associated records that must be removed first."
  rescue StandardError => e
    Rails.logger.error "❌ Error deleting user #{user_id}: #{e.message}"
    redirect_to admin_user_path(@user), alert: "Error deleting user: #{e.message}"
  end

  def make_admin
    if @user.update(role: "admin")
      redirect_to admin_user_path(@user), notice: "#{@user.full_name} is now an admin."
    else
      redirect_to admin_user_path(@user), alert: "Failed to make user an admin."
    end
  end

  def reset_password
    # Generate a new temporary password
    temp_password = SecureRandom.alphanumeric(12)
    
    if @user.update(password: temp_password, password_confirmation: temp_password)
      # Send password reset email
      UserMailer.admin_password_reset(@user, temp_password).deliver_later
      
      redirect_to admin_user_path(@user), 
        notice: "Password reset successfully. Temporary password: #{temp_password}. An email has been sent to the user."
    else
      redirect_to admin_user_path(@user), 
        alert: "Failed to reset password: #{@user.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    # Only allow role changes from the dedicated make_admin action, not from general updates
    params.require(:user).permit(:email, :first_name, :last_name, :onboarded, :agents_limit, :tools_limit, :integrations_limit)
  end
end
