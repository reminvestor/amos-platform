class DocumentsChannel < ApplicationCable::Channel
  def subscribed
    # Subscribe to updates for documents belonging to the current user's entity
    if current_user&.entity
      stream_from "documents:entity:#{current_user.entity_id}"
      stream_from "document:#{params[:document_id]}" if params[:document_id]
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
