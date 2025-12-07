# frozen_string_literal: true

module Scout
  class WorkItemsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_work_item, only: [:show, :mark_read, :mark_unread, :toggle_star, :archive]

    # GET /scout/work_items/unread_count
    def unread_count
      count = AgentWorkItem.unread_count_for(current_user, current_entity)
      render json: { count: count }
    end

    # GET /scout/work_items
    def index
      @work_items = AgentWorkItem.inbox_for(current_user, current_entity)
                                  .limit(params[:limit] || 50)
      
      render json: {
        work_items: @work_items.map { |item| work_item_json(item) },
        unread_count: AgentWorkItem.unread_count_for(current_user, current_entity)
      }
    end

    # GET /scout/work_items/:id
    def show
      render json: work_item_json(@work_item, include_details: true)
    end

    # POST /scout/work_items/:id/mark_read
    def mark_read
      @work_item.mark_as_read!
      
      # Broadcast count update
      broadcast_count_update
      
      render json: { success: true, read: true }
    end

    # POST /scout/work_items/:id/mark_unread
    def mark_unread
      @work_item.mark_as_unread!
      
      # Broadcast count update
      broadcast_count_update
      
      render json: { success: true, read: false }
    end

    # POST /scout/work_items/:id/toggle_star
    def toggle_star
      @work_item.toggle_starred!
      render json: { success: true, starred: @work_item.starred? }
    end

    # POST /scout/work_items/:id/archive
    def archive
      @work_item.archive!
      
      # Broadcast count update
      broadcast_count_update
      
      render json: { success: true, archived: true }
    end

    # POST /scout/work_items/mark_all_read
    def mark_all_read
      AgentWorkItem.inbox_for(current_user, current_entity)
                   .unread
                   .update_all(read: true, read_at: Time.current)
      
      # Broadcast count update
      broadcast_count_update
      
      render json: { success: true }
    end

    private

    def set_work_item
      @work_item = AgentWorkItem.find(params[:id])
      
      # Ensure user owns this work item
      unless @work_item.user_id == current_user.id
        render json: { error: 'Not authorized' }, status: :forbidden
      end
    end

    def work_item_json(item, include_details: false)
      json = {
        id: item.id,
        work_type: item.work_type,
        title: item.title,
        summary: item.summary,
        icon: item.icon,
        priority: item.priority,
        read: item.read?,
        starred: item.starred?,
        requires_action: item.requires_action?,
        agent_name: item.agent_name,
        created_at: item.created_at.iso8601,
        time_ago: item.time_ago,
        asset_type: item.asset_type,
        asset_id: item.asset_id,
        asset_data: item.asset_data
      }
      
      if include_details
        json[:details] = item.details
        json[:metadata] = item.metadata
        json[:execution_id] = item.agent_plugin_execution_id
      end
      
      json
    end

    def broadcast_count_update
      ActionCable.server.broadcast(
        "user_#{current_user.id}_work_items",
        {
          type: 'count_update',
          count: AgentWorkItem.unread_count_for(current_user, current_entity)
        }
      )
    end
  end
end

