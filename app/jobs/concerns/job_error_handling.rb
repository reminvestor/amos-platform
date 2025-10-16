module JobErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError do |exception|
      error_message = "#{exception.class}: #{exception.message}"
      backtrace = exception.backtrace.join("\n") if exception.backtrace

      # Log the error
      Rails.logger.error("#{self.class.name} failed: #{error_message}")
      Rails.logger.error(backtrace) if backtrace

      # Send email notification
      AdminMailer.error_notification(
        error_message,
        self.class.name,
        job_id,
        arguments
      ).deliver_now

      # Re-raise the exception if needed for job retry mechanisms
      raise
    end
  end
end
