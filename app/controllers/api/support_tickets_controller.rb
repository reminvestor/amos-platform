# frozen_string_literal: true

module Api
  class SupportTicketsController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [:create]
    before_action :authenticate_user!, except: [:create]
    
    def create
      # Allow both authenticated and unauthenticated ticket creation
      entity = current_user&.entity || Entity.find_by(slug: 'platform') || Entity.first
      
      ticket = SupportTicket.new(
        entity: entity,
        user: current_user,
        title: params[:title],
        description: params[:description],
        category: params[:category] || 'bug',
        source: 'user_reported',
        priority: determine_priority(params[:category]),
        status: 'open'
      )
      
      if ticket.save
        render json: {
          success: true,
          ticket_number: ticket.ticket_number,
          message: "Ticket created successfully"
        }, status: :created
      else
        render json: {
          success: false,
          error: ticket.errors.full_messages.join(', ')
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "[SupportTickets] Error creating ticket: #{e.message}"
      render json: {
        success: false,
        error: "Failed to create ticket. Please try again."
      }, status: :internal_server_error
    end
    
    private
    
    def determine_priority(category)
      case category
      when 'security'
        'critical'
      when 'bug', 'data_issue'
        'medium'
      when 'feature_request', 'documentation', 'ui_issue'
        'low'
      else
        'medium'
      end
    end
  end
end

