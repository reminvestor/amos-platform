module Api
  module V1
    class JobsController < Api::BaseController
      respond_to :json
      protect_from_forgery with: :null_session
      before_action :authenticate_api_request

      def show
        begin
          job_id = params[:id]
          Rails.logger.info("API JOB STATUS [#{Time.current.iso8601(3)}]: Looking up job #{job_id}")

          # First, check Redis for completed job results
          begin
            redis = safe_redis
            if redis
              key = "contact_import:#{job_id}"
              result = redis.get(key)

              if result
                Rails.logger.info("API JOB STATUS [#{Time.current.iso8601(3)}]: Found completed job in Redis: #{job_id}")
                # Job completed, return the stored results
                render json: JSON.parse(result)
                return
              end
            end
          rescue => e
            Rails.logger.error("API JOB STATUS [#{Time.current.iso8601(3)}]: Redis error: #{e.message}")
            # Continue to check Solid Queue if Redis failed
          end

          # Check if the job exists in Solid Queue
          begin
            job_record = Solid::Queue::Job.find_by(active_job_id: job_id)

            if job_record.nil?
              Rails.logger.warn("API JOB STATUS [#{Time.current.iso8601(3)}]: Job not found in queue: #{job_id}")
              render json: {
                success: false,
                error: "Job not found or expired",
                job_id: job_id
              }, status: :not_found
              return
            end

            # Try to deserialize the job
            begin
              job = ActiveJob::Base.deserialize(job_record.serialized_params)

              if job.nil?
                Rails.logger.error("API JOB STATUS [#{Time.current.iso8601(3)}]: Failed to deserialize job: #{job_id}")
                render json: {
                  success: false,
                  error: "Job found but could not be deserialized",
                  job_id: job_id
                }, status: :internal_server_error
                return
              end

              # Check job status
              status = if job_record.finished_at.present?
                "completed"
              elsif Solid::Queue::ClaimedExecution.exists?(job_id: job_record.id)
                "running"
              elsif Solid::Queue::FailedExecution.exists?(job_id: job_record.id)
                "failed"
              elsif Solid::Queue::ReadyExecution.exists?(job_id: job_record.id)
                "ready"
              elsif Solid::Queue::ScheduledExecution.exists?(job_id: job_record.id)
                "scheduled"
              else
                "unknown"
              end

              Rails.logger.info("API JOB STATUS [#{Time.current.iso8601(3)}]: Job #{job_id} status: #{status}")

              # Job found in queue, return status
              render json: {
                success: true,
                status: status,
                job_id: job_id,
                job_type: job.class.name,
                enqueued_at: job.enqueued_at&.iso8601,
                scheduled_at: job_record.scheduled_at&.iso8601,
                started_at: job_record.started_at&.iso8601,
                finished_at: job_record.finished_at&.iso8601
              }
            rescue => e
              Rails.logger.error("API JOB STATUS [#{Time.current.iso8601(3)}]: Error deserializing job: #{e.message}")
              render json: {
                success: false,
                error: "Error processing job data",
                message: e.message,
                job_id: job_id
              }, status: :internal_server_error
            end
          rescue => e
            Rails.logger.error("API JOB STATUS [#{Time.current.iso8601(3)}]: Error querying Solid Queue: #{e.message}")
            render json: {
              success: false,
              error: "Error looking up job",
              message: e.message,
              job_id: job_id
            }, status: :internal_server_error
          end
        rescue => e
          Rails.logger.error("API JOB STATUS ERROR: #{e.class.name}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))

          render json: {
            success: false,
            error: "Error processing job status request",
            message: e.message
          }, status: :internal_server_error
        end
      end

      private

      def authenticate_api_request
        # Get the API key from the Authorization header
        auth_header = request.headers["Authorization"]

        # Better header parsing
        if auth_header.blank?
          render json: { error: "Missing Authorization header" }, status: :unauthorized
          return
        end

        # Support both "Bearer <key>" and just "<key>" formats
        api_key = if auth_header.start_with?("Bearer ")
          auth_header.gsub("Bearer ", "")
        else
          auth_header
        end

        if api_key.blank?
          render json: { error: "Invalid Authorization header format" }, status: :unauthorized
          return
        end

        # Find user by API key
        @current_user = User.find_by(api_key: api_key)

        unless @current_user
          render json: { error: "Invalid API key" }, status: :unauthorized
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
