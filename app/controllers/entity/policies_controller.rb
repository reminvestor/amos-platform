class Entity::PoliciesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_entity_admin
  before_action :set_policy, only: [:show, :edit, :update, :destroy, :toggle]
  
  def index
    @policies = current_entity.policy_rules.order(created_at: :desc)
    
    @stats = {
      total: @policies.count,
      active: @policies.where(is_active: true).count,
      with_budgets: @policies.where.not(max_daily_calls: nil).count
    }
  end
  
  def show
  end
  
  def new
    @policy = current_entity.policy_rules.build
  end
  
  def create
    @policy = current_entity.policy_rules.build(policy_params)
    
    if @policy.save
      redirect_to entity_policies_path, notice: 'AI usage policy created successfully.'
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @policy.update(policy_params)
      redirect_to entity_policies_path, notice: 'Policy updated successfully.'
    else
      render :edit
    end
  end
  
  def destroy
    @policy.destroy
    redirect_to entity_policies_path, notice: 'Policy deleted successfully.'
  end
  
  def toggle
    @policy.update(is_active: !@policy.is_active)
    redirect_to entity_policies_path, notice: "Policy #{@policy.is_active ? 'enabled' : 'disabled'}."
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
  
  def require_entity_admin
    unless current_user.entity_admin?
      redirect_to root_path, alert: 'You must be an entity admin to manage policies.'
    end
  end
end

