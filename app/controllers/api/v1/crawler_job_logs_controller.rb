module Api
  module V1
    class CrawlerJobLogsController < Api::V1::BaseController
      # Skip CSRF for API endpoints
      skip_before_action :verify_authenticity_token
      
      # POST /api/v1/crawler_jobs/:id/logs
      def create
        # Find the crawler job
        crawler_job = CrawlerJob.find(params[:id])
        
        # Authentication is crucial - crawler should supply API key
        # This is the same auth as crawler_contacts_controller
        api_key = request.headers['Authorization']&.split(' ')&.last
        
        if api_key.blank?
          render json: { error: 'API key missing' }, status: :unauthorized
          return
        end
        
        # Connect API key to user that owns the job
        if crawler_job.user.api_key != api_key
          render json: { error: 'Invalid API key for this crawler job' }, status: :unauthorized
          return
        end
        
        # Create the log entry
        log_params = params.require(:log).permit(:message, :level)
        
        log = crawler_job.add_log(
          log_params[:message], 
          log_params[:level] || 'info'
        )
        
        if log.persisted?
          render json: { message: "Log entry created", log: log }, status: :created
        else
          render json: { error: "Failed to create log entry", details: log.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Crawler job not found" }, status: :not_found
      rescue ActionController::ParameterMissing => e
        render json: { error: "Invalid request format", details: e.message }, status: :bad_request
      rescue => e
        render json: { error: "Unexpected error", details: e.message }, status: :internal_server_error
      end
    end
  end
end 