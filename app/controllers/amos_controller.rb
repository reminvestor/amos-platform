# frozen_string_literal: true

# AmosController - Legacy Amos endpoints
#
# V3 Migration: All Amos orchestrator logic has been replaced by V3::AgentLoop.
# The main chat functionality is handled by ScoutController#chat_stream.
# This controller is kept for backward compatibility with API endpoints.
#
class AmosController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:callback]
  skip_before_action :authenticate_user!, only: [:callback]
  skip_before_action :check_token_balance, only: [:callback]
  skip_before_action :check_onboarding_status, only: [:callback]

  # Legacy chat endpoint — redirect to V3 via ScoutController
  def chat
    redirect_to scout_chat_stream_path(message: params[:message]), status: :moved_permanently
  end

  # Callback endpoint for async operations
  def callback
    # Handle job callbacks (still needed for background tasks)
    job_id = params[:job_id]
    result = params[:result]

    if job_id.present?
      Rails.logger.info "[Amos] Callback received for job #{job_id}"
      # Find and update job record if it exists
      job = Amos::JobRecord.find_by(job_id: job_id) rescue nil
      if job
        job.update(
          status: result&.dig("status") || "completed",
          result: result
        )
      end
      render json: { success: true }
    else
      render json: { error: "Missing job_id" }, status: :bad_request
    end
  end

  # Job status endpoint
  def job_status
    job_id = params[:id]
    job = Amos::JobRecord.find_by(job_id: job_id) rescue nil

    if job
      render json: {
        job_id: job.job_id,
        status: job.status,
        result: job.result,
        created_at: job.created_at
      }
    else
      render json: { error: "Job not found" }, status: :not_found
    end
  end
end
