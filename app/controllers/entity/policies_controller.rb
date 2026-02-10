class Entity::PoliciesController < Entity::BaseController
  before_action :set_policy, only: [ :show, :edit, :update, :destroy, :toggle ]

  def index
    redirect_to chat_mode_path, status: :moved_permanently
  end

  def show
  end

  def new
    @policy = current_entity.policy_rules.build
  end

  def create
    @policy = current_entity.policy_rules.build(policy_params)

    if @policy.save
      redirect_to chat_mode_path, notice: "AI usage policy created successfully."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @policy.update(policy_params)
      redirect_to chat_mode_path, notice: "Policy updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @policy.destroy
    redirect_to chat_mode_path, notice: "Policy deleted successfully."
  end

  def toggle
    @policy.update(is_active: !@policy.is_active)
    redirect_to chat_mode_path, notice: "Policy #{@policy.is_active ? 'enabled' : 'disabled'}."
  end

  private

  def set_policy
    @policy = current_entity.policy_rules.find(params[:id])
  end

  def policy_params
    params.require(:policy_rule).permit(
      :name, :resource_type, :resource_id, :agent_role, :action,
      :max_daily_calls, :max_write_calls, :requires_confirmation, :is_active,
      conditions: {}
    )
  end

end
