# frozen_string_literal: true

module Api
  module V1
    class ChatController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_user!

      # GET /api/v1/chat/history
      # Returns chat history for the current user (mobile app)
      def history
        limit = params[:limit]&.to_i || 20
        limit = [limit, 100].min # Max 100 messages

        before_id = params[:before_id]

        # Get messages for this user, ordered by newest first
        scope = ScoutMessage.where(user_id: current_user.id).recent_first

        if before_id.present?
          before_message = ScoutMessage.find_by(id: before_id)
          scope = scope.where("created_at < ?", before_message.created_at) if before_message
        end

        messages = scope.limit(limit)
        total_count = ScoutMessage.where(user_id: current_user.id).count

        render json: {
          messages: messages.map { |m| message_json(m) },
          has_more: messages.size == limit && total_count > limit,
          total: total_count
        }
      end

      # GET /api/v1/chat/conversations
      # Returns list of recent conversations for the user
      def conversations
        recent_sessions = ScoutMessage
          .where(user_id: current_user.id)
          .select(:session_id, "MIN(created_at) as started_at", "MAX(created_at) as last_message_at", "COUNT(*) as message_count")
          .group(:session_id)
          .order("MAX(created_at) DESC")
          .limit(20)

        conversations = recent_sessions.map do |session|
          first_message = ScoutMessage
            .where(session_id: session.session_id, role: "user")
            .order(:created_at)
            .first

          {
            session_id: session.session_id,
            started_at: session.started_at,
            last_message_at: session.last_message_at,
            message_count: session.message_count,
            preview: first_message&.content&.truncate(100)
          }
        end

        render json: { conversations: conversations }
      end

      # DELETE /api/v1/chat/clear
      # Clear all messages for the current user (or specific session)
      def clear
        session_id = params[:session_id]

        if session_id.present?
          ScoutMessage.where(user_id: current_user.id, session_id: session_id).destroy_all
        else
          ScoutMessage.where(user_id: current_user.id).destroy_all
        end

        render json: { message: "Conversation cleared" }
      end

      private

      def message_json(message)
        {
          id: message.id,
          role: message.role,
          content: message.content,
          timestamp: message.created_at.iso8601,
          session_id: message.session_id,
          metadata: message.respond_to?(:metadata) ? message.metadata : nil
        }
      end

      def authenticate_api_user!
        token = request.headers["Authorization"]&.gsub(/^Bearer /, "")

        unless token.present?
          render json: { message: "Authorization token required" }, status: :unauthorized
          return
        end

        @current_user = User.find_by(api_key: token)

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
    end
  end
end
