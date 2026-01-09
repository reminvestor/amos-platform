class BookmarksController < ApplicationController
  include Authorizable
  before_action :authenticate_user!
  before_action :set_bookmark, only: [:show, :edit, :update, :destroy, :share, :unshare]
  before_action -> { authorize_owner_or_admin!(@bookmark) }, only: [:destroy]

  layout "customer_admin"

  def index
    @bookmarks = current_entity.memory_bookmarks
                              .where(user: current_user)
                              .by_recency

    @conversations = @bookmarks.conversations
    @visualizations = @bookmarks.visualizations
    @context_blocks = @bookmarks.context_blocks
    @insights = @bookmarks.insights

    @filter = params[:filter]
    @bookmarks = case @filter
                 when 'conversations' then @conversations
                 when 'visualizations' then @visualizations
                 when 'context' then @context_blocks
                 when 'insights' then @insights
                 else @bookmarks
                 end
  end

  def show
    @bookmark.record_view!
  end

  def new
    @bookmark = current_entity.memory_bookmarks.build(user: current_user)
  end

  def create
    @bookmark = current_entity.memory_bookmarks.build(bookmark_params)
    @bookmark.user = current_user

    if @bookmark.save
      respond_to do |format|
        format.html { redirect_to bookmarks_path, notice: "Bookmark created." }
        format.json { render json: @bookmark.to_api_hash, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @bookmark.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def edit
  end

  def update
    if @bookmark.update(bookmark_params)
      respond_to do |format|
        format.html { redirect_to bookmarks_path, notice: "Bookmark updated." }
        format.json { render json: @bookmark.to_api_hash }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @bookmark.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @bookmark.destroy
    respond_to do |format|
      format.html { redirect_to bookmarks_path, notice: "Bookmark deleted." }
      format.json { head :no_content }
    end
  end

  def share
    share_url = @bookmark.share!
    respond_to do |format|
      format.html { redirect_to bookmarks_path, notice: "Bookmark shared! URL: #{share_url}" }
      format.json { render json: { success: true, share_url: share_url } }
    end
  end

  def unshare
    @bookmark.unshare!
    respond_to do |format|
      format.html { redirect_to bookmarks_path, notice: "Bookmark is now private." }
      format.json { render json: { success: true } }
    end
  end

  private

  def set_bookmark
    @bookmark = current_entity.memory_bookmarks.where(user: current_user).find(params[:id])
  end

  def bookmark_params
    params.require(:memory_bookmark).permit(:title, :description, :bookmark_type, :content_type, tags: [])
  end
end
