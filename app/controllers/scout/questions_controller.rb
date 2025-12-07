# frozen_string_literal: true

module Scout
  class QuestionsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_question, only: [:answer, :skip]

    # GET /scout/questions/pending
    def pending
      # Get pending questions for this user's session
      session_id = params[:session_id] || session[:scout_session_id]
      
      questions = AgentInputRequest.joins(agent_plugin_execution: :user)
                                   .where(agent_plugin_executions: { user_id: current_user.id })
                                   .active
                                   .by_priority

      # Filter by session if provided
      if session_id.present?
        questions = questions.for_session(session_id)
      end

      render json: {
        success: true,
        questions: questions.map(&:as_queue_json),
        count: questions.count
      }
    end

    # POST /scout/questions/:id/answer
    def answer
      answer_content = params[:answer]
      
      if answer_content.blank?
        render json: { success: false, error: "Answer cannot be empty" }, status: :unprocessable_entity
        return
      end

      @question.answer!(answer_content)
      
      Rails.logger.info "✅ User #{current_user.id} answered question #{@question.id}"
      
      render json: {
        success: true,
        message: "Answer submitted",
        question_id: @question.id
      }
    rescue => e
      Rails.logger.error "Failed to answer question #{@question.id}: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    # POST /scout/questions/:id/skip
    def skip
      reason = params[:reason]
      
      @question.skip!(reason: reason)
      
      Rails.logger.info "⏭️ User #{current_user.id} skipped question #{@question.id}"
      
      render json: {
        success: true,
        message: "Question skipped",
        question_id: @question.id
      }
    rescue => e
      Rails.logger.error "Failed to skip question #{@question.id}: #{e.message}"
      render json: { success: false, error: e.message }, status: :unprocessable_entity
    end

    private

    def set_question
      @question = AgentInputRequest.find(params[:id])
      
      # Verify ownership
      unless @question.agent_plugin_execution.user_id == current_user.id
        render json: { success: false, error: "Unauthorized" }, status: :forbidden
      end
    end
  end
end

