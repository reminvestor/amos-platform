class AdminMailer < ApplicationMailer
  def error_notification(error_message, job_class, job_id, arguments)
    @error_message = error_message
    @job_class = job_class
    @job_id = job_id
    @arguments = arguments
    @timestamp = Time.current

    mail(
      to: ENV["ADMIN_EMAIL"] || ENV["MAILGUN_FROM"],
      subject: "Error in #{job_class}: #{error_message.to_s.truncate(50)}"
    )
  end
end
