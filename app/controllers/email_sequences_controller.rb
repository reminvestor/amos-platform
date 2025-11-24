class EmailSequencesController < ApplicationController
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_sequence, only: [:show, :edit, :update, :destroy, :activate, :pause]

  def index
    @email_sequences = current_entity.email_sequences.order(created_at: :desc)
  end

  def show
    @steps = @sequence.sequence_steps.order(:step_number)
    @enrollments = @sequence.sequence_enrollments.order(created_at: :desc).page(params[:page]).per(20)
  end

  def new
    @sequence = current_entity.email_sequences.new(status: 'draft')
    @contact_groups = current_entity.contact_groups
  end

  def create
    @sequence = current_entity.email_sequences.new(sequence_params)
    
    if @sequence.save
      redirect_to @sequence, notice: 'Email sequence was successfully created.'
    else
      @contact_groups = current_entity.contact_groups
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contact_groups = current_entity.contact_groups
  end

  def update
    if @sequence.update(sequence_params)
      redirect_to @sequence, notice: 'Email sequence was successfully updated.'
    else
      @contact_groups = current_entity.contact_groups
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @sequence.destroy
    redirect_to email_sequences_path, notice: 'Email sequence was successfully deleted.'
  end

  def activate
    if @sequence.update(status: 'active')
      redirect_to @sequence, notice: 'Sequence activated. Contacts will now proceed through steps.'
    else
      redirect_to @sequence, alert: 'Could not activate sequence.'
    end
  end

  def pause
    if @sequence.update(status: 'paused')
      redirect_to @sequence, notice: 'Sequence paused.'
    else
      redirect_to @sequence, alert: 'Could not pause sequence.'
    end
  end

  private

  def set_sequence
    @sequence = current_entity.email_sequences.find(params[:id])
  end

  def sequence_params
    params.require(:email_sequence).permit(:name, :goal, :contact_group_id, :status)
  end
end

