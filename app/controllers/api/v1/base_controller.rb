# frozen_string_literal: true

module Api
  module V1
    class BaseController < Api::BaseController
      before_action :authenticate_api_user!

      private

      def authenticate_api_user!
        token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

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
