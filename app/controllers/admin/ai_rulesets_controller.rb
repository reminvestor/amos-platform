class Admin::AiRulesetsController < Admin::BaseController
  before_action :authorize_super_admin!, except: [:index, :show]
  before_action :set_ai_ruleset, only: [:show, :edit, :update, :destroy, :toggle, :clone]

  def index
    @ai_rulesets = AiRuleset.includes(:entity)
                            .order(is_system: :desc, priority: :desc, created_at: :asc)
                            .page(params[:page])

    # Apply filters
    @ai_rulesets = @ai_rulesets.by_category(params[:category]) if params[:category].present?
    @ai_rulesets = @ai_rulesets.active if params[:status] == "active"
    @ai_rulesets = @ai_rulesets.inactive if params[:status] == "inactive"
    @ai_rulesets = @ai_rulesets.global if params[:scope] == "global"
    @ai_rulesets = @ai_rulesets.where.not(entity_id: nil) if params[:scope] == "entity"
    @ai_rulesets = @ai_rulesets.system_presets if params[:scope] == "system"

    @stats = {
      total: AiRuleset.count,
      active: AiRuleset.active.count,
      global: AiRuleset.global.count,
      system: AiRuleset.system_presets.count,
      by_category: AiRuleset::CATEGORIES.index_with { |c| AiRuleset.by_category(c).count }
    }

    @entities = Entity.order(:name).pluck(:name, :id)
  end

  def show
    @preview_prompt = @ai_ruleset.to_prompt
  end

  def new
    @ai_ruleset = AiRuleset.new(is_active: true, priority: 0)
    @entities = Entity.order(:name).pluck(:name, :id)
  end

  def create
    @ai_ruleset = AiRuleset.new(ai_ruleset_params)

    if @ai_ruleset.save
      redirect_to admin_ai_ruleset_path(@ai_ruleset),
                  notice: "AI Ruleset '#{@ai_ruleset.name}' was successfully created."
    else
      @entities = Entity.order(:name).pluck(:name, :id)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @entities = Entity.order(:name).pluck(:name, :id)
  end

  def update
    if @ai_ruleset.is_system? && !params[:ai_ruleset][:rules].present?
      redirect_to admin_ai_ruleset_path(@ai_ruleset),
                  alert: "System presets can only have their rules modified."
      return
    end

    if @ai_ruleset.update(ai_ruleset_params)
      redirect_to admin_ai_ruleset_path(@ai_ruleset),
                  notice: "AI Ruleset '#{@ai_ruleset.name}' was successfully updated."
    else
      @entities = Entity.order(:name).pluck(:name, :id)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @ai_ruleset.is_system?
      redirect_to admin_ai_rulesets_path,
                  alert: "System presets cannot be deleted."
      return
    end

    name = @ai_ruleset.name
    @ai_ruleset.destroy
    redirect_to admin_ai_rulesets_path,
                notice: "AI Ruleset '#{name}' was successfully deleted."
  end

  def toggle
    @ai_ruleset.update(is_active: !@ai_ruleset.is_active)
    status = @ai_ruleset.is_active? ? "enabled" : "disabled"
    redirect_to admin_ai_rulesets_path,
                notice: "AI Ruleset '#{@ai_ruleset.name}' has been #{status}."
  end

  def clone
    new_ruleset = @ai_ruleset.dup
    new_ruleset.name = "#{@ai_ruleset.name} (Copy)"
    new_ruleset.is_system = false
    new_ruleset.entity_id = params[:target_entity_id] if params[:target_entity_id].present?

    if new_ruleset.save
      redirect_to admin_ai_ruleset_path(new_ruleset),
                  notice: "AI Ruleset cloned successfully."
    else
      redirect_to admin_ai_ruleset_path(@ai_ruleset),
                  alert: "Failed to clone ruleset: #{new_ruleset.errors.full_messages.join(', ')}"
    end
  end

  private

  def set_ai_ruleset
    @ai_ruleset = AiRuleset.find(params[:id])
  end

  def ai_ruleset_params
    permitted = params.require(:ai_ruleset).permit(
      :name, :description, :category, :is_active, :priority, :entity_id
    )

    # Handle rules as array from textarea (one rule per line)
    if params[:ai_ruleset][:rules].present?
      if params[:ai_ruleset][:rules].is_a?(String)
        permitted[:rules] = params[:ai_ruleset][:rules]
                              .split("\n")
                              .map(&:strip)
                              .reject(&:blank?)
      else
        permitted[:rules] = params[:ai_ruleset][:rules]
      end
    end

    permitted
  end

  def authorize_super_admin!
    authorize_admin!(:super_admin)
  end
end
