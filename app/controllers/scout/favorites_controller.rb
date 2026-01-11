# frozen_string_literal: true

module Scout
  class FavoritesController < ApplicationController
    include Authorizable
    before_action :authenticate_user!
    before_action :set_favorite_for_destroy, only: [:destroy]
    before_action -> { authorize_owner_or_admin!(@favorite) }, only: [:destroy]

    # POST /scout/favorites/toggle
    # Toggle favorite status for an item
    def toggle
      favoritable = find_favoritable
      
      unless favoritable
        render json: { success: false, error: "Item not found" }, status: :not_found
        return
      end

      result = UserFavorite.toggle!(
        user: current_user,
        entity: current_user.entity,
        favoritable: favoritable
      )

      render json: {
        success: true,
        favorited: result[:favorited],
        message: result[:message],
        item_type: params[:type],
        item_id: params[:id]
      }
    rescue => e
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # GET /scout/favorites
    # List user's favorites
    def index
      favorites = current_user.user_favorites
                              .includes(:favoritable)
                              .by_priority

      # Filter by type if specified
      favorites = favorites.where(favoritable_type: params[:type]) if params[:type].present?

      render json: {
        success: true,
        favorites: favorites.map { |f| serialize_favorite(f) },
        counts: {
          agents: current_user.user_favorites.agents.count,
          tools: current_user.user_favorites.tools.count,
          integrations: current_user.user_favorites.integrations.count
        }
      }
    end

    # DELETE /scout/favorites/:id
    # Remove a favorite
    def destroy
      unless @favorite
        render json: { success: false, error: "Favorite not found" }, status: :not_found
        return
      end

      @favorite.destroy
      render json: { success: true, message: "Removed from favorites" }
    end

    # PATCH /scout/favorites/:id
    # Update favorite (nickname, notes, priority)
    def update
      favorite = current_user.user_favorites.find_by(id: params[:id])

      unless favorite
        render json: { success: false, error: "Favorite not found" }, status: :not_found
        return
      end

      if favorite.update(favorite_params)
        render json: { success: true, favorite: serialize_favorite(favorite) }
      else
        render json: { success: false, errors: favorite.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # GET /scout/favorites/check
    # Check if items are favorited (batch check)
    def check
      items = params[:items] || []
      
      results = items.map do |item|
        favorited = UserFavorite.exists?(
          user: current_user,
          favoritable_type: item[:type],
          favoritable_id: item[:id]
        )
        { type: item[:type], id: item[:id], favorited: favorited }
      end

      render json: { success: true, results: results }
    end

    private

    def set_favorite_for_destroy
      @favorite = current_user.user_favorites.find_by(id: params[:id])
    end

    def find_favoritable
      case params[:type]
      when 'AgentPlugin'
        AgentPlugin.find_by(id: params[:id]) || AgentPlugin.find_by(slug: params[:id])
      when 'ToolDefinition'
        ToolDefinition.find_by(id: params[:id]) || ToolDefinition.find_by(name: params[:id])
      when 'Integration'
        Integration.find_by(id: params[:id]) || Integration.find_by(slug: params[:id])
      else
        nil
      end
    end

    def favorite_params
      params.permit(:nickname, :notes, :priority)
    end

    def serialize_favorite(favorite)
      item = favorite.favoritable
      {
        id: favorite.id,
        type: favorite.favoritable_type,
        item_id: favorite.favoritable_id,
        nickname: favorite.nickname,
        notes: favorite.notes,
        priority: favorite.priority,
        created_at: favorite.created_at.iso8601,
        item: {
          name: item&.name,
          slug: item.try(:slug),
          description: item.try(:description)&.truncate(100),
          role: item.try(:role)
        }
      }
    end
  end
end

