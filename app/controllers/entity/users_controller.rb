class Entity::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_entity_admin
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :change_role ]

  def index
    # Get all users for the current entity
    @users = User.where(entity: current_entity).order(created_at: :desc)

    @stats = {
      total_users: @users.count,
      onboarded: @users.where(onboarded: true).count,
      active_this_week: @users.where("current_sign_in_at > ?", 7.days.ago).count
    }
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to entity_user_path(@user), notice: "User updated successfully."
    else
      render :edit
    end
  end

  def destroy
    if @user == current_user
      redirect_to entity_users_path, alert: "You cannot delete yourself."
      return
    end

    @user.destroy
    redirect_to entity_users_path, notice: "#{@user.full_name} has been removed from your entity."
  end

  def change_role
    new_role = params[:role]
    if @user.update(role: new_role)
      redirect_to entity_user_path(@user), notice: "#{@user.full_name}'s role changed to #{new_role}."
    else
      redirect_to entity_user_path(@user), alert: "Failed to change role."
    end
  end

  private

  def set_user
    # Only allow accessing users from your own entity
    @user = User.find_by(id: params[:id], entity: current_entity)
    unless @user
      redirect_to entity_users_path, alert: "User not found or not in your entity."
    end
  end

  def user_params
    # Only allow role assignment for entity admins
    permitted_params = [ :first_name, :last_name, :email ]
    permitted_params << :role if current_user.entity_admin?
    params.require(:user).permit(*permitted_params)
  end

  def require_entity_admin
    unless current_user.entity_admin?
      redirect_to root_path, alert: "You must be an entity admin to access user management."
    end
  end
end
