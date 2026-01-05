class Entity::UsersController < Entity::BaseController
  before_action :set_user, only: [:show, :edit, :update, :destroy, :change_role]
  before_action :set_entity_user, only: [:edit_membership, :update_membership, :remove_member]
  before_action :set_invite, only: [:resend_invite, :cancel_invite]

  def index
    # Ensure current user is in entity_users (handles legacy users)
    current_user.ensure_entity_membership if current_user.entity_id.present?
    
    # Get all entity_users (team members) for the current entity
    @team_members = current_entity.entity_users.includes(:user).order(:role, :created_at)
    @pending_invites = TeamInvite.pending.where(entity: current_entity)
    @billing_account = EntityBillingAccount.find_by(entity: current_entity)

    @stats = {
      total_users: @team_members.count,
      owners: @team_members.where(role: 'owner').count,
      admins: @team_members.where(role: 'admin').count,
      members: @team_members.where(role: 'member').count,
      pending_invites: @pending_invites.count
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

  # === Team Invite Actions ===

  def new_invite
    @invite = TeamInvite.new
  end

  def create_invite
    @invite = TeamInvite.new(invite_params.merge(
      entity: current_entity,
      invited_by: current_user,
      token: SecureRandom.urlsafe_base64(32),
      expires_at: 7.days.from_now
    ))

    if @invite.save
      TeamMailer.invite_email(@invite).deliver_later
      respond_to do |format|
        format.html { redirect_to entity_users_path, notice: "Invitation sent to #{@invite.email}" }
        format.json { render json: { success: true, message: "Invitation sent to #{@invite.email}", invite: { id: @invite.id, email: @invite.email, role: @invite.role } } }
      end
    else
      respond_to do |format|
        format.html { render :new_invite, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @invite.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def resend_invite
    @invite.update!(expires_at: 7.days.from_now)
    TeamMailer.invite_email(@invite).deliver_later
    redirect_to entity_users_path, notice: "Invitation resent to #{@invite.email}"
  end

  def cancel_invite
    @invite.destroy
    redirect_to entity_users_path, notice: "Invitation cancelled"
  end

  # === Membership Management ===

  def edit_membership
    # @entity_user set by before_action
  end

  def update_membership
    if @entity_user.update(membership_params)
      redirect_to entity_users_path, notice: "#{@entity_user.user.full_name}'s role updated to #{@entity_user.role}"
    else
      render :edit_membership, status: :unprocessable_entity
    end
  end

  def remove_member
    if @entity_user.user == current_user
      redirect_to entity_users_path, alert: "You cannot remove yourself from the team"
      return
    end

    user_name = @entity_user.user.full_name
    if @entity_user.destroy
      redirect_to entity_users_path, notice: "#{user_name} has been removed from the team"
    else
      redirect_to entity_users_path, alert: @entity_user.errors.full_messages.join(", ")
    end
  end

  # === Shared Token Pool ===

  def toggle_shared_pool
    if current_entity.update(use_shared_token_pool: !current_entity.use_shared_token_pool)
      if current_entity.use_shared_token_pool
        # Ensure entity billing account exists
        EntityBillingAccount.for_entity(current_entity)
        redirect_to entity_users_path, notice: "Shared token pool enabled - team members now share tokens"
      else
        redirect_to entity_users_path, notice: "Shared token pool disabled - members use individual token balances"
      end
    else
      redirect_to entity_users_path, alert: "Failed to update token pool settings"
    end
  end

  private

  def set_user
    @user = User.find_by(id: params[:id], entity: current_entity)
    unless @user
      redirect_to entity_users_path, alert: "User not found or not in your entity."
    end
  end

  def set_entity_user
    @entity_user = current_entity.entity_users.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to entity_users_path, alert: "Team member not found"
  end

  def set_invite
    @invite = TeamInvite.find_by(id: params[:id], entity: current_entity)
    unless @invite
      redirect_to entity_users_path, alert: "Invitation not found"
    end
  end

  def user_params
    permitted_params = [:first_name, :last_name, :email]
    permitted_params << :role if current_user.entity_admin?
    params.require(:user).permit(*permitted_params)
  end

  def invite_params
    params.require(:team_invite).permit(:email, :role)
  end

  def membership_params
    params.require(:entity_user).permit(:role)
  end
end
