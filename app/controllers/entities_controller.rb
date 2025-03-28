class EntitiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_entity, only: [:show, :edit, :update, :destroy, :switch]
  before_action :require_entity_admin, only: [:edit, :update, :destroy]
  
  def index
    @entities = current_user.entities
  end

  def show
    # Set as current entity in session
    session[:entity_id] = @entity.id
  end

  def new
    @entity = Entity.new
  end

  def create
    @entity = Entity.new(entity_params)
    
    # Create the entity and add the current user as owner
    if @entity.save
      @entity.entity_users.create(user: current_user, role: 'owner')
      session[:entity_id] = @entity.id
      redirect_to @entity, notice: 'Entity was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @entity.update(entity_params)
      redirect_to @entity, notice: 'Entity was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    if @entity.destroy
      session[:entity_id] = nil
      redirect_to entities_path, notice: 'Entity was successfully deleted.'
    else
      redirect_to entities_path, alert: 'Unable to delete entity.'
    end
  end
  
  def switch
    # Switch to another entity
    session[:entity_id] = @entity.id
    redirect_back(fallback_location: root_path, notice: "Switched to #{@entity.name}")
  end
  
  private
  
  def set_entity
    @entity = current_user.entities.find(params[:id])
  end
  
  def entity_params
    params.require(:entity).permit(:name, :subdomain, :status, :timezone, :currency, :date_format, :logo_url, :primary_color)
  end
  
  def require_entity_admin
    unless current_user.entity_admin?(@entity)
      redirect_to entities_path, alert: "You don't have permission to manage this entity."
    end
  end
end
