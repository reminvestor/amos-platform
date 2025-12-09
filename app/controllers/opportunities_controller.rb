# frozen_string_literal: true

class OpportunitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_opportunity, only: [:show, :edit, :update, :destroy, :move_stage, :close_won, :close_lost]
  layout "customer_admin"

  def index
    @opportunities = current_entity.opportunities
                                   .includes(:contact, :user, :assigned_agent)
                                   .ordered_by_position

    # Group by stage for pipeline view
    @pipeline = Opportunity::STAGES.keys.each_with_object({}) do |stage, hash|
      stage_opps = @opportunities.select { |o| o.stage == stage }
      hash[stage] = {
        info: Opportunity::STAGES[stage],
        opportunities: stage_opps,
        count: stage_opps.count,
        total_value: stage_opps.sum(&:value) || 0
      }
    end

    @stats = Opportunity.pipeline_stats(current_entity)
  end

  def show
    @activities = @opportunity.activities.includes(:user, :performed_by_agent).order(created_at: :desc).limit(20)
  end

  def new
    @opportunity = current_entity.opportunities.build
    @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
    @users = current_entity.users
  end

  def create
    @opportunity = current_entity.opportunities.build(opportunity_params)
    @opportunity.user = current_user unless @opportunity.user_id.present?

    if @opportunity.save
      # Log the creation
      Activity.create!(
        entity: current_entity,
        opportunity: @opportunity,
        contact: @opportunity.contact,
        user: current_user,
        activity_type: "opportunity_created",
        subject: "Opportunity Created: #{@opportunity.name}",
        description: "Created with value #{helpers.number_to_currency(@opportunity.value)} in #{@opportunity.stage_label} stage",
        status: "completed",
        completed_at: Time.current
      )

      redirect_to opportunities_path, notice: "Opportunity created successfully."
    else
      @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
      @users = current_entity.users
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
    @users = current_entity.users
  end

  def update
    if @opportunity.update(opportunity_params)
      redirect_to opportunity_path(@opportunity), notice: "Opportunity updated successfully."
    else
      @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
      @users = current_entity.users
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @opportunity.destroy
    redirect_to opportunities_path, notice: "Opportunity deleted."
  end

  def move_stage
    new_stage = params[:stage]
    
    if Opportunity::STAGES.keys.include?(new_stage)
      old_stage = @opportunity.stage
      @opportunity.move_to_stage!(new_stage, user: current_user)
      
      respond_to do |format|
        format.html { redirect_to opportunities_path, notice: "Moved to #{@opportunity.stage_label}" }
        format.json { render json: { success: true, opportunity: @opportunity } }
      end
    else
      respond_to do |format|
        format.html { redirect_to opportunities_path, alert: "Invalid stage" }
        format.json { render json: { success: false, error: "Invalid stage" }, status: :unprocessable_entity }
      end
    end
  end

  def close_won
    @opportunity.close_won!(user: current_user)
    
    respond_to do |format|
      format.html { redirect_to opportunities_path, notice: "🎉 Congratulations! Deal closed won!" }
      format.json { render json: { success: true, opportunity: @opportunity } }
    end
  end

  def close_lost
    @opportunity.close_lost!(params[:lost_reason], user: current_user)
    
    respond_to do |format|
      format.html { redirect_to opportunities_path, notice: "Opportunity marked as lost." }
      format.json { render json: { success: true, opportunity: @opportunity } }
    end
  end

  private

  def set_opportunity
    @opportunity = current_entity.opportunities.find(params[:id])
  end

  def opportunity_params
    params.require(:opportunity).permit(
      :name, :contact_id, :user_id, :assigned_agent_id,
      :stage, :value, :probability, :expected_close_date,
      :source, :notes
    )
  end

  def current_entity
    current_user.entity
  end
end
