# frozen_string_literal: true

class WorkItemsChannel < ApplicationCable::Channel
  def subscribed
    if current_user
      stream_from "user_#{current_user.id}_work_items"
      Rails.logger.info "📥 WorkItemsChannel: User #{current_user.id} subscribed to work items"
    else
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "📥 WorkItemsChannel: User unsubscribed from work items"
  end
end

