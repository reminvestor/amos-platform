class ContactsController < ApplicationController
  before_action :authenticate_user!
  layout 'customer_admin'
  before_action :set_contact, only: [ :show, :edit, :update, :destroy ]

  def index
    @contacts = current_entity.contacts.order(created_at: :desc).page(params[:page])
  end

  def show
  end

  def new
    @contact = current_entity.contacts.new
    @contact_groups = current_entity.contact_groups
  end

  def create
    @contact = current_entity.contacts.new(contact_params)

    if @contact.save
      redirect_to contacts_path, notice: "Contact was successfully created."
    else
      @contact_groups = current_entity.contact_groups
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contact_groups = current_entity.contact_groups
  end

  def update
    if @contact.update(contact_params)
      redirect_to contacts_path, notice: "Contact was successfully updated."
    else
      @contact_groups = current_entity.contact_groups
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy
    redirect_to contacts_path, notice: "Contact was successfully deleted."
  end

  private

  def set_contact
    @contact = current_entity.contacts.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:email, :first_name, :last_name, :status, :tags, contact_group_ids: [])
  end
end
