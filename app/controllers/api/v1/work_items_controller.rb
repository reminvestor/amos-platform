# frozen_string_literal: true

module Api
  module V1
    class WorkItemsController < BaseController
      before_action :set_work_item, only: [:show, :mark_read, :toggle_starred, :archive, :unarchive]

      def index
        @work_items = AgentWorkItem.where(user: current_user, entity: current_entity)
                                   .order(created_at: :desc)
                                   .page(params[:page] || 1)
                                   .per(params[:per_page] || 20)

        # Apply filters
        case params[:filter]
        when 'unread'
          @work_items = @work_items.unread.not_archived
        when 'starred'
          @work_items = @work_items.starred.not_archived
        when 'action_required'
          @work_items = @work_items.requiring_action.not_archived
        when 'archived'
          @work_items = @work_items.archived
        else
          @work_items = @work_items.not_archived
        end

        if params[:work_type].present?
          @work_items = @work_items.where(work_type: params[:work_type])
        end

        if params[:priority].present?
          @work_items = @work_items.where(priority: params[:priority])
        end

        render json: {
          data: @work_items.map { |item| work_item_json(item) },
          pagination: {
            current_page: @work_items.current_page,
            total_pages: @work_items.total_pages,
            total_count: @work_items.total_count,
            per_page: @work_items.limit_value
          },
          counts: {
            unread: AgentWorkItem.where(user: current_user, entity: current_entity).unread.not_archived.count,
            starred: AgentWorkItem.where(user: current_user, entity: current_entity).starred.not_archived.count,
            action_required: AgentWorkItem.where(user: current_user, entity: current_entity).requiring_action.not_archived.count,
            total: AgentWorkItem.where(user: current_user, entity: current_entity).not_archived.count
          }
        }
      end

      def show
        render json: work_item_detail_json(@work_item)
      end

      def mark_read
        @work_item.mark_as_read!
        render json: work_item_json(@work_item)
      end

      def mark_all_read
        AgentWorkItem.where(user: current_user, entity: current_entity)
                     .unread
                     .not_archived
                     .update_all(read: true, read_at: Time.current)

        render json: { message: "All items marked as read" }
      end

      def toggle_starred
        @work_item.toggle_starred!
        render json: work_item_json(@work_item)
      end

      def archive
        @work_item.archive!
        render json: work_item_json(@work_item)
      end

      def unarchive
        @work_item.unarchive!
        render json: work_item_json(@work_item)
      end

      private

      def set_work_item
        @work_item = AgentWorkItem.where(user: current_user, entity: current_entity).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { message: "Work item not found" }, status: :not_found
      end

      def work_item_json(item)
        {
          id: item.id,
          work_type: item.work_type,
          title: item.title,
          summary: item.summary,
          icon: item.icon,
          category: item.category,
          priority: item.priority,
          read: item.read,
          starred: item.starred,
          archived: item.archived,
          requires_action: item.requires_action,
          action_type: item.action_type,
          action_due_at: item.action_due_at,
          agent_name: item.agent_name,
          time_ago: item.time_ago,
          created_at: item.created_at,
          updated_at: item.updated_at
        }
      end

      def work_item_detail_json(item)
        work_item_json(item).merge(
          details: item.details,
          asset_type: item.asset_type,
          asset_id: item.asset_id,
          asset_data: item.asset_data,
          metadata: item.metadata
        )
      end
    end
  end
end
