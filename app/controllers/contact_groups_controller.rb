class ContactGroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contact_group, only: [:show, :edit, :update, :destroy]
  
  def index
    @contact_groups = current_user.contact_groups.order(name: :asc).page(params[:page])
  end

  def show
    @contacts = @contact_group.contacts.order(last_name: :asc, first_name: :asc).page(params[:page])
  end

  def new
    @contact_group = current_user.contact_groups.new
    @available_contacts = current_user.contacts
  end

  def create
    @contact_group = current_user.contact_groups.new(contact_group_params)
    
    if @contact_group.save
      redirect_to contact_groups_path, notice: 'Contact group was successfully created.'
    else
      @available_contacts = current_user.contacts
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_contacts = current_user.contacts
  end

  def update
    if @contact_group.update(contact_group_params)
      redirect_to contact_groups_path, notice: 'Contact group was successfully updated.'
    else
      @available_contacts = current_user.contacts
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @contact_group.destroy
      redirect_to contact_groups_path, notice: 'Contact group was successfully deleted.'
    else
      redirect_to contact_groups_path, alert: @contact_group.errors.full_messages.to_sentence
    end
  end
  
  private
  
  def set_contact_group
    @contact_group = current_user.contact_groups.find(params[:id])
  end
  
  def contact_group_params
    params.require(:contact_group).permit(:name, :description, contact_ids: [])
  end
end
