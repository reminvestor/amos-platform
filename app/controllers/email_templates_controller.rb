require "ostruct"

class EmailTemplatesController < ApplicationController
  include EntityScoped
  include Authorizable
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_email_template, only: [ :show, :edit, :update, :destroy, :test_email ]
  before_action :authorize_destroy!, only: [:destroy]

  def index
    @email_templates = current_entity.email_templates.order(created_at: :desc)
  end

  def show
  end

  def new
    @email_template = current_entity.email_templates.new
  end

  def create
    @email_template = current_entity.email_templates.new(email_template_params)

    if @email_template.save
      redirect_to email_templates_path, notice: "Email template was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @email_template.update(email_template_params)
      respond_to do |format|
        format.html { redirect_to email_templates_path, notice: "Email template was successfully updated." }
        format.json { render json: { success: true, email_template: @email_template } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @email_template.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @email_template.destroy
    redirect_to email_templates_path, notice: "Email template was successfully deleted."
  end

  # Send a test email
  def test_email
    if params[:email].present?
      # Create a dummy contact
      test_contact = OpenStruct.new(
        first_name: "Test",
        last_name: "User",
        email: params[:email]
      )

      # Send test email
      TestEmailMailer.template_test(
        @email_template,
        test_contact,
        current_user
      ).deliver_now

      respond_to do |format|
        format.html { redirect_to @email_template, notice: "Test email sent to #{params[:email]}" }
        format.json { render json: { success: true, message: "Test email sent to #{params[:email]}" } }
      end
    else
      respond_to do |format|
        format.html { redirect_to @email_template, alert: "Please provide an email address" }
        format.json { render json: { success: false, message: "Please provide an email address" }, status: :unprocessable_entity }
      end
    end
  rescue => e
    Rails.logger.error("Test email error: #{e.message}")
    respond_to do |format|
      format.html { redirect_to @email_template, alert: "Error sending test email: #{e.message}" }
      format.json { render json: { success: false, message: "Error sending test email: #{e.message}" }, status: :internal_server_error }
    end
  end

  private

  def set_email_template
    @email_template = current_entity.email_templates.find(params[:id])
  end

  def email_template_params
    params.require(:email_template).permit(:name, :subject, :body)
  end
end
