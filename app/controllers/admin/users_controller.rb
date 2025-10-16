class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :make_admin ]
  before_action :authorize_editor!, only: [ :edit, :update, :destroy, :make_admin ]

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
    @user.destroy
    redirect_to admin_users_path, notice: "User deleted successfully."
  end

  def make_admin
    if @user.update(role: "admin")
      redirect_to admin_user_path(@user), notice: "#{@user.full_name} is now an admin."
    else
      redirect_to admin_user_path(@user), alert: "Failed to make user an admin."
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    # Only allow role changes from the dedicated make_admin action, not from general updates
    params.require(:user).permit(:email, :first_name, :last_name, :onboarded)
  end
end
