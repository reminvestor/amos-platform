module Api
  module V1
    class JobsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api_request
      
      def show
        job_id = params[:id]
        
        # Check ActiveJob status
        job = ActiveJob::Base.deserialize(Solid::Queue::Job.find_by(active_job_id: job_id)&.serialized_params)
        
        if job.nil?
          # Check if completed in Redis
          if defined?(Redis) && Redis.current.present?
            key = "contact_import:#{job_id}"
            result = Redis.current.get(key)
            
            if result
              # Job completed, return the stored results
              render json: JSON.parse(result)
              return
            end
          end
          
          # Not found in either place
          render json: {
            success: false,
            error: "Job not found or expired",
            job_id: job_id
          }, status: :not_found
          return
        end
        
        # Job found in queue, return status
        render json: {
          success: true,
          status: "queued",
          job_id: job_id,
          job_type: job.class.name,
          enqueued_at: job.enqueued_at&.iso8601
        }
      end
      
      private
      
      def authenticate_api_request
        # Get the API key from the Authorization header
        auth_header = request.headers['Authorization']
        
        # Better header parsing
        if auth_header.blank?
          render json: { error: 'Missing Authorization header' }, status: :unauthorized
          return
        end
        
        # Support both "Bearer <key>" and just "<key>" formats
        api_key = if auth_header.start_with?('Bearer ')
          auth_header.gsub('Bearer ', '')
        else
          auth_header
        end
        
        if api_key.blank?
          render json: { error: 'Invalid Authorization header format' }, status: :unauthorized
          return
        end
        
        # Find user by API key
        @current_user = User.find_by(api_key: api_key)
        
        unless @current_user
          render json: { error: 'Invalid API key' }, status: :unauthorized
          return
        end
        
        # Set current_user for the application controller
        Thread.current[:current_user] = @current_user
      end
      
      def current_user
        @current_user
      end
    end
  end
end 