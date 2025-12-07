# frozen_string_literal: true

module Scout
  class FeedbacksController < ApplicationController
    before_action :authenticate_user!

    # POST /scout/feedbacks
    # Create feedback for Scout messages (session-based auth)
    def create
      @feedback = UserFeedback.new(feedback_params)
      @feedback.user = current_user
      @feedback.entity = current_user.entity

      if @feedback.save
        render json: {
          success: true,
          message: feedback_message(@feedback.rating)
        }
      else
        render json: {
          success: false,
          errors: @feedback.errors.full_messages
        }, status: :unprocessable_entity
      end
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

    def feedback_message(rating)
      case rating
      when 1
        "Thank you for your positive feedback!"
      when -1
        "Thanks for letting us know. We'll work on improving."
      else
        "Feedback recorded."
      end
    end
  end
end

