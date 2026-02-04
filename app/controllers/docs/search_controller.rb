# frozen_string_literal: true

module Docs
  class SearchController < Docs::BaseController
    def index
      @query = params[:q].to_s.strip
      
      if @query.present?
        @results = search_pages(@query)
        @total = @results.count
      else
        @results = []
        @total = 0
      end
    end
    
    private
    
    def search_pages(query)
      # Full-text search across title, content, and summary
      DocPage.where(
        "title ILIKE :q OR content ILIKE :q OR summary ILIKE :q",
        q: "%#{query}%"
      ).order(updated_at: :desc).limit(50)
    rescue => e
      Rails.logger.error "Search error: #{e.message}"
      []
    end
  end
end
