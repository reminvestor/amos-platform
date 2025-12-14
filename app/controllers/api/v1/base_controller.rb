# frozen_string_literal: true

module Api
  module V1
    class BaseController < Api::BaseController
      before_action :authenticate_api_user!
      before_action :require_entity!

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

        # Cache user lookup by API key for 5 minutes to reduce DB load
        @current_user = Rails.cache.fetch("api_user:#{token}", expires_in: 5.minutes) do
          User.includes(:entity).find_by(api_key: token)
        end

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
