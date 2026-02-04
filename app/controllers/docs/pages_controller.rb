# frozen_string_literal: true

module Docs
  class PagesController < Docs::BaseController
    before_action :set_page, only: [:show, :edit, :update, :destroy, :history, :revision, :revert]
    before_action :require_editor!, only: [:new, :create, :edit, :update, :destroy, :revert]
    
    def index
      @featured_pages = DocPage.where(featured: true).order(:title).limit(6) rescue []
      @recent_pages = DocPage.order(updated_at: :desc).limit(10) rescue []
      @categories = DocCategory.includes(:doc_pages).order(:name) rescue []
      @stats = calculate_stats
    end
    
    def show
      @related_pages = @page&.related_pages&.limit(5) || []
    end
    
    def new
      @page = DocPage.new
      @categories = DocCategory.order(:name) rescue []
    end
    
    def create
      @page = DocPage.new(page_params)
      @page.created_by = current_user
      @page.last_edited_by = current_user
      
      if @page.save
        create_revision(@page, 'created')
        redirect_to docs_page_path(@page), notice: "Page created successfully!"
      else
        @categories = DocCategory.order(:name) rescue []
        render :new
      end
    rescue => e
      redirect_to docs_root_path, alert: "Could not create page: #{e.message}"
    end
    
    def edit
      @categories = DocCategory.order(:name) rescue []
    end
    
    def update
      old_content = @page.content
      @page.last_edited_by = current_user
      
      if @page.update(page_params)
        create_revision(@page, 'updated', old_content)
        redirect_to docs_page_path(@page), notice: "Page updated successfully!"
      else
        @categories = DocCategory.order(:name) rescue []
        render :edit
      end
    rescue => e
      redirect_to docs_page_path(@page), alert: "Could not update page: #{e.message}"
    end
    
    def destroy
      @page.destroy
      redirect_to docs_root_path, notice: "Page deleted."
    rescue => e
      redirect_to docs_page_path(@page), alert: "Could not delete page: #{e.message}"
    end
    
    def history
      @revisions = @page.revisions.order(created_at: :desc).page(params[:page]).per(20) rescue []
    end
    
    def revision
      @revision = @page.revisions.find(params[:revision_id]) rescue nil
    end
    
    def revert
      revision = @page.revisions.find(params[:revision_id])
      old_content = @page.content
      
      @page.update!(content: revision.content, last_edited_by: current_user)
      create_revision(@page, 'reverted', old_content)
      
      redirect_to docs_page_path(@page), notice: "Page reverted to earlier version."
    rescue => e
      redirect_to history_docs_page_path(@page), alert: "Could not revert: #{e.message}"
    end
    
    def recent
      @pages = DocPage.order(updated_at: :desc).page(params[:page]).per(25) rescue []
    end
    
    def categories
      @categories = DocCategory.includes(:doc_pages).order(:name) rescue []
    end
    
    private
    
    def set_page
      @page = DocPage.find_by!(slug: params[:id])
    rescue ActiveRecord::RecordNotFound
      # Create a stub for new page creation
      @page = DocPage.new(slug: params[:id], title: params[:id].titleize)
      redirect_to new_docs_page_path(title: params[:id].titleize) if action_name == 'show'
    end
    
    def page_params
      params.require(:doc_page).permit(:title, :slug, :content, :summary, :category_id, :featured)
    end
    
    def create_revision(page, action, old_content = nil)
      DocPageRevision.create!(
        doc_page: page,
        user: current_user,
        content: page.content,
        previous_content: old_content,
        action: action,
        summary: params[:edit_summary]
      )
    rescue => e
      Rails.logger.error "Failed to create revision: #{e.message}"
    end
    
    def calculate_stats
      {
        total_pages: DocPage.count,
        total_contributors: DocPage.distinct.count(:last_edited_by_id),
        recent_edits: DocPage.where('updated_at > ?', 7.days.ago).count
      }
    rescue
      { total_pages: 0, total_contributors: 0, recent_edits: 0 }
    end
  end
end
