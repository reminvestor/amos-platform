class RemindersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_reminder, only: [:show, :edit, :update, :destroy, :complete, :uncomplete]

  layout "customer_admin"

  def index
    @overdue_reminders = current_user.reminders.overdue
    @today_reminders = current_user.reminders.today
    @upcoming_reminders = current_user.reminders.upcoming.where.not(id: @today_reminders.pluck(:id)).limit(20)
    @completed_count = current_user.reminders.completed.count
  end

  def completed
    @reminders = current_user.reminders.completed.order(completed_at: :desc)
  end

  def show
  end

  def new
    @reminder = current_user.reminders.build(remind_at: 1.hour.from_now)
  end

  def create
    @reminder = current_user.reminders.build(reminder_params)

    if @reminder.save
      respond_to do |format|
        format.html { redirect_to reminders_path, notice: "Reminder created." }
        format.json { render json: @reminder, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @reminder.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @reminder.update(reminder_params)
      respond_to do |format|
        format.html { redirect_to reminders_path, notice: "Reminder updated." }
        format.json { render json: @reminder }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @reminder.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @reminder.destroy
    respond_to do |format|
      format.html { redirect_to reminders_path, notice: "Reminder deleted." }
      format.json { head :no_content }
    end
  end

  def complete
    @reminder.complete!
    respond_to do |format|
      format.html { redirect_to reminders_path, notice: "Reminder completed!" }
      format.json { render json: @reminder }
    end
  end

  def uncomplete
    @reminder.uncomplete!
    respond_to do |format|
      format.html { redirect_to completed_reminders_path, notice: "Reminder restored." }
      format.json { render json: @reminder }
    end
  end

  private

  def set_reminder
    @reminder = current_user.reminders.find(params[:id])
  end

  def reminder_params
    params.require(:user_reminder).permit(:title, :description, :remind_at, :repeat_interval, :priority)
  end
end
