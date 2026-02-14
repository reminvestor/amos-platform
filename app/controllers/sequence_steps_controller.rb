class SequenceStepsController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_sequence
  before_action :set_step, only: [:edit, :update, :destroy]
  before_action :authorize_destroy!, only: [:destroy]

  def new
    @step = @sequence.sequence_steps.new
    @email_templates = current_entity.email_templates
  end

  def create
    @step = @sequence.sequence_steps.new(step_params)
    
    # Auto-assign step number if not provided
    if @step.step_number.blank?
      last_step = @sequence.sequence_steps.order(:step_number).last
      @step.step_number = last_step ? last_step.step_number + 1 : 1
    end

    if @step.save
      redirect_to @sequence, notice: 'Step added successfully.'
    else
      @email_templates = current_entity.email_templates
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @email_templates = current_entity.email_templates
  end

  def update
    if @step.update(step_params)
      respond_to do |format|
        format.html { redirect_to @sequence, notice: 'Step updated successfully.' }
        format.json { render json: { success: true, message: 'Step updated successfully.' } }
      end
    else
      respond_to do |format|
        format.html do
          @email_templates = current_entity.email_templates
          render :edit, status: :unprocessable_entity
        end
        format.json { render json: { success: false, errors: @step.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @step.destroy
    redirect_to @sequence, notice: 'Step removed successfully.'
  end

  private

  def set_sequence
    @sequence = current_entity.email_sequences.find(params[:email_sequence_id])
  end

  def set_step
    @step = @sequence.sequence_steps.find(params[:id])
  end

  def step_params
    params.require(:sequence_step).permit(:step_number, :delay_hours, :email_template_id, :subject, :body)
  end
end

