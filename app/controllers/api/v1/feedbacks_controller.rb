# frozen_string_literal: true

module Api
  module V1
    class FeedbacksController < BaseController
      # POST /api/v1/feedbacks
      # Create user feedback for an agent execution, tool call, or other feedbackable
      def create
        @feedback = UserFeedback.new(feedback_params)
        @feedback.user = current_user
        @feedback.entity = current_entity

        if @feedback.save
          render json: {
            success: true,
            feedback: serialize_feedback(@feedback),
            message: feedback_message(@feedback.rating)
          }, status: :created
        else
          render json: {
            success: false,
            errors: @feedback.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/feedbacks
      # List user's feedback (with optional filters)
      def index
        @feedbacks = current_user.user_feedbacks
                                 .includes(:feedbackable)
                                 .recent

        # Optional filters
        @feedbacks = @feedbacks.by_session(params[:session_id]) if params[:session_id].present?
        @feedbacks = @feedbacks.where(feedbackable_type: params[:type]) if params[:type].present?
        @feedbacks = @feedbacks.where(rating: params[:rating].to_i) if params[:rating].present?
        @feedbacks = @feedbacks.where("created_at >= ?", params[:since].to_datetime) if params[:since].present?

        # Pagination
        @feedbacks = @feedbacks.page(params[:page] || 1).per(params[:per_page] || 20)

        render json: {
          success: true,
          feedbacks: @feedbacks.map { |f| serialize_feedback(f) },
          pagination: pagination_json(@feedbacks)
        }
      end

      # GET /api/v1/feedbacks/stats
      # Get feedback statistics for the current entity
      def stats
        base_scope = UserFeedback.where(entity: current_entity)
        
        # Time range filter
        if params[:since].present?
          base_scope = base_scope.where("created_at >= ?", params[:since].to_datetime)
        else
          base_scope = base_scope.where("created_at >= ?", 30.days.ago)
        end

        stats = {
          total: base_scope.count,
          positive: base_scope.positive.count,
          negative: base_scope.negative.count,
          neutral: base_scope.neutral.count,
          with_comments: base_scope.with_comments.count,
          satisfaction_score: base_scope.satisfaction_score.round(3),
          
          # By type breakdown
          by_type: base_scope.group(:feedbackable_type)
                             .count
                             .transform_keys { |k| k.underscore },
          
          # Recent trend (last 7 days daily)
          daily_trend: daily_trend(base_scope)
        }

        render json: { success: true, stats: stats }
      end

      # GET /api/v1/feedbacks/agent/:agent_id
      # Get feedback for a specific agent
      def agent_feedback
        agent = AgentPlugin.find_by(id: params[:agent_id]) || 
                AgentPlugin.find_by(slug: params[:agent_id])
        
        unless agent
          render json: { success: false, error: "Agent not found" }, status: :not_found
          return
        end

        feedbacks = UserFeedback.for_agent(agent.id)
                                .where(entity: current_entity)
                                .recent
                                .page(params[:page] || 1)
                                .per(params[:per_page] || 20)

        render json: {
          success: true,
          agent: {
            id: agent.id,
            name: agent.name,
            slug: agent.slug,
            satisfaction_score: agent.user_satisfaction_score.round(3),
            combined_reputation: agent.combined_reputation_score.round(3)
          },
          feedbacks: feedbacks.map { |f| serialize_feedback(f) },
          stats: UserFeedback.for_agent(agent.id).where(entity: current_entity).stats,
          pagination: pagination_json(feedbacks)
        }
      end

      # DELETE /api/v1/feedbacks/:id
      # Delete user's own feedback
      def destroy
        @feedback = current_user.user_feedbacks.find_by(id: params[:id])

        unless @feedback
          render json: { success: false, error: "Feedback not found" }, status: :not_found
          return
        end

        @feedback.destroy
        render json: { success: true, message: "Feedback deleted" }
      end

      private

      def feedback_params
        params.require(:feedback).permit(
          :feedbackable_type,
          :feedbackable_id,
          :rating,
          :comment,
          :feedback_type,
          :session_id,
          metadata: {}
        )
      end

      def serialize_feedback(feedback)
        {
          id: feedback.id,
          rating: feedback.rating,
          rating_label: feedback.rating_label,
          rating_emoji: feedback.rating_emoji,
          comment: feedback.comment,
          feedback_type: feedback.feedback_type,
          feedbackable_type: feedback.feedbackable_type,
          feedbackable_id: feedback.feedbackable_id,
          session_id: feedback.session_id,
          created_at: feedback.created_at.iso8601,
          metadata: feedback.metadata
        }
      end

      def feedback_message(rating)
        case rating
        when 1
          "Thank you for your positive feedback! This helps us improve."
        when -1
          "Thank you for your feedback. We'll work on doing better."
        else
          "Feedback recorded. Thank you!"
        end
      end

      def daily_trend(scope)
        # Get counts for last 7 days
        (0..6).to_a.reverse.map do |days_ago|
          date = days_ago.days.ago.to_date
          day_scope = scope.where(created_at: date.beginning_of_day..date.end_of_day)
          {
            date: date.iso8601,
            total: day_scope.count,
            positive: day_scope.positive.count,
            negative: day_scope.negative.count
          }
        end
      end
    end
  end
end

