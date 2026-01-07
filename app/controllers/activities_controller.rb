# frozen_string_literal: true

class ActivitiesController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  before_action :set_activity, only: [:show, :edit, :update, :destroy, :complete]
  before_action :authorize_destroy!, only: [:destroy]
  layout "customer_admin"

  def index
    @activities = current_entity.activities
                                .includes(:contact, :opportunity, :user, :performed_by_agent)
                                .order(created_at: :desc)
                                .limit(100)

    # Filter by type if specified
    @activities = @activities.by_type(params[:type]) if params[:type].present?
    
    # Filter by status
    @activities = @activities.by_status(params[:status]) if params[:status].present?

    @stats = Activity.stats_for(current_entity.activities)
  end

  def tasks
    @tasks = current_entity.activities
                           .tasks
                           .includes(:contact, :opportunity, :assigned_user, :assigned_agent)
                           .order(due_at: :asc)

    # Group tasks
    @overdue = @tasks.overdue
    @due_today = @tasks.where(due_at: Time.current.beginning_of_day..Time.current.end_of_day)
    @upcoming = @tasks.where("due_at > ?", Time.current.end_of_day).where(status: "pending")
    @completed = @tasks.completed.where("completed_at > ?", 7.days.ago)
  end

  def show
  end

  def new
    @activity = current_entity.activities.build
    @activity.activity_type = params[:type] || "note"
    @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
    @opportunities = current_entity.opportunities.open.order(:name)
  end

  def create
    @activity = current_entity.activities.build(activity_params)
    @activity.user = current_user

    if @activity.save
      # Update contact's last activity
      @activity.contact&.update(last_activity_at: Time.current)
      
      redirect_to activities_path, notice: "Activity logged successfully."
    else
      @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
      @opportunities = current_entity.opportunities.open.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
    @opportunities = current_entity.opportunities.open.order(:name)
  end

  def update
    if @activity.update(activity_params)
      redirect_to activities_path, notice: "Activity updated."
    else
      @contacts = current_entity.contacts.order(:first_name, :last_name).limit(100)
      @opportunities = current_entity.opportunities.open.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @activity.destroy
    redirect_to activities_path, notice: "Activity deleted."
  end

  def complete
    @activity.complete!(params[:outcome])
    
    respond_to do |format|
      format.html { redirect_to activities_path, notice: "Task completed!" }
      format.json { render json: { success: true, activity: @activity } }
    end
  end

  private

  def set_activity
    @activity = current_entity.activities.find(params[:id])
  end

  def activity_params
    params.require(:activity).permit(
      :activity_type, :contact_id, :opportunity_id,
      :subject, :description, :outcome,
      :scheduled_at, :due_at, :priority,
      :assigned_user_id, :assigned_agent_id
    )
  end

  def current_entity
    current_user.entity
  end
end
