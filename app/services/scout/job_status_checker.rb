module Scout
  class JobStatusChecker
    def initialize(user:, stream: nil)
      @user = user
      @stream = stream
    end

    # Check for active job status in cache
    def check_active_job_status(response_data)
      Rails.logger.info "🔍 Checking active job status for response data: #{response_data.keys}"

      # Only check for job status if the response includes canvas data with landing_page_id
      unless response_data[:canvas_data]&.dig(:landing_page_id)
        Rails.logger.info "❌ No canvas_data or landing_page_id found"
        return nil
      end

      landing_page_id = response_data[:canvas_data][:landing_page_id]
      job_status_key = "job_status_#{user.id}_#{landing_page_id}"

      Rails.logger.info "🔍 Looking for job status with key: #{job_status_key}"

      # Get job status from cache
      job_status = Rails.cache.read(job_status_key)

      if job_status
        Rails.logger.info "📊 Found job status for LP #{landing_page_id}: #{job_status[:type]} (#{job_status[:status]})"

        # Don't clear processing status, only clear completed/failed status
        if job_status[:status].in?([ "completed", "failed" ])
          Rails.cache.delete(job_status_key)
          Rails.logger.info "🗑️ Cleared consumed job status from cache"
        else
          Rails.logger.info "⏳ Keeping processing job status in cache for future checks"
        end

        return job_status
      else
        Rails.logger.info "❌ No job status found in cache for key: #{job_status_key}"
      end

      nil
    end

    # Send job started status if exists (requires stream)
    def send_job_started_status_if_exists(response_data)
      return unless stream

      # Only check if there's a landing page job
      return unless response_data[:canvas_data]&.dig(:landing_page_id)

      landing_page_id = response_data[:canvas_data][:landing_page_id]
      job_status_key = "job_status_#{user.id}_#{landing_page_id}"

      # Get job status from cache
      job_status = Rails.cache.read(job_status_key)

      if job_status && job_status[:status] == "processing"
        Rails.logger.info "📡 Sending job_started status via SSE: #{job_status[:type]}"

        # Send job status through SSE
        job_data = JSON.generate({ type: "job_status", data: job_status })
        job_chunk = "data: #{job_data}\n\n"
        stream.write(job_chunk)
        stream.flush if stream.respond_to?(:flush)
      else
        Rails.logger.info "❌ No processing job status found to send"
      end
    end

    private

    attr_reader :user, :stream
  end
end
