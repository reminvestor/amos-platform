class DashboardController < ApplicationController
  before_action :authenticate_user!
  
  def index
    @entity = current_entity
    
    # Quick stats
    @campaigns_count = current_user.campaigns.where(entity: @entity).count
    @contacts_count = current_user.contacts.where(entity: @entity).count
    @landing_pages_count = current_user.landing_pages.where(entity: @entity).count
    @email_templates_count = current_user.email_templates.where(entity: @entity).count
    
    # Recent activity
    @recent_campaigns = current_user.campaigns.where(entity: @entity).order(created_at: :desc).limit(5)
    @recent_landing_pages = current_user.landing_pages.where(entity: @entity).order(created_at: :desc).limit(5)
    @recent_contacts = current_user.contacts.where(entity: @entity).order(created_at: :desc).limit(5)
    
    # Connections
    @active_connections = current_user.connections.where(status: 'connected').includes(:integration)
  end
end

