# frozen_string_literal: true

module Api
  module V1
    class BaseController < Api::BaseController
      # Skip EntityScoped callbacks inherited from ApplicationController
      # API auth flow is different: authenticate_api_user! must run first
      skip_before_action :set_current_entity, raise: false
      skip_before_action :set_rls_context, raise: false
      skip_after_action :reset_rls_context, raise: false

      before_action :authenticate_api_user!
      before_action :require_entity!
      before_action :set_api_rls_context
      after_action :reset_api_rls_context

      private

      def require_entity!
        return if current_entity.present?

        render json: {
          message: "User must be associated with an entity",
          error: "no_entity"
        }, status: :forbidden
      end

      def authenticate_api_user!
        auth_header = request.headers["Authorization"]
        token = auth_header&.gsub(/^Bearer /, "")

        Rails.logger.info "🔐 API Auth: Header=#{auth_header.present? ? 'present' : 'MISSING'}, Token=#{token&.first(8)}..."

        unless token.present?
          render json: { message: "Authorization token required" }, status: :unauthorized
          return
        end

        # Cache only the user_id to avoid ActiveRecord association serialization issues
        # Full User object caching breaks associations like .entity
        user_id = Rails.cache.fetch("api_user_id:#{token}", expires_in: 5.minutes) do
          User.where(api_key: token).pick(:id)
        end

        @current_user = User.includes(:entity).find_by(id: user_id) if user_id

        unless @current_user
          render json: { message: "Invalid token" }, status: :unauthorized
          return
        end
      end

      def current_user
        @current_user
      end

      def current_entity
        @current_user&.entity
      end

      # Set RLS context for PostgreSQL Row-Level Security
      # Runs after authenticate_api_user! so current_entity is available
      def set_api_rls_context
        return unless current_entity

        ActiveRecord::Base.connection.execute(
          "SET app.current_entity_id = '#{current_entity.id.to_i}'"
        )
      rescue => e
        Rails.logger.error "SECURITY: Failed to set RLS context: #{e.message}"
        raise e if Rails.env.production?
      end

      # Clean up RLS context after each request
      def reset_api_rls_context
        ActiveRecord::Base.connection.execute("RESET app.current_entity_id")
      rescue => e
        Rails.logger.error "SECURITY: Failed to reset RLS context: #{e.message}"
      end

      # Shared pagination helper
      def pagination_json(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end
    end
  end
end
