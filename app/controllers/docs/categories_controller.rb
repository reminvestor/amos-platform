# frozen_string_literal: true

module Docs
  class CategoriesController < Docs::BaseController
    def index
      @categories = DocCategory.includes(:doc_pages)
                               .order(:name)
                               .map { |c| { category: c, count: c.doc_pages.count } }
    rescue
      @categories = []
    end
    
    def show
      @category = DocCategory.find_by!(slug: params[:id])
      @pages = @category.doc_pages.order(:title).page(params[:page]).per(20)
    rescue ActiveRecord::RecordNotFound
      redirect_to docs_categories_path, alert: "Category not found."
    end
  end
end
