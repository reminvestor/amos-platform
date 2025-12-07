# SharedController
#
# Handles public/shared content viewing without authentication.
# Currently supports:
# - Memory bookmarks (shared conversation outputs)
#
class SharedController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show, :conversation]
  layout 'marketing'

  # GET /shared/:token
  def show
    @bookmark = MemoryBookmark.find_by_share_token(params[:token])

    if @bookmark.nil?
      render_not_found
      return
    end

    # Record the view
    @bookmark.record_view!

    # Load context
    @context_messages = @bookmark.context_messages
    @main_message = @bookmark.scout_message
    @entity_name = @bookmark.entity&.name || "Business"
    @created_at = @bookmark.created_at
  end

  # GET /shared/:token/conversation
  # Returns JSON for AJAX loading of conversation context
  def conversation
    @bookmark = MemoryBookmark.find_by_share_token(params[:token])

    if @bookmark.nil?
      render json: { error: "Not found" }, status: :not_found
      return
    end

    render json: {
      title: @bookmark.title,
      description: @bookmark.description,
      messages: @bookmark.context_messages,
      main_message: {
        content: @bookmark.scout_message&.content,
        created_at: @bookmark.scout_message&.created_at&.iso8601
      },
      view_count: @bookmark.view_count,
      created_at: @bookmark.created_at.iso8601
    }
  end

  private

  def render_not_found
    respond_to do |format|
      format.html do
        render html: <<~HTML.html_safe, status: :not_found, layout: 'marketing'
          <div class="container py-5 text-center">
            <h1 class="display-4">Content Not Found</h1>
            <p class="lead text-muted">This shared content may have expired or been removed.</p>
            <a href="/" class="btn btn-primary mt-3">Go Home</a>
          </div>
        HTML
      end
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end
end
