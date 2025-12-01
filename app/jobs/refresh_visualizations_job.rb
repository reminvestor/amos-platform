# frozen_string_literal: true

class RefreshVisualizationsJob < ApplicationJob
  queue_as :maintenance
  
  def perform
    Rails.logger.info "🔄 Checking for visualizations needing refresh..."
    
    visualizations = SavedVisualization.needs_refresh.includes(:user, :entity)
    
    if visualizations.empty?
      Rails.logger.info "No visualizations need refresh at this time"
      return
    end
    
    Rails.logger.info "Found #{visualizations.count} visualizations to refresh"
    
    visualizations.find_each do |viz|
      begin
        viz.refresh!
        Rails.logger.info "Refreshed visualization: #{viz.name} (#{viz.id})"
      rescue => e
        Rails.logger.error "Failed to refresh visualization #{viz.id}: #{e.message}"
      end
    end
  end
end

