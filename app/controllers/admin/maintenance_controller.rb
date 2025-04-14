module Admin
  class MaintenanceController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin
    
    def index
    end
    
    def add_missing_email_deliveries
      # Start the maintenance task in background job
      AddMissingEmailDeliveriesJob.perform_later(current_user.id)
      redirect_to admin_maintenance_index_path, notice: "Task to add missing email deliveries has been started. This may take some time."
    end
    
    def fix_campaign_entity_ids
      # Start the fix entity IDs task in background job
      FixCampaignEntityIdsJob.perform_later(current_user.id)
      redirect_to admin_maintenance_index_path, notice: "Task to fix missing entity IDs on campaigns has been started."
    end
    
    def reprocess_drip_campaigns
      # Reprocess drip campaigns
      ProcessDripCampaignsJob.perform_later
      redirect_to admin_maintenance_index_path, notice: "Drip campaign processing has been triggered."
    end
    
    private
    
    def ensure_admin
      unless current_user&.admin?
        redirect_to root_path, alert: "You don't have permission to access this page."
      end
    end
  end
end 