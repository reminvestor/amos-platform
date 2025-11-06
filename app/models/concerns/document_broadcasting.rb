# Module to handle broadcasting document updates via Action Cable
module DocumentBroadcasting
  extend ActiveSupport::Concern

  included do
    after_update :broadcast_status_update, if: :saved_change_to_processing_status?
  end

  # Broadcast document status updates
  def broadcast_status_update
    ActionCable.server.broadcast(
      "documents:entity:#{rag_store.entity_id}",
      {
        action: 'update_status',
        document_id: id,
        status: processing_status,
        status_html: render_status_html,
        preview_html: render_preview_html,
        badge_class: status_badge_class,
        badge_text: status_badge_text
      }
    )

    # If processing is complete, send a special notification
    if processing_status == 'completed'
      ActionCable.server.broadcast(
        "documents:entity:#{rag_store.entity_id}",
        {
          action: 'processing_complete',
          document_id: id,
          redirect_url: Rails.application.routes.url_helpers.document_path(self)
        }
      )
    end
  end

  # Broadcast progress updates (called from jobs)
  def broadcast_progress_update
    ActionCable.server.broadcast(
      "documents:entity:#{rag_store.entity_id}",
      {
        action: 'update_progress',
        document_id: id,
        progress: processing_progress,
        stage: processing_stage,
        stage_description: processing_stage_description,
        embedding_stats: render_embedding_stats
      }
    )
  end

  private

  def render_status_html
    ApplicationController.render(
      partial: 'documents/status_cell',
      locals: { document: self }
    )
  end

  def render_preview_html
    ApplicationController.render(
      partial: 'documents/preview_content',
      locals: { document: self }
    )
  end

  def render_embedding_stats
    return nil unless processing_stage == 'embedding' && chunk_count > 0
    
    ApplicationController.render(
      partial: 'documents/embedding_stats',
      locals: { document: self }
    )
  end

  def status_badge_class
    case processing_status
    when 'processing' then 'badge badge-warning'
    when 'failed' then 'badge badge-danger'
    when 'completed' then 'badge badge-success'
    else 'badge badge-secondary'
    end
  end

  def status_badge_text
    case processing_status
    when 'processing' then 'Processing'
    when 'failed' then 'Failed'
    when 'completed' then 'Ready'
    else processing_status.humanize
    end
  end
end
