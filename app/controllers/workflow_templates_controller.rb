class WorkflowTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: [:show, :update, :destroy, :duplicate]

  def index
    @templates = WorkflowTemplate.for_entity(current_entity.id).active

    # Filter by category/industry if provided
    @templates = @templates.by_category(params[:category]) if params[:category].present?
    @templates = @templates.by_industry(params[:industry]) if params[:industry].present?
    @templates = @templates.tagged_with(params[:tag]) if params[:tag].present?

    respond_to do |format|
      format.html
      format.json { render json: @templates }
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @template }
    end
  end

  def duplicate
    unless @template.is_system? || @template.shared?
      render json: { error: "Can only duplicate system or shared templates" }, status: :unprocessable_entity
      return
    end

    @new_template = @template.duplicate_for_entity(current_entity)

    respond_to do |format|
      format.html { redirect_to workflow_templates_path, notice: "Template duplicated successfully." }
      format.json { render json: @new_template, status: :created }
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_to workflow_templates_path, alert: "Failed to duplicate template: #{e.message}" }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def update
    unless @template.entity_id == current_entity.id && !@template.is_system?
      render json: { error: "Cannot edit system templates" }, status: :forbidden
      return
    end

    if @template.update(template_params)
      respond_to do |format|
        format.html { redirect_to workflow_templates_path, notice: "Template updated." }
        format.json { render json: @template }
      end
    else
      respond_to do |format|
        format.html { render :edit }
        format.json { render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    unless @template.entity_id == current_entity.id && !@template.is_system?
      render json: { error: "Cannot delete system templates" }, status: :forbidden
      return
    end

    @template.destroy

    respond_to do |format|
      format.html { redirect_to workflow_templates_path, notice: "Template deleted." }
      format.json { head :no_content }
    end
  end

  private

  def set_template
    @template = WorkflowTemplate.find(params[:id])
  end

  def template_params
    params.require(:workflow_template).permit(:name, :description, :category, :industry, :shared, tags: [])
  end
end
