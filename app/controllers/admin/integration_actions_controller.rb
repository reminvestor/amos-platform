# frozen_string_literal: true

class Admin::IntegrationActionsController < Admin::BaseController
  before_action :set_integration
  before_action :set_action, only: [:show, :edit, :update, :destroy, :activate, :test]

  def index
    @actions = @integration.integration_actions.includes(:integration_operation).order(:action_name)
    @operations_without_actions = @integration.integration_operations.left_outer_joins(:integration_actions)
                                              .where(integration_actions: { id: nil })
                                              .order(:operation_id)
  end

  def show
    @executions = @action.executions.recent.limit(20)
  end

  def new
    @action = @integration.integration_actions.build
    @operations = @integration.integration_operations.order(:operation_id)
    
    # Pre-select operation if provided
    if params[:operation_id]
      @operation = @integration.integration_operations.find_by(id: params[:operation_id])
      @action.integration_operation = @operation if @operation
    end
  end

  def create
    @action = @integration.integration_actions.build(action_params)
    @action.created_by = current_user
    @action.mapping_code_generated_at = Time.current
    @action.mapping_code_generated_by = 'admin'

    if @action.save
      redirect_to admin_integration_integration_action_path(@integration, @action),
                  notice: "Action '#{@action.action_name}' created successfully."
    else
      @operations = @integration.integration_operations.order(:operation_id)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @operations = @integration.integration_operations.order(:operation_id)
  end

  def update
    if @action.update(action_params)
      redirect_to admin_integration_integration_action_path(@integration, @action),
                  notice: "Action updated successfully."
    else
      @operations = @integration.integration_operations.order(:operation_id)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @action.destroy
    redirect_to admin_integration_integration_actions_path(@integration),
                notice: "Action deleted successfully."
  end

  # Generate action for a specific operation
  def generate
    operation_id = params[:operation_id]
    use_ai = params[:use_ai] == 'true'

    operation = @integration.integration_operations.find_by(id: operation_id)
    unless operation
      redirect_to admin_integration_integration_actions_path(@integration),
                  alert: "Operation not found"
      return
    end

    result = Integrations::ActionGeneratorService.generate_for_operation(
      operation,
      use_ai: use_ai,
      user_id: current_user.id
    )

    if result[:success]
      redirect_to admin_integration_integration_action_path(@integration, result[:action]),
                  notice: "Action '#{result[:action].action_name}' generated successfully!"
    else
      redirect_to admin_integration_integration_actions_path(@integration),
                  alert: "Failed to generate action: #{result[:error]}"
    end
  end

  # Generate actions for all operations
  def generate_all
    use_ai = params[:use_ai] == 'true'

    results = Integrations::ActionGeneratorService.backfill_for_integration(
      @integration.slug,
      use_ai: use_ai,
      user_id: current_user.id
    )

    created = results[:created].length
    skipped = results[:skipped].length
    errors = results[:errors].length

    message = "Generated #{created} actions"
    message += ", skipped #{skipped}" if skipped > 0
    message += ", #{errors} errors" if errors > 0

    redirect_to admin_integration_integration_actions_path(@integration),
                notice: message
  end

  # Activate a draft action
  def activate
    @action.update!(status: :active)
    redirect_to admin_integration_integration_action_path(@integration, @action),
                notice: "Action activated successfully."
  end

  # Test an action's mapping
  def test
    test_inputs = params[:test_inputs]&.permit!&.to_h || @action.sample_input

    validation = @action.validate_inputs(test_inputs)
    unless validation[:valid]
      @test_result = { success: false, error: validation[:errors].join(', ') }
      render :show
      return
    end

    result = @action.test_mapping(test_inputs)
    @test_result = result
    render :show
  end

  private

  def set_integration
    @integration = Integration.find(params[:integration_id])
  end

  def set_action
    @action = @integration.integration_actions.find(params[:id])
  end

  def action_params
    params.require(:integration_action).permit(
      :action_name, :description, :category, :status,
      :integration_operation_id, :mapping_code, :response_mapping_code,
      input_schema: [:name, :type, :required, :description, :min, :max, values: []],
      sample_input: {},
      sample_output: {}
    )
  end
end

