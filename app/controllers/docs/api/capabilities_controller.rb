# frozen_string_literal: true

module Docs
  module Api
    class CapabilitiesController < Docs::BaseController
      skip_before_action :verify_authenticity_token
      
      # GET /api/capabilities
      # Returns all AMOS capabilities organized by category
      # Used by AMOS to understand what he can do
      def index
        categories = DocCategory.where(capability_docs: true)
                                .includes(:doc_pages)
                                .order(:name)
        
        capabilities = categories.map do |category|
          {
            category: category.slug,
            name: category.name,
            description: category.description,
            capabilities: category.doc_pages.map do |page|
              {
                id: page.slug,
                name: page.title,
                summary: page.summary,
                keywords: page.keywords,
                updated_at: page.updated_at
              }
            end
          }
        end
        
        render json: {
          version: '1.0',
          updated_at: DocPage.maximum(:updated_at),
          categories: capabilities
        }
      rescue => e
        render json: { error: e.message }, status: :internal_server_error
      end
      
      # GET /api/capabilities/:category
      # Returns detailed capabilities for a specific category
      def show
        category = DocCategory.find_by!(slug: params[:category])
        pages = category.doc_pages.order(:title)
        
        render json: {
          category: category.slug,
          name: category.name,
          description: category.description,
          capabilities: pages.map do |page|
            {
              id: page.slug,
              name: page.title,
              summary: page.summary,
              content: page.content, # Full content for detailed queries
              keywords: page.keywords,
              examples: page.examples,
              parameters: page.parameters,
              updated_at: page.updated_at
            }
          end
        }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Category not found' }, status: :not_found
      end
      
      # POST /api/suggest_update
      # AMOS can suggest documentation updates
      def suggest_update
        suggestion = DocSuggestion.create!(
          doc_page_id: params[:page_id],
          suggested_by: 'amos',
          suggestion_type: params[:type] || 'update',
          title: params[:title],
          content: params[:content],
          rationale: params[:rationale],
          source: params[:source] || 'ai_observation',
          status: 'pending'
        )
        
        render json: {
          success: true,
          suggestion_id: suggestion.id,
          message: "Suggestion queued for review"
        }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
